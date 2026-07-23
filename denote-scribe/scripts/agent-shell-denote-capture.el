;;; agent-shell-denote-capture.el --- Capture linked research notes -*- lexical-binding: t; -*-

;;; Commentary:

;; Offer an English-labeled agent-shell action that drafts a critical Denote
;; note and optional follow-up GTD tasks.  All mutations wait for explicit user
;; confirmation; the prompt links GTD resources to the note and GTD IDs back
;; into the note.

;;; Code:

(require 'subr-x)

(let ((root (file-name-directory (or load-file-name buffer-file-name))))
  (unless (featurep 'denote-scribe)
    (load (expand-file-name "denote-scribe.el" root) nil nil t))
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

(defgroup agent-shell-denote-capture nil
  "Capture agent-shell research as linked Denote and GTD records."
  :group 'denote-scribe)

(defcustom agent-shell-denote-capture-suppressed-turns 3
  "Turns hidden after starting capture to avoid recursive suggestions."
  :type 'natnum
  :group 'agent-shell-denote-capture)

(defvar agent-shell-denote-capture-last-shell-buffer nil
  "Most recent agent-shell buffer offering Denote capture.")

(defvar-local agent-shell-denote-capture--suppress-count 0
  "Number of upcoming completed turns that should hide Denote capture.")

(defun agent-shell-denote-capture--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the most recent capture shell."
  (let ((buffer (or shell-buffer
                    (and (derived-mode-p 'agent-shell-mode)
                         (current-buffer))
                    agent-shell-denote-capture-last-shell-buffer)))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

(defun agent-shell-denote-capture--applicable-p (shell-buffer state)
  "Return non-nil when SHELL-BUFFER and completed STATE can offer capture."
  (with-current-buffer shell-buffer
    (if (> agent-shell-denote-capture--suppress-count 0)
        (progn
          (setq agent-shell-denote-capture--suppress-count
                (1- agent-shell-denote-capture--suppress-count))
          nil)
      (member (plist-get state :stop-reason) '(nil "end_turn")))))

(defun agent-shell-denote-capture--turn-complete (shell-buffer _state)
  "Remember SHELL-BUFFER as the latest Denote capture source."
  (setq agent-shell-denote-capture-last-shell-buffer shell-buffer))

(defun agent-shell-denote-capture--prompt ()
  "Return the confirmed bidirectional Denote/GTD capture request."
  (concat
   "Use $denote-scribe and, when useful, $emacs-gtd-assistant to prepare a "
   "durable research capture from your immediately previous answer and our "
   "current discussion. Do not create or modify any file yet.\n\n"
   "First present an editable proposal in the conversation language: a concrete "
   "Denote title, language, keywords, compact evidence-backed coverage of every "
   "required critical-note section, relevant HTTP/document/file references, "
   "and zero to three concrete follow-up GTD candidates. Separate evidence from "
   "inference, include counter-evidence and uncertainty, and do not preserve "
   "the full transcript. Ask me to edit or explicitly confirm the note and the "
   "selected tasks.\n\n"
   "Only after explicit confirmation:\n"
   "1. Request the exact critical template, create a temporary body file, and "
   "call `denote-scribe-run' with `:operation capture' and "
   "`:authorization explicit'.\n"
   "2. If I confirmed follow-up tasks, call `emacs-gtd-execute' with "
   "`:operation add-many' and `:authorization explicit'. Add the returned "
   "Denote note as a structured `file:' resource link on every task and store "
   "SOURCE=agent-shell plus DENOTE_FILE in safe properties.\n"
   "3. Call `denote-scribe-run' with `:operation link-gtd', the created note "
   "file, the returned GTD IDs and titles, and `:authorization explicit' so "
   "the note links back with `id:' links.\n\n"
   "Do not create HyWiki pages, commit, push, or create unconfirmed tasks. If a "
   "later linking step fails after an earlier write, report the exact partial "
   "state and offer a repair; never claim atomic success across both files."))

;;;###autoload
(defun agent-shell-denote-capture (&optional shell-buffer)
  "Ask the same agent to prepare a linked Denote and optional GTD capture."
  (interactive)
  (let ((shell (agent-shell-denote-capture--shell-buffer shell-buffer)))
    (with-current-buffer shell
      (setq agent-shell-denote-capture--suppress-count
            agent-shell-denote-capture-suppressed-turns))
    (agent-shell-insert
     :text (agent-shell-denote-capture--prompt)
     :submit t
     :shell-buffer shell)))

;;;###autoload
(defun agent-shell-denote-capture-enable ()
  "Enable the English `Capture as Denote' agent-shell turn action."
  (interactive)
  (skill-agent-shell-register-turn-action
   'denote-capture
   :function #'agent-shell-denote-capture--turn-complete
   :command (lambda (shell-buffer _state)
              (agent-shell-denote-capture shell-buffer))
   :label "Capture as Denote"
   :applicable-p #'agent-shell-denote-capture--applicable-p
   :priority 30)
  (skill-agent-shell-bridge-enable))

;;;###autoload
(defun agent-shell-denote-capture-disable ()
  "Disable the agent-shell Denote capture action."
  (interactive)
  (skill-agent-shell-unregister-turn-action 'denote-capture))

(provide 'agent-shell-denote-capture)

;;; agent-shell-denote-capture.el ends here
