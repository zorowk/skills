;;; agent-shell-skill-usage-review.el --- Review skill calls on demand -*- lexical-binding: t; -*-

;;; Commentary:

;; Offer an English-labeled, read-only agent-shell action after a completed
;; turn with tool calls.  The same agent reviews only evidence already visible
;; in the conversation; no telemetry or task output is copied into Emacs.

;;; Code:

(require 'subr-x)

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  (unless (featurep 'agent-shell-bridge)
    (load (expand-file-name "../../common/scripts/agent-shell-bridge.el" root)
          nil nil t)))

(declare-function agent-shell-insert "agent-shell" (&rest arguments))
(declare-function skill-agent-shell-bridge-enable
                  "../../common/scripts/agent-shell-bridge" ())
(declare-function skill-agent-shell-register-turn-action
                  "../../common/scripts/agent-shell-bridge"
                  (id &rest arguments))
(declare-function skill-agent-shell-unregister-turn-action
                  "../../common/scripts/agent-shell-bridge" (id))

(defgroup agent-shell-skill-usage-review nil
  "Review visible skill usage from an agent-shell conversation."
  :group 'skill-agent-shell-bridge)

(defcustom agent-shell-skill-usage-review-suppressed-turns 2
  "Turns hidden after starting a review to avoid recursive review suggestions."
  :type 'natnum
  :group 'agent-shell-skill-usage-review)

(defvar agent-shell-skill-usage-review-last-shell-buffer nil
  "Most recent agent-shell buffer offering a skill usage review.")

(defvar-local agent-shell-skill-usage-review--suppress-count 0
  "Number of upcoming completed turns that should hide usage review.")

(defun agent-shell-skill-usage-review--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the most recent review shell."
  (let ((buffer
         (or shell-buffer
             (and (derived-mode-p 'agent-shell-mode) (current-buffer))
             agent-shell-skill-usage-review-last-shell-buffer)))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

(defun agent-shell-skill-usage-review--applicable-p (shell-buffer state)
  "Return non-nil when SHELL-BUFFER and completed STATE merit a review."
  (with-current-buffer shell-buffer
    (if (> agent-shell-skill-usage-review--suppress-count 0)
        (progn
          (setq agent-shell-skill-usage-review--suppress-count
                (1- agent-shell-skill-usage-review--suppress-count))
          nil)
      (and (member (plist-get state :stop-reason) '(nil "end_turn"))
           (plist-get state :tool-call-ids)))))

(defun agent-shell-skill-usage-review--turn-complete (shell-buffer _state)
  "Remember SHELL-BUFFER as the latest skill review source."
  (setq agent-shell-skill-usage-review-last-shell-buffer shell-buffer))

(defun agent-shell-skill-usage-review--prompt ()
  "Return the bounded, read-only skill review request."
  (concat
   "Use $skill-usage-review to evaluate only the skill calls visible in this "
   "conversation. Do not rerun the task or its tools, modify files, or create "
   "persistent telemetry solely for this review. Treat local character metrics "
   "as proxies rather than exact token usage, state missing-evidence limits, "
   "and return the compact outcome gate, per-skill evidence, measured totals, "
   "efficiency range, score, and at most three prioritized improvements. "
   "Separate observed facts from inferences."))

;;;###autoload
(defun agent-shell-skill-usage-review (&optional shell-buffer)
  "Ask the same agent to review visible skill calls in SHELL-BUFFER."
  (interactive)
  (let ((shell
         (agent-shell-skill-usage-review--shell-buffer shell-buffer)))
    (with-current-buffer shell
      (setq agent-shell-skill-usage-review--suppress-count
            agent-shell-skill-usage-review-suppressed-turns))
    (agent-shell-insert
     :text (agent-shell-skill-usage-review--prompt)
     :submit t
     :shell-buffer shell)))

;;;###autoload
(defun agent-shell-skill-usage-review-enable ()
  "Enable the English `Review skill usage' agent-shell turn action."
  (interactive)
  (skill-agent-shell-register-turn-action
   'skill-usage-review
   :function #'agent-shell-skill-usage-review--turn-complete
   :command (lambda (shell-buffer _state)
              (agent-shell-skill-usage-review shell-buffer))
   :label "Review skill usage"
   :applicable-p #'agent-shell-skill-usage-review--applicable-p
   :priority 10)
  (skill-agent-shell-bridge-enable))

;;;###autoload
(defun agent-shell-skill-usage-review-disable ()
  "Disable the agent-shell skill usage review action."
  (interactive)
  (skill-agent-shell-unregister-turn-action 'skill-usage-review))

(provide 'agent-shell-skill-usage-review)

;;; agent-shell-skill-usage-review.el ends here
