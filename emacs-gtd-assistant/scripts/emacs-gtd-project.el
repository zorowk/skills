;;; emacs-gtd-project.el --- Project tasks and context -*- lexical-binding: t; -*-

;;; Commentary:
;; Loaded by emacs-gtd-assistant.el. All AI mutations use emacs-gtd-execute.
;; PROJECT_DIR belongs to a project heading. IDs always belong to one heading.
;; CONTEXT holds the current handoff; LOGBOOK holds dated history;
;; RESOURCES holds document links.

;;; Code:
(require 'cl-lib)

(defvar emacs-gtd-default-headline)
(defvar emacs-gtd-capture-task-limit)
(defvar emacs-gtd-generated-content-maximum-characters)

(defcustom emacs-gtd-project-task-limit 50
  "Maximum children created by one explicitly requested project breakdown."
  :type 'positive-integer :group 'emacs-gtd-assistant)

(defcustom emacs-gtd-entry-maximum-characters 6000
  "Maximum own-entry text returned by a project context read."
  :type 'positive-integer :group 'emacs-gtd-assistant)

(defun emacs-gtd-project--validate-children (tasks)
  "Validate the project breakdown shape using the existing capture contract."
  (let ((emacs-gtd-capture-task-limit emacs-gtd-project-task-limit))
    (emacs-gtd--validate-task-list tasks)))

(defun emacs-gtd-project--own-text ()
  "Return current entry body excluding descendant entries."
  (save-excursion
    (org-back-to-heading t)
    (forward-line 1)
    (let ((beg (point)))
      (outline-next-heading)
      (buffer-substring-no-properties beg (point)))))

(defun emacs-gtd-project--drawer-text (name)
  "Return current entry drawer NAME's text using Org's parsed boundaries."
  (when-let* ((drawer (emacs-gtd--entry-drawer name)))
    (if-let* ((begin (org-element-property :contents-begin drawer)))
        (string-trim-right
         (buffer-substring-no-properties
          begin (org-element-property :contents-end drawer)))
      "")))

(defun emacs-gtd-project--snapshot ()
  "Read bounded own-entry context, identity and resources."
  (let ((text (emacs-gtd-project--own-text)))
    ;; Omit legacy session metadata from prose without parsing or rewriting it.
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
  (let ((marker (emacs-gtd--id-marker id)))
    (unwind-protect
        (with-current-buffer (marker-buffer marker)
          (org-with-wide-buffer
           (goto-char marker)
           (let ((task (emacs-gtd-project--snapshot))
                 project)
             (while (and (not project) (org-at-heading-p))
               (when (org-entry-get nil "PROJECT_DIR" nil)
                 (setq project (emacs-gtd-project--snapshot)))
               (unless (or project (org-up-heading-safe))
                 (goto-char (point-min))
                 (unless project (setq project 'absent))))
             (list :task task :project (unless (eq project 'absent) project)))))
      (set-marker marker nil))))

(defun emacs-gtd-project--directory (directory)
  "Validate and canonicalize a local existing DIRECTORY."
  (emacs-gtd--single-line directory "DIRECTORY")
  (when (or (file-remote-p directory) (not (file-directory-p directory)))
    (user-error "Project directory must exist locally: %s" directory))
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
    (user-error "TASKS must contain 1..%d project tasks" emacs-gtd-project-task-limit))
  (let* ((emacs-gtd-generated-content-maximum-characters 4000)
         (validated (mapcar #'emacs-gtd--validate-task-spec tasks))
         items)
    (save-current-buffer
      (emacs-gtd--find-id id)
      (let ((level (1+ (org-outline-level))))
        ;; Validate every state and all body content before changing anything.
        (dolist (task validated)
          (unless (member (or (plist-get task :todo) "TODO") org-todo-keywords-1)
            (user-error "Unknown task TODO state"))
          (when (and (plist-get task :body)
                     (string-match-p "^\\*+ " (plist-get task :body)))
            (user-error "Task BODY cannot contain Org headings")))
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
                  (user-error "Priority outside configured range"))
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

(provide 'emacs-gtd-project)
;;; emacs-gtd-project.el ends here
