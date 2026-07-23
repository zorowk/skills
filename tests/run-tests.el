;;; run-tests.el --- Load and run isolated skill test suites -*- lexical-binding: t; -*-

;;; Code:

(require 'package)
(package-initialize)

(defconst skill-test-suite-files
  '("skill-runtime-tests.el"
    "agent-shell-bridge-tests.el"
    "emacs-code-navigator-tests.el"
    "emacs-gtd-assistant-tests.el"
    "denote-scribe-tests.el"
    "org-blog-exporter-tests.el"
    "git-commit-tests.el"
    "skill-usage-review-tests.el"
    "routing-review-tests.el"
    "contract-conformance-tests.el")
  "Test suites loaded when no explicit suite arguments are supplied.")

(defun skill-test-runner--normalize-suite (argument)
  "Return a known suite basename for command-line ARGUMENT."
  (let ((suite (file-name-nondirectory argument)))
    (unless (member suite skill-test-suite-files)
      (error "Unknown skill test suite: %s" argument))
    suite))

(let* ((directory
        (file-name-directory (or load-file-name buffer-file-name)))
       (requested command-line-args-left)
       (suites
        (if requested
            (mapcar #'skill-test-runner--normalize-suite requested)
          skill-test-suite-files)))
  (setq command-line-args-left nil)
  (add-to-list 'load-path directory)
  (dolist (suite suites)
    (load (expand-file-name suite directory) nil nil t)))

(ert-run-tests-batch-and-exit)

;;; run-tests.el ends here
