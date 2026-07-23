;;; skill-usage-review-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/agent-shell-bridge.el"
   "skill-usage-review/scripts/agent-shell-skill-usage-review.el"))

(defvar agent-shell-skill-usage-review--suppress-count)
(defvar skill-agent-shell-turn-actions)

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

(ert-deftest skill-usage-review-action-is-read-only-and-tool-gated ()
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
    (should (string-match-p "diagnostic only" prompt)))
  (with-temp-buffer
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))
    (should
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "cancelled" :tool-call-ids ("call-1"))))
    (setq agent-shell-skill-usage-review--suppress-count 1)
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))
    (should
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))))

(ert-deftest skill-usage-review-registers-one-english-prompt-action ()
  (let ((skill-agent-shell-turn-actions nil)
        inserted)
    (cl-letf (((symbol-function 'skill-agent-shell-bridge-enable)
               #'ignore)
              ((symbol-function 'agent-shell-insert)
               (lambda (&rest arguments) (setq inserted arguments))))
      (agent-shell-skill-usage-review-enable)
      (agent-shell-skill-usage-review-enable)
      (let ((action
             (seq-find
              (lambda (entry)
                (eq (plist-get entry :id) 'skill-usage-review))
              skill-agent-shell-turn-actions)))
        (should (equal (plist-get action :label) "Review skill usage"))
        (should (= (plist-get action :priority) 10))
        (should
         (= (seq-count
             (lambda (entry)
               (eq (plist-get entry :id) 'skill-usage-review))
             skill-agent-shell-turn-actions)
            1)))
      (with-temp-buffer
        (agent-shell-skill-usage-review (current-buffer))
        (should (eq (plist-get inserted :submit) t))
        (should (eq (plist-get inserted :shell-buffer) (current-buffer)))
        (should
         (equal (plist-get inserted :text)
                (agent-shell-skill-usage-review--prompt)))))))

(provide 'skill-usage-review-tests)

;;; skill-usage-review-tests.el ends here
