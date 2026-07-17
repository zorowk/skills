;;; emacs-gtd-assistant.el --- Manage Org GTD through Emacs -*- lexical-binding: t; -*-

;;; Code:

(require 'org)
(require 'org-id)
(require 'seq)
(require 'subr-x)

(defgroup emacs-gtd-assistant nil
  "Manage Org GTD tasks through Emacs."
  :group 'org)

(defcustom emacs-gtd-directory "~/Dropbox/brain/"
  "Directory containing the user's Org GTD files."
  :type 'directory
  :group 'emacs-gtd-assistant)

(defcustom emacs-gtd-file "gtd.org"
  "GTD file name relative to `emacs-gtd-directory'."
  :type 'string
  :group 'emacs-gtd-assistant)

(defcustom emacs-gtd-default-headline "Personal"
  "Default top-level heading for newly added tasks."
  :type 'string
  :group 'emacs-gtd-assistant)

(defcustom emacs-gtd-work-headline "Deepin"
  "Top-level heading for tasks added with work context."
  :type 'string
  :group 'emacs-gtd-assistant)

(defun emacs-gtd--file ()
  "Return the absolute GTD file path."
  (expand-file-name emacs-gtd-file emacs-gtd-directory))

(defun emacs-gtd-preflight ()
  "Return a plist describing the configured GTD file."
  (let* ((directory (file-name-as-directory
                     (expand-file-name emacs-gtd-directory)))
         (file (emacs-gtd--file))
         (errors nil))
    (unless (file-directory-p directory)
      (push (format "GTD directory does not exist: %s" directory) errors))
    (unless (file-readable-p file)
      (push (format "GTD file is not readable: %s" file) errors))
    (unless (file-writable-p file)
      (push (format "GTD file is not writable: %s" file) errors))
    (list :directory directory
          :file file
          :readable (file-readable-p file)
          :writable (file-writable-p file)
          :errors (nreverse errors))))

(defun emacs-gtd--buffer (&optional writable)
  "Return the GTD file buffer, requiring WRITABLE access when non-nil."
  (let ((file (emacs-gtd--file)))
    (unless (file-readable-p file)
      (error "GTD file is not readable: %s" file))
    (when (and writable (not (file-writable-p file)))
      (error "GTD file is not writable: %s" file))
    (find-file-noselect file)))

(defun emacs-gtd--single-line (value label)
  "Return non-empty single-line VALUE or signal an error naming LABEL."
  (unless (and (stringp value)
               (not (string-empty-p value))
               (not (string-match-p "[\n\r]" value)))
    (error "%s must be a non-empty single-line string" label))
  value)

(defun emacs-gtd--save ()
  "Save current Org buffer."
  (when (buffer-modified-p)
    (save-buffer)))

(defun emacs-gtd--goto-heading (headline)
  "Move to top-level HEADLINE, creating it if missing."
  (let ((position
         (catch 'found
           (org-map-entries
            (lambda ()
              (when (and (= (org-outline-level) 1)
                         (string= (org-get-heading t t t t) headline))
                (throw 'found (point))))
            nil 'file))))
    (if position
        (goto-char position)
      (goto-char (point-max))
      (unless (bolp) (insert "\n"))
      (org-insert-heading)
      (org-edit-headline headline))))

(defun emacs-gtd--headline (plist)
  "Return the destination headline configured by task PLIST."
  (or (plist-get plist :headline)
      (pcase (plist-get plist :context)
        ('work emacs-gtd-work-headline)
        ((or 'personal 'nil) emacs-gtd-default-headline)
        (context (error "Unknown task context: %S" context)))))

(defun emacs-gtd--timestamp-value (name)
  "Return Org timestamp string for special property NAME."
  (org-entry-get (point) name))

;;;###autoload
(defun emacs-gtd-normalize-timestamp (text &optional inactive)
  "Return TEXT parsed as an Org timestamp string.

When INACTIVE is non-nil, return an inactive timestamp like
\"[2026-07-03 Fri 15:00]\".  Otherwise return an active timestamp like
\"<2026-07-03 Fri 15:00>\"."
  (unless (and (stringp text) (not (string-empty-p text)))
    (error "TEXT must be a non-empty string"))
  (let* ((time (org-read-date nil t text))
         (open (if inactive "[" "<"))
         (close (if inactive "]" ">")))
    (concat open (format-time-string "%Y-%m-%d %a %H:%M" time) close)))

(defun emacs-gtd--optional-timestamp (text)
  "Normalize optional timestamp TEXT for insertion into Org."
  (and text (emacs-gtd-normalize-timestamp text)))

(defun emacs-gtd--item-at-point (&optional create-id)
  "Return an alist for the Org heading at point.

Create an ID only when CREATE-ID is non-nil."
  (let* ((components (org-heading-components))
         (todo (nth 2 components))
         (priority (nth 3 components))
         (title (nth 4 components))
         (id (if create-id
                 (org-id-get-create)
               (org-entry-get (point) "ID")))
         (tags (org-get-tags nil t))
         (line (line-number-at-pos))
         (outline (org-get-outline-path t t)))
    `((id . ,id)
      (todo . ,todo)
      (priority . ,(and priority (char-to-string priority)))
      (title . ,(substring-no-properties title))
      (scheduled . ,(emacs-gtd--timestamp-value "SCHEDULED"))
      (deadline . ,(emacs-gtd--timestamp-value "DEADLINE"))
      (tags . ,tags)
      (file . ,(buffer-file-name))
      (line . ,line)
      (outline . ,outline))))

(defun emacs-gtd--actionable-heading-p ()
  "Return non-nil when the heading is a GTD item rather than a category."
  (or (org-get-todo-state)
      (org-entry-get (point) "SCHEDULED")
      (org-entry-get (point) "DEADLINE")))

(defun emacs-gtd--find-id (id)
  "Move point to Org entry with ID in the GTD file."
  (emacs-gtd--single-line id "ID")
  (set-buffer (emacs-gtd--buffer t))
  (widen)
  (let ((position (org-find-property "ID" id)))
    (unless position
      (error "No GTD item with ID: %s" id))
    (goto-char position)
    (org-back-to-heading t)))

(defun emacs-gtd--ensure-id-at-point ()
  "Ensure current heading has an ID and return it."
  (org-id-get-create))

;;;###autoload
(defun emacs-gtd-ensure-id-at-line (line)
  "Ensure the GTD item at LINE has an ID and return the item."
  (unless (and (integerp line) (> line 0))
    (error "LINE must be a positive integer"))
  (with-current-buffer (emacs-gtd--buffer t)
    (widen)
    (goto-char (point-min))
    (forward-line (1- line))
    (org-back-to-heading t)
    (emacs-gtd--ensure-id-at-point)
    (let ((item (emacs-gtd--item-at-point)))
      (emacs-gtd--save)
      item)))

;;;###autoload
(defun emacs-gtd-list (&optional include-done)
  "Return GTD items.  Omit done/cancelled items unless INCLUDE-DONE is non-nil."
  (with-current-buffer (emacs-gtd--buffer)
    (org-with-wide-buffer
     (let (items)
       (org-map-entries
       (lambda ()
          (let ((todo (org-get-todo-state)))
            (when (and (emacs-gtd--actionable-heading-p)
                       (or include-done
                           (not (member todo '("DONE" "CANCELLED")))))
              (push (emacs-gtd--item-at-point) items))))
        nil 'file)
       (nreverse items)))))

;;;###autoload
(defun emacs-gtd-find-by-title (query &optional include-done)
  "Return GTD items whose title matches QUERY.

QUERY is treated as a regular expression.  This function does not create IDs."
  (emacs-gtd--single-line query "QUERY")
  (seq-filter
   (lambda (item)
     (let ((title (cdr (assoc 'title item))))
       (and title (string-match-p query title))))
   (emacs-gtd-list include-done)))

;;;###autoload
(defun emacs-gtd-resolve-title (query &optional include-done)
  "Resolve QUERY to one mutable GTD item and ensure that item has an ID.

QUERY is the regular expression accepted by `emacs-gtd-find-by-title'.  Return
a plist whose :status is `resolved', `not-found', or `ambiguous'.  A resolved
result contains one :item with a persistent ID.  Other results contain
:matches for caller-visible disambiguation and do not modify the GTD file."
  (let ((matches (emacs-gtd-find-by-title query include-done)))
    (cond
     ((null matches)
      (list :status 'not-found :matches nil))
     ((cdr matches)
      (list :status 'ambiguous :matches matches))
     (t
      (let ((item (car matches)))
        (list :status 'resolved
              :item
              (or (and (cdr (assq 'id item)) item)
                  (emacs-gtd-ensure-id-at-line
                   (cdr (assq 'line item))))))))))

;;;###autoload
(defun emacs-gtd-add-task (title &optional plist)
  "Add TITLE as a GTD task according to PLIST and return the created item.

PLIST may select :context `personal' or `work', or override it with :headline."
  (emacs-gtd--single-line title "TITLE")
  (let* ((headline (emacs-gtd--single-line
                    (emacs-gtd--headline plist)
                    "HEADLINE"))
         (todo (or (plist-get plist :todo) "TODO"))
         (priority (plist-get plist :priority))
         (scheduled (emacs-gtd--optional-timestamp
                     (plist-get plist :scheduled)))
         (deadline (emacs-gtd--optional-timestamp
                    (plist-get plist :deadline)))
         (body (plist-get plist :body))
         (tags (plist-get plist :tags)))
    (emacs-gtd--single-line todo "TODO")
    (unless (or (null body) (stringp body))
      (error "BODY must be a string or nil"))
    (unless (or (null tags)
                (and (listp tags) (seq-every-p #'stringp tags)))
      (error "TAGS must be a list of strings or nil"))
    (with-current-buffer (emacs-gtd--buffer t)
      (unless (member todo org-todo-keywords-1)
        (error "Unknown TODO state in the configured Org buffer: %S" todo))
      (when priority
        (unless (and (stringp priority)
                     (= (length priority) 1)
                     (<= org-priority-highest (aref priority 0)
                         org-priority-lowest))
          (error "PRIORITY is outside the configured Org priority range: %S"
                 priority)))
      (org-with-wide-buffer
       (emacs-gtd--goto-heading headline)
       (org-insert-subheading nil)
       (org-edit-headline title)
       (org-todo todo)
       (when priority
         (org-priority (aref priority 0)))
       (when tags
         (org-set-tags tags))
       (let ((heading-point (point-marker)))
         (when scheduled
           (org-schedule nil scheduled))
         (when deadline
           (org-deadline nil deadline))
         (when (and body (not (string-empty-p body)))
           (goto-char heading-point)
           (org-end-of-meta-data t)
           (insert body)
           (unless (bolp) (insert "\n")))
         (goto-char heading-point)
         (let ((item (emacs-gtd--item-at-point t)))
           (set-marker heading-point nil)
           (emacs-gtd--save)
           item))))))

;;;###autoload
(defun emacs-gtd-set-state (id state)
  "Set GTD item ID to todo STATE and return the updated item."
  (emacs-gtd--find-id id)
  (emacs-gtd--single-line state "STATE")
  (unless (member state org-todo-keywords-1)
    (error "Unknown TODO state in the configured Org buffer: %S" state))
  (org-todo state)
  (let ((item (emacs-gtd--item-at-point t)))
    (emacs-gtd--save)
    item))

;;;###autoload
(defun emacs-gtd-delete (id)
  "Delete GTD item ID and return ID."
  (emacs-gtd--find-id id)
  (org-cut-subtree)
  (emacs-gtd--save)
  id)

;;;###autoload
(defun emacs-gtd-archive (id)
  "Archive GTD item ID and return ID."
  (emacs-gtd--find-id id)
  (org-archive-subtree)
  (emacs-gtd--save)
  id)

;;;###autoload
(defun emacs-gtd-reschedule (id timestamp)
  "Set SCHEDULED TIMESTAMP for GTD item ID and return the updated item."
  (emacs-gtd--find-id id)
  (org-schedule nil (emacs-gtd-normalize-timestamp timestamp))
  (let ((item (emacs-gtd--item-at-point t)))
    (emacs-gtd--save)
    item))

;;;###autoload
(defun emacs-gtd-set-deadline (id timestamp)
  "Set DEADLINE TIMESTAMP for GTD item ID and return the updated item."
  (emacs-gtd--find-id id)
  (org-deadline nil (emacs-gtd-normalize-timestamp timestamp))
  (let ((item (emacs-gtd--item-at-point t)))
    (emacs-gtd--save)
    item))

(provide 'emacs-gtd-assistant)

;;; emacs-gtd-assistant.el ends here
