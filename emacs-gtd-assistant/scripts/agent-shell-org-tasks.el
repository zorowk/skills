;;; agent-shell-org-tasks.el --- Org task entry points for agent-shell -*- lexical-binding: t; -*-

;;; Commentary:
;; Emacs owns routing and identities; the user sends prompts and accepts work.
;; Loading this file never starts an agent, moves transcripts, or changes tasks.

;;; Code:
(require 'cl-lib)
(require 'map)
(require 'org-agenda)
(unless (featurep 'emacs-gtd-assistant)
  (load (expand-file-name "emacs-gtd-assistant.el"
                          (file-name-directory (or load-file-name buffer-file-name))) nil nil t))

(defcustom emacs-gtd-agent-storage-directory "~/Dropbox/.agent-shell/"
  "Central directory for agent-shell transcripts and screenshots."
  :type 'directory :group 'emacs-gtd-assistant)

(defvar agent-shell-dot-subdir-function)
(defvar agent-shell--transcript-file)
(defvar agent-shell-prefer-viewport-interaction)
(defvar emacs-gtd-agent--starting-project-id nil)
(defvar-local emacs-gtd-agent-task-id nil
  "Org identity belonging to this shell; never inferred from buffer names.")
(defvar-local emacs-gtd-agent-project-id nil)
(defvar-local emacs-gtd-agent-config-id nil)
(defvar-local emacs-gtd-agent--subscription nil)
(defvar-local emacs-gtd-agent--saved-record nil)
(defvar-local emacs-gtd-agent--context nil)

(defun emacs-gtd-agent--call (request)
  "Execute facade REQUEST, converting a structured failure to a user error."
  (let ((result (emacs-gtd-execute request)))
    (unless (eq (plist-get result :status) 'ok)
      (user-error "%s" (or (plist-get (plist-get result :error) :message)
                            (format "Org operation failed: %S" result))))
    (plist-get result :data)))

(defun emacs-gtd-agent--marker ()
  "Return a task marker from Org, Agenda, shell or its viewport."
  (cond
   ((derived-mode-p 'org-agenda-mode)
    (or (org-get-at-bol 'org-hd-marker) (org-get-at-bol 'org-marker)
        (user-error "Select an Agenda task line first")))
   ((derived-mode-p 'org-mode)
    (save-excursion (org-back-to-heading t) (point-marker)))
   (t
    (let* ((shell (if (derived-mode-p 'agent-shell-mode) (current-buffer)
                    (when (and (fboundp 'agent-shell--shell-buffer)
                               (derived-mode-p 'agent-shell-viewport-edit-mode
                                               'agent-shell-viewport-view-mode))
                      (agent-shell--shell-buffer))))
           (id (and (buffer-live-p shell)
                    (buffer-local-value 'emacs-gtd-agent-task-id shell))))
      (unless id (user-error "Open an Org/Agenda task or an associated AI shell"))
      (save-current-buffer (emacs-gtd--find-id id) (point-marker))))))

(defun emacs-gtd-agent--ensure-identity (marker)
  "Ensure a local ID on managed heading MARKER through the facade."
  (with-current-buffer (marker-buffer marker)
    (save-excursion
      (save-restriction
        (widen)
        (goto-char marker)
        (unless (member (expand-file-name buffer-file-name) (emacs-gtd--files))
          (user-error "Add this file to the managed Org files first"))
        (or (org-entry-get nil "ID" nil)
            (plist-get
             (emacs-gtd-agent--call
              (list :operation 'ensure-id :file buffer-file-name
                    :line (line-number-at-pos) :authorization 'explicit)) :id))))))

(defun emacs-gtd-agent-configure-project ()
  "Associate the selected Org heading with a local project directory."
  (interactive)
  (let* ((marker (emacs-gtd-agent--marker))
         (directory (read-directory-name "Project code directory: " nil nil t))
         (id (emacs-gtd-agent--ensure-identity marker)))
    (emacs-gtd-agent--call (list :operation 'configure-project :id id
                                :directory directory :authorization 'explicit))
    (message "项目已关联，可在项目条目中添加仓库与架构文档链接。")))

(defun emacs-gtd-agent--storage-key (project-id cwd)
  "Return portable safe storage key for PROJECT-ID or unbound CWD."
  (if project-id
      (concat "projects/" (secure-hash 'sha256 project-id))
    (concat "unbound/" (secure-hash 'sha256 (file-truename cwd)))))

(defun emacs-gtd-agent-dot-subdir (subdir)
  "Resolve agent-shell SUBDIR under centralized storage, without creating it."
  (let ((key (emacs-gtd-agent--storage-key
              (or emacs-gtd-agent-project-id emacs-gtd-agent--starting-project-id)
              (agent-shell-cwd))))
    (expand-file-name subdir
                      (expand-file-name key emacs-gtd-agent-storage-directory))))

(defun emacs-gtd-agent--project-marker ()
  "Read the nearest explicit project without creating IDs or changing Org."
  (when (derived-mode-p 'org-mode 'org-agenda-mode)
    (let ((marker (condition-case nil (emacs-gtd-agent--marker) (user-error nil))))
      (when marker
        (with-current-buffer (marker-buffer marker)
          (save-excursion
            (save-restriction
              (widen)
              (goto-char marker)
              (when (and buffer-file-name
                         (member (expand-file-name buffer-file-name) (emacs-gtd--files)))
                (catch 'project
                  (while t
                    (when (org-entry-get nil "PROJECT_DIR" nil)
                      (throw 'project (point-marker)))
                    (unless (org-up-heading-safe) (throw 'project nil))))))))))))

(defun emacs-gtd-agent--same-directory-p (left right)
  "Compare local LEFT and RIGHT paths; missing/remote paths never match."
  (and (stringp left) (stringp right)
       (not (file-remote-p left)) (not (file-remote-p right))
       (equal (file-name-as-directory (file-truename left))
              (file-name-as-directory (file-truename right)))))

(defun emacs-gtd-agent--project-session-picker (original sessions)
  "Scope ORIGINAL's SESSIONS and live buffers to this project and agent."
  (if (not emacs-gtd-agent-project-id)
      (funcall original sessions)
    (let* ((cwd (agent-shell-cwd))
           (identifier emacs-gtd-agent-config-id)
           (task-id emacs-gtd-agent-task-id)
           (project-id emacs-gtd-agent-project-id)
           (context emacs-gtd-agent--context)
           (native-buffers (symbol-function 'agent-shell-buffers))
           (agent-shell-session-choices-function
            (lambda (choices)
              (seq-remove (lambda (choice)
                            (memq (cdr choice) '(:downloads-shell :temp-shell))) choices))))
      (cl-letf (((symbol-function 'agent-shell-buffers)
                 (lambda (&rest args)
                   (seq-filter
                    (lambda (buffer)
                      (with-current-buffer buffer
                        (and (emacs-gtd-agent--same-directory-p (agent-shell-cwd) cwd)
                             (equal (format "%s" (map-nested-elt agent-shell--state
                                                                '(:agent-config :identifier)))
                                    identifier))))
                    (apply native-buffers args)))))
        (let ((result
               (funcall original
                        (seq-filter
                         (lambda (session)
                           (emacs-gtd-agent--same-directory-p (map-elt session 'cwd) cwd))
                         sessions))))
          (when (and (eq result :other-shell) task-id)
            (let ((selected (window-buffer (selected-window))))
              (when (with-current-buffer selected (derived-mode-p 'agent-shell-mode))
                (emacs-gtd-agent--associate selected task-id project-id identifier context)
                (agent-shell-insert :text (emacs-gtd-agent--prompt context)
                                    :submit nil :shell-buffer selected))))
          result)))))

(defun emacs-gtd-agent--prompt (context)
  "Build an editable task handoff from facade CONTEXT."
  (let* ((task (plist-get context :task))
         (project (plist-get context :project)))
    (format
     (concat "当前 Org 工作项：%s\n任务 ID：%s\n项目目录：%s\n"
             "Org 来源：%s:%s\n\n项目资料：\n%s\n\n任务内容：\n%s%s\n\n"
             "以此任务为本次工作范围，先阅读相关项目文档。"
             "若当前是项目讨论，先形成需求/架构文档；收到拆分指令后，"
             "将实施步骤直接写成 Org 子任务，不另建重复的实施计划文档。"
             "使用 emacs-gtd-assistant 读取或更新任务。不要自行增加任务或标记 DONE。\n\n"
             "本次我希望：")
     (plist-get task :title) (plist-get task :id) (plist-get project :directory)
     (plist-get task :file) (plist-get task :line)
     (or (plist-get project :resources) "（尚无项目资料链接）")
     (or (plist-get task :text) "")
     (if (plist-get task :truncated) "\n（内容已截断，请按任务 ID 查询并按需读取原文。）" ""))))

(defun emacs-gtd-agent--record (buffer)
  "Persist BUFFER's ready session identity, idempotently.
Errors remain visible and do not interrupt normal agent operation."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (when-let* ((id emacs-gtd-agent-task-id)
                  (session (agent-shell-session-id)))
        (let ((record (list :operation 'attach-session :id id
                            :agent emacs-gtd-agent-config-id :session-id session
                            :cwd (agent-shell-cwd)
                            :transcript (and (boundp 'agent-shell--transcript-file)
                                             agent-shell--transcript-file)
                            :authorization 'explicit)))
          (unless (equal record emacs-gtd-agent--saved-record)
            (condition-case err
                (progn
                  (emacs-gtd-agent--call record)
                  (setq emacs-gtd-agent--saved-record record))
              (error (display-warning 'emacs-gtd-assistant
                                      (format "Session association not saved: %s" (error-message-string err))
                                      :warning)))))))))

(defun emacs-gtd-agent--associate (buffer id project-id identifier context)
  "Associate BUFFER with this work item, replacing any previous subscriber."
  (with-current-buffer buffer
    (when emacs-gtd-agent--subscription
      (agent-shell-unsubscribe :subscription emacs-gtd-agent--subscription))
    (setq-local emacs-gtd-agent-task-id id
                emacs-gtd-agent-project-id project-id
                emacs-gtd-agent-config-id identifier
                emacs-gtd-agent--context context
                emacs-gtd-agent--saved-record nil)
    (setq-local emacs-gtd-agent--subscription
                (agent-shell-subscribe-to
                 :shell-buffer buffer
                 :on-event
                 (lambda (event)
                   (when (memq (map-elt event :event)
                               '(init-finished session-restored input-submitted turn-complete))
                     (emacs-gtd-agent--record buffer)))))
    (emacs-gtd-agent--record buffer)))

(defun emacs-gtd-agent--start (config cwd new)
  "Start CONFIG at CWD with native project session selection, or NEW."
  (agent-shell--start :config config :cwd cwd :new-session t
                      :session-strategy (if new 'new 'prompt)))

;;;###autoload
(defun emacs-gtd-agent-open (&optional new)
  "Use the usual agent-shell key from Org or Agenda.
For an explicitly associated project, select an agent then its project session.
Unassociated entries keep native behavior without creating an Org identity."
  (interactive "P")
  (require 'agent-shell)
  (let ((project-marker (emacs-gtd-agent--project-marker)))
    (if (not project-marker)
        (let ((current-prefix-arg (and new '(4))))
          (call-interactively #'agent-shell))
      (let* ((cwd (with-current-buffer (marker-buffer project-marker)
                    (save-excursion
                      (goto-char project-marker)
                      (emacs-gtd-project--directory (org-entry-get nil "PROJECT_DIR" nil)))))
             ;; Select first: cancelling the agent picker must not mutate Org.
             (config (agent-shell-select-config :prompt "选择 AI: ")))
        (when config
          (let* ((id (emacs-gtd-agent--ensure-identity (emacs-gtd-agent--marker)))
                 (project-id (emacs-gtd-agent--ensure-identity project-marker))
                 (context (emacs-gtd-agent--call (list :operation 'get :id id)))
                 (emacs-gtd-agent--starting-project-id project-id)
                 (emacs-gtd-agent-project-id project-id)
                 (emacs-gtd-agent-task-id id)
                 (emacs-gtd-agent--context context)
                 (emacs-gtd-agent-config-id (format "%s" (map-elt config :identifier)))
                 (buffer (emacs-gtd-agent--start config cwd new)))
            (when (buffer-live-p buffer)
              (emacs-gtd-agent--associate buffer id project-id
                                         (format "%s" (map-elt config :identifier)) context)
              (agent-shell-insert :text (emacs-gtd-agent--prompt context)
                                  :submit nil :shell-buffer buffer))))))))

;;;###autoload
(defun emacs-gtd-agent-wrap-up ()
  "Prepare an editable request to save a task handoff; do not submit it."
  (interactive)
  (let* ((marker (emacs-gtd-agent--marker))
         (id (with-current-buffer (marker-buffer marker)
               (save-excursion (goto-char marker) (org-entry-get nil "ID" nil))))
         (shell
          (cond
           ((derived-mode-p 'agent-shell-mode) (current-buffer))
           ((derived-mode-p 'agent-shell-viewport-edit-mode 'agent-shell-viewport-view-mode)
            (agent-shell--shell-buffer))
           (t
            (let ((candidates
                   (seq-filter
                    (lambda (buffer)
                      (and id (with-current-buffer buffer
                                (and (derived-mode-p 'agent-shell-mode)
                                     (equal emacs-gtd-agent-task-id id)))))
                    (buffer-list))))
              (if (= (length candidates) 1) (car candidates)
                (when candidates
                  (get-buffer (completing-read "选择收尾会话: "
                                               (mapcar #'buffer-name candidates) nil t)))))))))
    (unless (and id (buffer-live-p shell))
      (user-error "请先用 C-z a 进入要收尾的会话"))
    (agent-shell-insert
     :text (format
            (concat "\n请为 Org 任务 %s 收尾：先核实当前修改和实际验证结果，"
                    "通过 emacs-gtd-assistant 的 add-note 记录完成内容、验证、阻塞与必要链接，"
                    "通过 set-context 更新简短接续点。这里明确授权写入这两项。"
                    "不创建新任务、不改变任务状态、不提交 Git。\n") id)
     :submit nil :shell-buffer shell)))

;;;###autoload
(defun emacs-gtd-agent-show-task ()
  "Jump from a shell or viewport back to its associated Org task."
  (interactive)
  (let ((marker (emacs-gtd-agent--marker)))
    (pop-to-buffer (marker-buffer marker))
    (widen) (goto-char marker) (org-show-entry)))

(defun emacs-gtd-agent-enable ()
  "Install centralized storage and Org/Agenda/shell task entry points."
  (interactive)
  (dolist (map (list org-mode-map org-agenda-mode-map))
    (define-key map (kbd "C-z a") #'emacs-gtd-agent-open)
    (define-key map (kbd "C-c C-x w") #'emacs-gtd-agent-wrap-up))
  (with-eval-after-load 'agent-shell
    (unless (advice-member-p #'emacs-gtd-agent--project-session-picker
                             #'agent-shell--prompt-select-session)
      (advice-add #'agent-shell--prompt-select-session :around
                  #'emacs-gtd-agent--project-session-picker))
    (setq agent-shell-dot-subdir-function #'emacs-gtd-agent-dot-subdir)
    (define-key agent-shell-mode-map (kbd "C-c C-x w") #'emacs-gtd-agent-wrap-up)
    (define-key agent-shell-mode-map (kbd "C-c C-x o") #'emacs-gtd-agent-show-task)))

(provide 'agent-shell-org-tasks)
;;; agent-shell-org-tasks.el ends here
