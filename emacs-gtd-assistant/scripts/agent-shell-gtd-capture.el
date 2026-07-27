;;; agent-shell-gtd-capture.el --- Capture conversation tasks into GTD -*- lexical-binding: t; -*-

;;; Commentary:

;; Provide an explicit command that asks the same agent to extract structured
;; candidates from its previous answer.  Extraction is read-only; the prompt
;; requires user confirmation before `add-many' mutates Org.

;;; Code:

(declare-function agent-shell-insert "agent-shell" (&rest arguments))

(defgroup agent-shell-gtd-capture nil
  "Capture valuable agent-shell follow-up work as Org GTD tasks."
  :group 'tools)

(defun agent-shell-gtd-capture--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the current agent-shell buffer."
  (let ((buffer (or shell-buffer
                    (and (derived-mode-p 'agent-shell-mode)
                         (current-buffer)))))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

(defun agent-shell-gtd-capture--prompt ()
  "Return the bounded candidate extraction request."
  (concat
   "Use $emacs-gtd-assistant to extract 1 to 3 valuable, concrete follow-up "
   "tasks from your immediately previous answer and our current discussion. "
   "Do not write to gtd.org yet.\n\n"
   "Present editable candidates in the conversation language. For each one, "
   "propose a concise next-action title, Org priority (A only for blocking or "
   "time-sensitive work, B for valuable research by default, C for optional "
   "exploration), up to five tags, a short context-notes summary, and only "
   "relevant HTTP, documentation, or file links. Propose safe properties such "
   "as SOURCE=agent-shell and PROJECT when supported by evidence. Do not save "
   "the full transcript. Use `:context work' for job or project-code tasks and "
   "`:context personal' otherwise; put research background in "
   "`:context-notes'.\n\n"
   "Ask me to select or edit the candidates. Only after my explicit "
   "confirmation, call `emacs-gtd-execute' with `:operation add-many', the "
   "confirmed structured `:tasks', and `:authorization explicit'."))

;;;###autoload
(defun agent-shell-gtd-capture (&optional shell-buffer)
  "Ask the same agent to prepare GTD candidates from its previous answer."
  (interactive)
  (let ((shell (agent-shell-gtd-capture--shell-buffer shell-buffer)))
    (agent-shell-insert
     :text (agent-shell-gtd-capture--prompt)
     :submit t
     :shell-buffer shell)))

(provide 'agent-shell-gtd-capture)

;;; agent-shell-gtd-capture.el ends here
