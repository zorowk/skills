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
                        :setupfile setupfile :full t))))
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
               '((:operation export)
                 (:operation export :full t)))
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
