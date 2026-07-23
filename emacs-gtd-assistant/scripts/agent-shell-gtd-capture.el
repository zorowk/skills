;;; agent-shell-gtd-capture.el --- Capture conversation tasks into GTD -*- lexical-binding: t; -*-

;;; Commentary:

;; Offer an English-labeled turn action that asks the same agent to extract
;; structured candidates from its previous answer.  Extraction is read-only;
;; the prompt requires user confirmation before `add-many' mutates Org.

;;; Code:

(require 'subr-x)

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  (unless (featurep 'emacs-gtd-assistant)
    (load (expand-file-name "emacs-gtd-assistant.el" root) nil nil t))
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

(defgroup agent-shell-gtd-capture nil
  "Capture valuable agent-shell follow-up work as Org GTD tasks."
  :group 'emacs-gtd-assistant)

(defcustom agent-shell-gtd-capture-suppressed-turns 2
  "Turns hidden after starting candidate extraction to avoid capture loops."
  :type 'natnum
  :group 'agent-shell-gtd-capture)

(defvar agent-shell-gtd-capture-last-shell-buffer nil
  "Most recent agent-shell buffer offering GTD capture.")

(defvar-local agent-shell-gtd-capture--suppress-count 0
  "Number of upcoming completed turns that should hide GTD capture.")

(defun agent-shell-gtd-capture--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the most recent capture shell."
  (let ((buffer (or shell-buffer
                    (and (derived-mode-p 'agent-shell-mode)
                         (current-buffer))
                    agent-shell-gtd-capture-last-shell-buffer)))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

(defun agent-shell-gtd-capture--applicable-p (shell-buffer state)
  "Return non-nil when SHELL-BUFFER and completed STATE can offer capture."
  (with-current-buffer shell-buffer
    (if (> agent-shell-gtd-capture--suppress-count 0)
        (progn
          (setq agent-shell-gtd-capture--suppress-count
                (1- agent-shell-gtd-capture--suppress-count))
          nil)
      (member (plist-get state :stop-reason) '(nil "end_turn")))))

(defun agent-shell-gtd-capture--turn-complete (shell-buffer _state)
  "Remember SHELL-BUFFER as the latest GTD capture source."
  (setq agent-shell-gtd-capture-last-shell-buffer shell-buffer))

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
    (with-current-buffer shell
      (setq agent-shell-gtd-capture--suppress-count
            agent-shell-gtd-capture-suppressed-turns))
    (agent-shell-insert
     :text (agent-shell-gtd-capture--prompt)
     :submit t
     :shell-buffer shell)))

;;;###autoload
(defun agent-shell-gtd-capture-enable ()
  "Enable the English `Capture as GTD' agent-shell turn action."
  (interactive)
  (skill-agent-shell-register-turn-action
   'gtd-capture
   :function #'agent-shell-gtd-capture--turn-complete
   :command (lambda (shell-buffer _state)
              (agent-shell-gtd-capture shell-buffer))
   :label "Capture as GTD"
   :applicable-p #'agent-shell-gtd-capture--applicable-p
   :priority 40)
  (skill-agent-shell-bridge-enable))

;;;###autoload
(defun agent-shell-gtd-capture-disable ()
  "Disable the agent-shell GTD capture action."
  (interactive)
  (skill-agent-shell-unregister-turn-action 'gtd-capture))

(provide 'agent-shell-gtd-capture)

;;; agent-shell-gtd-capture.el ends here
