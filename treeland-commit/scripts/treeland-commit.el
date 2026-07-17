;;; treeland-commit.el --- Format Treeland commit messages -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)

(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-toplevel "magit-git" (&optional directory))

(defgroup treeland-commit nil
  "Format Treeland commit messages."
  :group 'tools)

(defcustom treeland-commit-fill-column 100
  "Column used to fill commit-message prose."
  :type 'positive-integer
  :group 'treeland-commit)

(defcustom treeland-commit-maximum-column 120
  "Maximum permitted line length in a formatted message."
  :type 'positive-integer
  :group 'treeland-commit)

(defcustom treeland-commit-context-maximum-characters 30000
  "Maximum characters retained for each diff in commit context."
  :type 'positive-integer
  :group 'treeland-commit)

(defconst treeland-commit--placeholders
  '("修复的模块" "摘要" "详细描述")
  "Placeholder text rejected from formatted messages.")

(defun treeland-commit--single-line (value label &optional optional)
  "Validate single-line VALUE for LABEL; permit nil when OPTIONAL."
  (when (or value (not optional))
    (unless (and (stringp value)
                 (not (string-empty-p value))
                 (not (string-match-p "[\n\r]" value)))
      (error "%s must be a non-empty single-line string" label)))
  value)

(defun treeland-commit--fill (text)
  "Return TEXT filled as plain commit-message prose."
  (with-temp-buffer
    (text-mode)
    (setq-local fill-column treeland-commit-fill-column)
    (insert (string-trim text))
    (fill-region (point-min) (point-max))
    (string-trim-right (buffer-string))))

(defun treeland-commit--validate-result (message)
  "Validate formatted Treeland commit MESSAGE and return it."
  (dolist (placeholder treeland-commit--placeholders)
    (when (string-match-p (regexp-quote placeholder) message)
      (error "Commit message contains placeholder: %s" placeholder)))
  (dolist (line (split-string message "\n"))
    (when (> (string-width line) treeland-commit-maximum-column)
      (error "Commit message line exceeds %d columns: %s"
             treeland-commit-maximum-column line)))
  message)

(defun treeland-commit--field (label value)
  "Return filled LABEL field containing optional VALUE."
  (if value
      (treeland-commit--fill (format "%s: %s" label value))
    (concat label ":")))

(defun treeland-commit--git-output (&rest arguments)
  "Return complete Git output for ARGUMENTS through Magit."
  (with-temp-buffer
    (unless (zerop (apply #'magit-git-insert arguments))
      (error "Git command failed: git %s" (string-join arguments " ")))
    (string-trim-right (buffer-string))))

(defun treeland-commit--truncate-context (text)
  "Return TEXT capped for compact commit-message evidence."
  (if (<= (length text) treeland-commit-context-maximum-characters)
      text
    (concat
     (substring text 0 treeland-commit-context-maximum-characters)
     "\n[diff truncated by treeland-commit-context]")))

;;;###autoload
(defun treeland-commit-context (&optional directory)
  "Return Git evidence needed to draft a commit message for DIRECTORY.

Use the repository containing DIRECTORY or `default-directory'.  The returned
plist contains complete porcelain status and diff statistics, plus capped
unstaged and staged diffs.  Git is invoked through the running Emacs session's
Magit configuration."
  (unless (require 'magit nil t)
    (error "Magit is not available in this Emacs session"))
  (let* ((root (magit-toplevel (or directory default-directory))))
    (unless root
      (error "Not inside a Git repository: %s"
             (expand-file-name (or directory default-directory))))
    (let ((default-directory root))
      (list :git-root root
            :status (treeland-commit--git-output
                     "status" "--porcelain=v1" "--untracked-files=all")
            :unstaged-stat (treeland-commit--git-output "diff" "--stat")
            :staged-stat (treeland-commit--git-output
                          "diff" "--cached" "--stat")
            :unstaged-diff
            (treeland-commit--truncate-context
             (treeland-commit--git-output "diff" "--no-ext-diff"))
            :staged-diff
            (treeland-commit--truncate-context
             (treeland-commit--git-output
              "diff" "--cached" "--no-ext-diff"))))))

;;;###autoload
(defun treeland-commit-format
    (type module summary body log &optional pms influence)
  "Return a validated Treeland commit message.

TYPE and MODULE form the conventional subject.  BODY explains the changes.
LOG is a concise summary.  PMS and INFLUENCE may be nil when unknown."
  (dolist (pair `((,type . "TYPE") (,module . "MODULE")
                  (,summary . "SUMMARY") (,log . "LOG")))
    (treeland-commit--single-line (car pair) (cdr pair)))
  (treeland-commit--single-line pms "PMS" t)
  (treeland-commit--single-line influence "INFLUENCE" t)
  (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" type)
    (error "TYPE must be lowercase conventional-commit text: %S" type))
  (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" module)
    (error "MODULE must be a lowercase English scope: %S" module))
  (unless (and (stringp body) (not (string-empty-p (string-trim body))))
    (error "BODY must contain the change rationale"))
  (treeland-commit--validate-result
   (format "%s(%s): %s\n\n%s\n\n%s\n%s\n%s"
           type module summary (treeland-commit--fill body)
           (treeland-commit--field "Log" log)
           (treeland-commit--field "PMS" pms)
           (treeland-commit--field "Influence" influence))))

(provide 'treeland-commit)

;;; treeland-commit.el ends here
