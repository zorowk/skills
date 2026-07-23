;;; agent-shell-bridge-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/agent-shell-bridge.el"))

(defvar skill-agent-shell-context-maximum-characters)
(defvar skill-agent-shell-context-providers)
(defvar skill-agent-shell-turn-actions)
(defvar skill-agent-shell-last-context-metrics)
(defvar skill-agent-shell--turn-state)
(defvar skill-agent-shell--last-completed-turn)
(defvar skill-agent-shell--available-actions)
(defvar skill-agent-shell-minimum-version)
(defvar agent-shell--version)
(defvar agent-shell-context-sources)
(defvar agent-shell-mode-hook)

(ert-deftest agent-shell-bridge-reports-version-and-api-compatibility ()
  (let ((agent-shell--version skill-agent-shell-minimum-version)
        (agent-shell-context-sources '(files region error line))
        (agent-shell-mode-hook nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to) #'ignore)
              ((symbol-function 'agent-shell-unsubscribe) #'ignore))
      (let ((diagnostics (skill-agent-shell-compatibility)))
        (should (plist-get diagnostics :compatible))
        (should-not (plist-get diagnostics :missing)))
      (let ((agent-shell--version "0.63.2"))
        (should-error (skill-agent-shell--assert-compatible)
                      :type 'user-error))
      (let ((original-fboundp (symbol-function 'fboundp)))
        (cl-letf (((symbol-function 'fboundp)
                   (lambda (symbol)
                     (and (not (eq symbol 'agent-shell-unsubscribe))
                          (funcall original-fboundp symbol)))))
          (let ((diagnostics (skill-agent-shell-compatibility)))
            (should-not (plist-get diagnostics :compatible))
            (should
             (memq 'agent-shell-unsubscribe
                   (plist-get diagnostics :missing)))))))))

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
  (let ((skill-agent-shell-context-providers nil)
        (skill-agent-shell-turn-actions nil))
    (skill-agent-shell-register-context-provider
     'sample :function (lambda () "first") :priority 1)
    (skill-agent-shell-register-context-provider
     'sample :function (lambda () "second") :priority 2)
    (skill-agent-shell-register-turn-action
     'sample :command #'ignore :label "First" :priority 1)
    (skill-agent-shell-register-turn-action
     'sample :command #'ignore :label "Second" :priority 2)
    (should (= (length skill-agent-shell-context-providers) 1))
    (should (= (plist-get (car skill-agent-shell-context-providers)
                          :priority)
               2))
    (should (= (length skill-agent-shell-turn-actions) 1))
    (should (equal (plist-get (car skill-agent-shell-turn-actions) :label)
                   "Second"))))

(ert-deftest agent-shell-bridge-tracks-structured-turn-paths ()
  (with-temp-buffer
    (let ((skill-agent-shell-turn-actions nil)
          observed)
      (setq default-directory "/tmp/")
      (skill-agent-shell-register-turn-action
       'observe
       :function (lambda (_buffer state) (setq observed state))
       :command (lambda (&rest _) nil)
       :label "Observe turn")
      (skill-agent-shell--handle-event
       (current-buffer) '((:event . input-submitted)))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . file-write)
         (:data . ((:path . "one.el")))))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . tool-call-update)
         (:data
          . ((:tool-call
              . ((:diffs
                  . (((:file . "/tmp/two.el"))
                     ((:file . "/tmp/one.el"))))))))))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . turn-complete)
         (:data . ((:stop-reason . "end_turn")))))
      (should observed)
      (should
       (equal (skill-agent-shell-current-turn-paths (current-buffer))
              '("/tmp/one.el" "/tmp/two.el")))
      (should (equal (plist-get observed :stop-reason) "end_turn")))))

(ert-deftest agent-shell-bridge-offers-english-actions-without-file-writes ()
  (with-temp-buffer
    (let ((skill-agent-shell-turn-actions nil)
          (skill-agent-shell-notify-turn-actions nil))
      (skill-agent-shell-register-turn-action
       'capture
       :command (lambda (&rest _) nil)
       :label "Capture as GTD")
      (skill-agent-shell--handle-event
       (current-buffer) '((:event . input-submitted)))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . turn-complete)
         (:data . ((:stop-reason . "end_turn")))))
      (should
       (equal (mapcar (lambda (entry) (plist-get entry :label))
                      skill-agent-shell--available-actions)
              '("Capture as GTD"))))))

(provide 'agent-shell-bridge-tests)

;;; agent-shell-bridge-tests.el ends here
