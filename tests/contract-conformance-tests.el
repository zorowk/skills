;;; contract-conformance-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "emacs-code-navigator/scripts/emacs-code-navigator.el"
   "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
   "denote-scribe/scripts/denote-scribe.el"
   "org-blog-exporter/scripts/org-blog-exporter.el"
   "git-commit/scripts/ai-git-commit.el"))

(defvar denote-scribe-notes-directory)
(defvar denote-scribe-hywiki-directory)
(defvar denote-scribe-git-directory)
(defvar hywiki-directory)
(defvar emacs-gtd-directory)
(defvar emacs-gtd-file)
(defvar org-id-locations-file)

(defconst skill-contract-test-facades
  '((:name navigator
     :call emacs-code-navigator-query
     :required-operations
     (symbols region imenu file-state workspace-symbol xref locate locate-many
              diagnostics))
    (:name gtd
     :call emacs-gtd-execute
     :required-operations (preflight)
     :paged-operations (list))
    (:name denote
     :call denote-scribe-run
     :required-operations (preflight)
     :paged-operations (review list))
    (:name blog
     :call org-blog-exporter-run
     :paged-operations (export publish))
    (:name git
     :call ai-git-commit-run
     :required-operations (commit amend)))
  "Facade entry points and cross-facade contract expectations.")

(defconst skill-contract-test-destructive-requests
  '((:facade gtd :operation delete
     :request (:operation delete :id "sample"))
    (:facade denote :operation commit
     :request (:operation commit :title "Review note" :paths ("note.org")))
    (:facade blog :operation publish
     :request (:operation publish))
    (:facade git :operation commit
     :request (:operation commit)))
  "Representative destructive requests that must fail before effects.")

(defconst skill-contract-test-metric-fields
  '(:metrics-version :elapsed-ms :request-characters :request-field-count
    :payload-characters :base-response-characters :result-count :truncated
    :degraded :resolved-source)
  "Required fields in every facade metrics plist.")

(defun skill-contract-test-facade (name)
  "Return the registered facade named NAME."
  (or (seq-find
       (lambda (facade) (eq (plist-get facade :name) name))
       skill-contract-test-facades)
      (error "Unknown test facade: %s" name)))

(defun skill-contract-test-call (facade request)
  "Call FACADE with REQUEST."
  (funcall (plist-get facade :call) request))

(defun skill-contract-test-schema (facade operation)
  "Return FACADE schema for OPERATION."
  (plist-get
   (plist-get
    (skill-contract-test-call
     facade (list :operation 'describe :target operation))
    :data)
   :schema))

(defun skill-contract-test-proper-plist-p (value)
  "Return non-nil when VALUE is a proper keyword plist."
  (and (proper-list-p value)
       (zerop (% (length value) 2))
       (cl-loop for (key _) on value by #'cddr always (keywordp key))))

(defun skill-contract-test-assert-success-envelope (result operation)
  "Assert RESULT is a standard successful envelope for OPERATION."
  (should (= (plist-get result :protocol-version) 2))
  (should (eq (plist-get result :status) 'ok))
  (should (eq (plist-get result :operation) operation))
  (should (natnump (plist-get result :count)))
  (should (plist-member result :data))
  (let ((metrics (plist-get result :metrics)))
    (should (skill-contract-test-proper-plist-p metrics))
    (dolist (field skill-contract-test-metric-fields)
      (should (plist-member metrics field)))))

(defun skill-contract-test-destructive-request (entry)
  "Return the complete unauthorized request for destructive ENTRY."
  (let ((request (copy-tree (plist-get entry :request))))
    (if (eq (plist-get entry :facade) 'git)
        (append request skill-contract-tests-message-spec)
      request)))

(ert-deftest facade-schemas-expose-high-value-value-constraints ()
  (let* ((navigator
          (plist-get
           (plist-get
            (emacs-code-navigator-query
             '(:operation describe :target locate))
            :data)
           :schema))
         (commit
          (plist-get
           (plist-get
            (ai-git-commit-run '(:operation describe :target commit))
            :data)
           :schema))
         (template
          (plist-get
           (plist-get
            (denote-scribe-run '(:operation describe :target template))
            :data)
           :schema))
         (publish
          (plist-get
           (plist-get
            (org-blog-exporter-run
             '(:operation describe :target publish))
            :data)
           :schema)))
    (should (assq :kind (plist-get navigator :choices)))
    (should (assq :risk (plist-get commit :choices)))
    (should (assq :validation (plist-get commit :types)))
    (should (assq :language (plist-get template :choices)))
    (should (plist-get publish :verification))))

(ert-deftest skill-facades-describe-with-standard-envelope ()
  (dolist (facade skill-contract-test-facades)
    (let ((result
           (skill-contract-test-call facade '(:operation describe))))
      (skill-contract-test-assert-success-envelope result 'describe)
      (should (plist-get (plist-get result :data) :operations)))))

(ert-deftest skill-facades-return-structured-invalid-requests ()
  (dolist (facade skill-contract-test-facades)
    (let* ((result
            (skill-contract-test-call facade '(:operation unknown)))
           (error-data (plist-get result :error)))
      (skill-contract-tests-assert-failure
       result 'needs-input 'invalid-request)
      (dolist (field '(:code :message :retry :required-action))
        (should (plist-member error-data field)))
      (should (equal (plist-get error-data :field-path) '(:operation))))))

(ert-deftest facade-operation-schemas-carry-elisp-owned-guidance ()
  (dolist (facade skill-contract-test-facades)
    (let* ((description
            (plist-get
             (skill-contract-test-call facade '(:operation describe))
             :data))
           (operations (plist-get description :operations))
           (catalog (plist-get description :catalog)))
      (should (equal operations (mapcar (lambda (item)
                                          (plist-get item :operation))
                                        catalog)))
      (should (seq-every-p
               (lambda (item) (stringp (plist-get item :summary)))
               catalog))
      (dolist (operation operations)
        (let ((schema (skill-contract-test-schema facade operation)))
          (should (stringp (plist-get schema :summary))))))))

(ert-deftest facade-schemas-expose-migrated-core-operations ()
  (dolist (facade skill-contract-test-facades)
    (let ((operations
           (plist-get
            (plist-get
             (skill-contract-test-call facade '(:operation describe))
             :data)
            :operations)))
      (dolist (operation (plist-get facade :required-operations))
        (should (memq operation operations))))))

(ert-deftest facade-paginated-operations-declare-continuation-inputs ()
  (dolist (facade skill-contract-test-facades)
    (dolist (operation (plist-get facade :paged-operations))
      (let ((optional
             (plist-get
              (skill-contract-test-schema facade operation)
              :optional)))
        (should (memq :offset optional))
        (should (memq :limit optional))))))

(ert-deftest facade-effect-declarations-use-one-uniform-shape ()
  (dolist (facade skill-contract-test-facades)
    (let ((operations
           (plist-get
            (plist-get
             (skill-contract-test-call facade '(:operation describe))
             :data)
            :operations)))
      (dolist (operation operations)
        (when-let* ((effects
                    (plist-get
                     (skill-contract-test-schema facade operation)
                     :effects)))
          (should (proper-list-p effects))
          (should (seq-every-p #'symbolp effects))
          (should (= (length effects)
                     (length (delete-dups (copy-sequence effects))))))))))

(ert-deftest preflight-operations-return-standard-envelopes ()
  (let* ((root (make-temp-file "skill-preflight-" t))
         (notes (expand-file-name "notes" root))
         (hywiki (expand-file-name "hywiki" root))
         (gtd (expand-file-name "gtd" root))
         (emacs-gtd-directory gtd)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root))
         (denote-scribe-notes-directory notes)
         (denote-scribe-hywiki-directory hywiki)
         (denote-scribe-git-directory root)
         (hywiki-directory hywiki))
    (unwind-protect
        (progn
          (dolist (directory (list notes hywiki gtd))
            (make-directory directory))
          (with-temp-file (expand-file-name emacs-gtd-file gtd)
            (insert "* Tasks\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (dolist (result
                   (list (denote-scribe-run '(:operation preflight))
                         (emacs-gtd-execute '(:operation preflight))))
            (should (memq (plist-get result :status) '(ok blocked)))
            (should (eq (plist-get result :operation) 'preflight))
            (should (plist-member result :data))))
      (delete-directory root t))))

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

(ert-deftest destructive-facades-require-authorization-before-effects ()
  (dolist (entry skill-contract-test-destructive-requests)
    (let* ((facade
            (skill-contract-test-facade (plist-get entry :facade)))
           (operation (plist-get entry :operation))
           (schema (skill-contract-test-schema facade operation))
           (authorization
            (assq :authorization (plist-get schema :choices)))
           (result
            (skill-contract-test-call
             facade (skill-contract-test-destructive-request entry))))
      (should (memq :authorization (plist-get schema :required)))
      (should (equal authorization '(:authorization explicit)))
      (should (plist-get schema :effects))
      (skill-contract-tests-assert-failure
       result 'needs-input 'authorization-required)
      (should-not (plist-get result :effects)))))

(provide 'contract-conformance-tests)

;;; contract-conformance-tests.el ends here
