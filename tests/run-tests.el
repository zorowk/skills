;;; run-tests.el --- Load dependencies and run skill contracts -*- lexical-binding: t; -*-

;;; Code:

(require 'package)
(package-initialize)

(unless (require 'magit nil t)
  (error "Magit is required for the full contract suite; install it in an Emacs package directory"))

(unless (executable-find "git")
  (error "Git is required for the full contract suite"))

(load (expand-file-name
       "skill-contract-tests.el"
       (file-name-directory (or load-file-name buffer-file-name)))
      nil nil t)

(ert-run-tests-batch-and-exit)

;;; run-tests.el ends here
