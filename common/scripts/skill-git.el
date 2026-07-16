;;; skill-git.el --- Shared, path-scoped Git helpers for local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)
(require 'rx)

(declare-function magit-call-git "magit-process" (&rest args))
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
    (or (apply #'magit-git-string args) "")))

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

(defun skill-git-commit-paths
    (root subject paths &optional predicate description)
  "Commit explicit PATHS in ROOT with SUBJECT and return a result plist."
  (unless (and (stringp subject) (not (string-empty-p subject))
               (not (string-match-p "[\n\r]" subject)))
    (error "Git SUBJECT must be non-empty and contain no newline"))
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
    (unless (zerop (magit-call-git "commit" "--only" "-m" subject "--"
                                   relative-paths))
      (error "Magit failed to create the path-scoped commit"))
    (list :commit (magit-git-string "rev-parse" "--short" "HEAD")
          :subject subject
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
