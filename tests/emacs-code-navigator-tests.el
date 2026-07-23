;;; emacs-code-navigator-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/agent-shell-bridge.el"
   "emacs-code-navigator/scripts/emacs-code-navigator.el"
   "emacs-code-navigator/scripts/agent-shell-code-context.el"))

(defvar emacs-code-navigator-documentation-maximum-characters)
(defvar emacs-code-navigator-symbol-batch-limit)
(defvar emacs-code-navigator-agent-shell-context-enabled)
(defvar emacs-code-navigator-agent-shell-context-maximum-characters)
(defvar emacs-code-navigator-agent-shell-context-radius)
(defvar emacs-code-navigator-agent-shell-diagnostic-limit)
(defvar emacs-code-navigator-agent-shell-last-context-metrics)
(defvar emacs-code-navigator-agent-shell-semantic-level)
(defvar emacs-code-navigator-agent-shell-definition-limit)
(defvar emacs-code-navigator-agent-shell-semantic-timeout-ms)
(defvar emacs-code-navigator-semantic-buffer-policy)
(defvar emacs-code-navigator-semantic-buffer-limit)
(defvar emacs-code-navigator--semantic-buffers)
(defvar skill-agent-shell-context-providers)
(defvar agent-shell-context-sources)

(ert-deftest navigator-schema-validates-numeric-boolean-and-exclusive-fields ()
  (let* ((description
          (emacs-code-navigator-query
           '(:operation describe :target context)))
         (schema (plist-get (plist-get description :data) :schema))
         (types (plist-get schema :types)))
    (should (equal (cadr (assq :line types)) '(integer :min 1)))
    (should (eq (cadr (assq :definitions types)) 'boolean)))
  (dolist
      (request
       '((:operation context :file "/tmp/example.el" :line "1")
         (:operation context :file "/tmp/example.el" :line 1
                     :definitions yes)
         (:operation locate-many :query "value"
                     :directories ("/a" "/b" "/c" "/d" "/e" "/f"))
         (:operation diagnostics :file "/tmp/example.el"
                     :directory "/tmp")))
    (skill-contract-tests-assert-failure
     (emacs-code-navigator-query request)
     'needs-input 'invalid-request)))

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
            (let* ((noninteractive nil)
                   (matches
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

(ert-deftest navigator-source-provenance-distinguishes-live-and-disk ()
  (let* ((root (make-temp-file "navigator-source-" t))
         (file (expand-file-name "sample.el" root))
         live-buffer)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "disk-value\n"))
          (setq live-buffer (find-file-noselect file))
          (with-current-buffer live-buffer
            (goto-char (point-max))
            (insert "live-value\n"))
          (let* ((live
                  (emacs-code-navigator-query
                   (list :operation 'region :file file :start-line 1
                         :end-line 2 :source 'live)))
                 (disk
                  (emacs-code-navigator-query
                   (list :operation 'region :file file :start-line 1
                         :end-line 2 :source 'disk)))
                 (state
                  (plist-get
                   (emacs-code-navigator-query
                    (list :operation 'file-state :file file))
                   :data)))
            (should (string-match-p "live-value" (plist-get live :data)))
            (should-not (string-match-p "live-value" (plist-get disk :data)))
            (should (eq (plist-get (plist-get live :provenance)
                                   :resolved-source)
                        'live))
            (should (eq (plist-get (plist-get disk :provenance)
                                   :resolved-source)
                        'disk))
            (should (eq (plist-get (plist-get disk :provenance) :session)
                        'batch))
            (should (eq (plist-get (plist-get disk :provenance) :degraded)
                        t))
            (should (eq (plist-get state :buffer-modified) t))
            (should (eq (plist-get state :diverged) t))))
      (when (buffer-live-p live-buffer)
        (with-current-buffer live-buffer
          (set-buffer-modified-p nil))
        (kill-buffer live-buffer))
      (delete-directory root t))))

(ert-deftest navigator-disk-source-rejects-live-semantic-queries ()
  (let* ((result
          (emacs-code-navigator-query
           '(:operation workspace-symbol :file "/tmp/sample.el"
             :pattern "sample" :source disk)))
         (error-data (plist-get result :error)))
    (skill-contract-tests-assert-failure
     result 'blocked 'unavailable)
    (should (equal (plist-get error-data :capability)
                   "Workspace-symbol queries"))
    (should (eq (plist-get error-data :actual-source) 'disk))
    (should (equal (plist-get error-data :required-source)
                   '(auto live)))))

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

(ert-deftest navigator-agent-shell-context-is-live-bounded-and-cheap ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "(message sample-symbol)\n")
    (goto-char (point-min))
    (search-forward "sample-symbol")
    (backward-char 1)
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 180)
          (emacs-code-navigator-agent-shell-context-radius 2)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0)
          (emacs-code-navigator-agent-shell-semantic-level 'definitions)
          request)
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (value)
                   (setq request value)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("message" (1 2 1 9) emacs-lisp-mode nil 1)
                            :region "1:(message sample-symbol)")
                     :provenance (:session live :resolved-source live
                                  :buffer-modified t :disk-diverged t)))))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "\\[live-emacs-code-context\\]" context))
          (should (string-match-p "symbol: sample-symbol" context))
          (should (<= (length context) 180))
          (should (= (plist-get
                      emacs-code-navigator-agent-shell-last-context-metrics
                      :characters)
                     (length context)))
          (should-not
           (plist-member emacs-code-navigator-agent-shell-last-context-metrics
                         :context))
          (should (eq (plist-get request :operation) 'context))
          (should (eq (plist-get request :source) 'live))
          (should (eq (plist-get request :definitions) t))
          (should (= (plist-get request :column) 21))
          (should (= (plist-get request :radius) 2)))))))

(ert-deftest navigator-agent-shell-context-formats-bounded-semantics ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample-symbol\n")
    (goto-char (point-min))
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 1200)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0)
          (emacs-code-navigator-agent-shell-semantic-level 'definitions))
      (cl-letf (((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:project-root "/tmp/"
                            :scope "Sample::method"
                            :symbol ("sample-symbol" nil emacs-lisp-mode t nil)
                            :region "1:sample-symbol"
                            :semantic
                            (:status ok :provider eglot
                             :definitions
                             (("/tmp/definition.el" 7 "sample definition"))
                             :eldoc ("sample-signature")))
                     :provenance (:session live :resolved-source live))))
                ((symbol-function 'flymake-diagnostics) (lambda (&rest _) nil)))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "scope: Sample::method" context))
          (should (string-match-p "provider=eglot" context))
          (should (string-match-p "definition.el:7" context))
          (should (string-match-p "signature: sample-signature" context)))))))

(ert-deftest navigator-agent-shell-context-falls-through-when-inapplicable ()
  (with-temp-buffer
    (should-not (emacs-code-navigator-agent-shell-context)))
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (cl-letf (((symbol-function 'emacs-code-navigator-query)
               (lambda (&rest _) (error "unavailable"))))
      (should-not (emacs-code-navigator-agent-shell-context)))))

(ert-deftest navigator-agent-shell-context-honors-tiny-hard-budget ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample")
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 8)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("sample" nil emacs-lisp-mode nil nil)
                            :region "1:sample")
                     :provenance (:session live :resolved-source live)))))
        (should (= (length (emacs-code-navigator-agent-shell-context)) 8))))))

(ert-deftest navigator-agent-shell-context-reads-existing-diagnostics-only ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample\n")
    (let ((flymake-mode t)
          (emacs-code-navigator-agent-shell-context-maximum-characters 1200)
          (emacs-code-navigator-agent-shell-diagnostic-limit 1))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("sample" nil emacs-lisp-mode nil nil)
                            :region "1:sample")
                     :provenance (:session live :resolved-source live))))
                ((symbol-function 'flymake-diagnostics)
                 (lambda (&rest _) '(first second)))
                ((symbol-function 'flymake-diagnostic-beg)
                 (lambda (&rest _) (point-min)))
                ((symbol-function 'flymake-diagnostic-end)
                 (lambda (&rest _) (point-max)))
                ((symbol-function 'flymake-diagnostic-type)
                 (lambda (&rest _) 'warning))
                ((symbol-function 'flymake-diagnostic-text)
                 (lambda (diagnostic) (format "%s diagnostic" diagnostic)))
                ((symbol-function 'flymake-start)
                 (lambda (&rest _) (ert-fail "Flymake must not be started"))))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "first diagnostic" context))
          (should-not (string-match-p "second diagnostic" context)))))))

(ert-deftest navigator-agent-shell-enable-preserves-explicit-priority ()
  (let ((agent-shell-context-sources
         '(files region error emacs-code-navigator-agent-shell-context
                 line custom-source))
        (skill-agent-shell-context-providers nil))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (eq feature 'agent-shell)))
              ((symbol-function 'skill-agent-shell--assert-compatible)
               #'ignore))
      (emacs-code-navigator-agent-shell-enable)
      (emacs-code-navigator-agent-shell-enable))
    (should
     (equal agent-shell-context-sources
            '(region error skill-agent-shell-context
                     files line custom-source)))
    (should (= (length skill-agent-shell-context-providers) 1))
    (should (eq (plist-get (car skill-agent-shell-context-providers) :id)
                'emacs-code-navigator))))

(ert-deftest navigator-semantic-context-uses-the-exact-column-and-limit ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-semantic.el")
    (insert "alpha beta\n")
    (let (seen-identifier)
      (cl-letf (((symbol-function 'emacs-code-navigator--require-live-semantic)
                 (lambda (&rest _) t))
                ((symbol-function 'emacs-code-navigator--file-buffer)
                 (lambda (&rest _) (current-buffer)))
                ((symbol-function 'emacs-code-navigator--semantic-xref-backend)
                 (lambda () 'test-backend))
                ((symbol-function 'xref-backend-definitions)
                 (lambda (_backend identifier)
                   (setq seen-identifier identifier)
                   '(first second third)))
                ((symbol-function 'emacs-code-navigator--xref-location-data)
                 (lambda (item) (list "/tmp/definition.el" 1 (format "%s" item))))
                ((symbol-function 'emacs-code-navigator-eldoc-at-line)
                 (lambda (&rest _) '("beta-signature"))))
        (let ((semantic
               (emacs-code-navigator-semantic-at-position
                buffer-file-name 1 7 t 2 t 200)))
          (should (equal seen-identifier "beta"))
          (should (eq (plist-get semantic :status) 'ok))
          (should (= (length (plist-get semantic :definitions)) 2))
          (should (equal (plist-get semantic :eldoc) '("beta-signature"))))))))

(ert-deftest navigator-semantic-buffer-policy-opens-and-safely-cleans-anchor ()
  (let* ((root (make-temp-file "navigator-semantic-root-" t))
         (file (expand-file-name "anchor.cpp" root))
         (emacs-code-navigator-semantic-buffer-policy 'open-on-demand)
         (emacs-code-navigator-semantic-buffer-limit 1)
         (emacs-code-navigator--semantic-buffers nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "void sample();\n"))
          (cl-letf (((symbol-function 'emacs-code-navigator-project-root)
                     (lambda (&rest _) root))
                    ((symbol-function 'emacs-code-navigator-search)
                     (lambda (&rest _) (list (list file 1 "sample")))))
            (let* ((anchor
                    (emacs-code-navigator--semantic-anchor root "sample"))
                   (buffer (plist-get anchor :buffer)))
              (should (eq (plist-get anchor :origin) 'navigator-opened))
              (should (buffer-live-p buffer))
              (with-current-buffer buffer (set-buffer-modified-p t))
              (should (= (emacs-code-navigator-close-semantic-buffers) 0))
              (should (buffer-live-p buffer))
              (with-current-buffer buffer (set-buffer-modified-p nil))
              (should (= (emacs-code-navigator-close-semantic-buffers) 1))
              (should-not (buffer-live-p buffer)))))
      (dolist (buffer emacs-code-navigator--semantic-buffers)
        (when (buffer-live-p buffer) (kill-buffer buffer)))
      (delete-directory root t))))

(ert-deftest navigator-locate-many-preserves-order-and-isolates-errors ()
  (cl-letf (((symbol-function 'emacs-code-navigator--locate-many-project)
             (lambda (directory &rest _)
               (if (string-match-p "broken" directory)
                   (error "broken project")
                 (list :directory directory :strategy 'text
                       :matches (list directory))))))
    (let* ((result
            (emacs-code-navigator-query
             '(:operation locate-many :query "drag"
               :directories ("/tmp/one" "/tmp/broken" "/tmp/three"))))
           (projects (plist-get result :data)))
      (should (equal (mapcar (lambda (item) (plist-get item :directory)) projects)
                     '("/tmp/one" "/tmp/broken" "/tmp/three")))
      (should (eq (plist-get (nth 1 projects) :status) 'error))
      (should (equal (plist-get (nth 2 projects) :matches)
                     '("/tmp/three"))))))

(ert-deftest navigator-locate-many-falls-back-to-bounded-disk-search ()
  (let ((emacs-code-navigator-semantic-buffer-policy 'existing-only))
    (cl-letf (((symbol-function 'emacs-code-navigator-project-root)
               (lambda (directory) (file-name-as-directory directory)))
              ((symbol-function 'emacs-code-navigator--semantic-anchor)
               (lambda (directory _query)
                 (list :origin 'none :project-root directory)))
              ((symbol-function 'emacs-code-navigator--locate-request)
               (lambda (request)
                 (should (eq (plist-get request :kind) 'text))
                 (list :strategy 'text :matches '(("drag.cpp" 4 "drag"))))))
      (let ((project
             (emacs-code-navigator--locate-many-project
              "/tmp/project" "drag" 'auto 3 nil nil 'auto)))
        (should (eq (plist-get project :source) 'disk))
        (should (eq (plist-get project :strategy) 'text))
        (should (= (length (plist-get project :matches)) 1))))))

(ert-deftest navigator-semantic-backend-runs-only-eglot-deferred-hook ()
  (require 'eglot)
  (with-temp-buffer
    (let ((unrelated-hook-ran nil)
          (eglot-hook-ran nil))
      (setq buffer-file-name "/tmp/navigator-eglot.el")
      (setq-local post-command-hook
                  (list (lambda () (setq unrelated-hook-ran t))))
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () nil))
                ((symbol-function 'eglot-ensure)
                 (lambda ()
                   (add-hook
                    'post-command-hook
                    (lambda () (setq eglot-hook-ran t))
                    'append t)))
                ((symbol-function 'xref-find-backend)
                 (lambda () (and eglot-hook-ran 'semantic-backend))))
        (should
         (eq (emacs-code-navigator--semantic-xref-backend)
             'semantic-backend))
        (should eglot-hook-ran)
        (should-not unrelated-hook-ran)))))

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

(ert-deftest navigator-reports-documentation-truncation ()
  (let* ((emacs-code-navigator-documentation-maximum-characters 3)
         (facet (emacs-code-navigator--compact-facet
                 '(:symbol "sample" :kinds (function)
                   :documentation "abcdef" :source nil))))
    (should (equal (plist-get facet :documentation) "abc"))
    (should (eq (plist-get facet :documentation-truncated) t))
    (should (= (plist-get facet :documentation-original-length) 6))))

(ert-deftest navigator-batches-known-and-missing-symbols-in-order ()
  (let* ((missing "emacs-code-navigator-test-missing-symbol")
         (noninteractive nil)
         (result
          (emacs-code-navigator-query
           (list :operation 'symbols :names (list 'car missing 'user-init-file))))
         (data (plist-get result :data))
         (provenance (plist-get result :provenance)))
    (should (= (plist-get result :count) 3))
    (should (equal (mapcar (lambda (item) (plist-get item :symbol)) data)
                   (list "car" missing "user-init-file")))
    (should (eq (plist-get (nth 0 data) :found) t))
    (should-not (plist-get (nth 1 data) :found))
    (should (stringp (plist-get (nth 1 data) :error)))
    (should (eq (plist-get (nth 2 data) :found) t))
    (should (eq (plist-get provenance :session) 'live))
    (should (eq (plist-get provenance :resolved-source) 'session))))

(ert-deftest navigator-batch-symbol-limit-is-enforced ()
  (let ((emacs-code-navigator-symbol-batch-limit 2))
    (should-error
     (emacs-code-navigator-symbols '(car cdr cons)))))

(provide 'emacs-code-navigator-tests)

;;; emacs-code-navigator-tests.el ends here
