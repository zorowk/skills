;;; skill-usage-review-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

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

(provide 'skill-usage-review-tests)

;;; skill-usage-review-tests.el ends here
