;;; ai-git-commit.el --- Evidence-backed Git messages for AI skills -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)
(require 'seq)

(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-git-success "magit-git" (&rest args))
(declare-function magit-toplevel "magit-git" (&optional directory))

(define-obsolete-variable-alias
  'treeland-commit-fill-column 'ai-git-commit-fill-column "2026-07-17")
(define-obsolete-variable-alias
  'treeland-commit-maximum-column 'ai-git-commit-maximum-column "2026-07-17")
(define-obsolete-variable-alias
  'treeland-commit-context-maximum-characters
  'ai-git-commit-context-maximum-characters "2026-07-17")
(define-obsolete-variable-alias
  'treeland-commit-compact-maximum-characters
  'ai-git-commit-compact-maximum-characters "2026-07-17")

(defgroup ai-git-commit nil
  "Format Git commit messages."
  :group 'tools)

(defcustom ai-git-commit-fill-column 100
  "Column used to fill commit-message prose."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-maximum-column 100
  "Maximum permitted line length in a formatted message."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-context-maximum-characters 30000
  "Maximum characters retained for each full-mode commit diff."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-compact-maximum-characters 12000
  "Maximum characters retained for compact combined commit diff context."
  :type 'positive-integer
  :group 'ai-git-commit)

(defconst ai-git-commit--placeholders
  '("修复的模块" "摘要" "详细描述")
  "Placeholder text rejected from formatted messages.")

(defconst ai-git-commit--body-label-regexp
  (concat "\\(?:\\`\\|\n\\)"
          "\\(?:Context\\|Changes\\|Reason\\|Validation\\|Boundary"
          "\\|背景\\|变更\\|原因\\|验证\\|边界\\):")
  "Section labels rejected from naturally structured commit bodies.")

(defun ai-git-commit--single-line (value label &optional optional)
  "Validate single-line VALUE for LABEL; permit nil when OPTIONAL."
  (when (or value (not optional))
    (unless (and (stringp value)
                 (not (string-empty-p value))
                 (not (string-match-p "[\n\r]" value)))
      (error "%s must be a non-empty single-line string" label)))
  value)

(defun ai-git-commit--fill (text)
  "Return TEXT filled as plain commit-message prose."
  (with-temp-buffer
    (text-mode)
    (setq-local fill-column ai-git-commit-fill-column)
    (insert (string-trim text))
    (fill-region (point-min) (point-max))
    (string-trim-right (buffer-string))))

(defun ai-git-commit--fill-bullet (text)
  "Return TEXT as a filled commit-message bullet."
  (with-temp-buffer
    (text-mode)
    (setq-local fill-column ai-git-commit-fill-column)
    (insert "- " (string-trim text))
    (fill-region (point-min) (point-max))
    (string-trim-right (buffer-string))))

(defun ai-git-commit--validate-result (message)
  "Validate formatted Git commit MESSAGE and return it."
  (dolist (placeholder ai-git-commit--placeholders)
    (when (string-match-p (regexp-quote placeholder) message)
      (error "Commit message contains placeholder: %s" placeholder)))
  (dolist (line (split-string message "\n"))
    (when (> (string-width line) ai-git-commit-maximum-column)
      (error "Commit message line exceeds %d columns: %s"
             ai-git-commit-maximum-column line)))
  message)

(defun ai-git-commit--field (label value)
  "Return filled LABEL field containing optional VALUE."
  (if value
      (ai-git-commit--fill (format "%s: %s" label value))
    (concat label ":")))

(defun ai-git-commit--git-output (&rest arguments)
  "Return complete Git output for ARGUMENTS through Magit."
  (with-temp-buffer
    (unless (zerop (apply #'magit-git-insert arguments))
      (error "Git command failed: git %s" (string-join arguments " ")))
    (string-trim-right (buffer-string))))

(defun ai-git-commit--truncate-context (text &optional maximum)
  "Return TEXT capped at MAXIMUM for commit-message evidence."
  (let ((limit (or maximum ai-git-commit-context-maximum-characters)))
    (if (<= (length text) limit)
        text
      (concat
       (substring text 0 limit)
       "\n[diff truncated by ai-git-commit-context]"))))

;;;###autoload
(defun ai-git-commit-context (&optional directory compact)
  "Return Git evidence needed to draft a commit message for DIRECTORY.

Use the repository containing DIRECTORY or `default-directory'.  Preserve the
original separate unstaged and staged diffs by default.  When COMPACT is
non-nil, return status, statistics, change count, and one bounded diff against
HEAD.  Git uses the running Emacs session's Magit settings."
  (unless (require 'magit nil t)
    (error "Magit is not available in this Emacs session"))
  (let* ((root (magit-toplevel (or directory default-directory))))
    (unless root
      (error "Not inside a Git repository: %s"
             (expand-file-name (or directory default-directory))))
    (let* ((default-directory root)
           (status (ai-git-commit--git-output
                    "status" "--porcelain=v1" "--untracked-files=all"))
           (unstaged-stat (ai-git-commit--git-output "diff" "--stat"))
           (staged-stat (ai-git-commit--git-output
                         "diff" "--cached" "--stat")))
      (if compact
          (let* ((has-head
                  (magit-git-success "rev-parse" "--verify" "HEAD"))
                 (combined
                  (if has-head
                      (ai-git-commit--git-output
                       "diff" "HEAD" "--no-ext-diff")
                    (string-join
                     (delq nil
                           (mapcar
                            (lambda (text)
                              (and (not (string-empty-p text)) text))
                            (list
                             (ai-git-commit--git-output
                              "diff" "--cached" "--no-ext-diff")
                             (ai-git-commit--git-output
                              "diff" "--no-ext-diff"))))
                     "\n"))))
            (list :git-root root
                  :status status
                  :change-count (length (split-string status "\n" t))
                  :unstaged-stat unstaged-stat
                  :staged-stat staged-stat
                  :diff-base (if has-head "HEAD" "index/worktree")
                  :diff
                  (ai-git-commit--truncate-context
                   combined ai-git-commit-compact-maximum-characters)))
        (list :git-root root
              :status status
              :unstaged-stat unstaged-stat
              :staged-stat staged-stat
              :unstaged-diff
              (ai-git-commit--truncate-context
               (ai-git-commit--git-output "diff" "--no-ext-diff"))
              :staged-diff
              (ai-git-commit--truncate-context
               (ai-git-commit--git-output
                "diff" "--cached" "--no-ext-diff")))))))

(defun ai-git-commit--required-text (value label)
  "Return trimmed non-empty VALUE or signal an error naming LABEL."
  (unless (and (stringp value)
               (not (string-empty-p (string-trim value))))
    (error "%s must be a non-empty string" label))
  (string-trim value))

(defun ai-git-commit--changes (changes)
  "Return validated non-empty commit CHANGES."
  (unless (and (listp changes) changes
               (seq-every-p
                (lambda (change)
                  (and (stringp change)
                       (not (string-empty-p (string-trim change)))))
                changes))
    (error "CHANGES must be a non-empty list of non-empty strings"))
  (mapcar #'string-trim changes))

(defun ai-git-commit--subject (type scope summary)
  "Return a validated conventional subject from TYPE, SCOPE, and SUMMARY."
  (ai-git-commit--single-line type "TYPE")
  (ai-git-commit--single-line summary "SUMMARY")
  (ai-git-commit--single-line scope "SCOPE" t)
  (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" type)
    (error "TYPE must be lowercase conventional-commit text: %S" type))
  (when (and scope
             (not (string-match-p "\\`[a-z][a-z0-9-]*\\'" scope)))
    (error "SCOPE must be lowercase English text: %S" scope))
  (if scope
      (format "%s(%s): %s" type scope summary)
    (format "%s: %s" type summary)))

(defun ai-git-commit--natural-body
    (context changes reason validation boundary)
  "Return an unlabeled body from structured commit evidence."
  (let ((body
         (string-join
          (list
           (ai-git-commit--fill
            (ai-git-commit--required-text context "CONTEXT"))
           (string-join
            (mapcar #'ai-git-commit--fill-bullet
                    (ai-git-commit--changes changes))
            "\n")
           (ai-git-commit--fill
            (ai-git-commit--required-text reason "REASON"))
           (ai-git-commit--fill
            (ai-git-commit--required-text validation "VALIDATION"))
           (ai-git-commit--fill
            (ai-git-commit--required-text boundary "BOUNDARY")))
          "\n\n")))
    (when (string-match-p ai-git-commit--body-label-regexp body)
      (error "Commit body must not contain structural section labels"))
    body))

(defun ai-git-commit--optional-trailers (log pms influence)
  "Return optional LOG, PMS, and INFLUENCE trailers."
  (let (trailers)
    (dolist (pair `(("Log" . ,log) ("PMS" . ,pms)
                    ("Influence" . ,influence)))
      (when (cdr pair)
        (ai-git-commit--single-line (cdr pair) (car pair))
        (push (ai-git-commit--field (car pair) (cdr pair)) trailers)))
    (string-join (nreverse trailers) "\n")))

;;;###autoload
(defun ai-git-commit-format (spec)
  "Return a validated, evidence-backed commit message from SPEC.

SPEC requires :type, :summary, :context, :changes, :reason, :validation,
and :boundary.  :scope and the :log, :pms, and :influence trailers are
optional.  The output body preserves that semantic order using natural
paragraphs and bullets without structural section labels."
  (unless (listp spec)
    (error "SPEC must be a plist"))
  (let* ((subject
          (ai-git-commit--subject
           (plist-get spec :type)
           (plist-get spec :scope)
           (plist-get spec :summary)))
         (body
          (ai-git-commit--natural-body
           (plist-get spec :context)
           (plist-get spec :changes)
           (plist-get spec :reason)
           (plist-get spec :validation)
           (plist-get spec :boundary)))
         (trailers
          (ai-git-commit--optional-trailers
           (plist-get spec :log)
           (plist-get spec :pms)
           (plist-get spec :influence))))
    (ai-git-commit--validate-result
     (string-join (delq nil
                        (list subject body
                              (and (not (string-empty-p trailers)) trailers)))
                  "\n\n"))))

;;;###autoload
(defun ai-git-commit-run (request)
  "Execute Git commit REQUEST through one compact public entry point.

Use :operation `context' with optional :directory and :full keys.  Use
:operation `format' with the structured keys accepted by `ai-git-commit-format'."
  (unless (listp request)
    (error "REQUEST must be a plist"))
  (let* ((operation (plist-get request :operation))
         (result
          (pcase operation
            ('context
             (ai-git-commit-context
              (plist-get request :directory)
              (not (plist-get request :full))))
            ('format (ai-git-commit-format request))
            (_ (error "Unknown Git commit operation: %S" operation)))))
    (list :status 'ok
          :operation operation
          :count (if (eq operation 'context)
                     (plist-get result :change-count)
                   1)
          :result result)))

;; Compatibility for callers that still use the former Treeland API.
(define-obsolete-function-alias
  'treeland-commit-context #'ai-git-commit-context "2026-07-17")

(defun treeland-commit-format
    (type module summary body log &optional pms influence)
  "Format the legacy Treeland commit fields through Git Commit validation."
  (dolist (pair `((,type . "TYPE") (,module . "MODULE")
                  (,summary . "SUMMARY") (,log . "LOG")))
    (ai-git-commit--single-line (car pair) (cdr pair)))
  (ai-git-commit--single-line pms "PMS" t)
  (ai-git-commit--single-line influence "INFLUENCE" t)
  (ai-git-commit--subject type module summary)
  (ai-git-commit--required-text body "BODY")
  (ai-git-commit--validate-result
   (format "%s(%s): %s\n\n%s\n\n%s\n%s\n%s"
           type module summary (ai-git-commit--fill body)
           (ai-git-commit--field "Log" log)
           (ai-git-commit--field "PMS" pms)
           (ai-git-commit--field "Influence" influence))))

(defun treeland-commit-run (request)
  "Execute legacy Treeland REQUEST through the Git Commit implementation."
  (pcase (plist-get request :operation)
    ('context (ai-git-commit-run request))
    ('format
     (list :status 'ok :operation 'format :count 1
           :result
           (treeland-commit-format
            (plist-get request :type)
            (plist-get request :module)
            (plist-get request :summary)
            (plist-get request :body)
            (plist-get request :log)
            (plist-get request :pms)
            (plist-get request :influence))))
    (_ (error "Unknown legacy Treeland operation: %S"
              (plist-get request :operation)))))

(provide 'ai-git-commit)
(provide 'treeland-commit)

;;; ai-git-commit.el ends here
