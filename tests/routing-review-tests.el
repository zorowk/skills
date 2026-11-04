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

(defconst skill-routing-review-test-case-classes
  '(positive negative ambiguous unauthorized partial-recovery schema-mismatch
             false-completion))

(defconst skill-routing-review-test-controls
  '(execute answer-without-skill ask-and-stop inspect-and-retry-selectively
            describe-and-retry-once report-incomplete))

(defun skill-routing-review-test-assert-case (case)
  "Assert the routing fixture CASE has explicit, consistent boundaries."
  (should (proper-list-p case))
  (should (zerop (% (length case) 2)))
  (let* ((required '(:id :case-class :request :expected :excluded
                    :expected-operations :mutation :control :completion :reason))
         (keys (cl-loop for (key _) on case by #'cddr collect key))
         (expected (plist-get case :expected))
         (excluded (plist-get case :excluded))
         (operations (plist-get case :expected-operations))
         (control (plist-get case :control))
         (completion (plist-get case :completion)))
    (should (equal keys (seq-uniq keys)))
    (dolist (key required)
      (should (plist-member case key)))
    (dolist (key keys)
      (should (memq key (cons :completion-condition required))))
    (should (plist-get case :id))
    (should (symbolp (plist-get case :id)))
    (dolist (key '(:request :reason))
      (should (stringp (plist-get case key)))
      (should-not (string-empty-p (string-trim (plist-get case key)))))
    (should (memq (plist-get case :case-class)
                  skill-routing-review-test-case-classes))
    (dolist (skills (list expected excluded))
      (should (proper-list-p skills))
      (should (equal skills (seq-uniq skills)))
      (dolist (skill skills)
        (should (assq skill skill-routing-review-test-schemas))
        (should (file-readable-p
                 (expand-file-name (format "%s/SKILL.md" skill)
                                   skill-contract-tests-root)))))
    (should (or expected excluded))
    (should-not (seq-intersection expected excluded))
    (should (memq (plist-get case :mutation) '(allowed forbidden conditional)))
    (should (memq control skill-routing-review-test-controls))
    (should (memq completion '(allowed forbidden conditional)))
    (if (eq completion 'conditional)
        (progn
          (should (stringp (plist-get case :completion-condition)))
          (should-not (string-empty-p
                       (string-trim (plist-get case :completion-condition)))))
      (should-not (plist-member case :completion-condition)))
    (should (proper-list-p operations))
    (dolist (entry operations)
      (should (consp entry))
      (should (memq (car entry) expected))
      (should (cdr entry))
      (should (symbolp (cdr entry)))
      (should (assq (cdr entry)
                    (symbol-value (alist-get (car entry)
                                             skill-routing-review-test-schemas)))))
    (should (equal (mapcar #'car operations)
                   (seq-uniq (mapcar #'car operations))))
    (when (memq control '(execute inspect-and-retry-selectively
                         describe-and-retry-once))
      (should expected)
      (should (= (length expected) (length operations))))
    (when (memq control '(answer-without-skill ask-and-stop report-incomplete))
      (should-not operations))
    (when (eq control 'answer-without-skill)
      (should-not expected)
      (should (eq (plist-get case :mutation) 'forbidden)))
    (when (memq control '(ask-and-stop report-incomplete))
      (should (eq (plist-get case :mutation) 'forbidden))
      (should (eq completion 'forbidden)))
    (when (eq control 'describe-and-retry-once)
      (should operations)
      (should (seq-every-p (lambda (entry) (eq (cdr entry) 'describe)) operations))
      (should (eq (plist-get case :mutation) 'conditional))
      (should (eq completion 'conditional)))
    (when (eq control 'inspect-and-retry-selectively)
      (should (eq (plist-get case :mutation) 'conditional))
      (should (eq completion 'conditional)))))

(ert-deftest routing-review-cases-have-valid-skill-boundaries ()
  (let (ids)
    (dolist (case skill-routing-review-cases)
      (ert-info ((format "Routing case: %S" (plist-get case :id)))
        (skill-routing-review-test-assert-case case)
        (should-not (memq (plist-get case :id) ids))
        (push (plist-get case :id) ids)))))

(ert-deftest routing-review-validator-rejects-invalid-boundaries ()
  (let ((valid (car skill-routing-review-cases)))
    (dolist (replacement
             '((:id nil)
               (:expected (emacs-code-navigator emacs-code-navigator))
               (:excluded (git-commit git-commit))
               (:expected-operations ((emacs-code-navigator . nonexistent)))
               (:expected-operations ((emacs-code-navigator . context)
                                      (emacs-code-navigator . context)))
               (:expected-operations ((git-commit . context)))
               (:expected-operations nil)
               (:control ask-and-stop)
               (:completion conditional)
               (:expected-operation context)))
      (ert-info ((format "Invalid replacement: %S" replacement))
        (should-error
         (skill-routing-review-test-assert-case
          (plist-put (copy-tree valid) (car replacement) (cadr replacement)))
         :type 'ert-test-failed)))
    (should-error
     (skill-routing-review-test-assert-case (cddr valid))
     :type 'ert-test-failed)
    (should-error
     (skill-routing-review-test-assert-case (append valid '(:id duplicate)))
     :type 'ert-test-failed)))

(ert-deftest routing-review-validator-rejects-unconditional-recovery ()
  (dolist (case skill-routing-review-cases)
    (when (memq (plist-get case :control)
                '(inspect-and-retry-selectively describe-and-retry-once))
      (dolist (replacement '((:mutation allowed)
                             (:completion allowed)
                             (:completion-condition " ")
                             (:expected-operations nil)))
        (ert-info ((format "Recovery case: %S, replacement: %S"
                           (plist-get case :id) replacement))
          (should-error
           (skill-routing-review-test-assert-case
            (plist-put (copy-tree case) (car replacement) (cadr replacement)))
           :type 'ert-test-failed))))))

(ert-deftest routing-review-cases-cover-control-failure-classes ()
  (dolist (case-class skill-routing-review-test-case-classes)
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :case-class) case-class))
      skill-routing-review-cases))))

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

(provide 'routing-review-tests)

;;; routing-review-tests.el ends here
