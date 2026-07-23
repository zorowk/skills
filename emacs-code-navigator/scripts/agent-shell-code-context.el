;;; agent-shell-code-context.el --- Bounded live code context for agent-shell -*- lexical-binding: t; -*-

;;; Commentary:

;; Provide compact position, semantic, and existing diagnostic context through
;; the shared agent-shell bridge without displaying or modifying source buffers.

;;; Code:

(require 'seq)
(require 'subr-x)

(unless (featurep 'agent-shell-bridge)
  (load (expand-file-name "../../common/scripts/agent-shell-bridge.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil t))

(unless (featurep 'emacs-code-navigator)
  (load (expand-file-name "emacs-code-navigator.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil t))

(declare-function emacs-code-navigator-query "emacs-code-navigator"
                  (request))
(declare-function flymake-diagnostic-beg "flymake" (diagnostic))
(declare-function flymake-diagnostic-end "flymake" (diagnostic))
(declare-function flymake-diagnostic-text "flymake" (diagnostic))
(declare-function flymake-diagnostic-type "flymake" (diagnostic))
(declare-function flymake-diagnostics "flymake" (&optional beg end))
(declare-function skill-agent-shell-register-context-provider
                  "../../common/scripts/agent-shell-bridge"
                  (id &rest arguments))
(declare-function skill-agent-shell-unregister-context-provider
                  "../../common/scripts/agent-shell-bridge" (id))
(declare-function skill-agent-shell-bridge-enable
                  "../../common/scripts/agent-shell-bridge" ())
(defvar agent-shell-context-sources)

(defgroup emacs-code-navigator-agent-shell nil
  "Bounded live Emacs context for agent-shell."
  :group 'emacs-code-navigator)

(defcustom emacs-code-navigator-agent-shell-context-enabled t
  "Whether to return automatic code context to agent-shell."
  :type 'boolean
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-context-maximum-characters 1800
  "Maximum characters returned as one automatic code context block."
  :type 'positive-integer
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-context-radius 2
  "Number of source lines included before and after point."
  :type 'natnum
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-diagnostic-limit 3
  "Maximum existing Flymake diagnostics included near point."
  :type 'natnum
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-diagnostic-maximum-characters 240
  "Maximum characters included from one Flymake diagnostic."
  :type 'positive-integer
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-semantic-level 'definitions
  "Semantic detail included in automatic context.

`none' disables semantic queries.  `definitions' requests compact xref
definitions and synchronous Eldoc from the current live buffer."
  :type '(choice (const none) (const definitions))
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-definition-limit 2
  "Maximum xref definitions included in automatic context."
  :type 'positive-integer
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-semantic-timeout-ms 200
  "Maximum total milliseconds spent collecting automatic semantic context."
  :type 'positive-integer
  :group 'emacs-code-navigator-agent-shell)

(defcustom emacs-code-navigator-agent-shell-eldoc-maximum-characters 400
  "Maximum total Eldoc characters included in automatic context."
  :type 'positive-integer
  :group 'emacs-code-navigator-agent-shell)

(defvar emacs-code-navigator-agent-shell-last-context-metrics nil
  "Metrics for the latest automatic context attempt, without context text.")

(defun emacs-code-navigator-agent-shell-applicable-p ()
  "Return non-nil when the current buffer can provide live code context."
  (and emacs-code-navigator-agent-shell-context-enabled
       buffer-file-name
       (derived-mode-p 'prog-mode)
       (not (file-remote-p buffer-file-name))))

(defun emacs-code-navigator-agent-shell--truncate (text maximum)
  "Return TEXT bounded to MAXIMUM characters with a visible suffix."
  (let ((suffix "...")
        (value (or text "")))
    (if (<= (length value) maximum)
        value
      (if (<= maximum (length suffix))
          (substring suffix 0 maximum)
        (concat (substring value 0 (- maximum (length suffix)))
                suffix)))))

(defun emacs-code-navigator-agent-shell--existing-diagnostics (line)
  "Return bounded existing Flymake diagnostics intersecting LINE.

Do not enable or start Flymake."
  (when (and (> emacs-code-navigator-agent-shell-diagnostic-limit 0)
             (bound-and-true-p flymake-mode)
             (fboundp 'flymake-diagnostics))
    (seq-take
     (delq
      nil
      (mapcar
       (lambda (diagnostic)
         (let ((beg-line
                (line-number-at-pos
                 (flymake-diagnostic-beg diagnostic)))
               (end-line
                (line-number-at-pos
                 (flymake-diagnostic-end diagnostic))))
           (when (and (<= beg-line line) (>= end-line line))
             (format "- %s at %d: %s"
                     (flymake-diagnostic-type diagnostic)
                     beg-line
                     (emacs-code-navigator-agent-shell--truncate
                      (string-trim
                       (substring-no-properties
                        (flymake-diagnostic-text diagnostic)))
                      emacs-code-navigator-agent-shell-diagnostic-maximum-characters)))))
       (flymake-diagnostics)))
     emacs-code-navigator-agent-shell-diagnostic-limit)))

(defun emacs-code-navigator-agent-shell--format
    (file line column root result diagnostics)
  "Format bounded context for FILE at LINE and COLUMN.

ROOT is the project root.  RESULT is a navigator envelope and DIAGNOSTICS are
already-existing Flymake messages."
  (let* ((data (plist-get result :data))
         (provenance (plist-get result :provenance))
         (symbol-data (plist-get data :symbol))
         (semantic (plist-get data :semantic))
         (symbol-at-point (thing-at-point 'symbol t))
         (shown-file
          (if (and root (file-in-directory-p file root))
              (file-relative-name file root)
            file))
         (lines
          (delq
           nil
           (list
            "[live-emacs-code-context]"
            (format "file: %s" shown-file)
            (and root (format "project: %s" (directory-file-name root)))
            (format "position: line %d, column %d" line column)
            (when-let* ((scope (plist-get data :scope)))
              (format "scope: %s" scope))
            (when-let* ((symbol (or symbol-at-point (car symbol-data))))
              (format "symbol: %s" symbol))
            (format "mode: %s%s"
                    (or (nth 2 symbol-data) major-mode)
                    (if (nth 3 symbol-data) ", eglot-managed=yes" ""))
            (format "buffer: modified=%s, disk-diverged=%s"
                    (if (plist-get provenance :buffer-modified) "yes" "no")
                    (if (plist-get provenance :disk-diverged) "yes" "no"))
            (when semantic
              (format "semantic: status=%s%s"
                      (plist-get semantic :status)
                      (if-let* ((provider (plist-get semantic :provider)))
                          (format ", provider=%s" provider)
                        "")))
            (when-let* ((definitions (plist-get semantic :definitions)))
              (format
               "definitions:\n%s"
               (string-join
                (mapcar
                 (lambda (definition)
                   (pcase-let ((`(,definition-file ,definition-line ,summary)
                                definition))
                     (format "- %s:%s — %s"
                             (if (and root definition-file
                                      (file-in-directory-p definition-file root))
                                 (file-relative-name definition-file root)
                               definition-file)
                             (or definition-line "?") summary)))
                 definitions)
                "\n")))
            (when-let* ((eldoc (plist-get semantic :eldoc)))
              (format
               "signature: %s"
               (emacs-code-navigator-agent-shell--truncate
                (string-join eldoc " | ")
                emacs-code-navigator-agent-shell-eldoc-maximum-characters)))
            (when-let* ((nearby (plist-get data :region)))
              (format "nearby:\n%s" nearby))
            (when diagnostics
              (format "diagnostics:\n%s" (string-join diagnostics "\n"))))))
         (text (string-join lines "\n"))
         (maximum emacs-code-navigator-agent-shell-context-maximum-characters)
         (suffix "\n[context truncated]"))
    (if (<= (length text) maximum)
        text
      (if (<= maximum (length suffix))
          (substring suffix 0 maximum)
        (concat
         (substring text 0 (- maximum (length suffix)))
         suffix)))))

;;;###autoload
(defun emacs-code-navigator-agent-shell-context ()
  "Return compact live code context for the current agent-shell request.

Return nil outside local file-backed programming buffers or after any context
collection error, allowing agent-shell to try its next configured source."
  (let ((started (float-time)))
    (if (not (emacs-code-navigator-agent-shell-applicable-p))
        (progn
          (setq emacs-code-navigator-agent-shell-last-context-metrics
                (list :status 'skipped :reason 'inapplicable))
          nil)
      (condition-case nil
          (let* ((file (expand-file-name buffer-file-name))
                 (line (line-number-at-pos))
                 (column (current-column))
                 (semantic
                  (eq emacs-code-navigator-agent-shell-semantic-level
                      'definitions))
                 (result
                  (emacs-code-navigator-query
                   (list :operation 'context
                         :file file
                         :line line
                         :column column
                         :radius emacs-code-navigator-agent-shell-context-radius
                         :definitions semantic
                         :definition-limit
                         emacs-code-navigator-agent-shell-definition-limit
                         :eldoc semantic
                         :semantic-timeout-ms
                         emacs-code-navigator-agent-shell-semantic-timeout-ms
                         :source 'live)))
                 (root (plist-get (plist-get result :data) :project-root))
                 (diagnostics
                  (emacs-code-navigator-agent-shell--existing-diagnostics line))
                 (context
                  (emacs-code-navigator-agent-shell--format
                   file line column root result diagnostics)))
            (setq emacs-code-navigator-agent-shell-last-context-metrics
                  (list :status 'ok
                        :elapsed-ms
                        (round (* 1000 (- (float-time) started)))
                        :characters (length context)
                        :maximum-characters
                        emacs-code-navigator-agent-shell-context-maximum-characters
                        :semantic-status
                        (plist-get (plist-get (plist-get result :data) :semantic)
                                   :status)
                        :definition-count
                        (length (plist-get
                                 (plist-get (plist-get result :data) :semantic)
                                 :definitions))
                        :navigator-metrics (plist-get result :metrics)))
            context)
        (error
         (setq emacs-code-navigator-agent-shell-last-context-metrics
               (list :status 'error
                     :elapsed-ms
                     (round (* 1000 (- (float-time) started)))))
         nil)))))

;;;###autoload
;;;###autoload
(defun emacs-code-navigator-agent-shell-enable ()
  "Register bounded code context with the shared agent-shell bridge."
  (interactive)
  (when (boundp 'agent-shell-context-sources)
    (setq agent-shell-context-sources
          (remove #'emacs-code-navigator-agent-shell-context
                  agent-shell-context-sources)))
  (skill-agent-shell-register-context-provider
   'emacs-code-navigator
   :function #'emacs-code-navigator-agent-shell-context
   :applicable-p #'emacs-code-navigator-agent-shell-applicable-p
   :priority 50
   :maximum-characters
   emacs-code-navigator-agent-shell-context-maximum-characters)
  (skill-agent-shell-bridge-enable))

;;;###autoload
(defun emacs-code-navigator-agent-shell-disable ()
  "Unregister bounded code context from the shared agent-shell bridge."
  (interactive)
  (when (boundp 'agent-shell-context-sources)
    (setq agent-shell-context-sources
          (remove #'emacs-code-navigator-agent-shell-context
                  agent-shell-context-sources)))
  (skill-agent-shell-unregister-context-provider 'emacs-code-navigator))

(provide 'agent-shell-code-context)

;;; agent-shell-code-context.el ends here
