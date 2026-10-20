;;; org-blog-exporter-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "org-blog-exporter/scripts/org-blog-exporter.el"))

(defvar org-blog-exporter-setupfile)
(defvar skill-git--body-label-regexp)

(defun blog-tests--with-repository (function)
  "Call FUNCTION with NOTES, BLOG, SOURCE and SETUP in a local-only Git fixture."
  (skill-tests-require-git)
  (skill-tests-require-magit)
  (let* ((root (make-temp-file "blog-recovery-test-" t))
         (notes (expand-file-name "notes" root))
         (blog (expand-file-name "blog" root))
         (remote (expand-file-name "remote.git" root))
         (source (expand-file-name "sample.org" notes))
         (setup (expand-file-name "setupfile.org" notes))
         (org-blog-exporter--recoveries nil))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory blog)
          (let ((default-directory root))
            (skill-tests-git "init" "--bare" "-q" remote))
          (let ((default-directory (file-name-as-directory blog)))
            (skill-tests-git "init" "-q")
            (skill-tests-git "config" "user.name" "Blog Tests")
            (skill-tests-git "config" "user.email" "tests@example.invalid")
            (skill-tests-git "config" "commit.gpgsign" "false")
            (skill-tests-git "branch" "-M" "main")
            (with-temp-file "style.css" (insert "body {}\n"))
            (skill-tests-git "add" ".")
            (skill-tests-git "commit" "-qm" "initial")
            (skill-tests-git "remote" "add" "origin" remote)
            (skill-tests-git "push" "-qu" "origin" "main"))
          (with-temp-file source (insert "#+title: Sample\n\nText.\n"))
          (with-temp-file setup
            (insert "#+options: toc:nil\n#+BLOG_REPOSITORY_URL: " remote "\n"))
          (funcall function notes blog source setup))
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer)))
          (when (file-in-directory-p file root)
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (delete-directory root t))))

(ert-deftest blog-push-failure-retains-commit-and-resumes-without-another-commit ()
  (blog-tests--with-repository
   (lambda (notes blog source setup)
     (let ((push-function (symbol-function 'skill-git-push))
           (export-function (symbol-function 'org-blog-exporter--export-file-artifact))
           (push-count 0) (export-count 0))
       (cl-letf (((symbol-function 'skill-git-push)
                  (lambda (root)
                    (setq push-count (1+ push-count))
                    (if (< push-count 3) (error "Injected push failure")
                      (funcall push-function root))))
                 ((symbol-function 'org-blog-exporter--export-file-artifact)
                  (lambda (&rest args)
                    (setq export-count (1+ export-count))
                    (apply export-function args))))
         (let* ((first (org-blog-exporter-run
                        (list :operation 'publish :authorization 'explicit
                              :files (list source) :notes-dir notes
                              :repository-dir blog :setupfile setup)))
                (token (plist-get (plist-get first :error) :recovery-token))
                (commit (plist-get (plist-get first :effects) :commit))
                (default-directory (file-name-as-directory blog))
                (head (skill-tests-git "rev-parse" "HEAD")))
           (skill-contract-tests-assert-failure first 'partial 'partial-failure)
           (should token)
           (should (plist-get commit :commit))
           (should-not (plist-get (plist-get first :effects) :push))
           (should (plist-get (plist-get (plist-get first :verification) :repository)
                              :commit-exists))
           (skill-contract-tests-assert-failure
            (org-blog-exporter-run (list :operation 'resume :recovery-token token))
            'needs-input 'authorization-required)
           (let* ((retry (org-blog-exporter-run
                          (list :operation 'resume :authorization 'explicit
                                :recovery-token token)))
                  (next-token (plist-get (plist-get retry :error) :recovery-token)))
             (skill-contract-tests-assert-failure retry 'partial 'partial-failure)
             (should next-token)
             (should-not (equal next-token token))
             (setq token next-token))
           (let ((resumed (org-blog-exporter-run
                           (list :operation 'resume :authorization 'explicit
                                 :recovery-token token))))
             (should (eq (plist-get resumed :status) 'ok))
             (should (plist-get (plist-get (plist-get resumed :effects) :push) :verified))
             (should (equal head (skill-tests-git "rev-parse" "HEAD")))
             (should (equal head (skill-tests-git "rev-parse" "@{upstream}")))
             (should (= export-count 1))
             (should (= push-count 3)))
           (skill-contract-tests-assert-failure
            (org-blog-exporter-run (list :operation 'resume :authorization 'explicit
                                         :recovery-token token))
            'needs-input 'not-found)))))))

(ert-deftest blog-asset-recovery-preserves-artifacts-and-rejects-stale-inputs ()
  (blog-tests--with-repository
   (lambda (notes blog source setup)
     (let ((copy-function (symbol-function 'org-blog-exporter--copy-assets))
           (export-function (symbol-function 'org-blog-exporter--export-file-artifact))
           (index-function (symbol-function 'org-blog-exporter-update-index))
           (copy-count 0) (export-count 0) (index-count 0))
       (with-temp-file (expand-file-name "sample.png" notes) (insert "image"))
       (with-temp-file source (insert "#+title: Sample\n\n[[file:sample.png]]\n"))
       (cl-letf (((symbol-function 'org-blog-exporter--copy-assets)
                  (lambda (&rest args)
                    (setq copy-count (1+ copy-count))
                    (if (= copy-count 1) (signal 'file-error '("Injected copy failure"))
                      (apply copy-function args))))
                 ((symbol-function 'org-blog-exporter--export-file-artifact)
                  (lambda (&rest args)
                    (setq export-count (1+ export-count)) (apply export-function args)))
                 ((symbol-function 'org-blog-exporter-update-index)
                  (lambda (&rest args)
                    (setq index-count (1+ index-count)) (apply index-function args))))
         (let* ((first (org-blog-exporter-run
                        (list :operation 'publish :authorization 'explicit
                              :files (list source) :notes-dir notes
                              :repository-dir blog :setupfile setup)))
                (token (plist-get (plist-get first :error) :recovery-token))
                (request (list :operation 'resume :authorization 'explicit :recovery-token token))
                (output (expand-file-name "sample.html" blog))
                (original-source (with-temp-buffer (insert-file-contents source) (buffer-string)))
                (original-html (with-temp-buffer (insert-file-contents output) (buffer-string))))
           (skill-contract-tests-assert-failure first 'partial 'partial-failure)
           (should token)
           (dolist (file (list source output (expand-file-name "unrelated.txt" blog)))
             (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
             (with-temp-file file (insert "changed"))
             (skill-contract-tests-assert-failure
              (org-blog-exporter-run request) 'blocked 'stale-context)
             (cond ((equal file source) (with-temp-file file (insert original-source)))
                   ((equal file output) (with-temp-file file (insert original-html)))
                   (t (delete-file file))))
           (let ((default-directory (file-name-as-directory blog)))
             (skill-tests-git "config" "remote.origin.url" "/tmp/changed-origin.invalid")
             (skill-contract-tests-assert-failure
              (org-blog-exporter-run request) 'blocked 'stale-context)
             (skill-tests-git "config" "remote.origin.url"
                              (expand-file-name "../remote.git" blog))
             (skill-tests-git "checkout" "-qb" "other")
             (skill-tests-git "commit" "--allow-empty" "-qm" "Changed HEAD")
             (skill-contract-tests-assert-failure
              (org-blog-exporter-run request) 'blocked 'stale-context)
             (skill-tests-git "checkout" "-q" "main"))
           (let ((result (org-blog-exporter-run request)))
             (should (eq (plist-get result :status) 'ok))
             (should (= export-count 1))
             (should (= index-count 1))
             (should (file-exists-p (expand-file-name "image/sample.png" blog)))
             (should (plist-get (plist-get (plist-get result :effects) :push) :verified)))))))))

(ert-deftest blog-recovery-retries-only-unfinished-export-index-or-commit ()
  (dolist (stage '(export export-all index commit))
    (ert-info ((format "Recovery stage: %s" stage))
      (blog-tests--with-repository
       (lambda (notes blog source setup)
         (let ((export-function (symbol-function 'org-blog-exporter--export-file-artifact))
               (index-function (symbol-function 'org-blog-exporter-update-index))
               (commit-function (symbol-function 'skill-git-commit-paths))
               (export-count 0) (index-count 0) (commit-count 0)
               (org-blog-exporter-setupfile setup)
               (second-source (expand-file-name "second.org" notes)))
           (with-temp-file second-source (insert "#+title: Second\n\nSecond.\n"))
           (cl-letf
               (((symbol-function 'org-blog-exporter--export-file-artifact)
                 (lambda (&rest args)
                   (setq export-count (1+ export-count))
                   (if (and (memq stage '(export export-all)) (= export-count 2))
                       (signal 'file-error '("Injected export failure"))
                     (apply export-function args))))
                ((symbol-function 'org-blog-exporter-update-index)
                 (lambda (&rest args)
                   (setq index-count (1+ index-count))
                   (if (and (eq stage 'index) (= index-count 1))
                       (signal 'file-error '("Injected index failure"))
                     (apply index-function args))))
                ((symbol-function 'skill-git-commit-paths)
                 (lambda (&rest args)
                   (setq commit-count (1+ commit-count))
                   (if (and (eq stage 'commit) (= commit-count 1))
                       (error "Injected commit failure")
                     (apply commit-function args)))))
             (let* ((first (org-blog-exporter-run
                            (append
                             (list :operation 'publish :authorization 'explicit
                                   :notes-dir notes :repository-dir blog :setupfile setup)
                             (unless (eq stage 'export-all)
                               (list :files (list source second-source))))))
                    (token (plist-get (plist-get first :error) :recovery-token)))
               (skill-contract-tests-assert-failure first 'partial 'partial-failure)
               (should (eq (plist-get (plist-get first :error) :stage)
                           (if (eq stage 'export-all) 'export stage)))
               (should token)
               (let ((result (org-blog-exporter-run
                              (list :operation 'resume :authorization 'explicit
                                    :recovery-token token))))
                 (should (eq (plist-get result :status) 'ok))
                 (should (= export-count (if (memq stage '(export export-all)) 3 2)))
                 (should (= index-count (if (eq stage 'index) 2 1)))
                 (should (= commit-count (if (eq stage 'commit) 2 1)))
                 (should (plist-get (plist-get (plist-get result :effects) :push)
                                    :verified)))))))))))

(ert-deftest blog-facade-exports-into-an-isolated-directory ()
  (let* ((root (make-temp-file "blog-facade-" t))
         (notes (expand-file-name "notes" root))
         (output (expand-file-name "output" root))
         (source (expand-file-name "sample.org" notes))
         (setupfile (expand-file-name "setupfile.org" notes))
         (org-blog-exporter-setupfile setupfile))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory output)
          (with-temp-file setupfile (insert "#+options: toc:nil\n"))
          (with-temp-file source
            (insert "#+title: Temporary article\n\n* Body\nTemporary text.\n"))
          (let ((result
                 (org-blog-exporter-run
                  (list :operation 'export :files (list source)
                        :notes-dir notes :output-dir output
                        :setupfile setupfile :full t
                        :authorization 'explicit))))
            (let* ((verification (plist-get result :verification))
                   (artifact (plist-get verification :artifact))
                   (mapping (car (plist-get artifact :source-output-map))))
              (should (eq (plist-get result :status) 'ok))
              (should (equal (plist-get result :effects)
                             '(:exported-count 1)))
              (should (file-exists-p
                       (car (plist-get
                             (plist-get result :data) :exported))))
              (should (equal (plist-get mapping :source) source))
              (should (file-exists-p (plist-get mapping :output)))
              (should (eq (plist-get artifact :outputs-exist) t))
              (should (eq (plist-get artifact :public-policy-passed) t))
              (should (eq (plist-get artifact :asset-links-verified) t)))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest blog-export-verifies-rewritten-resource-links ()
  (let* ((root (make-temp-file "blog-assets-" t))
         (notes (expand-file-name "notes" root))
         (output (expand-file-name "output" root))
         (assets (expand-file-name "image" output))
         (source (expand-file-name "sample.org" notes))
         (image (expand-file-name "sample.png" notes))
         (published (expand-file-name "sample.png" assets))
         (setupfile (expand-file-name "setupfile.org" notes)))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory assets t)
          (with-temp-file setupfile (insert "#+options: toc:nil\n"))
          (with-temp-file image (insert "image"))
          (with-temp-file published (insert "image"))
          (with-temp-file source
            (insert "#+title: Asset article\n\n[[file:sample.png]]\n"))
          (let* ((artifact
                  (org-blog-exporter--export-file-artifact
                   source output setupfile
                   (list (cons image published)) notes))
                 (exported (plist-get artifact :output))
                 (html
                  (with-temp-buffer
                    (insert-file-contents exported)
                    (buffer-string))))
            (should (plist-get artifact :asset-links-verified))
            (should (= (length (plist-get artifact :rewritten-assets)) 1))
            (should (string-match-p "image/sample\\.png" html))
            (should-not (string-match-p "file:sample\\.png" html))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest blog-copying-the-same-resource-twice-is-idempotent ()
  (let* ((root (make-temp-file "blog-copy-idempotent-" t))
         (source (expand-file-name "source/sample.png" root))
         (target (expand-file-name "output/image/sample.png" root))
         (plan (list (list :source source :target target)))
         (copy-count 0))
    (unwind-protect
        (progn
          (make-directory (file-name-directory source) t)
          (with-temp-file source (insert "same image"))
          (cl-letf
              (((symbol-function 'org-publish-attachment)
                (lambda (_plist asset directory)
                  (setq copy-count (1+ copy-count))
                  (copy-file
                   asset
                   (expand-file-name
                    (file-name-nondirectory asset) directory)
                   t))))
            (should (equal (org-blog-exporter--copy-assets plan)
                           (list target)))
            (should (equal (org-blog-exporter--copy-assets plan)
                           (list target)))
            (should (= copy-count 1))
            (should (equal
                     (with-temp-buffer
                       (insert-file-contents target)
                       (buffer-string))
                     "same image"))))
      (delete-directory root t))))

(ert-deftest blog-partial-results-expose-retryable-failure-details ()
  (let ((partial
         '(:scope all
           :candidate-count 2
           :exported-count 1
           :exported ("/tmp/one.html")
           :error-count 1
           :errors (("/tmp/two.org" "Export failed"))
           :output-directory "/tmp/output")))
    (cl-letf (((symbol-function 'org-blog-exporter-export)
               (lambda (&rest _) partial)))
      (dolist (request
               '((:operation export :authorization explicit)
                 (:operation export :full t :authorization explicit)))
        (let* ((result (org-blog-exporter-run request))
               (error-data (plist-get result :error)))
          (skill-contract-tests-assert-failure
           result 'partial 'partial-failure)
          (should (= (plist-get error-data :failure-count) 1))
          (should (equal (plist-get error-data :causes)
                         '(("/tmp/two.org" "Export failed"))))
          (should (equal (plist-get result :effects)
                         '(:exported-count 1)))
          (should (equal (plist-get
                          (plist-get result :data) :exported)
                         '("/tmp/one.html"))))))))

(ert-deftest blog-publish-stops-before-commit-when-index-fails ()
  (let* ((root (make-temp-file "blog-index-failure-" t))
         (notes (expand-file-name "notes" root))
         (output (expand-file-name "output" root))
         (source (expand-file-name "sample.org" notes))
         (exported (expand-file-name "sample.html" output))
         (setupfile (expand-file-name "setupfile.org" notes)))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory output)
          (with-temp-file source (insert "#+title: Sample\n"))
          (with-temp-file exported (insert "<html></html>\n"))
          (with-temp-file setupfile (insert "#+options: toc:nil\n"))
          (cl-letf
              (((symbol-function
                 'org-blog-exporter--prepare-publish-repository)
                (lambda (&rest _) (list :git-root output)))
               ((symbol-function 'org-blog-exporter--asset-plan)
                (lambda (&rest _) nil))
               ((symbol-function
                 'org-blog-exporter--export-file-artifacts)
                (lambda (&rest _)
                  (list
                   (list :source source :output exported
                         :output-exists t :public-policy-passed t
                         :asset-links-verified t))))
               ((symbol-function 'org-blog-exporter-update-index)
                (lambda (&rest _)
                  (signal 'file-error '("Index write denied"))))
               ((symbol-function 'org-blog-exporter--finish-publish)
                (lambda (&rest _)
                  (ert-fail "commit and push must not run"))))
            (let* ((result
                    (org-blog-exporter-run
                     (list :operation 'publish
                           :files (list source)
                           :authorization 'explicit
                           :notes-dir notes
                           :repository-dir output
                           :setupfile setupfile)))
                   (workflow
                    (plist-get (plist-get result :verification)
                               :workflow)))
              (skill-contract-tests-assert-failure
               result 'partial 'partial-failure)
              (should (eq (plist-get (plist-get result :error) :stage)
                          'index))
              (should-not (plist-get workflow :index-updated))
              (should-not (plist-get (plist-get result :effects) :commit))
              (should-not (plist-get (plist-get result :effects) :push)))))
      (delete-directory root t))))

(ert-deftest blog-publish-reports-copied-assets-before-resource-failure ()
  (let* ((root (make-temp-file "blog-asset-failure-" t))
         (notes (expand-file-name "notes" root))
         (output (expand-file-name "output" root))
         (asset-output (expand-file-name "image" output))
         (source (expand-file-name "sample.org" notes))
         (exported (expand-file-name "sample.html" output))
         (setupfile (expand-file-name "setupfile.org" notes))
         (index (expand-file-name "index.html" output))
         (asset-one (expand-file-name "one.png" notes))
         (asset-two (expand-file-name "two.png" notes))
         (target-one (expand-file-name "one.png" asset-output))
         (target-two (expand-file-name "two.png" asset-output)))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory output)
          (with-temp-file source (insert "#+title: Sample\n"))
          (with-temp-file exported (insert "<html></html>\n"))
          (with-temp-file setupfile (insert "#+options: toc:nil\n"))
          (with-temp-file index (insert "<html></html>\n"))
          (with-temp-file asset-one (insert "one"))
          (with-temp-file asset-two (insert "two"))
          (cl-letf
              (((symbol-function
                 'org-blog-exporter--prepare-publish-repository)
                (lambda (&rest _) (list :git-root output)))
               ((symbol-function 'org-blog-exporter--asset-plan)
                (lambda (&rest _)
                  (list (list :source asset-one :target target-one)
                        (list :source asset-two :target target-two))))
               ((symbol-function
                 'org-blog-exporter--export-file-artifacts)
                (lambda (&rest _)
                  (list
                   (list :source source :output exported
                         :output-exists t :public-policy-passed t
                         :asset-links-verified t))))
               ((symbol-function 'org-blog-exporter-update-index)
                (lambda (&rest _) index))
               ((symbol-function 'org-publish-attachment)
                (lambda (_plist asset directory)
                  (if (equal asset asset-two)
                      (signal 'file-error '("Asset copy denied"))
                    (copy-file
                     asset
                     (expand-file-name
                      (file-name-nondirectory asset) directory)
                     t))))
               ((symbol-function 'org-blog-exporter--finish-publish)
                (lambda (&rest _)
                  (ert-fail "commit and push must not run"))))
            (let* ((result
                    (org-blog-exporter-run
                     (list :operation 'publish
                           :files (list source)
                           :authorization 'explicit
                           :notes-dir notes
                           :repository-dir output
                           :setupfile setupfile)))
                   (workflow
                    (plist-get (plist-get result :verification)
                               :workflow)))
              (skill-contract-tests-assert-failure
               result 'partial 'partial-failure)
              (should (eq (plist-get (plist-get result :error) :stage)
                          'assets))
              (should (eq (plist-get workflow :index-updated) t))
              (should (= (plist-get workflow :assets-planned) 2))
              (should (= (plist-get workflow :assets-copied) 1))
              (should (file-regular-p target-one))
              (should-not (file-exists-p target-two))
              (should-not (plist-get (plist-get result :effects) :commit))
              (should-not (plist-get (plist-get result :effects) :push)))))
      (delete-directory root t))))

(ert-deftest blog-publish-all-delegates-to-shared-finalization ()
  (let ((files '("/tmp/one.org" "/tmp/two.org"))
        (plan '((:source "/tmp/image.png" :target "/tmp/blog/image.png")))
        captured)
    (cl-letf
        (((symbol-function 'org-blog-exporter--prepare-publish-repository)
          (lambda (&rest _) '(:git-root "/tmp/blog/")))
         ((symbol-function 'org-blog-exporter-list-candidates)
          (lambda (&rest _) files))
         ((symbol-function 'org-blog-exporter--asset-plan)
          (lambda (&rest _) plan))
         ((symbol-function 'org-blog-exporter--asset-targets)
          (lambda (&rest _) '("/tmp/blog/image.png")))
         ((symbol-function 'org-blog-exporter-export-all)
          (lambda (&rest _)
            (list :error-count 0 :candidates files
                  :exported '("/tmp/blog/one.html"))))
         ((symbol-function 'org-blog-exporter--complete-publish)
          (lambda (&rest arguments)
            (setq captured arguments)
            '(:completed t))))
      (should (equal (org-blog-exporter-publish-all
                      "publish all" "/tmp/notes" "/tmp/blog" "/tmp/setup.org")
                     '(:completed t)))
      (should (equal (nth 1 captured) files))
      (should (equal (nth 4 captured) plan))
      (should (equal (plist-get (nth 5 captured) :assets) nil))
      (should (equal (nth 6 captured) "publish all")))))

(ert-deftest blog-internal-commit-uses-shared-full-message ()
  (let (captured)
    (cl-letf (((symbol-function 'skill-git-relative-path)
               (lambda (_root path &rest _) path))
              ((symbol-function 'skill-git-status)
               (lambda (&rest _) " M page.html"))
              ((symbol-function 'skill-git-commit-paths)
               (lambda (_root message paths &rest _)
                 (setq captured message)
                 (list :commit "abc123" :paths paths)))
              ((symbol-function 'skill-git-assert-clean) (lambda (_) t))
              ((symbol-function 'skill-git-push)
               (lambda (_)
                 '(:commit "abc123000"
                   :upstream-commit "abc123000"
                   :branch "main"
                   :upstream "origin/main"
                   :verified t))))
      (org-blog-exporter--finish-publish
       '(:git-root "/tmp/repository/") '("page.html") "publish page"))
    (should (string-prefix-p "chore(blog): publish page" captured))
    (should (string-match-p "\n\n" captured))
    (should-not (string-match-p skill-git--body-label-regexp captured))))

(ert-deftest blog-repeated-clean-publish-does-not-commit-or-push-twice ()
  (let ((statuses '(" M page.html" ""))
        (commit-count 0)
        (push-count 0))
    (cl-letf
        (((symbol-function 'skill-git-relative-path)
          (lambda (_root path &rest _) path))
         ((symbol-function 'skill-git-status)
          (lambda (&rest _) (pop statuses)))
         ((symbol-function 'skill-git-commit-paths)
          (lambda (_root _message paths &rest _)
            (setq commit-count (1+ commit-count))
            (list :commit "abc123" :paths paths)))
         ((symbol-function 'skill-git-assert-clean) (lambda (_) t))
         ((symbol-function 'skill-git-push)
          (lambda (_)
            (setq push-count (1+ push-count))
            '(:commit "abc123000"
              :upstream-commit "abc123000"
              :branch "main"
              :upstream "origin/main"
              :verified t))))
      (let ((first
             (org-blog-exporter--finish-publish
              '(:git-root "/tmp/repository/")
              '("page.html") "publish page"))
            (retry
             (org-blog-exporter--finish-publish
              '(:git-root "/tmp/repository/")
              '("page.html") "publish page")))
        (should (eq (plist-get first :changed) t))
        (should-not (plist-get retry :changed))
        (should (= commit-count 1))
        (should (= push-count 1))
        (should
         (eq
          (plist-get
           (plist-get retry :repository-verification)
           :generated-files-committed)
          'already-clean))
        (should
         (eq
          (plist-get
           (plist-get retry :repository-verification)
           :push-succeeded)
          'not-needed))))))

(ert-deftest blog-effects-report-export-and-publish-mutations ()
  (should
   (equal (org-blog-exporter--effects
           'export '(:exported ("one.html" "two.html")))
          '(:exported-count 2)))
  (should
   (equal (org-blog-exporter--effects
           'publish '(:exported-count 1 :changed t :commit "abc" :push t))
          '(:exported-count 1 :changed t :commit "abc" :push t))))

(provide 'org-blog-exporter-tests)

;;; org-blog-exporter-tests.el ends here
