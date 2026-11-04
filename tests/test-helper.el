;;; test-helper.el --- Shared infrastructure for skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'xref)

(defconst skill-tests-directory
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory containing the skill test suites.")

(defconst skill-contract-tests-root
  (file-name-directory (directory-file-name skill-tests-directory))
  "Repository root used by skill test suites.")

(defun skill-tests-load (relative)
  "Load repository file RELATIVE to `skill-contract-tests-root'."
  (load (expand-file-name relative skill-contract-tests-root) nil nil t))

(defun skill-tests-load-many (files)
  "Load each repository-relative file in FILES."
  (dolist (file files)
    (skill-tests-load file)))

(defun skill-tests-require-git ()
  "Require the Git executable for an integration suite."
  (unless (executable-find "git")
    (error "Git is required for this skill test suite")))

(defun skill-tests-require-magit ()
  "Require Magit for a Git integration suite."
  (unless (require 'magit nil t)
    (error
     "Magit is required for this skill test suite; install it in an Emacs package directory")))

(defun skill-tests-git (&rest args)
  "Run Git ARGS in `default-directory', failing on any unsuccessful command."
  (with-temp-buffer
    (unless (zerop (apply #'process-file "git" nil (current-buffer) nil args))
      (error "Test Git command failed: %S: %s" args (buffer-string)))
    (string-trim-right (buffer-string))))

(defmacro skill-tests-with-git-repository (&rest body)
  "Run BODY in an isolated Git repository bound as ROOT, then remove it."
  (declare (indent 0))
  `(let* ((root (make-temp-file "skill-git-test-" t))
          (default-directory (file-name-as-directory root)))
     (unwind-protect
         (progn
           (skill-tests-git "init" "-q")
           (skill-tests-git "config" "user.name" "Skill Tests")
           (skill-tests-git "config" "user.email" "tests@example.invalid")
           ,@body)
       (delete-directory root t))))

(defun skill-contract-tests-assert-failure (result status code)
  "Assert RESULT is a structured failure with STATUS and CODE."
  (should (= (plist-get result :protocol-version) 2))
  (should (eq (plist-get result :status) status))
  (should (eq (plist-get (plist-get result :error) :code) code))
  (should (plist-member result :effects))
  (should (plist-get result :metrics))
  result)

(defconst skill-contract-tests-message-spec
  '(:type "refactor"
    :scope "skills"
    :summary "standardize compact contracts"
    :risk low
    :context "Skill facades need one predictable result shape for efficient AI calls."
    :changes ("Return data, paging metadata, and effects through shared helpers.")
    :reason "One protocol removes skill-specific parsing and unnecessary retries."
    :validation "Validated formatter, pagination, schema, and authorization contracts."
    :boundary
    "Domain capabilities remain available and external actions still require authorization.")
  "Reusable structured evidence for formatter and conformance tests.")

(defvar skill-tests-workflow-metrics nil
  "Call metrics dynamically bound by a real workflow smoke test.")

(defvar skill-tests-workflow-observations nil
  "Privacy-safe observations from completed workflow smoke tests.")

(defun skill-tests-workflow-call (facade request)
  "Call FACADE with REQUEST and collect its actual metrics for this workflow."
  (let ((result (funcall facade request)))
    (push (plist-get result :metrics) skill-tests-workflow-metrics)
    result))

(defun skill-tests-record-workflow (name checks)
  "Record NAME's completed CHECKS and actual facade cost without request text."
  (push (list :workflow name :checks checks
              :cost (skill-runtime-summarize-metrics
                     (reverse skill-tests-workflow-metrics)))
        skill-tests-workflow-observations))

(provide 'test-helper)

;;; test-helper.el ends here
