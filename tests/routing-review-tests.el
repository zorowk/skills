;;; routing-review-tests.el --- Validate routing review fixtures -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)
(require 'routing-cases)

(skill-tests-load-many
 '("emacs-code-navigator/scripts/emacs-code-navigator.el"
   "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
   "denote-scribe/scripts/denote-scribe.el"
   "org-blog-exporter/scripts/org-blog-exporter.el"
   "git-commit/scripts/ai-git-commit.el"))

(defconst skill-routing-review-test-schemas
  '((emacs-code-navigator . emacs-code-navigator--schemas)
    (emacs-gtd-assistant . emacs-gtd--schemas)
    (denote-scribe . denote-scribe--schemas)
    (org-blog-exporter . org-blog-exporter--schemas)
    (git-commit . ai-git-commit--schemas)))

(ert-deftest routing-review-operations-exist-in-the-expected-facade ()
  (dolist (case skill-routing-review-cases)
    (let* ((expected (plist-get case :expected))
           (operation (plist-get case :expected-operation))
           (operations (plist-get case :expected-operations)))
      (when (cdr expected)
        (should-not operation)
        (should (equal (sort (copy-sequence expected) #'string<)
                       (sort (mapcar #'car operations) #'string<))))
      (when operation
        (should (= (length expected) 1))
        (setq operations (list (cons (car expected) operation))))
      (dolist (entry operations)
        (should (memq (car entry) expected))
        (let ((schema-symbol (alist-get (car entry) skill-routing-review-test-schemas)))
          (should schema-symbol)
          (should (assq (cdr entry) (symbol-value schema-symbol))))))))

(defun skill-routing-review-test-symbol-list-p (value)
  "Return non-nil when VALUE is a proper list of symbols."
  (and (proper-list-p value) (seq-every-p #'symbolp value)))

(defconst skill-routing-review-test-case-classes
  '(positive negative ambiguous unauthorized partial-recovery schema-mismatch
             false-completion))

(defconst skill-routing-review-test-controls
  '(execute answer-without-skill ask-and-stop inspect-and-retry-selectively
            describe-and-retry-once report-incomplete))

(ert-deftest routing-review-cases-have-valid-skill-boundaries ()
  (let (ids)
    (should (>= (length skill-routing-review-cases) 8))
    (dolist (case skill-routing-review-cases)
      (let ((id (plist-get case :id))
            (case-class (plist-get case :case-class))
            (request (plist-get case :request))
            (expected (plist-get case :expected))
            (excluded (plist-get case :excluded))
            (operation (plist-get case :expected-operation))
            (mutation (plist-get case :mutation))
            (control (plist-get case :control))
            (completion (plist-get case :completion))
            (reason (plist-get case :reason)))
        (should (symbolp id))
        (should-not (memq id ids))
        (push id ids)
        (should (and (stringp request) (not (string-empty-p request))))
        (should (and (stringp reason) (not (string-empty-p reason))))
        (should (memq case-class skill-routing-review-test-case-classes))
        (should (skill-routing-review-test-symbol-list-p expected))
        (should (skill-routing-review-test-symbol-list-p excluded))
        (should (or (null operation) (symbolp operation)))
        (should (plist-member case :expected-operation))
        (should (memq mutation '(allowed forbidden conditional)))
        (should (memq control skill-routing-review-test-controls))
        (should (memq completion '(allowed forbidden conditional)))
        (should (or expected excluded))
        (should-not (seq-intersection expected excluded))
        (dolist (skill (append expected excluded))
          (should
           (file-readable-p
            (expand-file-name
             (format "%s/SKILL.md" skill)
             skill-contract-tests-root))))))))

(ert-deftest routing-review-cases-cover-control-failure-classes ()
  (dolist (case-class skill-routing-review-test-case-classes)
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :case-class) case-class))
      skill-routing-review-cases))))

(ert-deftest routing-review-cases-forbid-mutation-before-stop ()
  (dolist (case skill-routing-review-cases)
    (when (memq (plist-get case :control)
                '(ask-and-stop describe-and-retry-once report-incomplete))
      (should-not (eq (plist-get case :mutation) 'allowed))
      (should (eq (plist-get case :completion) 'forbidden)))))

(ert-deftest routing-review-cases-preserve-core-positive-and-negative-examples ()
  (dolist (id '(navigator-unsaved-buffer
                navigator-general-xref-explanation
                gtd-possible-next-step
                gtd-confirmed-capture
                git-explicit-review
                git-no-passive-review
                denote-no-persistence-request))
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :id) id))
      skill-routing-review-cases))))

(ert-deftest facade-skills-defer-mechanical-recovery-to-runtime ()
  (dolist (skill '(denote-scribe emacs-code-navigator emacs-gtd-assistant
                    git-commit org-blog-exporter))
    (let ((contract
           (with-temp-buffer
             (insert-file-contents
              (expand-file-name
               (format "%s/SKILL.md" skill)
               skill-contract-tests-root))
             (buffer-string))))
      (dolist (duplicate '("## Execution and recovery"
                           "known schema"
                           "invalid-request #1"))
        (should-not (string-match-p (regexp-quote duplicate) contract))))))

(ert-deftest repository-documents-semantic-skill-body-boundary ()
  (let ((readme
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name "README.md" skill-contract-tests-root))
           (buffer-string))))
    (should
     (string-match-p
      (regexp-quote
       "SKILL.md 不是 facade 的使用手册，也不是错误目录。它只保存无法在 Elisp 中可靠编码的语义决策。")
      readme))))

(provide 'routing-review-tests)

;;; routing-review-tests.el ends here
