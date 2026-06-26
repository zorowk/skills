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

(defcustom denote-scribe-extra-load-paths
  '("~/.emacs.d/straight/build/denote"
    "~/.emacs.d/straight/repos/denote")
  "Extra directories to add to `load-path' before requiring Denote."
  :type '(repeat directory)
  :group 'denote-scribe)

(defun denote-scribe--ensure-denote ()
  "Ensure Denote is available in the current Emacs session."
  (dolist (dir denote-scribe-extra-load-paths)
    (let ((expanded (expand-file-name dir)))
      (when (file-directory-p expanded)
        (add-to-list 'load-path expanded))))
  (unless (or (fboundp 'denote)
              (require 'denote nil t)
              (fboundp 'denote))
    (error "Denote is unavailable in this Emacs server: pid=%s server-name=%S locate-library=%S"
           (emacs-pid) server-name (locate-library "denote"))))

(defun denote-scribe--nonempty (value)
  "Return VALUE when it is a non-empty string, otherwise nil."
  (and (stringp value) (not (string= value "")) value))

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
  (denote-scribe--ensure-denote)
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
