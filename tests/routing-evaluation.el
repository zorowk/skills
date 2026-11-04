;;; routing-evaluation.el --- Inputs for independent routing evaluation -*- lexical-binding: t; -*-

;;; Commentary:

;; This exports fixture data only.  Model execution and human verdicts are
;; deliberately external; ERT cannot establish semantic routing correctness.

;;; Code:

(require 'seq)
(require 'routing-cases)

(defun skill-routing-evaluation--case (id)
  "Return the routing fixture named ID, or signal an error."
  (or (seq-find (lambda (case) (eq (plist-get case :id) id))
                skill-routing-review-cases)
      (error "Unknown routing case: %S" id)))

(defun skill-routing-evaluation-input (id)
  "Return ID's session messages without expected decisions or explanations.
History tool calls are synthetic data, never requests to execute.  The caller
must provide the skill catalog and pin model, prompt and fixture revisions."
  (let ((case (skill-routing-evaluation--case id)))
    (list :case-id id
          :messages
          (append (copy-tree (plist-get case :history))
                  (list (list :role 'user :content (plist-get case :request)))))))

(defun skill-routing-evaluation-check-calls (id calls)
  "Compare proposed next CALLS with ID's operation and critical field constraints.
CALLS is an alist of (SKILL . REQUEST-PLIST).  This is an exact data comparison;
it neither executes calls nor proves full schema or semantic correctness.
Only declared critical fields are compared.  Equivalent safe alternatives
still require human review, including paths expressed in another form."
  (let* ((case (skill-routing-evaluation--case id))
         (expected (plist-get case :expected-operations))
         (operations (mapcar (lambda (call)
                               (cons (car call) (plist-get (cdr call) :operation)))
                             calls))
         failures)
    (dolist (entry (plist-get case :expected-arguments))
      (let ((actual (alist-get (car entry) calls))
            (fields (cdr entry)))
        (while fields
          (unless (and (plist-member actual (car fields))
                       (equal (plist-get actual (car fields)) (cadr fields)))
            (push (list :skill (car entry) :field (car fields)
                        :expected (cadr fields)
                        :actual (if (plist-member actual (car fields))
                                    (plist-get actual (car fields)) 'missing))
                  failures))
          (setq fields (cddr fields)))))
    (list :operations-match (and (= (length operations) (length expected))
                                 (seq-set-equal-p operations expected))
          :arguments-match (null failures) :mismatches (nreverse failures))))

(provide 'routing-evaluation)

;;; routing-evaluation.el ends here
