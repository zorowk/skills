;;; git-commit-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "common/scripts/agent-shell-bridge.el"
   "git-commit/scripts/ai-git-commit.el"
   "git-commit/scripts/agent-shell-git-review.el"))

(defvar ai-git-commit-include-validation-in-message)
(defvar ai-git-commit-untracked-file-maximum-characters)
(defvar ai-git-commit-untracked-maximum-characters)
(defvar magit-display-buffer-noselect)
(defvar magit-process-popup-time)
(defvar skill-git--body-label-regexp)

(skill-tests-require-git)
(skill-tests-require-magit)

(ert-deftest git-message-auto-compacts-low-risk-work ()
  (let ((message (ai-git-commit-format skill-contract-tests-message-spec)))
    (should-not (string-match-p "Domain capabilities" message))
    (should-not (string-match-p skill-git--body-label-regexp message))
    (should (seq-every-p
             (lambda (line) (<= (string-width line) 100))
             (split-string message "\n")))))

(ert-deftest git-message-full-preserves-boundary ()
  (let ((message
         (ai-git-commit-format
          (plist-put (copy-sequence skill-contract-tests-message-spec)
                     :detail 'full))))
    (should (string-match-p "Domain capabilities" message))))

(ert-deftest git-message-keeps-validation-internal-by-default ()
  (let ((ai-git-commit-include-validation-in-message nil)
        (message
         (ai-git-commit-format
          (plist-put (copy-sequence skill-contract-tests-message-spec)
                     :detail 'full))))
    (should-not (string-match-p "Validated formatter" message))
    (should (string-match-p "Domain capabilities" message)))
  (let ((ai-git-commit-include-validation-in-message t))
    (should
     (string-match-p
      "Validated formatter"
      (ai-git-commit-format
       (plist-put (copy-sequence skill-contract-tests-message-spec)
                  :detail 'full))))))

(ert-deftest agent-shell-git-request-preserves-advisory-boundary ()
  (with-temp-buffer
    (setq-local skill-agent-shell--last-completed-turn
                '(:paths (("/tmp/repository/one.el" . file-write))))
    (cl-letf (((symbol-function 'agent-shell-git-review--root)
               (lambda (_path) "/tmp/repository/")))
      (let ((text
             (agent-shell-git-review--request-text
              (current-buffer) 'commit)))
        (should (string-match-p "re-read actual Git/Magit" text))
        (should (string-match-p "/tmp/repository/one.el" text))
        (should (string-match-p "omit test results" text))))))

(ert-deftest git-message-auto-compacts-routine-medium-risk-work ()
  (let* ((spec (copy-sequence skill-contract-tests-message-spec))
         (spec (plist-put spec :risk 'medium))
         (spec (plist-put spec :changes
                          '("Add bounded untracked-file evidence."
                            "Stage an explicit path set."
                            "Document the compact workflow.")))
         (message (ai-git-commit-format spec)))
    (should-not (string-match-p "Domain capabilities" message))))

(ert-deftest git-context-collects-bounded-untracked-diffs ()
  (let ((ai-git-commit-untracked-file-maximum-characters 24))
    (cl-letf (((symbol-function 'magit-git-lines)
               (lambda (&rest _) '("new.el")))
              ((symbol-function 'magit-git-insert)
               (lambda (&rest _)
                 (insert "diff --git a/new.el b/new.el\n+some long new content\n")
                 1)))
      (let ((result (ai-git-commit--untracked-diff)))
        (should (equal (plist-get result :files) '("new.el")))
        (should (string-prefix-p "diff --git" (plist-get result :text)))
        (should (eq (plist-get result :truncated) t))))))

(ert-deftest git-context-paths-hide-global-status-names ()
  (let ((original-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest arguments)
                 (if (eq feature 'magit)
                     t
                   (apply original-require feature arguments))))
              ((symbol-function 'magit-toplevel) (lambda (&rest _) "/repo/"))
              ((symbol-function 'ai-git-commit--normalize-paths)
               (lambda (&rest _) '("target.el")))
              ((symbol-function 'ai-git-commit--git-output)
               (lambda (&rest _)
                 " M target.el\n?? unrelated-secret.el"))
              ((symbol-function 'ai-git-commit--git-output-for-paths)
               (lambda (arguments _paths)
                 (if (equal (car arguments) "status") " M target.el" "")))
              ((symbol-function 'ai-git-commit--untracked-diff)
               (lambda (&rest _)
                 '(:text "" :files nil :truncated nil)))
              ((symbol-function 'magit-git-success) (lambda (&rest _) t)))
      (let ((data
             (ai-git-commit-context "/repo/" t '("target.el"))))
        (should (equal (plist-get data :status) " M target.el"))
        (should (= (plist-get data :change-count) 1))
        (should (= (plist-get data :excluded-change-count) 1))
        (should-not
         (string-match-p "unrelated-secret.el"
                         (plist-get data :status)))))))

(ert-deftest git-context-paths-exclude-unrelated-untracked-content ()
  (unless (require 'magit nil t)
    (ert-skip "Magit is unavailable in the pure -Q contract environment"))
  (let* ((root (make-temp-file "git-context-scope-" t))
         (default-directory root)
         (target (expand-file-name "target.el" root))
         (new (expand-file-name "new.el" root))
         (unrelated (expand-file-name "unrelated-secret.el" root)))
    (unwind-protect
        (progn
          (should (zerop (call-process "git" nil nil nil "init" "-q")))
          (with-temp-file target (insert "baseline\n"))
          (should (zerop (call-process "git" nil nil nil "add" "target.el")))
          (should
           (zerop
            (call-process "git" nil nil nil
                          "-c" "user.name=Skill Test"
                          "-c" "user.email=skill@example.invalid"
                          "commit" "-q" "-m" "baseline")))
          (with-temp-file target (insert "changed target\n"))
          (with-temp-file new (insert "new scoped content\n"))
          (with-temp-file unrelated (insert "UNRELATED-SECRET-CONTENT\n"))
          (let* ((result
                  (ai-git-commit-run
                   (list :operation 'context :directory root
                         :paths '("target.el" "new.el"))))
                 (data (plist-get result :data))
                 (diff (plist-get data :diff)))
            (should (equal (plist-get data :diff-scope)
                           '("target.el" "new.el")))
            (should (= (plist-get data :change-count) 2))
            (should (= (plist-get data :excluded-change-count) 1))
            (should (equal (plist-get data :status)
                           (plist-get data :scoped-status)))
            (should-not (string-match-p "unrelated-secret.el"
                                        (plist-get data :status)))
            (should-not (string-match-p "UNRELATED-SECRET-CONTENT" diff))
            (should (string-match-p "changed target" diff))
            (should (string-match-p "new scoped content" diff))))
      (delete-directory root t))))

(ert-deftest git-path-validation-allows-tracked-deletions-and-rejects-escape ()
  (let ((root (make-temp-file "git-commit-paths-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'magit-git-lines)
                   (lambda (&rest _) '("gone.el"))))
          (should (equal (ai-git-commit--normalize-paths
                          root '("gone.el" "gone.el"))
                         '("gone.el")))
          (should-error
           (ai-git-commit--normalize-paths root '("../outside.el"))))
      (delete-directory root t))))

(ert-deftest git-push-verifies-the-configured-upstream-commit ()
  (unless (require 'magit nil t)
    (ert-skip "Magit is unavailable in the pure -Q contract environment"))
  (let* ((root (make-temp-file "git-push-verification-" t))
         (remote (expand-file-name "remote.git" root))
         (checkout (expand-file-name "checkout" root))
         (tracked (expand-file-name "page.html" checkout)))
    (cl-labels
        ((git
          (directory &rest arguments)
          (let ((default-directory directory))
            (with-temp-buffer
              (unless
                  (zerop
                   (apply #'call-process
                          "git" nil (current-buffer) nil arguments))
                (ert-fail
                 (format "git %S failed: %s"
                         arguments (buffer-string))))
              (string-trim (buffer-string))))))
      (unwind-protect
          (progn
            (make-directory remote)
            (git remote "init" "--bare" "-q")
            (git root "clone" "-q" remote checkout)
            (git checkout "checkout" "-b" "main")
            (with-temp-file tracked (insert "one\n"))
            (git checkout "add" "page.html")
            (git checkout
                 "-c" "user.name=Skill Test"
                 "-c" "user.email=skill@example.invalid"
                 "commit" "-q" "-m" "initial")
            (git checkout "push" "-q" "-u" "origin" "main")
            (with-temp-file tracked (insert "two\n"))
            (git checkout "add" "page.html")
            (git checkout
                 "-c" "user.name=Skill Test"
                 "-c" "user.email=skill@example.invalid"
                 "commit" "-q" "-m" "update")
            (let* ((result (skill-git-push checkout))
                   (remote-commit
                    (git root "--git-dir" remote
                         "rev-parse" "refs/heads/main")))
              (should (plist-get result :verified))
              (should (equal (plist-get result :branch) "main"))
              (should (equal (plist-get result :upstream) "origin/main"))
              (should (equal (plist-get result :commit) remote-commit))
              (should
               (equal (plist-get result :upstream-commit)
                      remote-commit))))
        (delete-directory root t)))))

(ert-deftest git-message-rejects-labels-and-missing-evidence ()
  (should-error
   (ai-git-commit-format
    (plist-put (copy-sequence skill-contract-tests-message-spec)
               :context "Context: redundant label")))
  (should-error
   (ai-git-commit-format '(:type "fix" :summary "reject incomplete input"))))

(ert-deftest git-commit-facade-uses-one-headless-magit-message-argument ()
  (let (captured)
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'ai-git-commit--ensure-magit)
               (lambda () t))
              ((symbol-function 'magit-commit-create)
               (lambda (arguments)
                 (should (= magit-process-popup-time -1))
                 (should (eq magit-display-buffer-noselect t))
                 (should (eq inhibit-message t))
                 (should (null message-log-max))
                 (setq captured arguments)
                 'fake-process))
              ((symbol-function 'ai-git-commit--wait-for-process)
               (lambda (process)
                 (should (eq process 'fake-process))
                 (should (= magit-process-popup-time -1))
                 (should (eq magit-display-buffer-noselect t))
                 (should (eq inhibit-message t))
                 (should (null message-log-max))
                 0))
              ((symbol-function 'ai-git-commit--head-message)
               (lambda () (concat (nth 2 captured) "\n")))
              ((symbol-function 'magit-rev-parse)
               (lambda (&rest _) "abc123")))
      (let* ((request
              (append '(:operation commit :authorization explicit)
                      skill-contract-tests-message-spec))
             (expected (ai-git-commit-format request))
             (result (ai-git-commit-run request)))
        (should (equal captured
                       (list "--cleanup=verbatim" "-m" expected)))
        (should (equal (plist-get (plist-get result :data) :commit) "abc123"))
        (should (equal (plist-get result :effects)
                       '(:committed t :amended nil)))))))

(ert-deftest git-commit-facade-stages-and-commits-only-explicit-paths ()
  (let (commit-arguments stage-arguments)
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'ai-git-commit--ensure-magit)
               (lambda () t))
              ((symbol-function 'ai-git-commit--normalize-paths)
               (lambda (_root _paths) '("new.el" "gone.el")))
              ((symbol-function 'magit-call-git)
               (lambda (&rest arguments)
                 (setq stage-arguments arguments)
                 0))
              ((symbol-function 'magit-commit-create)
               (lambda (arguments)
                 (setq commit-arguments arguments)
                 'fake-process))
              ((symbol-function 'ai-git-commit--wait-for-process)
               (lambda (_) 0))
              ((symbol-function 'ai-git-commit--head-message)
               (lambda () (concat (nth 2 commit-arguments) "\n")))
              ((symbol-function 'magit-rev-parse)
               (lambda (&rest _) "abc123")))
      (let* ((request
              (append '(:operation commit :authorization explicit
                        :paths ("new.el" "gone.el"))
                      skill-contract-tests-message-spec))
             (result (ai-git-commit-run request)))
        (should (equal stage-arguments
                       '("add" "--" "new.el" "gone.el")))
        (should (equal (last commit-arguments 4)
                       '("--only" "--" "new.el" "gone.el")))
        (should (equal (plist-get (plist-get result :data) :paths)
                       '("new.el" "gone.el")))))))

(ert-deftest git-amend-facade-verifies-committed-message ()
  (cl-letf (((symbol-function 'magit-toplevel)
             (lambda (&optional _) "/tmp/repository/"))
            ((symbol-function 'ai-git-commit--ensure-magit)
             (lambda () t))
            ((symbol-function 'magit-commit-amend)
             (lambda (_arguments) 'fake-process))
            ((symbol-function 'ai-git-commit--wait-for-process)
             (lambda (_) 0))
            ((symbol-function 'ai-git-commit--head-message)
             (lambda () "different message\n"))
            ((symbol-function 'magit-rev-parse)
             (lambda (&rest _) "abc123")))
    (should-error
     (ai-git-commit-run
      (append '(:operation amend :authorization explicit)
              skill-contract-tests-message-spec))
     :type 'error)))

(ert-deftest git-commit-head-message-keeps-the-complete-body ()
  (cl-letf (((symbol-function 'magit-rev-insert-format)
             (lambda (&rest _)
               (insert "subject\n\nbody\n")
               0)))
    (should (equal (ai-git-commit--head-message)
                   "subject\n\nbody\n"))))

(provide 'git-commit-tests)

;;; git-commit-tests.el ends here
