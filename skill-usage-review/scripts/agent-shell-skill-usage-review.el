;;; agent-shell-skill-usage-review.el --- Review skill calls on demand -*- lexical-binding: t; -*-

;;; Commentary:

;; Provide an explicit, read-only command.  The same agent reviews only evidence
;; already visible in the conversation; no telemetry or task output is copied
;; into Emacs.

;;; Code:

(declare-function agent-shell-insert "agent-shell" (&rest arguments))

(defgroup agent-shell-skill-usage-review nil
  "Review visible skill usage from an agent-shell conversation."
  :group 'tools)

(defun agent-shell-skill-usage-review--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the current agent-shell buffer."
  (let ((buffer
         (or shell-buffer
             (and (derived-mode-p 'agent-shell-mode) (current-buffer)))))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

(defun agent-shell-skill-usage-review--prompt ()
  "Return the bounded, read-only skill review request."
  (concat
   "Use $skill-usage-review to evaluate only the skill calls visible in this "
   "conversation. Do not rerun the task or its tools, modify files, or create "
   "persistent telemetry solely for this review. Treat local character metrics "
   "as proxies rather than exact token usage, state missing-evidence limits, "
   "and return the compact outcome gate, per-skill evidence, measured totals, "
   "and independent 0-3 ratings for correctness, evidence sufficiency, safety, "
   "and economy. Do not combine the ratings into a composite score. Report "
   "observed recovery cost separately from inferred latent recovery risk, treat "
   "the efficiency range as diagnostic only, and give at most three prioritized "
   "improvements. Separate observed facts from inferences."))

;;;###autoload
(defun agent-shell-skill-usage-review (&optional shell-buffer)
  "Ask the same agent to review visible skill calls in SHELL-BUFFER."
  (interactive)
  (let ((shell
         (agent-shell-skill-usage-review--shell-buffer shell-buffer)))
    (agent-shell-insert
     :text (agent-shell-skill-usage-review--prompt)
     :submit t
     :shell-buffer shell)))

(provide 'agent-shell-skill-usage-review)

;;; agent-shell-skill-usage-review.el ends here
