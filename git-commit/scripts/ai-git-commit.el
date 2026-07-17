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
(defvar magit-display-buffer-noselect)
(defvar magit-process-popup-time)
(declare-function skill-git-format-message "../../common/scripts/skill-git"
                  (spec))
(declare-function skill-runtime-describe "../../common/scripts/skill-runtime"
                  (schemas &optional target))
(declare-function skill-runtime-result "../../common/scripts/skill-runtime"
                  (operation data &optional count status page effects))
(declare-function skill-runtime-require-authorization
                  "../../common/scripts/skill-runtime" (request action))
(declare-function skill-runtime-truncate "../../common/scripts/skill-runtime"
                  (text maximum label))
(declare-function skill-runtime-validate-request
                  "../../common/scripts/skill-runtime" (schemas request))

(declare-function magit-commit-amend "magit-commit" (&optional args))
(declare-function magit-commit-create "magit-commit" (&optional args))
(declare-function magit-git-insert "magit-git" (&rest args))
(declare-function magit-git-success "magit-git" (&rest args))
(declare-function magit-rev-insert-format "magit-git"
                  (format &optional rev args))
(declare-function magit-rev-parse "magit-git" (&rest args))
(declare-function magit-toplevel "magit-git" (&optional directory))

(defgroup ai-git-commit nil
  "Collect evidence for Git commit messages."
  :group 'skill-git)

(defcustom ai-git-commit-fill-column 100
  "Column used to fill commit-message prose."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-maximum-column 100
  "Maximum permitted line width in generated commit messages."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-context-maximum-characters 30000
  "Maximum characters retained for each full-mode commit diff."
  :type 'positive-integer
  :group 'ai-git-commit)

(defcustom ai-git-commit-compact-maximum-characters 12000
  "Maximum characters retained for compact combined commit context."
  :type 'positive-integer
  :group 'ai-git-commit)

(defconst ai-git-commit--schemas
  '((context :summary "Collect bounded staged and unstaged evidence; compact by default."
             :optional (:directory :full) :effects nil)
    (format :summary "Generate and validate one evidence-backed message."
            :required (:type :summary :context :changes :reason :validation
                            :boundary)
            :optional (:scope :risk :detail :log :pms :influence)
            :effects nil)
    (commit
     :summary "Commit through headless Magit, then verify the complete HEAD message."
     :required (:type :summary :context :changes :reason :validation
                :boundary :authorization)
     :optional (:scope :risk :detail :log :pms :influence :directory)
     :effects (:committed))
    (amend
     :summary "Amend through headless Magit, then verify the complete HEAD message."
     :required (:type :summary :context :changes :reason :validation
                :boundary :authorization)
     :optional (:scope :risk :detail :log :pms :influence :directory)
     :effects (:committed :amended))
    (describe :summary "Return operation names or one complete schema."
              :optional (:target) :effects nil))
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
    (ai-git-commit--validate-message (skill-git-format-message spec))))

(defun ai-git-commit--validate-message (message)
  "Return MESSAGE after validating its maximum line width."
  (dolist (line (split-string message "\n"))
    (when (> (string-width line) ai-git-commit-maximum-column)
      (error "Commit line exceeds %d columns" ai-git-commit-maximum-column)))
  message)

(defun ai-git-commit--normalize-terminal-newline (message)
  "Remove only terminal newline characters from MESSAGE."
  (replace-regexp-in-string "[\r\n]+\\'" "" message))

(defun ai-git-commit--wait-for-process (process)
  "Wait for Magit PROCESS and return its successful exit status."
  (unless (processp process)
    (error "Magit did not return a commit process"))
  (while (process-live-p process)
    (accept-process-output process 0.05))
  (let ((status (process-exit-status process)))
    (unless (zerop status)
      (error "Magit commit failed with exit status %d" status))
    status))

(defun ai-git-commit--ensure-magit ()
  "Require Magit or signal that the current Emacs cannot commit."
  (unless (require 'magit nil t)
    (error "Magit is not available in this Emacs session")))

(defun ai-git-commit--head-message ()
  "Return the complete message for HEAD through Magit."
  (with-temp-buffer
    (unless (zerop (magit-rev-insert-format "%B" "HEAD"))
      (error "Magit could not read the committed HEAD message"))
    (buffer-string)))

(defun ai-git-commit--commit (request amend)
  "Commit formatted REQUEST through Magit; AMEND means replace HEAD."
  (skill-runtime-require-authorization
   request (if amend "Amend" "Commit"))
  (ai-git-commit--ensure-magit)
  (let ((root (magit-toplevel
               (or (plist-get request :directory) default-directory))))
    (unless root
      (error "Not inside a Git repository: %s"
             (expand-file-name
              (or (plist-get request :directory) default-directory))))
    (let* ((default-directory root)
           (message (ai-git-commit-format request))
           ;; A single -m value bypasses the editor.  Verbatim cleanup keeps
           ;; the formatter output intact and avoids any temporary file.
           (arguments (list "--cleanup=verbatim" "-m" message)))
      ;; Keep the complete asynchronous operation headless.  In particular,
      ;; the process sentinel runs while `accept-process-output' waits below,
      ;; so these bindings must outlive the initial Magit call.
      (let ((magit-process-popup-time -1)
            (magit-display-buffer-noselect t)
            (inhibit-message t)
            (message-log-max nil))
        (let ((process (if amend
                           (magit-commit-amend arguments)
                         (magit-commit-create arguments))))
          (ai-git-commit--wait-for-process process)
          (let* ((expected
                  (ai-git-commit--normalize-terminal-newline message))
                 (actual
                  (ai-git-commit--normalize-terminal-newline
                   (ai-git-commit--head-message))))
            (ai-git-commit--validate-message actual)
            (unless (string= actual expected)
              (error "Committed message differs from formatter output"))
            (list :commit (magit-rev-parse "HEAD")
                  :message actual
                  :amended (and amend t))))))))

;;;###autoload
(defun ai-git-commit-run (request)
  "Execute compact Git commit REQUEST and return a standard envelope."
  (skill-runtime-validate-request ai-git-commit--schemas request)
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
      ((or 'commit 'amend)
       (let* ((amend (eq operation 'amend))
              (data (ai-git-commit--commit request amend)))
         (skill-runtime-result
          operation data 1 'ok nil
          (list :committed t :amended amend))))
      (_ (error "Unknown Git commit operation %S; expected %S"
                operation (mapcar #'car ai-git-commit--schemas))))))

(provide 'ai-git-commit)

;;; ai-git-commit.el ends here
