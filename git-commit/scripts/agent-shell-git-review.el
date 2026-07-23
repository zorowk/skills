;;; agent-shell-git-review.el --- Review agent-shell turn changes -*- lexical-binding: t; -*-

;;; Commentary:

;; Treat agent-shell write events as advisory candidates only.  Every review
;; and commit request is scoped to explicit paths and re-reads Git through the
;; evidence-backed ai-git-commit facade.

;;; Code:

(require 'cl-lib)
(require 'diff-mode)
(require 'seq)
(require 'subr-x)

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  (unless (featurep 'ai-git-commit)
    (load (expand-file-name "ai-git-commit.el" root) nil nil t))
  (unless (featurep 'agent-shell-bridge)
    (load (expand-file-name "../../common/scripts/agent-shell-bridge.el" root)
          nil nil t)))

(declare-function ai-git-commit-run "ai-git-commit" (request))
(declare-function agent-shell-insert "agent-shell" (&rest arguments))
(declare-function magit-toplevel "magit-git" (&optional directory))
(declare-function skill-agent-shell-bridge-enable
                  "../../common/scripts/agent-shell-bridge" ())
(declare-function skill-agent-shell-current-turn-paths
                  "../../common/scripts/agent-shell-bridge"
                  (&optional shell-buffer))
(declare-function skill-agent-shell-register-turn-action
                  "../../common/scripts/agent-shell-bridge"
                  (id &rest arguments))
(declare-function skill-agent-shell-unregister-turn-action
                  "../../common/scripts/agent-shell-bridge" (id))

(defgroup agent-shell-git-review nil
  "Path-scoped Git review after agent-shell turns."
  :group 'skill-agent-shell-bridge)

(defvar agent-shell-git-review-last-shell-buffer nil
  "Most recent agent-shell buffer with Git review candidates.")

(defun agent-shell-git-review--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the most recent candidate shell."
  (let ((buffer (or shell-buffer
                    (and (derived-mode-p 'agent-shell-mode)
                         (current-buffer))
                    agent-shell-git-review-last-shell-buffer)))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell turn with candidate files"))
    buffer))

(defun agent-shell-git-review--root (path)
  "Return the Magit root containing PATH, or nil."
  (when (require 'magit nil t)
    (let ((default-directory
           (if (file-directory-p path) path (file-name-directory path))))
      (ignore-errors (magit-toplevel default-directory)))))

(defun agent-shell-git-review--groups (shell-buffer)
  "Group advisory paths from SHELL-BUFFER by actual Git root."
  (let (groups)
    (dolist (path (skill-agent-shell-current-turn-paths shell-buffer))
      (when-let* ((root (agent-shell-git-review--root path)))
        (let ((entry (assoc-string root groups)))
          (if entry
              (setcdr entry (append (cdr entry) (list path)))
            (setq groups (append groups (list (cons root (list path)))))))))
    groups))

(defun agent-shell-git-review--require-groups (shell-buffer)
  "Return Git groups for SHELL-BUFFER or signal a user-facing error."
  (or (agent-shell-git-review--groups shell-buffer)
      (user-error "The completed turn has no candidate paths in a Git repository")))

(defun agent-shell-git-review--context (root paths)
  "Return fresh Git context for explicit PATHS under ROOT."
  (ai-git-commit-run
   (list :operation 'context :directory root :paths paths)))

;;;###autoload
(defun agent-shell-git-review-current-turn (&optional shell-buffer)
  "Display fresh Git diffs for the completed turn's candidate files."
  (interactive)
  (let* ((shell (agent-shell-git-review--shell-buffer shell-buffer))
         (groups (agent-shell-git-review--require-groups shell))
         (buffer (get-buffer-create "*Agent Shell Git Review*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (dolist (group groups)
          (let* ((root (car group))
                 (paths (cdr group))
                 (result (agent-shell-git-review--context root paths))
                 (data (plist-get result :data)))
            (insert (format "Repository: %s\n" root))
            (insert (format "Candidate paths: %d\n" (length paths)))
            (insert "Git scoped status:\n"
                    (or (plist-get data :scoped-status) "")
                    "\n\n")
            (insert (or (plist-get data :diff) ""))
            (insert "\n\n")))
        (goto-char (point-min))
        (diff-mode)))
    (pop-to-buffer buffer)
    buffer))

(defun agent-shell-git-review--request-text (shell-buffer action)
  "Return an explicit git-commit request for SHELL-BUFFER and ACTION."
  (let* ((groups (agent-shell-git-review--require-groups shell-buffer))
         (scope
          (mapconcat
           (lambda (group)
             (format "Repository %s:\n%s"
                     (car group)
                     (mapconcat (lambda (path) (format "- %s" path))
                                (cdr group) "\n")))
           groups "\n\n")))
    (format
     (concat
      "Use $git-commit for the following candidate paths.\n\n%s\n\n"
      "Treat this list only as an agent-shell trigger: re-read actual Git/Magit "
      "context for exactly these paths and do not include unrelated changes. %s "
      "Keep validation as internal evidence and omit test results from the "
      "commit body unless I explicitly request them.")
     scope
     (if (eq action 'commit)
         "Commit each repository separately after verifying the explicit path set."
       "Generate a commit-message proposal only; do not commit."))))

;;;###autoload
(defun agent-shell-git-review-request-message (&optional shell-buffer)
  "Insert a scoped git-commit proposal request into SHELL-BUFFER."
  (interactive)
  (let ((shell (agent-shell-git-review--shell-buffer shell-buffer)))
    (agent-shell-insert
     :text (agent-shell-git-review--request-text shell 'message)
     :submit nil
     :shell-buffer shell)))

;;;###autoload
(defun agent-shell-git-review-request-commit (&optional shell-buffer)
  "Confirm and submit a scoped git-commit request in SHELL-BUFFER."
  (interactive)
  (let ((shell (agent-shell-git-review--shell-buffer shell-buffer)))
    (when (yes-or-no-p
           "Ask the agent to re-read Git and commit only the candidate paths? ")
      (agent-shell-insert
       :text (agent-shell-git-review--request-text shell 'commit)
       :submit t
       :shell-buffer shell))))

;;;###autoload
(defun agent-shell-git-review-menu (&optional shell-buffer)
  "Offer review actions for SHELL-BUFFER without modifying Git."
  (interactive)
  (let* ((shell (agent-shell-git-review--shell-buffer shell-buffer))
         (choice
          (read-char-choice
           "[v] view current diff, [g] generate message, [c] request commit: "
           '(?v ?g ?c))))
    (pcase choice
      (?v (agent-shell-git-review-current-turn shell))
      (?g (agent-shell-git-review-request-message shell))
      (?c (agent-shell-git-review-request-commit shell)))))

(defun agent-shell-git-review--applicable-p (_shell-buffer state)
  "Return non-nil when advisory STATE includes paths."
  (plist-get state :paths))

(defun agent-shell-git-review--turn-complete (shell-buffer state)
  "Remember SHELL-BUFFER for Git review of advisory STATE."
  (setq agent-shell-git-review-last-shell-buffer shell-buffer)
  state)

;;;###autoload
(defun agent-shell-git-review-enable ()
  "Enable Git review actions for completed agent-shell turns."
  (interactive)
  (skill-agent-shell-register-turn-action
   'git-review
   :function #'agent-shell-git-review--turn-complete
   :command (lambda (shell-buffer _state)
              (agent-shell-git-review-menu shell-buffer))
   :label "Review Git changes"
   :applicable-p #'agent-shell-git-review--applicable-p
   :priority 50)
  (skill-agent-shell-bridge-enable))

;;;###autoload
(defun agent-shell-git-review-disable ()
  "Disable Git review actions for completed agent-shell turns."
  (interactive)
  (skill-agent-shell-unregister-turn-action 'git-review))

(provide 'agent-shell-git-review)

;;; agent-shell-git-review.el ends here
