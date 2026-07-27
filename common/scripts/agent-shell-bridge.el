;;; agent-shell-bridge.el --- Shared agent-shell integration for skills -*- lexical-binding: t; -*-

;;; Commentary:

;; Register one bounded automatic-context source.  Skill adapters retain their
;; domain logic; this bridge only coordinates context providers and budgets.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defgroup skill-agent-shell-bridge nil
  "Shared agent-shell integration for local skills."
  :group 'tools)

(defcustom skill-agent-shell-context-maximum-characters 1800
  "Hard character budget shared by all automatic context providers."
  :type 'positive-integer
  :group 'skill-agent-shell-bridge)

(defconst skill-agent-shell-minimum-version "0.63.3"
  "Minimum agent-shell version validated with the shared bridge.")

(defvar skill-agent-shell-context-providers nil
  "Registered automatic context provider plists.")

(defvar skill-agent-shell-last-context-metrics nil
  "Privacy-safe metrics for the latest aggregate context attempt.")

(defvar agent-shell-context-sources)
(defvar agent-shell--version)

(defun skill-agent-shell-compatibility ()
  "Return agent-shell bridge compatibility diagnostics as a plist."
  (let* ((version
          (and (boundp 'agent-shell--version)
               (stringp agent-shell--version)
               agent-shell--version))
         (version-ok
          (and version
               (condition-case nil
                   (not (version< version
                                  skill-agent-shell-minimum-version))
                 (error nil))))
         (missing
          (delq
           nil
           (list
            (unless (boundp 'agent-shell-context-sources)
              'agent-shell-context-sources)))))
    (list :compatible (and version-ok (null missing))
          :version version
          :minimum-version skill-agent-shell-minimum-version
          :missing missing)))

(defun skill-agent-shell--assert-compatible ()
  "Require a compatible loaded agent-shell and return its diagnostics."
  (let* ((diagnostics (skill-agent-shell-compatibility))
         (version (or (plist-get diagnostics :version) "unknown"))
         (missing (plist-get diagnostics :missing)))
    (unless (plist-get diagnostics :compatible)
      (user-error
       "agent-shell %s+ required (found %s%s)"
       skill-agent-shell-minimum-version
       version
       (if missing
           (format "; missing API: %s"
                   (mapconcat #'symbol-name missing ", "))
         "")))
    diagnostics))

;;;###autoload
(defun skill-agent-shell-diagnose ()
  "Report whether the loaded agent-shell supports the shared bridge."
  (interactive)
  (unless (featurep 'agent-shell)
    (user-error "agent-shell is not loaded"))
  (let ((diagnostics (skill-agent-shell--assert-compatible)))
    (message "agent-shell %s is compatible with the skill bridge"
             (plist-get diagnostics :version))
    diagnostics))

(defun skill-agent-shell--entry (id entries)
  "Return the entry identified by ID in ENTRIES."
  (seq-find (lambda (entry) (eq (plist-get entry :id) id)) entries))

(defun skill-agent-shell--sort (entries)
  "Return ENTRIES ordered by descending numeric priority."
  (sort (copy-sequence entries)
        (lambda (left right)
          (> (or (plist-get left :priority) 0)
             (or (plist-get right :priority) 0)))))

(cl-defun skill-agent-shell-register-context-provider
    (id &key function applicable-p (priority 0) maximum-characters)
  "Register context provider ID.

FUNCTION is called without arguments and should return text or nil.
APPLICABLE-P, when non-nil, is checked first.  PRIORITY orders providers.
MAXIMUM-CHARACTERS is a provider-local cap inside the shared hard budget."
  (unless (symbolp id)
    (error "Context provider ID must be a symbol: %S" id))
  (unless (functionp function)
    (error "Context provider FUNCTION must be callable: %S" function))
  (when (and applicable-p (not (functionp applicable-p)))
    (error "Context provider APPLICABLE-P must be callable: %S" applicable-p))
  (when (and maximum-characters
             (not (and (integerp maximum-characters)
                       (> maximum-characters 0))))
    (error "Context provider maximum must be positive: %S"
           maximum-characters))
  (setq skill-agent-shell-context-providers
        (cons (list :id id
                    :function function
                    :applicable-p applicable-p
                    :priority priority
                    :maximum-characters maximum-characters)
              (seq-remove
               (lambda (entry) (eq (plist-get entry :id) id))
               skill-agent-shell-context-providers)))
  id)

(defun skill-agent-shell-unregister-context-provider (id)
  "Unregister context provider ID."
  (setq skill-agent-shell-context-providers
        (seq-remove (lambda (entry) (eq (plist-get entry :id) id))
                    skill-agent-shell-context-providers))
  id)

(defun skill-agent-shell--bounded-text (text maximum)
  "Return TEXT bounded to MAXIMUM characters."
  (let ((value (substring-no-properties text)))
    (if (<= (length value) maximum)
        value
      (let ((suffix "\n[provider context truncated]"))
        (if (<= maximum (length suffix))
            (substring suffix 0 maximum)
          (concat (substring value 0 (- maximum (length suffix))) suffix))))))

(defun skill-agent-shell-context ()
  "Return aggregate bounded context from applicable registered providers."
  (let ((started (float-time))
        (remaining skill-agent-shell-context-maximum-characters)
        blocks
        metrics)
    (dolist (provider (skill-agent-shell--sort
                       skill-agent-shell-context-providers))
      (when (> remaining 0)
        (let* ((id (plist-get provider :id))
               (provider-started (float-time))
               (applicable-p (plist-get provider :applicable-p))
               (status 'skipped)
               text)
          (condition-case nil
              (when (or (not applicable-p) (funcall applicable-p))
                (setq text (funcall (plist-get provider :function))
                      status (if (and (stringp text)
                                      (not (string-empty-p text)))
                                 'ok
                               'empty)))
            (error (setq status 'error text nil)))
          (when (eq status 'ok)
            (let* ((separator (if blocks "\n\n" ""))
                   (available (max 0 (- remaining (length separator))))
                   (local (or (plist-get provider :maximum-characters)
                              available))
                   (bounded (skill-agent-shell--bounded-text
                             text (min available local))))
              (when (> (length bounded) 0)
                (push (concat separator bounded) blocks)
                (setq remaining (- remaining
                                   (length separator)
                                   (length bounded))))))
          (push (list :id id
                      :status status
                      :elapsed-ms
                      (max 0 (round (* 1000
                                       (- (float-time) provider-started))))
                      :characters (if (stringp text) (length text) 0))
                metrics))))
    (let ((result (apply #'concat (nreverse blocks))))
      (setq skill-agent-shell-last-context-metrics
            (list :elapsed-ms
                  (max 0 (round (* 1000 (- (float-time) started))))
                  :characters (length result)
                  :maximum-characters
                  skill-agent-shell-context-maximum-characters
                  :providers (nreverse metrics)))
      (unless (string-empty-p result) result))))

(defun skill-agent-shell--install-context-source ()
  "Install the aggregate source after explicit region and error sources."
  (let* ((function #'skill-agent-shell-context)
         (sources (remove function agent-shell-context-sources))
         (priority (seq-filter (lambda (source) (memq source '(region error)))
                               sources))
         (fallbacks (seq-remove (lambda (source) (memq source '(region error)))
                                sources)))
    (setq agent-shell-context-sources
          (append priority (list function) fallbacks))))

;;;###autoload
(defun skill-agent-shell-bridge-enable ()
  "Enable shared automatic context after agent-shell loads."
  (interactive)
  (if (featurep 'agent-shell)
      (progn
        (skill-agent-shell--assert-compatible)
        (skill-agent-shell--install-context-source))
    (with-eval-after-load 'agent-shell
      (skill-agent-shell--assert-compatible)
      (skill-agent-shell--install-context-source))))

;;;###autoload
(defun skill-agent-shell-bridge-disable ()
  "Disable shared automatic context."
  (interactive)
  (when (boundp 'agent-shell-context-sources)
    (setq agent-shell-context-sources
          (remove #'skill-agent-shell-context agent-shell-context-sources))))

(provide 'agent-shell-bridge)

;;; agent-shell-bridge.el ends here
