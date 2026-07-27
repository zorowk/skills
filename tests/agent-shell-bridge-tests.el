;;; agent-shell-bridge-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/agent-shell-bridge.el"))

(defvar skill-agent-shell-context-maximum-characters)
(defvar skill-agent-shell-context-providers)
(defvar skill-agent-shell-last-context-metrics)
(defvar skill-agent-shell-minimum-version)
(defvar agent-shell--version)
(defvar agent-shell-context-sources)

(ert-deftest agent-shell-bridge-reports-version-and-api-compatibility ()
  (let ((agent-shell--version skill-agent-shell-minimum-version)
        (agent-shell-context-sources '(files region error line)))
    (let ((diagnostics (skill-agent-shell-compatibility)))
      (should (plist-get diagnostics :compatible))
      (should-not (plist-get diagnostics :missing)))
    (let ((agent-shell--version "0.63.2"))
      (should-error (skill-agent-shell--assert-compatible)
                    :type 'user-error))))

(ert-deftest agent-shell-bridge-shares-one-hard-context-budget ()
  (let ((skill-agent-shell-context-providers nil)
        (skill-agent-shell-context-maximum-characters 12))
    (skill-agent-shell-register-context-provider
     'first :function (lambda () "abcdefgh") :priority 20)
    (skill-agent-shell-register-context-provider
     'broken :function (lambda () (error "unavailable")) :priority 15)
    (skill-agent-shell-register-context-provider
     'second :function (lambda () "ijklmnop") :priority 10)
    (let ((context (skill-agent-shell-context)))
      (should (= (length context) 12))
      (should (string-prefix-p "abcdefgh" context))
      (should (= (length
                  (plist-get skill-agent-shell-last-context-metrics
                             :providers))
                 3))
      (should-not
       (string-match-p "unavailable"
                       (prin1-to-string
                        skill-agent-shell-last-context-metrics))))))

(ert-deftest agent-shell-bridge-replaces-registrations-by-id ()
  (let ((skill-agent-shell-context-providers nil))
    (skill-agent-shell-register-context-provider
     'sample :function (lambda () "first") :priority 1)
    (skill-agent-shell-register-context-provider
     'sample :function (lambda () "second") :priority 2)
    (should (= (length skill-agent-shell-context-providers) 1))
    (should (= (plist-get (car skill-agent-shell-context-providers)
                          :priority)
               2))))

(provide 'agent-shell-bridge-tests)

;;; agent-shell-bridge-tests.el ends here
