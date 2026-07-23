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
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let ((result (funcall call '(:operation describe))))
      (should (eq (plist-get result :status) 'ok))
      (should (eq (plist-get result :operation) 'describe))
      (should (plist-member result :data))
      (should (plist-member result :metrics))
      (should (natnump
               (plist-get (plist-get result :metrics) :elapsed-ms)))
      (should (plist-get (plist-get result :data) :operations)))))

(ert-deftest skill-facades-return-structured-invalid-requests ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let ((result (funcall call '(:operation unknown))))
      (skill-contract-tests-assert-failure
       result 'needs-input 'invalid-request)
      (should (equal
               (plist-get (plist-get result :error) :field-path)
               '(:operation))))))

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
    (dolist (operation
             '(symbols region imenu file-state workspace-symbol xref locate locate-many
                       diagnostics))
      (should (memq operation navigator)))
    (should (memq 'preflight denote))
    (should (memq 'preflight gtd))
    (should (memq 'commit git-commit))
    (should (memq 'amend git-commit))))

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

(ert-deftest destructive-facades-require-authorization-before-effects ()
  (dolist
      (result
       (list
        (emacs-gtd-execute '(:operation delete :id "sample"))
        (denote-scribe-run
         '(:operation commit :title "Review note" :paths ("note.org")))
        (org-blog-exporter-run '(:operation publish))
        (ai-git-commit-run
         (append '(:operation commit) skill-contract-tests-message-spec))))
    (skill-contract-tests-assert-failure
     result 'needs-input 'authorization-required)
    (should-not (plist-get result :effects))))

(provide 'contract-conformance-tests)

;;; contract-conformance-tests.el ends here
