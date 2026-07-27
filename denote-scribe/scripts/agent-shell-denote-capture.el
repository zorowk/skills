;;; agent-shell-denote-capture.el --- Capture linked research notes -*- lexical-binding: t; -*-

;;; Commentary:

;; Provide an explicit command that drafts a critical Denote note and optional
;; follow-up GTD tasks.  All mutations wait for explicit user confirmation; the
;; prompt links GTD resources to the note and GTD IDs back into the note.

;;; Code:

(declare-function agent-shell-insert "agent-shell" (&rest arguments))

(defgroup agent-shell-denote-capture nil
  "Capture agent-shell research as linked Denote and GTD records."
  :group 'tools)

(defun agent-shell-denote-capture--shell-buffer (&optional shell-buffer)
  "Return a live SHELL-BUFFER or the current agent-shell buffer."
  (let ((buffer (or shell-buffer
                    (and (derived-mode-p 'agent-shell-mode)
                         (current-buffer)))))
    (unless (buffer-live-p buffer)
      (user-error "No live agent-shell conversation is available"))
    buffer))

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
   "the full transcript. Proactively propose GTD candidates when the evidence "
   "reveals important actionable follow-up; do not require a separate capture "
   "request. Ask me to edit or explicitly confirm the note and selected "
   "tasks.\n\n"
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
    (agent-shell-insert
     :text (agent-shell-denote-capture--prompt)
     :submit t
     :shell-buffer shell)))

(provide 'agent-shell-denote-capture)

;;; agent-shell-denote-capture.el ends here
