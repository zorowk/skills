;;; emacs-gtd-assistant.el --- Manage Org GTD through Emacs -*- lexical-binding: t; -*-

;;; Code:

(require 'org)
(require 'org-id)
(require 'cl-lib)
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

(defun emacs-gtd--file ()
  "Return the absolute GTD file path."
  (expand-file-name emacs-gtd-file emacs-gtd-directory))

(defun emacs-gtd--save ()
  "Save current Org buffer."
  (when (buffer-modified-p)
    (save-buffer)))

(defun emacs-gtd--goto-heading (headline)
  "Move to top-level HEADLINE, creating it if missing."
  (goto-char (point-min))
  (unless (re-search-forward
           (format "^\\* %s\\s-*$" (regexp-quote headline))
           nil t)
    (goto-char (point-max))
    (unless (bolp) (insert "\n"))
    (insert "* " headline "\n"))
  (beginning-of-line))

(defun emacs-gtd--timestamp-value (name)
  "Return Org timestamp string for special property NAME."
  (org-entry-get (point) name))

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
  (find-file (emacs-gtd--file))
  (widen)
   (goto-char (point-min))
   (unless (re-search-forward
            (format "^[ \t]*:ID:[ \t]+%s[ \t]*$" (regexp-quote id))
            nil t)
     (error "No GTD item with ID: %s" id))
   (org-back-to-heading t)
   (unless (and (org-at-heading-p)
                (string= (org-entry-get (point) "ID") id))
     (error "No GTD item with ID: %s" id)))

(defun emacs-gtd--ensure-id-at-point ()
  "Ensure current heading has an ID and return it."
  (org-id-get-create))

;;;###autoload
(defun emacs-gtd-ensure-id-at-line (line)
  "Ensure the GTD item at LINE has an ID and return the item."
  (with-current-buffer (find-file-noselect (emacs-gtd--file))
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
  (with-current-buffer (find-file-noselect (emacs-gtd--file))
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
  (cl-remove-if-not
   (lambda (item)
     (let ((title (cdr (assoc 'title item))))
       (and title (string-match-p query title))))
   (emacs-gtd-list include-done)))

;;;###autoload
(defun emacs-gtd-add-task (title &optional plist)
  "Add TITLE as a GTD task according to PLIST and return the created item."
  (unless (and (stringp title) (not (string-empty-p title)))
    (error "TITLE must be a non-empty string"))
  (let* ((headline (or (plist-get plist :headline) "Personal"))
         (todo (or (plist-get plist :todo) "TODO"))
         (priority (plist-get plist :priority))
         (scheduled (plist-get plist :scheduled))
         (deadline (plist-get plist :deadline))
         (body (plist-get plist :body))
         (tags (plist-get plist :tags)))
    (with-current-buffer (find-file-noselect (emacs-gtd--file))
      (org-with-wide-buffer
       (emacs-gtd--goto-heading headline)
       (org-end-of-subtree t t)
       (unless (bolp) (insert "\n"))
       (let ((heading-point (point)))
         (insert "** " todo " ")
         (when priority
           (insert "[#" priority "] "))
         (insert title)
         (when tags
           (insert " :" (string-join tags ":") ":"))
         (insert "\n")
         (when scheduled
           (insert "SCHEDULED: " scheduled "\n"))
         (when deadline
           (insert "DEADLINE: " deadline "\n"))
         (when (and body (not (string-empty-p body)))
         (insert body "\n"))
         (goto-char heading-point)
         (let ((item (emacs-gtd--item-at-point t)))
           (emacs-gtd--save)
           item))))))

;;;###autoload
(defun emacs-gtd-set-state (id state)
  "Set GTD item ID to todo STATE and return the updated item."
  (emacs-gtd--find-id id)
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
  (org-schedule nil timestamp)
  (let ((item (emacs-gtd--item-at-point t)))
    (emacs-gtd--save)
    item))

;;;###autoload
(defun emacs-gtd-set-deadline (id timestamp)
  "Set DEADLINE TIMESTAMP for GTD item ID and return the updated item."
  (emacs-gtd--find-id id)
  (org-deadline nil timestamp)
  (let ((item (emacs-gtd--item-at-point t)))
    (emacs-gtd--save)
    item))

(provide 'emacs-gtd-assistant)

;;; emacs-gtd-assistant.el ends here
