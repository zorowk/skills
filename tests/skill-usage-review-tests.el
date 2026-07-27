;;; skill-usage-review-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "skill-usage-review/scripts/agent-shell-skill-usage-review.el"))

(ert-deftest skill-usage-review-keeps-quality-dimensions-independent ()
  (let ((contract
         (with-temp-buffer
           (insert-file-contents
            (expand-file-name
             "skill-usage-review/SKILL.md"
             skill-contract-tests-root))
           (buffer-string))))
    (dolist (dimension
             '("Correctness:" "Evidence sufficiency:" "Safety:" "Economy:"))
      (should (string-match-p (regexp-quote dimension) contract)))
    (should
     (string-match-p
      (regexp-quote
       "Do not sum, average, weight, or otherwise combine the four ratings")
      contract))
    (should (string-match-p "Observed recovery cost:" contract))
    (should (string-match-p "Latent recovery risk:" contract))
    (should (string-match-p "Metrics are diagnostic evidence" contract))
    (should (string-match-p "optimization targets" contract))
    (should-not (string-match-p "Call economy: 25" contract))
    (should-not (string-match-p "Response relevance: 25" contract))))

(ert-deftest skill-usage-review-command-is-read-only ()
  (let ((prompt (agent-shell-skill-usage-review--prompt)))
    (should (string-match-p "\\$skill-usage-review" prompt))
    (should (string-match-p "Do not rerun" prompt))
    (should (string-match-p "modify files" prompt))
    (should (string-match-p "rather than exact token usage" prompt))
    (dolist (dimension
             '("correctness" "evidence sufficiency" "safety" "economy"))
      (should (string-match-p dimension prompt)))
    (should (string-match-p "Do not combine" prompt))
    (should (string-match-p "composite score" prompt))
    (should (string-match-p "observed recovery cost" prompt))
    (should (string-match-p "latent recovery risk" prompt))
    (should (string-match-p "diagnostic only" prompt))))

(ert-deftest skill-usage-review-inserts-one-explicit-request ()
  (let (inserted)
    (cl-letf (((symbol-function 'agent-shell-insert)
               (lambda (&rest arguments) (setq inserted arguments))))
      (with-temp-buffer
        (agent-shell-skill-usage-review (current-buffer))
        (should (eq (plist-get inserted :submit) t))
        (should (eq (plist-get inserted :shell-buffer) (current-buffer)))
        (should
         (equal (plist-get inserted :text)
                (agent-shell-skill-usage-review--prompt)))))))

(provide 'skill-usage-review-tests)

;;; skill-usage-review-tests.el ends here
