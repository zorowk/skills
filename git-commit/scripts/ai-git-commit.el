;;; ai-git-commit.el --- Evidence-backed Git messages for AI skills -*- lexical-binding: t; -*-

;;; Code:

(require 'subr-x)
(require 'seq)

(let ((common (expand-file-name "../../common/scripts/"
                                (file-name-directory
                                 (or load-file-name buffer-file-name)))))
  (unless (featurep 'skill-runtime)
    (load (expand-file-name "skill-runtime.el" common) nil nil t))
  (unless (featurep 'skill-git)
    (load (expand-file-name "skill-git.el" common) nil nil t)))

(defvar skill-git-message-column)
(declare-function skill-git--fill "../../common/scripts/skill-git"
                  (text &optional prefix))
(declare-function skill-git--required-text "../../common/scripts/skill-git"
                  (value label))
(declare-function skill-git--single-line "../../common/scripts/skill-git"
                  (value label &optional optional))
(declare-function skill-git--subject "../../common/scripts/skill-git"
                  (type scope summary))
(declare-function skill-git-format-message "../../common/scripts/skill-git"
                  (spec))
(declare-function skill-runtime-describe "../../common/scripts/skill-runtime"
                  (schemas &optional target))
(declare-function skill-runtime-result "../../common/scripts/skill-runtime"
                  (operation data &optional count status page effects))
(declare-function skill-runtime-truncate "../../common/scripts/skill-runtime"
                  (text maximum label))

(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-git-success "magit-git" (&rest args))
(declare-function magit-toplevel "magit-git" (&optional directory))

(defgroup ai-git-commit nil
  "Collect evidence for Git commit messages."
  :group 'skill-git)

(define-obsolete-variable-alias
  'treeland-commit-fill-column 'ai-git-commit-fill-column "2026-07-17")
(define-obsolete-variable-alias
  'treeland-commit-maximum-column 'ai-git-commit-maximum-column "2026-07-17")

(defcustom ai-git-commit-fill-column 100
  "Column used to fill commit-message prose."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-maximum-column 100
  "Maximum permitted line width in generated commit messages."
  :type 'positive-integer
  :group 'ai-git-commit)

(define-obsolete-variable-alias
  'treeland-commit-context-maximum-characters
  'ai-git-commit-context-maximum-characters "2026-07-17")
(define-obsolete-variable-alias
  'treeland-commit-compact-maximum-characters
  'ai-git-commit-compact-maximum-characters "2026-07-17")

(defcustom ai-git-commit-context-maximum-characters 30000
  "Maximum characters retained for each full-mode commit diff."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-compact-maximum-characters 12000
  "Maximum characters retained for compact combined commit context."
  :type 'positive-integer
  :group 'ai-git-commit)

(defconst ai-git-commit--schemas
  '((context :optional (:directory :full) :effects nil)
    (format :required (:type :summary :context :changes :reason :validation
                            :boundary)
            :optional (:scope :risk :detail :log :pms :influence)
            :effects nil)
    (describe :optional (:target) :effects nil))
  "Compact request schemas for `ai-git-commit-run'.")

(defun ai-git-commit--git-output (&rest arguments)
  "Return complete Git output for ARGUMENTS through Magit."
  (with-temp-buffer
    (unless (zerop (apply #'magit-git-insert arguments))
      (error "Git command failed: git %s" (string-join arguments " ")))
    (string-trim-right (buffer-string))))

(defun ai-git-commit--bounded-diff (text maximum label)
  "Return TEXT plus explicit truncation metadata for MAXIMUM and LABEL."
  (skill-runtime-truncate text maximum label))

;;;###autoload
(defun ai-git-commit-context (&optional directory compact)
  "Return Git evidence for DIRECTORY with explicit truncation metadata.

Use one combined bounded diff against HEAD when COMPACT is non-nil.  Otherwise
return separate staged and unstaged diffs."
  (unless (require 'magit nil t)
    (error "Magit is not available in this Emacs session"))
  (let ((root (magit-toplevel (or directory default-directory))))
    (unless root
      (error "Not inside a Git repository: %s"
             (expand-file-name (or directory default-directory))))
    (let* ((default-directory root)
           (status (ai-git-commit--git-output
                    "status" "--porcelain=v1" "--untracked-files=all"))
           (unstaged-stat (ai-git-commit--git-output "diff" "--stat"))
           (staged-stat (ai-git-commit--git-output "diff" "--cached" "--stat")))
      (if compact
          (let* ((has-head (magit-git-success "rev-parse" "--verify" "HEAD"))
                 (combined
                  (if has-head
                      (ai-git-commit--git-output "diff" "HEAD" "--no-ext-diff")
                    (string-join
                     (seq-remove
                      #'string-empty-p
                      (list
                       (ai-git-commit--git-output
                        "diff" "--cached" "--no-ext-diff")
                       (ai-git-commit--git-output "diff" "--no-ext-diff")))
                     "\n")))
                 (bounded
                  (ai-git-commit--bounded-diff
                   combined ai-git-commit-compact-maximum-characters 'diff)))
            (list :git-root root
                  :status status
                  :change-count (length (split-string status "\n" t))
                  :unstaged-stat unstaged-stat
                  :staged-stat staged-stat
                  :diff-base (if has-head "HEAD" "index/worktree")
                  :diff (plist-get bounded :text)
                  :truncated (plist-get bounded :truncated)
                  :original-length (plist-get bounded :original-length)))
        (let* ((unstaged
                (ai-git-commit--bounded-diff
                 (ai-git-commit--git-output "diff" "--no-ext-diff")
                 ai-git-commit-context-maximum-characters 'unstaged-diff))
               (staged
                (ai-git-commit--bounded-diff
                 (ai-git-commit--git-output
                  "diff" "--cached" "--no-ext-diff")
                 ai-git-commit-context-maximum-characters 'staged-diff)))
          (list :git-root root
                :status status
                :change-count (length (split-string status "\n" t))
                :unstaged-stat unstaged-stat
                :staged-stat staged-stat
                :unstaged-diff (plist-get unstaged :text)
                :unstaged-truncated (plist-get unstaged :truncated)
                :staged-diff (plist-get staged :text)
                :staged-truncated (plist-get staged :truncated)))))))

;;;###autoload
(defun ai-git-commit-format (spec)
  "Return a validated adaptive commit message from structured SPEC."
  (let ((skill-git-message-column ai-git-commit-fill-column))
    (let ((message (skill-git-format-message spec)))
      (dolist (line (split-string message "\n"))
        (when (> (string-width line) ai-git-commit-maximum-column)
          (error "Commit line exceeds %d columns" ai-git-commit-maximum-column)))
      message)))

;;;###autoload
(defun ai-git-commit-run (request)
  "Execute compact Git commit REQUEST and return a standard envelope."
  (unless (listp request)
    (error "REQUEST must be a plist"))
  (let ((operation (plist-get request :operation)))
    (pcase operation
      ('describe
       (skill-runtime-result
        operation
        (skill-runtime-describe
         ai-git-commit--schemas (plist-get request :target))))
      ('context
       (let ((data (ai-git-commit-context
                    (plist-get request :directory)
                    (not (plist-get request :full)))))
         (skill-runtime-result operation data (plist-get data :change-count))))
      ('format
       (skill-runtime-result operation (ai-git-commit-format request) 1))
      (_ (error "Unknown Git commit operation %S; expected %S"
                operation (mapcar #'car ai-git-commit--schemas))))))

;; Compatibility for callers using the former Treeland interface.
(define-obsolete-function-alias
  'treeland-commit-context #'ai-git-commit-context "2026-07-17")

(defun treeland-commit-format
    (type module summary body log &optional pms influence)
  "Format legacy Treeland fields through shared Git validation."
  (skill-git--single-line log "LOG")
  (skill-git--single-line pms "PMS" t)
  (skill-git--single-line influence "INFLUENCE" t)
  (let* ((skill-git-message-column ai-git-commit-fill-column)
         (message
          (format "%s\n\n%s\n\n%s\n%s\n%s"
                  (skill-git--subject type module summary)
                  (skill-git--fill
                   (skill-git--required-text body "BODY"))
                  (skill-git--fill (format "Log: %s" log))
                  (if pms (skill-git--fill (format "PMS: %s" pms)) "PMS:")
                  (if influence
                      (skill-git--fill (format "Influence: %s" influence))
                    "Influence:"))))
    (dolist (line (split-string message "\n"))
      (when (> (string-width line) ai-git-commit-maximum-column)
        (error "Legacy commit line exceeds %d columns"
               ai-git-commit-maximum-column)))
    message))

(defun treeland-commit-run (request)
  "Execute legacy Treeland REQUEST through the shared implementation."
  (pcase (plist-get request :operation)
    ('context
     (let ((data
            (ai-git-commit-context
             (plist-get request :directory)
             (not (plist-get request :full)))))
       (list :status 'ok :operation 'context
             :count (plist-get data :change-count)
             :result data)))
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
