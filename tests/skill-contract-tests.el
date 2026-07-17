;;; skill-contract-tests.el --- Contract tests for local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar emacs-code-navigator-documentation-maximum-characters)
(defvar emacs-gtd-directory)
(defvar emacs-gtd-file)
(defvar org-blog-exporter-setupfile)
(defvar org-id-locations-file)
(defvar skill-git--body-label-regexp)

(declare-function skill-runtime-result "../common/scripts/skill-runtime"
                  (operation data &optional count status page effects))
(declare-function skill-runtime-page "../common/scripts/skill-runtime"
                  (items offset limit total))
(declare-function skill-runtime-truncate "../common/scripts/skill-runtime"
                  (text maximum label))
(declare-function skill-runtime-validate-request "../common/scripts/skill-runtime"
                  (schemas request))
(declare-function emacs-code-navigator-query
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (request))
(declare-function emacs-code-navigator--compact-facet
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (info))
(declare-function emacs-code-navigator-search
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (directory regexp &optional limit glob literal))
(declare-function emacs-code-navigator-context-at-line
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (file line &optional radius include-defun include-eldoc
                        include-diagnostics diagnostic-radius))
(declare-function emacs-gtd-execute
                  "../emacs-gtd-assistant/scripts/emacs-gtd-assistant"
                  (request))
(declare-function denote-scribe-run
                  "../denote-scribe/scripts/denote-scribe" (request))
(declare-function denote-scribe-git-commit
                  "../denote-scribe/scripts/denote-scribe"
                  (title paths review-completed &optional kind git-dir))
(declare-function org-blog-exporter-run
                  "../org-blog-exporter/scripts/org-blog-exporter" (request))
(declare-function org-blog-exporter--finish-publish
                  "../org-blog-exporter/scripts/org-blog-exporter"
                  (repository exported title))
(declare-function org-blog-exporter--effects
                  "../org-blog-exporter/scripts/org-blog-exporter"
                  (operation result))
(declare-function ai-git-commit-run
                  "../git-commit/scripts/ai-git-commit" (request))
(declare-function ai-git-commit-format
                  "../git-commit/scripts/ai-git-commit" (spec))
(declare-function ai-git-commit--wait-for-process
                  "../git-commit/scripts/ai-git-commit" (process))
(declare-function ai-git-commit--ensure-magit
                  "../git-commit/scripts/ai-git-commit" ())
(declare-function ai-git-commit--head-message
                  "../git-commit/scripts/ai-git-commit" ())

(defconst skill-contract-tests-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(dolist (relative
         '("common/scripts/skill-runtime.el"
           "common/scripts/skill-git.el"
           "emacs-code-navigator/scripts/emacs-code-navigator.el"
           "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
           "denote-scribe/scripts/denote-scribe.el"
           "org-blog-exporter/scripts/org-blog-exporter.el"
           "git-commit/scripts/ai-git-commit.el"))
  (load (expand-file-name relative skill-contract-tests-root) nil nil t))

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
  "Reusable structured evidence for formatter tests.")

(ert-deftest skill-runtime-standard-envelope ()
  (should
   (equal (skill-runtime-result 'list '(a b) 2 'ok '(:truncated nil))
          '(:status ok :operation list :count 2 :data (a b)
                    :page (:truncated nil)))))

(ert-deftest skill-runtime-pagination-exposes-next-offset ()
  (let ((page (skill-runtime-page '(a b c d) 1 2 4)))
    (should (equal (plist-get page :items) '(b c)))
    (should (eq (plist-get (plist-get page :page) :truncated) t))
    (should (= (plist-get (plist-get page :page) :next-offset) 3))))

(ert-deftest skill-runtime-truncation-is-machine-readable ()
  (let ((bounded (skill-runtime-truncate "abcdef" 3 'sample)))
    (should (equal (plist-get bounded :text) "abc"))
    (should (eq (plist-get bounded :truncated) t))
    (should (= (plist-get bounded :original-length) 6))))

(ert-deftest skill-runtime-validates-required-request-fields ()
  (let ((schemas
         '((sample :summary "Validate a sample request."
                   :required (:name)
                   :required-one-of (:file :directory)))))
    (should
     (equal
      (skill-runtime-validate-request
       schemas '(:operation sample :name "item" :file "/tmp/item"))
      '(:operation sample :name "item" :file "/tmp/item")))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :file "/tmp/item")))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :name "item")))
    (should-error
     (skill-runtime-validate-request schemas '(:operation unknown)))))

(ert-deftest skill-facades-describe-with-standard-envelope ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let ((result (funcall call '(:operation describe))))
      (should (eq (plist-get result :status) 'ok))
      (should (eq (plist-get result :operation) 'describe))
      (should (plist-member result :data))
      (should (plist-get (plist-get result :data) :operations)))))

(ert-deftest facade-operation-schemas-carry-elisp-owned-guidance ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let* ((description
            (plist-get (funcall call '(:operation describe)) :data))
           (operations (plist-get description :operations))
           (catalog (plist-get description :catalog)))
      (should (equal operations (mapcar (lambda (item)
                                          (plist-get item :operation))
                                        catalog)))
      (should (seq-every-p
               (lambda (item) (stringp (plist-get item :summary)))
               catalog))
      (dolist (operation operations)
        (let* ((result
                (funcall call
                         (list :operation 'describe :target operation)))
               (schema
                (plist-get (plist-get result :data) :schema)))
          (should (stringp (plist-get schema :summary))))))))

(ert-deftest navigator-workspace-symbol-stays-in-requested-project ()
  (let* ((root (make-temp-file "navigator-project-" t))
         (other-root (make-temp-file "navigator-installed-" t))
         (source (expand-file-name "sample.el" root))
         (other (expand-file-name "sample.el" other-root)))
    (unwind-protect
        (progn
          (with-temp-file source (insert "(defun sample-symbol () t)\n"))
          (with-temp-file other (insert "(defun sample-symbol () nil)\n"))
          (cl-letf (((symbol-function
                      'emacs-code-navigator--semantic-xref-backend)
                     (lambda () 'test-backend))
                    ((symbol-function 'emacs-code-navigator-project-root)
                     (lambda (_directory) root))
                    ((symbol-function 'xref-backend-apropos)
                     (lambda (_backend _pattern)
                       (list
                        (xref-make
                         "sample-symbol"
                         (xref-make-file-location other 1 0))
                        (xref-make
                         "sample-symbol"
                         (xref-make-file-location source 1 0))))))
            (let ((matches
                   (emacs-code-navigator-workspace-symbol
                    source "sample-symbol" 10)))
              (should (= (length matches) 1))
              (should (equal (caar matches) source)))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t)
      (delete-directory other-root t))))

(ert-deftest navigator-locate-prefers-the-requested-file-imenu ()
  (let* ((root (make-temp-file "navigator-imenu-" t))
         (source (expand-file-name "sample.el" root)))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(defun requested-symbol () t)\n"))
          (cl-letf (((symbol-function
                      'emacs-code-navigator-workspace-symbol)
                     (lambda (&rest _)
                       '(("/tmp/installed/sample.el" 1 "requested-symbol")))))
            (let* ((result
                    (emacs-code-navigator-query
                     (list :operation 'locate :query "requested-symbol"
                           :file source :limit 3)))
                   (data (plist-get result :data)))
              (should (eq (plist-get data :strategy) 'imenu))
              (should (equal (caar (plist-get data :matches)) source)))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-facade-mutates-only-the-configured-file ()
  (let* ((root (make-temp-file "gtd-facade-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Personal\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (let* ((inhibit-message t)
                 (message-log-max nil)
                 (added
                  (emacs-gtd-execute
                   '(:operation add :title "Temporary task"
                     :headline "Personal")))
                 (id (plist-get (plist-get added :data) :id))
                 (listed
                  (emacs-gtd-execute
                   '(:operation list :query "Temporary task" :limit 5))))
            (should (stringp id))
            (should (= (plist-get listed :count) 1))
            (should
             (eq (plist-get
                  (emacs-gtd-execute
                   (list :operation 'delete :id id
                         :authorization 'explicit))
                  :status)
                 'ok))
            (should (= (plist-get
                        (emacs-gtd-execute
                         '(:operation list :query "Temporary task" :limit 5))
                        :count)
                       0))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

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
            (should (eq (plist-get result :status) 'ok))
            (should (equal (plist-get result :effects)
                           '(:exported-count 1)))
            (should (file-exists-p
                     (car (plist-get (plist-get result :data) :exported))))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest facade-schemas-expose-migrated-core-operations ()
  (let ((navigator
         (plist-get
          (plist-get
           (emacs-code-navigator-query '(:operation describe)) :data)
          :operations))
        (denote
         (plist-get
          (plist-get (denote-scribe-run '(:operation describe)) :data)
          :operations))
        (gtd
         (plist-get
          (plist-get (emacs-gtd-execute '(:operation describe)) :data)
          :operations))
        (git-commit
         (plist-get
          (plist-get (ai-git-commit-run '(:operation describe)) :data)
          :operations)))
    (dolist (operation '(region imenu workspace-symbol xref locate diagnostics))
      (should (memq operation navigator)))
    (should (memq 'preflight denote))
    (should (memq 'preflight gtd))
    (should (memq 'commit git-commit))
    (should (memq 'amend git-commit))))

(ert-deftest navigator-region-and-imenu-use-the-facade ()
  (let* ((file (expand-file-name "common/scripts/skill-runtime.el"
                                 skill-contract-tests-root))
         (region
          (emacs-code-navigator-query
           (list :operation 'region :file file :start-line 1 :end-line 3)))
         (imenu
          (emacs-code-navigator-query
           (list :operation 'imenu :file file))))
    (should (string-match-p "skill-runtime.el" (plist-get region :data)))
    (should (listp (plist-get imenu :data)))))

(ert-deftest navigator-search-honors-global-limit-and-glob ()
  (let ((matches
         (emacs-code-navigator-search
          skill-contract-tests-root "emacs-code-navigator" 2 "*.el" t)))
    (should (= (length matches) 2))
    (should (seq-every-p
             (lambda (match) (string-suffix-p ".el" (car match)))
             matches))))

(ert-deftest navigator-default-context-does-not-trigger-expensive-providers ()
  (let ((file (expand-file-name "common/scripts/skill-runtime.el"
                                skill-contract-tests-root)))
    (cl-letf (((symbol-function 'emacs-code-navigator-defun-at-line)
               (lambda (&rest _) (ert-fail "defun should be opt-in")))
              ((symbol-function 'emacs-code-navigator-eldoc-at-line)
               (lambda (&rest _) (ert-fail "Eldoc should be opt-in")))
              ((symbol-function 'emacs-code-navigator-diagnostics-at-line)
               (lambda (&rest _) (ert-fail "Flymake should be opt-in"))))
      (let ((context (emacs-code-navigator-context-at-line file 3 1)))
        (should (plist-get context :symbol))
        (should (stringp (plist-get context :region)))
        (should-not (plist-member context :defun))
        (should-not (plist-member context :eldoc))
        (should-not (plist-member context :diagnostics))))))

(ert-deftest navigator-semantic-backend-activates-deferred-buffer-hooks ()
  (with-temp-buffer
    (let (ready)
      (setq-local post-command-hook (list (lambda () (setq ready t))))
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () nil))
                ((symbol-function 'xref-find-backend)
                 (lambda () (and ready 'semantic-backend))))
        (should
         (eq (emacs-code-navigator--semantic-xref-backend)
             'semantic-backend))))))

(ert-deftest navigator-locate-prefers-workspace-symbol-and-falls-back-to-text ()
  (let ((symbol-match '(("symbol.cpp" 4 "Widget")))
        (text-match '(("usage.cpp" 9 "Widget widget;"))))
    (cl-letf (((symbol-function 'emacs-code-navigator-workspace-symbol)
               (lambda (&rest _) symbol-match))
              ((symbol-function 'emacs-code-navigator-search)
               (lambda (&rest _) (ert-fail "text fallback should not run"))))
      (let ((result
             (plist-get
              (emacs-code-navigator-query
               '(:operation locate :query "Widget" :file "/tmp/context.cpp"))
              :data)))
        (should (eq (plist-get result :strategy) 'workspace-symbol))
        (should (equal (plist-get result :matches) symbol-match))))
    (cl-letf (((symbol-function 'emacs-code-navigator-workspace-symbol)
               (lambda (&rest _) nil))
              ((symbol-function 'emacs-code-navigator-search)
               (lambda (&rest _) text-match)))
      (let ((result
             (plist-get
              (emacs-code-navigator-query
               '(:operation locate :query "Widget" :file "/tmp/context.cpp"))
              :data)))
        (should (eq (plist-get result :strategy) 'text-fallback))
        (should (equal (plist-get result :matches) text-match))))))

(ert-deftest preflight-operations-return-standard-envelopes ()
  (dolist (result
           (list (denote-scribe-run '(:operation preflight))
                 (emacs-gtd-execute '(:operation preflight))))
    (should (memq (plist-get result :status) '(ok blocked)))
    (should (eq (plist-get result :operation) 'preflight))
    (should (plist-member result :data))))

(ert-deftest removed-compatibility-symbols-stay-absent ()
  (dolist (symbol '(treeland-commit-context treeland-commit-format
                    treeland-commit-run denote-scribe-git-hywiki-state))
    (should-not (fboundp symbol)))
  (dolist (symbol '(treeland-commit-fill-column
                    treeland-commit-maximum-column
                    treeland-commit-context-maximum-characters
                    treeland-commit-compact-maximum-characters
                    denote-scribe-hywiki-commit-interval
                    denote-scribe-hywiki-commit-marker))
    (should-not (boundp symbol)))
  (should-not (featurep 'treeland-commit)))

(ert-deftest navigator-reports-documentation-truncation ()
  (let* ((emacs-code-navigator-documentation-maximum-characters 3)
         (facet (emacs-code-navigator--compact-facet
                 '(:symbol "sample" :kinds (function)
                   :documentation "abcdef" :source nil))))
    (should (equal (plist-get facet :documentation) "abc"))
    (should (eq (plist-get facet :documentation-truncated) t))
    (should (= (plist-get facet :documentation-original-length) 6))))

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

(ert-deftest git-message-rejects-labels-and-missing-evidence ()
  (should-error
   (ai-git-commit-format
    (plist-put (copy-sequence skill-contract-tests-message-spec)
               :context "Context: redundant label")))
  (should-error
   (ai-git-commit-format '(:type "fix" :summary "reject incomplete input"))))

(ert-deftest destructive-facades-require-authorization-before-effects ()
  (should-error (emacs-gtd-execute '(:operation delete :id "sample")))
  (should-error (denote-scribe-run '(:operation commit)))
  (should-error (org-blog-exporter-run '(:operation publish)))
  (should-error
   (ai-git-commit-run
    (append '(:operation commit) skill-contract-tests-message-spec))))

(ert-deftest git-commit-facade-uses-one-headless-magit-message-argument ()
  (let (captured)
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'ai-git-commit--ensure-magit)
               (lambda () t))
              ((symbol-function 'magit-commit-create)
               (lambda (arguments)
                 (setq captured arguments)
                 'fake-process))
              ((symbol-function 'ai-git-commit--wait-for-process)
               (lambda (process)
                 (should (eq process 'fake-process))
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

(ert-deftest denote-internal-commit-uses-shared-full-message ()
  (let (captured)
    (cl-letf (((symbol-function 'denote-scribe--git-root)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'skill-git-commit-paths)
               (lambda (_root message _paths &rest _)
                 (setq captured message)
                 '(:commit "abc123"))))
      (denote-scribe-git-commit "record result" '("note.org") nil))
    (should (string-prefix-p "feat(notes): record result" captured))
    (should (string-match-p "\n\n" captured))
    (should-not (string-match-p skill-git--body-label-regexp captured))))

(ert-deftest blog-internal-commit-uses-shared-full-message ()
  (let (captured)
    (cl-letf (((symbol-function 'skill-git-relative-path)
               (lambda (_root path &rest _) path))
              ((symbol-function 'skill-git-status)
               (lambda (&rest _) " M page.html"))
              ((symbol-function 'skill-git-commit-paths)
               (lambda (_root message _paths &rest _)
                 (setq captured message)
                 '(:commit "abc123")))
              ((symbol-function 'skill-git-assert-clean) (lambda (_) t))
              ((symbol-function 'skill-git-push)
               (lambda (_) '(:commit "abc123"))))
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

(provide 'skill-contract-tests)

;;; skill-contract-tests.el ends here
