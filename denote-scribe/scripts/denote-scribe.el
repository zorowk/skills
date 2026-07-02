;;; denote-scribe.el --- Create Denote reports from AI conversations -*- lexical-binding: t; -*-

;; This file is intended to be loaded into the user's running Emacs
;; through emacsclient or from init.el.

;;; Code:

(defgroup denote-scribe nil
  "Create Denote reports from AI conversation summaries."
  :group 'denote)

(defcustom denote-scribe-notes-directory "~/Dropbox/notes/"
  "Directory where `denote-scribe-create' creates Denote notes."
  :type 'directory
  :group 'denote-scribe)

(defvar denote-directory)
(defvar denote-save-buffers)
(declare-function denote "denote")

(defun denote-scribe--nonempty (value)
  "Return VALUE when it is a non-empty string, otherwise nil."
  (and (stringp value) (not (string= value "")) value))

(defun denote-scribe-preflight (&optional notes-dir)
  "Return a plist describing whether Denote report creation is available."
  (let* ((target-dir (file-name-as-directory
                      (expand-file-name
                       (or (denote-scribe--nonempty notes-dir)
                           denote-scribe-notes-directory))))
         (denote-available (require 'denote nil t))
         (errors nil))
    (unless (file-directory-p target-dir)
      (push (format "Notes directory does not exist: %s" target-dir) errors))
    (unless denote-available
      (push "Denote is not available in this Emacs session" errors))
    (list :notes-directory target-dir
          :notes-directory-exists (file-directory-p target-dir)
          :denote-available (and denote-available t)
          :errors (nreverse errors))))

(defun denote-scribe--result-file (result)
  "Return a file path from Denote RESULT or the current buffer."
  (cond
   ((stringp result) result)
   ((buffer-file-name) (buffer-file-name))
   (t nil)))

;;;###autoload
(defun denote-scribe-create (title body-file &optional keywords notes-dir signature date)
  "Create an Org Denote report with TITLE and insert BODY-FILE.

KEYWORDS is a list of strings.  When nil, use (\"ai\" \"report\").
NOTES-DIR overrides `denote-scribe-notes-directory'.
SIGNATURE and DATE are passed to Denote when non-nil.

Return the created file path."
  (unless (and (stringp title) (not (string= title "")))
    (error "TITLE must be a non-empty string"))
  (unless (and (stringp body-file) (file-readable-p body-file))
    (error "BODY-FILE is not readable: %S" body-file))
  (require 'denote)
  (let* ((target-dir (file-name-as-directory
                      (file-truename
                       (expand-file-name
                        (or (denote-scribe--nonempty notes-dir)
                            denote-scribe-notes-directory)))))
         (denote-directory target-dir)
         (denote-save-buffers t)
         (keyword-list (or keywords '("ai" "report")))
         (file (denote-scribe--result-file
                (denote title keyword-list 'org target-dir date nil signature nil))))
    (unless file
      (error "Denote did not return or visit a file"))
    (find-file file)
    (goto-char (point-max))
    (unless (bolp)
      (insert "\n"))
    (insert "\n")
    (insert-file-contents body-file)
    (save-buffer)
    file))

(provide 'denote-scribe)

;;; denote-scribe.el ends here
