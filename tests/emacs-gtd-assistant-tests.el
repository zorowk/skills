;;; emacs-gtd-assistant-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/agent-shell-bridge.el"
   "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
   "emacs-gtd-assistant/scripts/agent-shell-gtd-capture.el"))

(defvar agent-shell-gtd-capture--suppress-count)
(defvar emacs-gtd-capture-task-limit)
(defvar emacs-gtd-directory)
(defvar emacs-gtd-file)
(defvar org-id-locations-file)

(ert-deftest gtd-facade-mutates-only-the-configured-file ()
  (let* ((root (make-temp-file "gtd-facade-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Personal\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (let* ((inhibit-message t)
                 (message-log-max nil)
                 (added
                  (emacs-gtd-execute
                   '(:operation add :title "Temporary task"
                     :headline "Personal")))
                 (id (plist-get (plist-get added :data) :id))
                 (listed
                  (emacs-gtd-execute
                   '(:operation list :query "Temporary task" :limit 5))))
            (should (stringp id))
            (should (= (plist-get listed :count) 1))
            (should
             (eq (plist-get
                  (emacs-gtd-execute
                   (list :operation 'delete :id id
                         :authorization 'explicit))
                  :status)
                 'ok))
            (should (= (plist-get
                        (emacs-gtd-execute
                         '(:operation list :query "Temporary task" :limit 5))
                        :count)
                       0))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-mutations-structure-missing-and-ambiguous-targets ()
  (let* ((root (make-temp-file "gtd-target-failures-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Personal\n"
                    "** TODO Duplicate task\n"
                    "** TODO Duplicate task\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (let* ((missing-id
                  (emacs-gtd-execute
                   '(:operation set-state :id "missing-id" :state "DONE")))
                 (missing-title
                  (emacs-gtd-execute
                   '(:operation set-state :query "Absent task"
                     :state "DONE")))
                 (ambiguous
                  (emacs-gtd-execute
                   '(:operation set-state :query "Duplicate task"
                     :state "DONE"))))
            (skill-contract-tests-assert-failure
             missing-id 'needs-input 'not-found)
            (should
             (eq (plist-get (plist-get missing-id :error) :target-type)
                 'gtd-id))
            (skill-contract-tests-assert-failure
             missing-title 'needs-input 'not-found)
            (should (= (plist-get missing-title :count) 0))
            (skill-contract-tests-assert-failure
             ambiguous 'needs-input 'ambiguous)
            (should (= (plist-get ambiguous :count) 2))
            (should
             (= (length
                 (plist-get (plist-get ambiguous :data) :matches))
                2))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-conversation-capture-requires-confirmation-and-writes-structure ()
  (let* ((root (make-temp-file "gtd-capture-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root))
         (request
          '(:operation add-many
            :tasks
            ((:title "Trace drop action mapping"
              :headline "Deepin"
              :priority "B"
              :tags ("research" "wayland")
              :context-notes "Find the cursor update boundary."
              :properties (("SOURCE" . "agent-shell")
                           ("PROJECT" . "qt6-wayland"))
              :links
              ((:target "https://wayland.app/protocols/wayland"
                :description "Wayland protocol")
               (:target "file:/tmp/drag.cpp::42"
                :description "Drag implementation")))))))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Personal\n* Deepin\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (skill-contract-tests-assert-failure
           (emacs-gtd-execute request)
           'needs-input 'authorization-required)
          (let ((result
                 (emacs-gtd-execute
                  (append request '(:authorization explicit)))))
            (should (= (plist-get result :count) 1))
            (with-temp-buffer
              (insert-file-contents file)
              (let ((text (buffer-string)))
                (should (string-match-p
                         "\\*\\* TODO \\[#B\\] Trace drop action mapping"
                         text))
                (should (string-match-p ":SOURCE:.*agent-shell" text))
                (should (string-match-p ":CONTEXT:" text))
                (should (string-match-p ":RESOURCES:" text))
                (should (string-match-p "Wayland protocol" text))))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-add-many-schema-exposes-and-enforces-task-shape ()
  (let* ((description
          (emacs-gtd-execute '(:operation describe :target add-many)))
         (schema (plist-get (plist-get description :data) :schema))
         (tasks-type (cadr (assq :tasks (plist-get schema :types))))
         (task-type (cadr tasks-type)))
    (should (eq (car tasks-type) 'list-of))
    (should (eq (car task-type) 'plist))
    (should (plist-get (cdr task-type) :closed))
    (should (assq :tasks (plist-get schema :validators))))
  (let* ((result
          (emacs-gtd-execute
           '(:operation add-many :authorization explicit
             :tasks ((:title "Task" :priority "AB")))))
         (error-data (plist-get result :error)))
    (skill-contract-tests-assert-failure
     result 'needs-input 'invalid-request)
    (should (string-match-p "tasks\\[0\\]"
                            (plist-get error-data :message))))
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many :authorization explicit
      :tasks ((:title "Task" :unknown t))))
   'needs-input 'invalid-request)
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many :authorization explicit
      :tasks ((:title "Task" :context someday))))
   'needs-input 'invalid-request)
  (let ((emacs-gtd-capture-task-limit 1))
    (skill-contract-tests-assert-failure
     (emacs-gtd-execute
      '(:operation add-many :authorization explicit
        :tasks ((:title "One") (:title "Two"))))
     'needs-input 'invalid-request)))

(ert-deftest gtd-capture-prompt-is-read-only-and-suppresses-loops ()
  (let ((prompt (agent-shell-gtd-capture--prompt)))
    (should (string-match-p "Do not write to gtd.org yet" prompt))
    (should (string-match-p ":operation add-many" prompt))
    (should (string-match-p ":authorization explicit" prompt))
    (should (string-match-p ":context work" prompt)))
  (with-temp-buffer
    (setq agent-shell-gtd-capture--suppress-count 1)
    (should-not
     (agent-shell-gtd-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))
    (should
     (agent-shell-gtd-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))))

(ert-deftest gtd-capture-rejects-executable-org-links ()
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many
      :authorization explicit
      :tasks
      ((:title "Unsafe link"
        :links ((:target "elisp:(message \"unsafe\")"))))))
   'needs-input 'invalid-request))

(provide 'emacs-gtd-assistant-tests)

;;; emacs-gtd-assistant-tests.el ends here
