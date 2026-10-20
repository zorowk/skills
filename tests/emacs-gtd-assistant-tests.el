;;; emacs-gtd-assistant-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"))

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
                     :headline "Personal" :authorization explicit)))
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
                   '(:operation set-state :id "missing-id" :state "DONE"
                     :authorization explicit)))
                 (missing-title
                  (emacs-gtd-execute
                   '(:operation set-state :query "Absent task"
                     :state "DONE" :authorization explicit)))
                 (ambiguous
                  (emacs-gtd-execute
                   '(:operation set-state :query "Duplicate task"
                     :state "DONE" :authorization explicit))))
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

(defmacro gtd-project-tests-with-files (&rest body)
  "Run BODY with isolated primary and secondary managed Org files."
  (declare (indent 0) (debug t))
  `(let* ((root (make-temp-file "gtd-project-" t))
          (file (expand-file-name "gtd.org" root))
          (other (expand-file-name "notes.org" root))
          (emacs-gtd-directory root)
          (emacs-gtd-file "gtd.org")
          (emacs-gtd-extra-files (list other))
          (org-id-locations-file (expand-file-name "ids" root))
          (org-id-locations nil))
     (unwind-protect
         (progn
           (with-temp-file org-id-locations-file (insert "()\n"))
           (with-temp-file file (insert "* Personal\n"))
           (with-temp-file other
             (insert "* Project\n:PROPERTIES:\n:ID: project\n:PROJECT_DIR: " root
                     "/\n:END:\n** TODO Existing\n:PROPERTIES:\n:ID: task\n:END:\n"))
           ,@body)
       (dolist (path (list file other))
         (when-let* ((buffer (get-file-buffer path)))
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer)))
       (delete-directory root t))))

(ert-deftest gtd-project-read-is-nonmutating-and-uses-nearest-project ()
  (gtd-project-tests-with-files
    (let* ((result (emacs-gtd-execute '(:operation get :id "task")))
           (data (plist-get result :data)))
      (should (eq (plist-get result :status) 'ok))
      (should (equal (plist-get (plist-get data :task) :id) "task"))
      (should (equal (plist-get (plist-get data :project) :id) "project"))
      (should-not (buffer-modified-p (get-file-buffer other)))
      (should (= (plist-get (emacs-gtd-execute '(:operation list)) :count) 1))
      (should (equal (plist-get (car (plist-get
                                    (emacs-gtd-execute '(:operation list)) :data)) :id) "task")))))

(ert-deftest gtd-project-breakdown-is-authorized-atomic-and-unscheduled ()
  (gtd-project-tests-with-files
    (let ((request '(:operation add-children :parent-id "project"
                     :tasks ((:title "One" :body "Acceptance: passes tests.")
                             (:title "Two") (:title "Three") (:title "Four")))))
      (should (eq (plist-get (emacs-gtd-execute request) :status) 'needs-input))
      (let ((result (emacs-gtd-execute (append request '(:authorization explicit)))))
        (should (eq (plist-get result :status) 'ok))
        (should (= (plist-get result :count) 4))
        (dolist (item (plist-get result :data))
          (should-not (plist-get item :scheduled))
          (should (equal (car (plist-get item :outline)) "Project"))))
      (should (= (plist-get (emacs-gtd-execute '(:operation list)) :count) 5)))
    (should-error
     (emacs-gtd-execute '(:operation add-children :parent-id "project" :authorization explicit
                         :tasks ((:title "Never persists") (:title "Invalid" :todo "BOGUS")))))
    (should (= (plist-get (emacs-gtd-execute '(:operation list)) :count) 5))))

(ert-deftest gtd-project-session-history-and-drawers-belong-to-own-entry ()
  (gtd-project-tests-with-files
    ;; Inserting a missing parent drawer must never overwrite its child's drawer.
    (emacs-gtd-execute '(:operation set-context :id "task" :context-notes "Child context"
                        :authorization explicit))
    (emacs-gtd-execute '(:operation set-context :id "project" :context-notes "Parent context"
                        :authorization explicit))
    (should (equal (plist-get (plist-get (plist-get
                              (emacs-gtd-execute '(:operation get :id "task")) :data) :task) :context)
                   "Child context"))
    (dolist (session '("first" "second" "first"))
      (should (eq (plist-get
                   (emacs-gtd-execute (list :operation 'attach-session :id "task"
                                            :agent "codex" :session-id session :cwd root
                                            :transcript "/tmp/example.md" :authorization 'explicit))
                   :status) 'ok)))
    (let* ((data (plist-get (emacs-gtd-execute '(:operation get :id "task")) :data))
           (sessions (plist-get data :sessions)))
      (should (= (length sessions) 2))
      (should (equal (plist-get (car sessions) :session-id) "first"))
      (should (equal (plist-get (plist-get data :task) :state) "TODO")))
    (emacs-gtd-execute '(:operation set-state :id "task" :state "DONE" :authorization explicit))
    (should (= (plist-get (emacs-gtd-execute '(:operation list)) :count) 0))))

(ert-deftest gtd-project-create-and-own-task-id ()
  (gtd-project-tests-with-files
    (let* ((result (emacs-gtd-execute (list :operation 'create-project :title "New project"
                                           :directory root :authorization 'explicit
                                           :links '((:target "https://example.com/design" :description "Design")))))
           (data (plist-get result :data)))
      (should (eq (plist-get result :status) 'ok))
      (should (plist-get (plist-get data :project) :id))
      (should (string-match-p "Design" (plist-get (plist-get data :project) :resources))))
    (with-current-buffer (find-file-noselect other)
      (goto-char (point-max))
      (insert "** TODO No ID\n")
      (save-buffer))
    (let* ((result (emacs-gtd-execute (list :operation 'ensure-id :file other :line 10
                                           :authorization 'explicit)))
           (id (plist-get (plist-get result :data) :id)))
      (should (stringp id))
      (should-not (equal id "project"))
      (should (eq (plist-get (emacs-gtd-execute (list :operation 'get :id id)) :status) 'ok)))))

(skill-tests-load "emacs-gtd-assistant/scripts/agent-shell-org-tasks.el")
(defvar-local gtd-agent-test-session nil)

(ert-deftest gtd-agent-open-selects-agent-then-native-project-session ()
  (require 'agent-shell)
  (gtd-project-tests-with-files
    (let (shell starts inserts events)
      (unwind-protect
          (cl-letf (((symbol-function 'agent-shell-select-config)
                     (lambda (&rest _) (push 'agent events) '((:identifier . codex))))
                    ((symbol-function 'agent-shell-cwd) (lambda () default-directory))
                    ((symbol-function 'agent-shell-session-id) (lambda (&rest _) gtd-agent-test-session))
                    ((symbol-function 'agent-shell-subscribe-to) (lambda (&rest _) 1))
                    ((symbol-function 'agent-shell-insert)
                     (lambda (&rest args) (push args inserts)))
                    ((symbol-function 'emacs-gtd-agent--start)
                     (lambda (config cwd new)
                       (push 'sessions events)
                       (push (list config cwd new) starts)
                       (setq shell (generate-new-buffer " *gtd-project-picker*"))
                       (with-current-buffer shell
                         (setq major-mode 'agent-shell-mode default-directory cwd))
                       shell)))
            (with-current-buffer (find-file-noselect other)
              (goto-char (point-min)) (search-forward "** TODO")
              (emacs-gtd-agent-open))
            (should (equal (reverse events) '(agent sessions)))
            (should (emacs-gtd-agent--same-directory-p (nth 1 (car starts)) root))
            (should-not (nth 2 (car starts)))
            (should-not (plist-get (car inserts) :submit))
            (with-current-buffer shell
              (should (equal emacs-gtd-agent-task-id "task"))
              (setq-local gtd-agent-test-session "selected-project-session")
              (emacs-gtd-agent--record shell)
              (emacs-gtd-agent-wrap-up))
            (should (string-match-p "add-note" (plist-get (car inserts) :text)))
            (should (= (length starts) 1))
            (should (equal (plist-get (car (plist-get
                                           (emacs-gtd-agent--call '(:operation get :id "task")) :sessions))
                                     :session-id) "selected-project-session")))
        (when (buffer-live-p shell) (kill-buffer shell))))))

(ert-deftest gtd-agent-unassociated-entry-preserves-native-behavior-and-does-not-mutate ()
  (require 'agent-shell)
  (gtd-project-tests-with-files
    (let (called)
      (cl-letf (((symbol-function 'agent-shell)
                 (lambda () (interactive) (setq called t))))
        (with-current-buffer (find-file-noselect file)
          (goto-char (point-min))
          (emacs-gtd-agent-open)
          (should called)
          (should-not (org-entry-get nil "ID" nil))
          (should-not (buffer-modified-p)))))))

(ert-deftest gtd-agent-session-picker-filters-project-and-live-agent ()
  (require 'agent-shell)
  (gtd-project-tests-with-files
    (let ((emacs-gtd-agent-project-id "project")
          (emacs-gtd-agent-config-id "codex")
          (default-directory root)
          (sessions `(((sessionId . "yes") (cwd . ,root))
                      ((sessionId . "no") (cwd . "/different-project"))
                      ((sessionId . "unknown"))))
          buffers)
      (unwind-protect
          (progn
            (dolist (spec `(("codex" ,root) ("other-ai" ,root) ("codex" "/different-project/")))
              (let ((buffer (generate-new-buffer " *gtd-scope*")))
                (push buffer buffers)
                (with-current-buffer buffer
                  (setq default-directory (cadr spec))
                  (setq-local agent-shell--state
                              `((:agent-config . ((:identifier . ,(intern (car spec))))))))))
            (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () default-directory))
                      ((symbol-function 'agent-shell-buffers) (lambda (&rest _) buffers)))
              (emacs-gtd-agent--project-session-picker
               (lambda (filtered)
                 (should (= (length filtered) 1))
                 (should (equal (map-elt (car filtered) 'sessionId) "yes"))
                 (should (= (length (agent-shell-buffers)) 1))
                 (should (equal (funcall agent-shell-session-choices-function
                                        '(("New" . :new-shell) ("Downloads" . :downloads-shell)))
                                '(("New" . :new-shell)))))
               sessions)))
        (mapc #'kill-buffer buffers)))))

(ert-deftest gtd-agent-storage-is-portable-and-does-not-create-directories ()
  (gtd-project-tests-with-files
    (let ((emacs-gtd-agent-storage-directory (expand-file-name ".agent-shell" root))
          (emacs-gtd-agent-project-id "portable-id")
          (default-directory root))
      (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () default-directory)))
        (let ((first (emacs-gtd-agent-dot-subdir "transcripts")))
          (setq default-directory temporary-file-directory)
          (should (equal first (emacs-gtd-agent-dot-subdir "transcripts")))
          (should-not (file-exists-p emacs-gtd-agent-storage-directory))
          (let ((emacs-gtd-agent-project-id nil))
            (should-not (equal first (emacs-gtd-agent-dot-subdir "transcripts")))))))))

(ert-deftest gtd-agent-agenda-marker-routes-to-original-entry ()
  (gtd-project-tests-with-files
    (let ((marker (with-current-buffer (find-file-noselect other)
                    (goto-char (point-min)) (search-forward "** TODO")
                    (beginning-of-line) (point-marker))))
      (with-temp-buffer
        (insert (propertize "Existing task\n" 'org-hd-marker marker))
        (setq major-mode 'org-agenda-mode)
        (goto-char (point-min))
        (should (equal (emacs-gtd-agent--ensure-identity (emacs-gtd-agent--marker)) "task"))))))

(ert-deftest gtd-project-id-survives-moves-and-rejects-duplicates ()
  (gtd-project-tests-with-files
    (with-current-buffer (find-file-noselect other)
      (goto-char (point-min)) (search-forward "** TODO") (beginning-of-line)
      (let ((text (buffer-substring-no-properties (point) (point-max))))
        (delete-region (point) (point-max))
        (save-buffer)
        (with-current-buffer (find-file-noselect file)
          (goto-char (point-max))
          (insert (replace-regexp-in-string "Existing" "Renamed" text))
          (save-buffer))))
    (let ((data (emacs-gtd-agent--call '(:operation get :id "task"))))
      (should (equal (plist-get (plist-get data :task) :title) "Renamed"))
      (should (equal (plist-get (plist-get data :task) :file) file))
      (should-not (plist-get data :project)))
    (with-current-buffer (find-file-noselect other)
      (goto-char (point-max))
      (insert "** TODO Duplicate ID\n:PROPERTIES:\n:ID: task\n:END:\n")
      (save-buffer))
    (skill-contract-tests-assert-failure
     (emacs-gtd-execute '(:operation get :id "task")) 'needs-input 'ambiguous)))
