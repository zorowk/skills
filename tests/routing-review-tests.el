;;; routing-review-tests.el --- Validate routing review fixtures -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)
(require 'routing-cases)

(defun skill-routing-review-test-symbol-list-p (value)
  "Return non-nil when VALUE is a proper list of symbols."
  (and (proper-list-p value) (seq-every-p #'symbolp value)))

(ert-deftest routing-review-cases-have-valid-skill-boundaries ()
  (let (ids)
    (should (>= (length skill-routing-review-cases) 8))
    (dolist (case skill-routing-review-cases)
      (let ((id (plist-get case :id))
            (request (plist-get case :request))
            (expected (plist-get case :expected))
            (excluded (plist-get case :excluded))
            (reason (plist-get case :reason)))
        (should (symbolp id))
        (should-not (memq id ids))
        (push id ids)
        (should (and (stringp request) (not (string-empty-p request))))
        (should (and (stringp reason) (not (string-empty-p reason))))
        (should (skill-routing-review-test-symbol-list-p expected))
        (should (skill-routing-review-test-symbol-list-p excluded))
        (should (or expected excluded))
        (should-not (seq-intersection expected excluded))
        (dolist (skill (append expected excluded))
          (should
           (file-readable-p
            (expand-file-name
             (format "%s/SKILL.md" skill)
             skill-contract-tests-root))))))))

(ert-deftest routing-review-cases-preserve-core-positive-and-negative-examples ()
  (dolist (id '(navigator-unsaved-buffer
                navigator-general-xref-explanation
                gtd-possible-next-step
                gtd-confirmed-capture))
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :id) id))
      skill-routing-review-cases))))

(provide 'routing-review-tests)

;;; routing-review-tests.el ends here
