;;; skill-git.el --- Shared, path-scoped Git helpers for local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)
(require 'rx)
(require 'seq)

(defgroup skill-git nil
  "Shared Git behavior for local skills."
  :group 'tools)

(defcustom skill-git-message-column 100
  "Fill and hard-limit column for generated commit messages."
  :type 'positive-integer
  :group 'skill-git)

(defconst skill-git--body-label-regexp
  (concat "\\(?:\\`\\|\n\\)"
          "\\(?:Context\\|Changes\\|Reason\\|Validation\\|Boundary"
          "\\|背景\\|变更\\|原因\\|验证\\|边界\\):")
  "Section labels rejected from natural commit bodies.")

(defconst skill-git--message-placeholders
  '("修复的模块" "摘要" "详细描述")
  "Placeholder text rejected from generated commit messages.")

(declare-function magit-call-git "magit-process" (&rest args))
(declare-function magit-git-lines "magit-git" (&rest args))
(declare-function magit-git-string "magit-git" (&rest args))
(declare-function magit-git-success "magit-git" (&rest args))
(declare-function magit-toplevel "magit-git" (&optional directory))

(defun skill-git-directory (directory)
  "Return DIRECTORY expanded as an absolute directory name."
  (file-name-as-directory (expand-file-name directory)))

(defun skill-git--require-magit ()
  "Require Magit or signal a useful error."
  (unless (require 'magit nil t)
    (error "Magit is not available in this Emacs session")))

(defun skill-git-root (directory)
  "Return the repository root containing DIRECTORY."
  (skill-git--require-magit)
  (let* ((expanded (skill-git-directory directory))
         (root (and (file-directory-p expanded)
                    (magit-toplevel expanded))))
    (unless root
      (error "Not inside a Git repository: %s" expanded))
    (file-name-as-directory (file-truename root))))

(defun skill-git-remote-url (root &optional remote)
  "Return REMOTE's URL in repository ROOT.  REMOTE defaults to origin."
  (let* ((default-directory (skill-git-root root))
         (name (or remote "origin"))
         (url (magit-git-string "remote" "get-url" name)))
    (unless (and url (not (string-empty-p url)))
      (error "Git remote has no URL: %s" name))
    url))

(defun skill-git-assert-remote (root expected-url &optional remote)
  "Require REMOTE in ROOT to equal EXPECTED-URL and return its URL."
  (let ((actual (skill-git-remote-url root remote)))
    (unless (string= actual expected-url)
      (error "Refusing unexpected Git remote: expected %s, got %s"
             expected-url actual))
    actual))

(defun skill-git-status (root &optional paths)
  "Return porcelain status text for ROOT, optionally restricted to PATHS."
  (let* ((default-directory (skill-git-root root))
         (args (append '("status" "--porcelain=v1" "--untracked-files=all")
                       (and paths (cons "--" paths)))))
    (string-join (apply #'magit-git-lines args) "\n")))

(defun skill-git-assert-clean (root)
  "Require ROOT to have no tracked, staged, or untracked changes."
  (let ((status (skill-git-status root)))
    (unless (string-empty-p status)
      (error "Refusing dirty Git worktree in %s:\n%s"
             (skill-git-root root) status)))
  t)

(defun skill-git-ensure-repository (remote-url directory)
  "Return a plist for DIRECTORY, cloning REMOTE-URL when it is absent.

Refuse an existing non-repository directory or a repository whose origin URL
does not exactly match REMOTE-URL."
  (skill-git--require-magit)
  (let* ((target (skill-git-directory directory))
         (existed (file-exists-p target)))
    (if existed
        (unless (file-directory-p target)
          (error "Repository path is not a directory: %s" target))
      (make-directory (file-name-directory (directory-file-name target)) t)
      (let ((default-directory
             (file-name-directory (directory-file-name target))))
        (unless (zerop
                 (magit-call-git "clone" "--origin" "origin" "--"
                                 remote-url (directory-file-name target)))
          (error "Git clone failed: %s -> %s" remote-url target))))
    (let ((root (skill-git-root target)))
      (unless (string= (file-truename (directory-file-name root))
                       (file-truename (directory-file-name target)))
        (error "Repository path resolves inside another repository: %s" target))
      (skill-git-assert-remote root remote-url)
      (list :git-root root :remote-url remote-url :cloned (not existed)))))

(defun skill-git-pull-ff-only (root)
  "Fast-forward ROOT from its configured upstream."
  (let ((default-directory (skill-git-root root)))
    (unless (zerop (magit-call-git "pull" "--ff-only"))
      (error "Git pull --ff-only failed in %s" default-directory)))
  t)

(defun skill-git-upstream-ahead-count (root)
  "Return how many commits ROOT is ahead of its configured upstream."
  (let* ((default-directory (skill-git-root root))
         (value (magit-git-string "rev-list" "--count"
                                  "@{upstream}..HEAD")))
    (unless (and value
                 (string-match-p (rx string-start (+ digit) string-end) value))
      (error "Current branch has no usable Git upstream in %s"
             default-directory))
    (string-to-number value)))

(defun skill-git-relative-path (root path &optional predicate description)
  "Return repository-relative PATH below ROOT.

Require PATH to be a regular file.  When PREDICATE is non-nil, it receives the
relative path and must return non-nil.  DESCRIPTION explains that constraint."
  (unless (and (stringp path) (file-regular-p path))
    (error "Commit path is not a regular file: %S" path))
  (let* ((git-root (skill-git-root root))
         (relative (file-relative-name (file-truename path) git-root)))
    (when (or (string= relative "..") (string-prefix-p "../" relative))
      (error "Refusing path outside repository: %s" path))
    (when (and predicate (not (funcall predicate relative)))
      (error "Refusing path outside %s: %s"
             (or description "the allowed path set") path))
    relative))

(defun skill-git--required-text (value label)
  "Return trimmed non-empty VALUE or signal an error naming LABEL."
  (unless (and (stringp value)
               (not (string-empty-p (string-trim value))))
    (error "%s must be a non-empty string" label))
  (string-trim value))

(defun skill-git--single-line (value label &optional optional)
  "Validate single-line VALUE for LABEL; permit nil when OPTIONAL."
  (when (or value (not optional))
    (unless (and (stringp value)
                 (not (string-empty-p value))
                 (not (string-match-p "[\n\r]" value)))
      (error "%s must be a non-empty single-line string" label)))
  value)

(defun skill-git--fill (text &optional prefix)
  "Fill TEXT to `skill-git-message-column', optionally with PREFIX."
  (with-temp-buffer
    (text-mode)
    (setq-local fill-column skill-git-message-column)
    (insert (or prefix "") (string-trim text))
    (fill-region (point-min) (point-max))
    (string-trim-right (buffer-string))))

(defun skill-git--changes (changes)
  "Return validated non-empty commit CHANGES."
  (unless (and (listp changes) changes
               (seq-every-p
                (lambda (change)
                  (and (stringp change)
                       (not (string-empty-p (string-trim change)))))
                changes))
    (error "CHANGES must be a non-empty list of non-empty strings"))
  (mapcar #'string-trim changes))

(defun skill-git--subject (type scope summary)
  "Return a validated conventional subject from TYPE, SCOPE, and SUMMARY."
  (skill-git--single-line type "TYPE")
  (skill-git--single-line summary "SUMMARY")
  (skill-git--single-line scope "SCOPE" t)
  (unless (string-match-p "\\`[a-z][a-z0-9-]*\\'" type)
    (error "TYPE must be lowercase conventional-commit text: %S" type))
  (when (and scope
             (not (string-match-p "\\`[a-z][a-z0-9-]*\\'" scope)))
    (error "SCOPE must be lowercase English text: %S" scope))
  (if scope
      (format "%s(%s): %s" type scope summary)
    (format "%s: %s" type summary)))

(defun skill-git--detail (spec changes)
  "Resolve adaptive message detail from SPEC and CHANGES."
  (let ((detail (or (plist-get spec :detail) 'auto))
        (risk (or (plist-get spec :risk) 'medium)))
    (unless (memq detail '(auto compact full))
      (error "DETAIL must be auto, compact, or full: %S" detail))
    (unless (memq risk '(low medium high))
      (error "RISK must be low, medium, or high: %S" risk))
    (if (eq detail 'auto)
        (if (or (and (eq risk 'low) (<= (length changes) 2))
                (and (eq risk 'medium) (= (length changes) 1)))
            'compact
          'full)
      detail)))

(defun skill-git--trailers (spec)
  "Return evidence-backed optional trailers from SPEC."
  (let (trailers)
    (dolist (pair `(("Log" . ,(plist-get spec :log))
                    ("PMS" . ,(plist-get spec :pms))
                    ("Influence" . ,(plist-get spec :influence))))
      (when (cdr pair)
        (skill-git--single-line (cdr pair) (car pair))
        (push (skill-git--fill (format "%s: %s" (car pair) (cdr pair)))
              trailers)))
    (string-join (nreverse trailers) "\n")))

(defun skill-git-format-message (spec)
  "Return a natural, evidence-backed commit message from structured SPEC.

Require :type, :summary, :context, :changes, :reason, :validation, and
:boundary.  :scope, :risk, :detail, and trailers are optional.  Adaptive
detail is compact only for low-risk changes containing at most two items."
  (unless (listp spec)
    (error "SPEC must be a plist"))
  (let* ((changes (skill-git--changes (plist-get spec :changes)))
         (context (skill-git--required-text
                   (plist-get spec :context) "CONTEXT"))
         (reason (skill-git--required-text
                  (plist-get spec :reason) "REASON"))
         (validation (skill-git--required-text
                      (plist-get spec :validation) "VALIDATION"))
         (boundary (skill-git--required-text
                    (plist-get spec :boundary) "BOUNDARY"))
         (detail (skill-git--detail spec changes))
         (body
          (string-join
           (if (eq detail 'compact)
               (list (skill-git--fill context)
                     (string-join
                      (mapcar (lambda (change)
                                (skill-git--fill change "- "))
                              changes)
                      "\n")
                     (skill-git--fill (concat reason " " validation)))
             (list (skill-git--fill context)
                   (string-join
                    (mapcar (lambda (change)
                              (skill-git--fill change "- "))
                            changes)
                    "\n")
                   (skill-git--fill reason)
                   (skill-git--fill validation)
                   (skill-git--fill boundary)))
           "\n\n"))
         (trailers (skill-git--trailers spec))
         (message
          (string-join
           (delq nil
                 (list (skill-git--subject
                        (plist-get spec :type)
                        (plist-get spec :scope)
                        (plist-get spec :summary))
                       body
                       (and (not (string-empty-p trailers)) trailers)))
           "\n\n")))
    (when (string-match-p skill-git--body-label-regexp body)
      (error "Commit body must not contain structural section labels"))
    (dolist (placeholder skill-git--message-placeholders)
      (when (string-match-p (regexp-quote placeholder) message)
        (error "Commit message contains placeholder: %s" placeholder)))
    (dolist (line (split-string message "\n"))
      (when (> (string-width line) skill-git-message-column)
        (error "Commit message line exceeds %d columns: %s"
               skill-git-message-column line)))
    message))

(defun skill-git-commit-paths
    (root message paths &optional predicate description)
  "Commit explicit PATHS in ROOT with full MESSAGE and return a result plist."
  (unless (and (stringp message) (not (string-empty-p message))
               (not (string-match-p "\r" message)))
    (error "Git MESSAGE must be non-empty and contain no carriage return"))
  (unless (and (listp paths) paths)
    (error "Git PATHS must be a non-empty list"))
  (let* ((git-root (skill-git-root root))
         (default-directory git-root)
         (relative-paths
          (delete-dups
           (mapcar (lambda (path)
                     (skill-git-relative-path git-root path
                                              predicate description))
                   paths))))
    (unless (zerop (magit-call-git "add" "--" relative-paths))
      (error "Magit failed to stage the explicit path set"))
    (when (magit-git-success "diff" "--cached" "--quiet" "--"
                             relative-paths)
      (error "No changes to commit in the explicit path set"))
    (unless (zerop (magit-call-git "commit" "--only" "-m" message "--"
                                   relative-paths))
      (error "Magit failed to create the path-scoped commit"))
    (list :commit (magit-git-string "rev-parse" "--short" "HEAD")
          :subject (car (split-string message "\n"))
          :message message
          :paths relative-paths)))

(defun skill-git-push (root)
  "Push ROOT's current branch to its configured upstream."
  (let ((default-directory (skill-git-root root)))
    (unless (zerop (magit-call-git "push" "--porcelain"))
      (error "Git push failed in %s" default-directory))
    (list :git-root default-directory
          :commit (magit-git-string "rev-parse" "--short" "HEAD"))))

(provide 'skill-git)

;;; skill-git.el ends here
