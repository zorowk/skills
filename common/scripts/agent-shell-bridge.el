;;; agent-shell-bridge.el --- Shared agent-shell integration for skills -*- lexical-binding: t; -*-

;;; Commentary:

;; Register one bounded automatic-context source and one public event
;; subscription per agent-shell buffer.  Skill adapters retain their domain
;; logic; this bridge only coordinates budgets, lifecycle, and advisory paths.

;;; Code:

(require 'cl-lib)
(require 'map)
(require 'seq)
(require 'subr-x)

(defgroup skill-agent-shell-bridge nil
  "Shared agent-shell integration for local skills."
  :group 'tools)

(defcustom skill-agent-shell-context-maximum-characters 1800
  "Hard character budget shared by all automatic context providers."
  :type 'positive-integer
  :group 'skill-agent-shell-bridge)

(defcustom skill-agent-shell-notify-turn-actions t
  "Whether to mention available actions after a turn changed files."
  :type 'boolean
  :group 'skill-agent-shell-bridge)

(defvar skill-agent-shell-context-providers nil
  "Registered automatic context provider plists.")

(defvar skill-agent-shell-turn-actions nil
  "Registered turn-complete action plists.")

(defvar skill-agent-shell-last-context-metrics nil
  "Privacy-safe metrics for the latest aggregate context attempt.")

(defvar agent-shell-context-sources)
(defvar agent-shell-mode-hook)

(defvar-local skill-agent-shell--subscription nil
  "agent-shell event subscription token for the current shell buffer.")

(defvar-local skill-agent-shell--turn-state nil
  "Advisory state collected for the current agent turn.")

(defvar-local skill-agent-shell--last-completed-turn nil
  "Frozen advisory state for the latest completed agent turn.")

(declare-function agent-shell-subscribe-to "agent-shell"
                  (&key shell-buffer event on-event))
(declare-function agent-shell-unsubscribe "agent-shell"
                  (&key subscription))

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

(defun skill-agent-shell--path (path shell-buffer)
  "Return normalized local PATH relative to SHELL-BUFFER defaults."
  (when (and (stringp path) (not (string-empty-p path)))
    (with-current-buffer shell-buffer
      (let ((expanded (expand-file-name path default-directory)))
        (unless (file-remote-p expanded) expanded)))))

(defun skill-agent-shell--record-path (path shell-buffer source)
  "Record advisory PATH from SOURCE for SHELL-BUFFER."
  (when-let* ((normalized (skill-agent-shell--path path shell-buffer)))
    (with-current-buffer shell-buffer
      (let ((paths (plist-get skill-agent-shell--turn-state :paths)))
        (unless (assoc-string normalized paths)
          (setq skill-agent-shell--turn-state
                (plist-put skill-agent-shell--turn-state :paths
                           (append paths (list (cons normalized source))))))))))

(defun skill-agent-shell--record-tool-call (data shell-buffer)
  "Record structured diff paths from tool-call event DATA."
  (let* ((tool-call (map-elt data :tool-call))
         (diffs (map-elt tool-call :diffs)))
    (dolist (diff diffs)
      (skill-agent-shell--record-path
       (map-elt diff :file) shell-buffer 'tool-call-diff))))

(cl-defun skill-agent-shell-register-turn-action
    (id &key function applicable-p (priority 0))
  "Register turn-complete action ID.

FUNCTION receives SHELL-BUFFER and the frozen turn state.  APPLICABLE-P, when
non-nil, receives the same arguments and gates the action."
  (unless (and (symbolp id) (functionp function))
    (error "Turn action requires a symbol ID and callable FUNCTION"))
  (setq skill-agent-shell-turn-actions
        (cons (list :id id :function function :applicable-p applicable-p
                    :priority priority)
              (seq-remove
               (lambda (entry) (eq (plist-get entry :id) id))
               skill-agent-shell-turn-actions)))
  id)

(defun skill-agent-shell-unregister-turn-action (id)
  "Unregister turn-complete action ID."
  (setq skill-agent-shell-turn-actions
        (seq-remove (lambda (entry) (eq (plist-get entry :id) id))
                    skill-agent-shell-turn-actions))
  id)

(defun skill-agent-shell--run-turn-actions (shell-buffer state)
  "Run applicable registered actions for SHELL-BUFFER and frozen STATE."
  (dolist (action (skill-agent-shell--sort skill-agent-shell-turn-actions))
    (condition-case err
        (when (or (not (plist-get action :applicable-p))
                  (funcall (plist-get action :applicable-p)
                           shell-buffer state))
          (funcall (plist-get action :function) shell-buffer state))
      (error
       (message "agent-shell action %s failed: %s"
                (plist-get action :id) (error-message-string err))))))

(defun skill-agent-shell--handle-event (shell-buffer event)
  "Handle agent-shell EVENT for SHELL-BUFFER."
  (when (buffer-live-p shell-buffer)
    (let ((kind (map-elt event :event))
          (data (map-elt event :data)))
      (with-current-buffer shell-buffer
        (pcase kind
          ('input-submitted
           (setq skill-agent-shell--turn-state
                 (list :paths nil :write-seen nil
                       :started-at (float-time))))
          ('file-write
           (setq skill-agent-shell--turn-state
                 (plist-put skill-agent-shell--turn-state :write-seen t))
           (skill-agent-shell--record-path
            (map-elt data :path) shell-buffer 'file-write))
          ('tool-call-update
           (skill-agent-shell--record-tool-call data shell-buffer))
          ('turn-complete
           (let ((frozen
                  (append
                   (copy-tree skill-agent-shell--turn-state)
                   (list :completed-at (float-time)
                         :stop-reason (map-elt data :stop-reason)))))
             (setq skill-agent-shell--last-completed-turn frozen)
             (when (plist-get frozen :paths)
               (skill-agent-shell--run-turn-actions shell-buffer frozen))))
          ('clean-up
           (skill-agent-shell--unsubscribe)))))))

(defun skill-agent-shell--subscribe ()
  "Subscribe the current agent-shell buffer once."
  (unless skill-agent-shell--subscription
    (let ((shell-buffer (current-buffer)))
      (setq skill-agent-shell--turn-state (list :paths nil :write-seen nil))
      (setq skill-agent-shell--subscription
            (agent-shell-subscribe-to
             :shell-buffer shell-buffer
             :on-event
             (lambda (event)
               (skill-agent-shell--handle-event shell-buffer event)))))))

(defun skill-agent-shell--unsubscribe ()
  "Unsubscribe the current shell buffer and clear bridge state."
  (when skill-agent-shell--subscription
    (agent-shell-unsubscribe :subscription skill-agent-shell--subscription)
    (setq skill-agent-shell--subscription nil)))

(defun skill-agent-shell-current-turn-paths (&optional shell-buffer)
  "Return advisory absolute paths from SHELL-BUFFER's completed turn."
  (with-current-buffer (or shell-buffer (current-buffer))
    (mapcar #'car (plist-get skill-agent-shell--last-completed-turn :paths))))

;;;###autoload
(defun skill-agent-shell-bridge-enable ()
  "Enable shared context and lifecycle integration after agent-shell loads."
  (interactive)
  (if (featurep 'agent-shell)
      (progn
        (skill-agent-shell--install-context-source)
        (add-hook 'agent-shell-mode-hook #'skill-agent-shell--subscribe)
        (dolist (buffer (buffer-list))
          (with-current-buffer buffer
            (when (derived-mode-p 'agent-shell-mode)
              (skill-agent-shell--subscribe)))))
    (with-eval-after-load 'agent-shell
      (skill-agent-shell--install-context-source)
      (add-hook 'agent-shell-mode-hook #'skill-agent-shell--subscribe))))

;;;###autoload
(defun skill-agent-shell-bridge-disable ()
  "Disable shared context and lifecycle integration."
  (interactive)
  (when (boundp 'agent-shell-context-sources)
    (setq agent-shell-context-sources
          (remove #'skill-agent-shell-context agent-shell-context-sources)))
  (remove-hook 'agent-shell-mode-hook #'skill-agent-shell--subscribe)
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer
      (when skill-agent-shell--subscription
        (skill-agent-shell--unsubscribe)))))

(provide 'agent-shell-bridge)

;;; agent-shell-bridge.el ends here
