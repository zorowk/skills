;;; denote-scribe.el --- Create Denote reports from AI conversations -*- lexical-binding: t; -*-

;; This file is intended to be loaded into the user's running Emacs
;; through emacsclient or from init.el.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-element)

(unless (featurep 'skill-runtime)
  (load (expand-file-name "../../common/scripts/skill-runtime.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil t))

(declare-function skill-runtime-describe "../../common/scripts/skill-runtime"
                  (schemas &optional target))
(declare-function skill-runtime-measure "../../common/scripts/skill-runtime"
                  (request function))
(declare-function skill-runtime-page "../../common/scripts/skill-runtime"
                  (items offset limit total))
(declare-function skill-runtime-require-authorization
                  "../../common/scripts/skill-runtime" (request action))
(declare-function skill-runtime-result "../../common/scripts/skill-runtime"
                  (operation data &optional count status page effects error
                             verification))
(declare-function skill-runtime-validate-request
                  "../../common/scripts/skill-runtime" (schemas request))

(defgroup denote-scribe nil
  "Create Denote reports from AI conversation summaries."
  :group 'denote)

(defcustom denote-scribe-notes-directory "~/Dropbox/notes/"
  "Directory where `denote-scribe-create' creates Denote notes."
  :type 'directory
  :group 'denote-scribe)

(defcustom denote-scribe-fill-column 100
  "Column used to fill prose paragraphs in generated Org files."
  :type 'positive-integer
  :group 'denote-scribe)

(defcustom denote-scribe-linked-gtd-limit 3
  "Maximum GTD backlinks added by one explicitly requested association."
  :type 'positive-integer
  :group 'denote-scribe)

(defvar denote-directory)
(defvar denote-save-buffers)
(declare-function denote "denote")
(declare-function denote-directory-files "denote"
                  (&optional regexp omit-current text-only exclude-regexp has-identifier))
(declare-function denote-file-has-denoted-filename-p "denote" (file))
(declare-function denote-retrieve-filename-identifier "denote" (file))
(declare-function denote-extract-keywords-from-path "denote" (path))
(declare-function denote-date-identifier-p "denote" (identifier))
(defconst denote-scribe--schemas
  '((preflight :summary "Validate Denote and the notes directory."
               :optional (:notes-dir))
    (create :summary "Create one Denote note from a completed body file."
            :required (:title :body-file :authorization)
            :optional (:kind :keywords :notes-dir :signature :date)
            :choices ((:kind critical) (:authorization explicit))
            :effects (:created))
    (capture
     :summary "Create one confirmed conversation note with explicit authorization."
     :required (:title :body-file :authorization)
     :optional (:kind :keywords :notes-dir :signature :date)
     :choices ((:kind critical) (:authorization explicit))
     :effects (:created))
    (link-gtd
     :summary "Add confirmed GTD id links below the note's open questions."
     :required (:file :tasks :authorization)
     :optional (:notes-dir)
     :choices ((:authorization explicit))
     :effects (:mutated))
    (list :summary "Return a filtered page of Denote notes."
          :optional (:start :end :notes-dir :keywords :offset :limit))
    (describe :summary "Return operation names or one complete schema."
              :optional (:target)))
  "Compact request schemas for `denote-scribe-run'.")

(defun denote-scribe--nonempty (value)
  "Return VALUE when it is a non-empty string, otherwise nil."
  (and (stringp value) (not (string-empty-p value)) value))

(defun denote-scribe--directory (override default)
  "Return OVERRIDE or DEFAULT expanded as a directory name."
  (file-name-as-directory
   (expand-file-name (or (denote-scribe--nonempty override) default))))

(defun denote-scribe--org-tree ()
  "Return a parsed Org tree for the current buffer."
  (org-element-parse-buffer))

(defun denote-scribe--top-level-headings (tree)
  "Return the level-1 heading names in Org TREE."
  (org-element-map tree 'headline
    (lambda (headline)
      (when (= (org-element-property :level headline) 1)
        (org-element-property :raw-value headline)))))

(defun denote-scribe--validate-note-body (body-file &optional kind)
  "Check readable, nonempty BODY-FILE; KIND may be nil or `critical'."
  (unless (memq kind '(nil critical))
    (error "Unknown Denote note kind: %S" kind))
  (unless (and (stringp body-file) (file-regular-p body-file)
               (file-readable-p body-file))
    (error "Note body is not a readable file: %S" body-file))
  (with-temp-buffer
    (insert-file-contents body-file)
    (when (string-empty-p (string-trim (buffer-string)))
      (error "Note body must not be empty"))))

(defun denote-scribe--fill-org-buffer ()
  "Fill prose paragraphs in the current Org buffer."
  (let* ((tree (denote-scribe--org-tree))
         (positions
          (org-element-map tree 'paragraph
            (lambda (paragraph)
              (org-element-property :begin paragraph))))
         (fill-column denote-scribe-fill-column))
    (save-excursion
      (dolist (position (sort positions #'>))
        (goto-char position)
        (org-fill-paragraph)))))

(defun denote-scribe--single-line (value label)
  "Return non-empty single-line VALUE or signal an error naming LABEL."
  (unless (and (stringp value)
               (not (string-empty-p value))
               (not (string-match-p "[\n\r]" value)))
    (error "%s must be a non-empty single-line string" label))
  value)

(defun denote-scribe--note-file (file &optional notes-dir)
  "Return validated Denote FILE below NOTES-DIR."
  (unless (and (stringp file) (file-regular-p file) (file-writable-p file))
    (error "Denote FILE must be a writable regular file: %S" file))
  (let* ((root (file-name-as-directory
                (file-truename
                 (denote-scribe--directory
                  notes-dir denote-scribe-notes-directory))))
         (resolved (file-truename file)))
    (require 'denote)
    (unless (and (file-in-directory-p resolved root)
                 (equal (file-name-extension resolved) "org")
                 (denote-file-has-denoted-filename-p resolved))
      (error "Refusing non-Denote note outside configured notes: %s" file))
    resolved))

(defun denote-scribe--validated-gtd-tasks (tasks)
  "Return validated GTD TASKS for backlink insertion."
  (unless (and (listp tasks) tasks)
    (error "TASKS must be a non-empty list"))
  (when (> (length tasks) denote-scribe-linked-gtd-limit)
    (error "TASKS exceeds the configured limit of %d"
           denote-scribe-linked-gtd-limit))
  (mapcar
   (lambda (task)
     (unless (listp task)
       (error "Each GTD task must be a plist"))
     (let ((id (denote-scribe--single-line
                (plist-get task :id) "GTD task ID"))
           (title (denote-scribe--single-line
                   (plist-get task :title) "GTD task title")))
       (unless (string-match-p "\\`[[:alnum:]_-]+\\'" id)
         (error "Unsafe GTD task ID: %S" id))
       (list :id id :title title)))
   tasks))

;;;###autoload
(defun denote-scribe-link-gtd (file tasks &optional notes-dir)
  "Add bidirectional GTD TASK backlinks to Denote FILE.

Insert links under Open Questions or 开放问题, adding that section if absent.
Existing prose and arbitrary headings are preserved."
  (let* ((note (denote-scribe--note-file file notes-dir))
         (validated (denote-scribe--validated-gtd-tasks tasks)))
    (denote-scribe--validate-note-body note)
    (with-current-buffer (find-file-noselect note)
      (org-with-wide-buffer
       (goto-char (point-min))
       (unless (re-search-forward "^\\* \\(Open Questions\\|开放问题\\)[ \t]*$"
                                  nil t)
         (goto-char (point-max))
         (unless (bolp) (insert "\n"))
         (insert "* Open Questions\n")
         (forward-line -1))
       (beginning-of-line)
       (let* ((chinese (string= (org-get-heading t t t t) "开放问题"))
              (heading (if chinese "相关 GTD" "Related GTD"))
              (subtree-end (save-excursion (org-end-of-subtree t t) (point)))
              (section
               (save-excursion
                 (when (re-search-forward
                        (format "^\\*\\* %s[ \t]*$" (regexp-quote heading))
                        subtree-end t)
                   (line-beginning-position)))))
         (unless section
           (goto-char subtree-end)
           (unless (bolp) (insert "\n"))
           (insert (format "** %s\n" heading))
           (setq section (line-beginning-position 0)))
         (goto-char section)
         (org-end-of-subtree t t)
         (dolist (task validated)
           (let ((target (concat "id:" (plist-get task :id))))
             (unless (save-excursion
                       (goto-char section)
                       (re-search-forward
                        (regexp-quote (concat "[[" target "]["))
                        (save-excursion (org-end-of-subtree t t) (point))
                        t))
               (unless (bolp) (insert "\n"))
               (insert
                (format "- %s\n"
                        (org-link-make-string
                         target (plist-get task :title)))))))
         (save-buffer))))
    (list :file note :tasks validated)))

(defun denote-scribe-preflight (&optional notes-dir)
  "Describe whether Denote and the notes directory are available."
  (let* ((target-dir (denote-scribe--directory notes-dir denote-scribe-notes-directory))
         (denote-available (require 'denote nil t))
         errors)
    (unless (file-directory-p target-dir)
      (push (format "Notes directory does not exist: %s" target-dir) errors))
    (unless denote-available
      (push "Denote is not available in this Emacs session" errors))
    (list :notes-directory target-dir
          :notes-directory-exists (file-directory-p target-dir)
          :denote-available (and denote-available t) :errors (nreverse errors))))

(defun denote-scribe--date-id (date label)
  "Normalize DATE to YYYYMMDD or signal an error mentioning LABEL."
  (unless (and (stringp date)
               (string-match
                "\\`\\([0-9]\\{4\\}\\)-?\\([0-9]\\{2\\}\\)-?\\([0-9]\\{2\\}\\)\\'"
                date))
    (error "%s must use YYYY-MM-DD or YYYYMMDD: %S" label date))
  (let* ((year (string-to-number (match-string 1 date)))
         (month (string-to-number (match-string 2 date)))
         (day (string-to-number (match-string 3 date)))
         (normalized (format "%04d%02d%02d" year month day)))
    (condition-case nil
        (let ((encoded (encode-time 0 0 12 day month year)))
          (unless (string= normalized (format-time-string "%Y%m%d" encoded))
            (error "Normalized calendar date differs"))
          normalized)
      (error (error "%s is not a valid calendar date: %S" label date)))))

(defun denote-scribe-list-notes (start end &optional notes-dir keywords)
  "List Denote Org files from inclusive START through END.

START and END use YYYY-MM-DD or YYYYMMDD.  When both are nil, list the
Denote Org corpus recursively, respecting Denote exclusions.  Supplying only one date is an error.  NOTES-DIR defaults to
`denote-scribe-notes-directory'.  When KEYWORDS is non-nil, require every listed
keyword; otherwise do not filter by keywords."
  (unless (eq (null start) (null end))
    (error "START and END must either both be dates or both be nil"))
  (let* ((start-id (and start (denote-scribe--date-id start "START")))
         (end-id (and end (denote-scribe--date-id end "END")))
         (target-dir
          (denote-scribe--directory notes-dir denote-scribe-notes-directory)))
    (unless (file-directory-p target-dir)
      (error "Notes directory does not exist: %s" target-dir))
    (when (and start-id (string> start-id end-id))
      (error "START must not be after END: %s > %s" start end))
    (require 'denote)
    (let ((denote-directory target-dir))
      (seq-filter
       (lambda (file)
         (let ((identifier (denote-retrieve-filename-identifier file))
               (file-keywords (denote-extract-keywords-from-path file)))
           (and (file-in-directory-p file target-dir)
                (or (null start-id)
                    (and (denote-date-identifier-p identifier)
                         (not (string< identifier (concat start-id "T000000")))
                         (not (string> identifier (concat end-id "T235959")))))
                (seq-every-p
                 (lambda (keyword)
                   (member keyword file-keywords))
                 keywords))))
       (denote-directory-files "[.]org$" nil nil nil t)))))

(defalias 'denote-scribe-list-reports #'denote-scribe-list-notes)

;;;###autoload
(defun denote-scribe-create
    (title body-file &optional keywords notes-dir signature date kind)
  "Create an Org Denote report with TITLE and insert BODY-FILE.

KEYWORDS is a list of strings.  When nil, do not add keywords.
NOTES-DIR overrides `denote-scribe-notes-directory'.
SIGNATURE and DATE are passed to Denote when non-nil.  KIND, when supplied,
must be `critical'.

Return the created file path."
  (unless (and (stringp title) (not (string= title "")))
    (error "TITLE must be a non-empty string"))
  (denote-scribe--validate-note-body body-file kind)
  (require 'denote)
  (let* ((target-dir
          (file-name-as-directory
           (file-truename
            (denote-scribe--directory notes-dir
                                      denote-scribe-notes-directory))))
         (denote-directory target-dir)
         (denote-save-buffers t)
         (file
          (save-window-excursion
            (denote title keywords 'org target-dir date nil signature nil))))
    (unless file
      (error "Denote did not return or visit a file"))
    (with-current-buffer (find-file-noselect file)
      (goto-char (point-max))
      (unless (bolp)
        (insert "\n"))
      (insert "\n")
      (insert-file-contents body-file)
      (denote-scribe--fill-org-buffer)
      (save-buffer))
    file))

;;;###autoload
(defun denote-scribe--run (request)
  "Execute Denote Scribe REQUEST through one compact public entry point.

Use :operation `describe' to request operation schemas only when needed."
  (skill-runtime-validate-request denote-scribe--schemas request)
  (let ((operation (plist-get request :operation)))
    (when (plist-get (alist-get operation denote-scribe--schemas) :effects)
      (skill-runtime-require-authorization request operation))
    (pcase operation
      ('preflight
       (let ((data
              (denote-scribe-preflight
               (plist-get request :notes-dir))))
         (skill-runtime-result
          operation data 1
          (if (plist-get data :errors) 'blocked 'ok))))
      ('describe
       (skill-runtime-result
        operation
        (skill-runtime-describe
         denote-scribe--schemas (plist-get request :target))))
      ((or 'create 'capture)
       (let ((created
              (denote-scribe-create
               (plist-get request :title)
               (plist-get request :body-file)
               (plist-get request :keywords)
               (plist-get request :notes-dir)
               (plist-get request :signature)
               (plist-get request :date)
               (plist-get request :kind))))
         (skill-runtime-result operation (list :file created) 1 nil nil
                               (list :created t))))
      ('link-gtd
       (skill-runtime-result
        operation
        (denote-scribe-link-gtd
         (plist-get request :file)
         (plist-get request :tasks)
         (plist-get request :notes-dir))
        1 nil nil (list :mutated t)))
      ('list
       (let* ((files
               (denote-scribe-list-notes
                (plist-get request :start)
                (plist-get request :end)
                (plist-get request :notes-dir)
                (plist-get request :keywords)))
              (offset (or (plist-get request :offset) 0))
              (limit (or (plist-get request :limit) 8))
              (page (skill-runtime-page files offset limit (length files))))
         (skill-runtime-result
          operation (plist-get page :items) (length files) 'ok
          (plist-get page :page))))
      (_ (error "Unknown Denote Scribe operation %S; expected %S"
                operation (mapcar #'car denote-scribe--schemas))))))

;;;###autoload
(defun denote-scribe-run (request)
  "Execute measured Denote Scribe REQUEST."
  (skill-runtime-measure request (lambda () (denote-scribe--run request))))

(provide 'denote-scribe)

;;; denote-scribe.el ends here
