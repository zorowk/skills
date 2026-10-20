;;; emacs-gtd-project.el --- Project tasks and session identities -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded by emacs-gtd-assistant.el. All AI mutations use emacs-gtd-execute.
;; PROJECT_DIR belongs to a project heading. IDs always belong to one heading.
;; CONTEXT holds the current handoff; LOGBOOK holds dated history;
;; RESOURCES holds document links; AI_SESSIONS holds JSON session records.

;;; Code:
(require 'json)
(require 'cl-lib)

(defcustom emacs-gtd-project-task-limit 50
  "Maximum children created by one explicitly requested project breakdown."
  :type 'positive-integer :group 'emacs-gtd-assistant)

(defcustom emacs-gtd-entry-maximum-characters 6000
  "Maximum own-entry text returned by a project context read."
  :type 'positive-integer :group 'emacs-gtd-assistant)

(setq emacs-gtd--schemas
      (append emacs-gtd--schemas
              '((get :summary "Read a managed entry, nearest project and session history without mutation."
                     :required (:id))
                (ensure-id :summary "Give the heading at FILE and LINE its own identity."
                           :required (:file :line :authorization)
                           :types ((:file string) (:line (integer :min 1)))
                           :choices ((:authorization explicit)) :effects (:mutated))
                (create-project :summary "Create a project container with directory and document resources."
                                :required (:title :directory :authorization)
                                :optional (:headline :links)
                                :choices ((:authorization explicit)) :effects (:mutated))
                (configure-project :summary "Set an existing heading's project directory and optionally resources."
                                   :required (:id :directory :authorization)
                                   :optional (:links)
                                   :choices ((:authorization explicit)) :effects (:mutated))
                (add-children :summary "Atomically append unscheduled tasks below an explicit parent ID; supports up to 50 tasks."
                              :required (:parent-id :tasks :authorization)
                              :choices ((:authorization explicit)) :effects (:mutated))
                (attach-session :summary "Record agent, session ID, cwd and transcript under a task; leaves task state unchanged."
                                :required (:id :agent :session-id :cwd :authorization)
                                :optional (:transcript)
                                :choices ((:authorization explicit)) :effects (:mutated)))))

(defun emacs-gtd-project--validate-children (tasks)
  "Validate the project breakdown shape using the existing capture contract."
  (let ((emacs-gtd-capture-task-limit emacs-gtd-project-task-limit))
    (emacs-gtd--validate-task-list tasks)))

;; Reuse the structured task schema without inheriting capture cardinality.
(let* ((schema (copy-tree (alist-get 'add-many emacs-gtd--schemas)))
       (children (alist-get 'add-children emacs-gtd--schemas)))
  (setq children (plist-put children :types (plist-get schema :types)))
  (setq children
        (plist-put children :validators
                   '((:tasks emacs-gtd-project--validate-children
                             "Project breakdown is bounded by emacs-gtd-project-task-limit."))))
  (setf (alist-get 'add-children emacs-gtd--schemas) children))

(defun emacs-gtd-project--own-text ()
  "Return current entry body excluding descendant entries."
  (save-excursion
    (org-back-to-heading t)
    (forward-line 1)
    (let ((beg (point)))
      (outline-next-heading)
      (buffer-substring-no-properties beg (point)))))

(defun emacs-gtd-project--drawer-text (name)
  "Return current entry drawer NAME or nil."
  (let ((text (emacs-gtd-project--own-text)))
    (with-temp-buffer
      (insert text)
      (goto-char (point-min))
      (when (re-search-forward (format "^:%s:[ \t]*$" (regexp-quote name)) nil t)
        (forward-line 1)
        (let ((beg (point)))
          (unless (re-search-forward "^:END:[ \t]*$" nil t)
            (error "Unterminated %s drawer" name))
          (string-trim-right (buffer-substring-no-properties beg (line-beginning-position))))))))

(defun emacs-gtd-project--sessions ()
  "Read structured sessions stored on the current heading."
  (when-let* ((text (emacs-gtd-project--drawer-text "AI_SESSIONS")))
    (unless (string-empty-p text)
      (json-parse-string text :object-type 'plist :array-type 'list))))

(defun emacs-gtd-project--snapshot ()
  "Read bounded own-entry context, identity and resources."
  (let ((text (emacs-gtd-project--own-text)))
    (setq text (replace-regexp-in-string
                "^:AI_SESSIONS:[ \t]*\n[^\n]*\n:END:[ \t]*\n?" "" text))
    (list :id (org-entry-get nil "ID" nil)
          :title (org-get-heading t t t t)
          :file buffer-file-name :line (line-number-at-pos)
          :state (org-get-todo-state)
          :directory (org-entry-get nil "PROJECT_DIR" nil)
          :resources (emacs-gtd-project--drawer-text "RESOURCES")
          :context (emacs-gtd-project--drawer-text "CONTEXT")
          :text (substring text 0 (min (length text) emacs-gtd-entry-maximum-characters))
          :truncated (> (length text) emacs-gtd-entry-maximum-characters))))

(defun emacs-gtd-project-context (id)
  "Read entry ID and nearest project context from managed files."
  (save-current-buffer
    (emacs-gtd--find-id id)
    (save-excursion
      (let ((task (emacs-gtd-project--snapshot))
            (sessions (emacs-gtd-project--sessions))
            project)
        (while (and (not project) (org-at-heading-p))
          (when (org-entry-get nil "PROJECT_DIR" nil)
            (setq project (emacs-gtd-project--snapshot)))
          (unless (or project (org-up-heading-safe))
            (goto-char (point-min))
            (unless project (setq project 'absent))))
        (list :task task :project (unless (eq project 'absent) project)
              :sessions sessions)))))

(defun emacs-gtd-project--directory (directory)
  "Validate and canonicalize a local existing DIRECTORY."
  (emacs-gtd--single-line directory "DIRECTORY")
  (when (or (file-remote-p directory) (not (file-directory-p directory)))
    (error "Project directory must exist locally: %s" directory))
  (file-name-as-directory (file-truename directory)))

(defun emacs-gtd-project-configure (id directory &optional links replace-links)
  "Configure ID with DIRECTORY and optionally replace LINKS."
  (setq directory (emacs-gtd-project--directory directory)
        links (emacs-gtd--validate-links links))
  (save-current-buffer
    (emacs-gtd--find-id id)
    (atomic-change-group
      (org-entry-put nil "PROJECT_DIR" directory)
      (when replace-links
        (emacs-gtd--replace-drawer-content "RESOURCES" (emacs-gtd--resource-text links)))
      (emacs-gtd--save)))
  (emacs-gtd-project-context id))

(defun emacs-gtd-project-create (request)
  "Create a project from validated REQUEST in the primary GTD file."
  (let ((title (emacs-gtd--single-line (plist-get request :title) "TITLE"))
        (directory (emacs-gtd-project--directory (plist-get request :directory)))
        (links (emacs-gtd--validate-links (plist-get request :links)))
        id)
    (with-current-buffer (emacs-gtd--buffer t)
      (org-with-wide-buffer
       (atomic-change-group
         (emacs-gtd--goto-heading (or (plist-get request :headline) emacs-gtd-default-headline))
         (let ((level (1+ (org-outline-level))))
           (org-end-of-subtree t t)
           (unless (bolp) (insert "\n"))
           (let ((beg (point)))
             (insert (make-string level ?*) " " title "\n")
             (goto-char beg)))
         (org-entry-put nil "PROJECT_DIR" directory)
         (setq id (org-id-get-create))
         (save-excursion
           (org-end-of-meta-data t)
           (emacs-gtd--insert-drawer "RESOURCES" (emacs-gtd--resource-text links)))
         (emacs-gtd--save))))
    (emacs-gtd-project-context id)))

(defun emacs-gtd-project-add-children (id tasks)
  "Atomically add validated unscheduled TASKS below managed heading ID."
  (unless (and (listp tasks) tasks (<= (length tasks) emacs-gtd-project-task-limit))
    (error "TASKS must contain 1..%d project tasks" emacs-gtd-project-task-limit))
  (let* ((emacs-gtd-generated-content-maximum-characters 4000)
         (validated (mapcar #'emacs-gtd--validate-task-spec tasks))
         items)
    (save-current-buffer
      (emacs-gtd--find-id id)
      (let ((level (1+ (org-outline-level))))
        ;; Validate every state and all body content before changing anything.
        (dolist (task validated)
          (unless (member (or (plist-get task :todo) "TODO") org-todo-keywords-1)
            (error "Unknown task TODO state"))
          (when (and (plist-get task :body)
                     (string-match-p "^\\*+ " (plist-get task :body)))
            (error "Task BODY cannot contain Org headings")))
        (atomic-change-group
          (org-end-of-subtree t t)
          (unless (bolp) (insert "\n"))
          (dolist (task validated)
            (let ((beg (point)))
              (insert (make-string level ?*) " "
                      (or (plist-get task :todo) "TODO") " "
                      (plist-get task :title) "\n")
              (goto-char beg)
              (when-let* ((priority (plist-get task :priority)))
                (unless (<= org-priority-highest (aref priority 0) org-priority-lowest)
                  (error "Priority outside configured range"))
                (org-priority (aref priority 0)))
              (when-let* ((tags (plist-get task :tags))) (org-set-tags tags))
              (dolist (property (plist-get task :properties))
                (org-entry-put nil (car property) (cdr property)))
              (when-let* ((date (plist-get task :scheduled)))
                (org-schedule nil (emacs-gtd-normalize-timestamp date)))
              (when-let* ((date (plist-get task :deadline)))
                (org-deadline nil (emacs-gtd-normalize-timestamp date)))
              (push (emacs-gtd--item-at-point t) items)
              (org-end-of-meta-data t)
              (when-let* ((body (plist-get task :body)))
                (insert (emacs-gtd--drawer-content body) "\n"))
              (emacs-gtd--insert-drawer "CONTEXT" (plist-get task :context-notes))
              (emacs-gtd--insert-drawer "RESOURCES"
                                       (emacs-gtd--resource-text (plist-get task :links)))
              (unless (bolp) (insert "\n"))))
          (emacs-gtd--save))))
    (nreverse items)))

(defun emacs-gtd-project-attach-session (request)
  "Persist one session identity from REQUEST on its task."
  (let* ((id (plist-get request :id))
         (agent (emacs-gtd--single-line (plist-get request :agent) "AGENT"))
         (session (emacs-gtd--single-line (plist-get request :session-id) "SESSION-ID"))
         (cwd (emacs-gtd-project--directory (plist-get request :cwd)))
         (transcript (plist-get request :transcript)))
    (when transcript (emacs-gtd--single-line transcript "TRANSCRIPT"))
    (save-current-buffer
      (emacs-gtd--find-id id)
      (let* ((sessions (emacs-gtd-project--sessions))
             (existing (seq-find (lambda (item)
                                   (and (equal (plist-get item :agent) agent)
                                        (equal (plist-get item :session-id) session))) sessions))
             (record (list :agent agent :session-id session :cwd cwd
                           :updated (format-time-string "%FT%T%z")
                           :transcript (or transcript (plist-get existing :transcript) ""))))
        (setq sessions (cons record (delete existing sessions)))
        (atomic-change-group
          (emacs-gtd--replace-drawer-content "AI_SESSIONS"
                                           (json-serialize (vconcat sessions)))
          (emacs-gtd--save))))
    (emacs-gtd-project-context id)))

(defun emacs-gtd-project-execute (request)
  "Dispatch project operations validated by the shared facade."
  (let* ((operation (plist-get request :operation))
         (mutated (not (eq operation 'get)))
         (data
          (pcase operation
            ('get (emacs-gtd-project-context (plist-get request :id)))
            ('ensure-id
             (emacs-gtd--compact-item
              (emacs-gtd-ensure-id-at-line (plist-get request :line) (plist-get request :file))))
            ('create-project (emacs-gtd-project-create request))
            ('configure-project
             (emacs-gtd-project-configure (plist-get request :id) (plist-get request :directory)
                                          (plist-get request :links) (plist-member request :links)))
            ('add-children
             (mapcar #'emacs-gtd--compact-item
                     (emacs-gtd-project-add-children (plist-get request :parent-id)
                                                     (plist-get request :tasks))))
            ('attach-session (emacs-gtd-project-attach-session request))
            (_ (error "Unknown GTD operation: %s" operation)))))
    (skill-runtime-result operation data (if (eq operation 'add-children) (length data) 1)
                          nil nil (when mutated (list :mutated t)))))

(provide 'emacs-gtd-project)
;;; emacs-gtd-project.el ends here
