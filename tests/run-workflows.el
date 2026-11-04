;;; run-workflows.el --- Exercise isolated native workflows -*- lexical-binding: t; -*-

;;; Commentary:
;; Run: emacs --batch -l tests/run-workflows.el > /tmp/skills-workflows.el
;; Stdout contains verified checks and real facade cost only.  ERT diagnostics
;; go to stderr.  These tests use temporary Org files and local Git remotes;
;; they exercise native execution, not model routing or production data.

;;; Code:

(require 'package)
(package-initialize)

(add-to-list 'load-path (file-name-directory (or load-file-name buffer-file-name)))
(require 'test-helper)

(skill-tests-load-many
 '("tests/emacs-gtd-assistant-tests.el"
   "tests/git-commit-tests.el"
   "tests/org-blog-exporter-tests.el"))

(setq skill-tests-workflow-observations nil)
(let ((stats (ert-run-tests-batch
              '(member gtd-query-mutation-creates-id-only-after-authorization
                       git-context-paths-exclude-unrelated-untracked-content
                       blog-push-failure-retains-commit-and-resumes-without-another-commit))))
  (prin1 (reverse skill-tests-workflow-observations))
  (terpri)
  (kill-emacs (if (zerop (ert-stats-completed-unexpected stats)) 0 1)))

;;; run-workflows.el ends here
