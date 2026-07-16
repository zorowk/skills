;;; denote-scribe.el --- Create Denote reports from AI conversations -*- lexical-binding: t; -*-

;; This file is intended to be loaded into the user's running Emacs
;; through emacsclient or from init.el.

;;; Code:

(require 'seq)
(require 'subr-x)
(require 'org)
(require 'org-element)

(unless (featurep 'skill-git)
  (let* ((script-directory
          (file-name-directory (or load-file-name buffer-file-name)))
         (shared-file
          (expand-file-name "../../common/scripts/skill-git.el"
                            script-directory)))
    (unless (file-readable-p shared-file)
      (error "Shared Git helper is not readable: %s" shared-file))
    (load shared-file nil nil t)))

(defgroup denote-scribe nil
  "Create Denote reports from AI conversation summaries."
  :group 'denote)

(defconst denote-scribe--skill-directory
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Absolute Denote Scribe skill directory.")

(defcustom denote-scribe-notes-directory "~/Dropbox/notes/"
  "Directory where `denote-scribe-create' creates Denote notes."
  :type 'directory
  :group 'denote-scribe)

(defcustom denote-scribe-hywiki-directory "~/Dropbox/hywiki/"
  "Directory where Denote Scribe creates stable HyWiki concept pages."
  :type 'directory
  :group 'denote-scribe)

(defcustom denote-scribe-git-directory "~/Dropbox/"
  "Git repository containing Denote notes and HyWiki pages."
  :type 'directory
  :group 'denote-scribe)

(define-obsolete-variable-alias
  'denote-scribe-hywiki-commit-interval
  'denote-scribe-review-commit-interval "2026-07-16")

(defcustom denote-scribe-review-commit-interval 5
  "Number of repository commits between AI reviews."
  :type 'positive-integer
  :group 'denote-scribe)

(defcustom denote-scribe-fill-column 100
  "Column used to fill prose paragraphs in generated Org files."
  :type 'positive-integer
  :group 'denote-scribe)

(define-obsolete-variable-alias
  'denote-scribe-hywiki-commit-marker
  'denote-scribe-review-commit-marker "2026-07-16")

(defconst denote-scribe-review-commit-marker "🔒"
  "Literal commit-subject marker for a completed AI review.")

(defvar denote-directory)
(defvar denote-save-buffers)
(defvar hywiki-directory)
(declare-function denote "denote")
(declare-function hywiki-add-page "hywiki" (page-name &optional force-flag))
(declare-function hywiki-get-existing-page-file "hywiki" (reference))
(declare-function hywiki-word-is-p "hywiki" (word))
(declare-function magit-git-string "magit-git" (&rest args))

(defconst denote-scribe-critical-headings
  '("Goal" "Question" "Context" "Evidence" "Hypotheses" "Investigation"
    "Analysis" "Conclusion" "Reflection" "Open Questions" "Extract Concepts")
  "Required English headings for a critical Denote body, in order.")

(defconst denote-scribe-critical-headings-zh
  '("目标" "核心问题" "背景" "证据" "假设" "探究过程" "分析" "结论" "反思"
    "开放问题" "提取概念")
  "Required Chinese headings for a critical Denote body, in order.")

(defconst denote-scribe-hywiki-headings
  '("Context" "Definition" "My Understanding" "Why It Matters" "Evidence"
    "Reasoning" "Boundaries" "Related Concepts" "Open Questions" "Provenance")
  "Required English headings for a HyWiki concept body, in order.")

(defconst denote-scribe-hywiki-headings-zh
  '("背景" "定义" "我的理解" "价值" "证据" "推理" "边界" "相关概念" "开放问题"
    "溯源")
  "Required Chinese headings for a HyWiki concept body, in order.")

;;;###autoload
(defun denote-scribe-template-file (kind &optional language)
  "Return the bundled template for KIND and LANGUAGE.

KIND is `critical' or `hywiki'.  LANGUAGE is `en' or `zh' and defaults to
`en'.  Signal an error if the selected template is unavailable."
  (let* ((lang (or language 'en))
         (name
          (pcase (cons kind lang)
            (`(critical . en) "critical-note-template.org")
            (`(critical . zh) "critical-note-template-zh.org")
            (`(hywiki . en) "hywiki-concept-template.org")
            (`(hywiki . zh) "hywiki-concept-template-zh.org")
            (_ (error "Unknown template kind/language: %S/%S" kind lang))))
         (file (expand-file-name name
                                 (expand-file-name "assets"
                                                   denote-scribe--skill-directory))))
    (unless (file-readable-p file)
      (error "Denote Scribe template is not readable: %s" file))
    file))

(defun denote-scribe--nonempty (value)
  "Return VALUE when it is a non-empty string, otherwise nil."
  (and (stringp value) (not (string-empty-p value)) value))

(defun denote-scribe--directory (override default)
  "Return OVERRIDE or DEFAULT expanded as a directory name."
  (skill-git-directory (or (denote-scribe--nonempty override) default)))

(defun denote-scribe--org-tree ()
  "Return a parsed Org tree for the current buffer."
  (org-element-parse-buffer))

(defun denote-scribe--top-level-headings (tree)
  "Return the level-1 heading names in Org TREE."
  (org-element-map tree 'headline
    (lambda (headline)
      (when (= (org-element-property :level headline) 1)
        (org-element-property :raw-value headline)))))

(defun denote-scribe--validate-headings (tree schemas label)
  "Return the matching heading schema for Org TREE.

SCHEMAS is a list of accepted top-level heading lists for LABEL."
  (let* ((actual (denote-scribe--top-level-headings tree))
         (matched (seq-find (lambda (schema) (equal actual schema)) schemas)))
    (unless matched
      (error "%s has invalid top-level headings: %S" label actual))
    matched))

(defun denote-scribe--validate-critical-body (body-file)
  "Validate critical-note structure in readable Org BODY-FILE."
  (with-temp-buffer
    (insert-file-contents body-file)
    (delay-mode-hooks (org-mode))
    (let* ((tree (denote-scribe--org-tree))
           (schema
            (denote-scribe--validate-headings
             tree
             (list denote-scribe-critical-headings
                   denote-scribe-critical-headings-zh)
             "Critical body"))
           (concept-parent (car (last schema)))
           (concept
            (org-element-map
                tree 'headline
              (lambda (headline)
                (when (= (org-element-property :level headline) 2)
                  (let ((parent (org-element-lineage headline 'headline)))
                    (and parent
                         (string= (org-element-property :raw-value parent)
                                  concept-parent)))))
              nil t)))
      (unless concept
        (error "%s must contain a level-2 concept heading" concept-parent)))))

(defun denote-scribe--validate-hywiki-body (body-file)
  "Validate concept-page structure in readable Org BODY-FILE."
  (with-temp-buffer
    (insert-file-contents body-file)
    (delay-mode-hooks (org-mode))
    (denote-scribe--validate-headings
     (denote-scribe--org-tree)
     (list denote-scribe-hywiki-headings denote-scribe-hywiki-headings-zh)
     "HyWiki body")))

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

(defun denote-scribe-preflight (&optional notes-dir hywiki-dir git-dir)
  "Return a plist describing whether Denote, HyWiki, and Magit are available."
  (let* ((target-dir
          (denote-scribe--directory notes-dir denote-scribe-notes-directory))
         (target-hywiki-dir
          (denote-scribe--directory hywiki-dir
                                    denote-scribe-hywiki-directory))
         (denote-available (require 'denote nil t))
         (hywiki-available (require 'hywiki nil t))
         (magit-available (require 'magit nil t))
         (target-git-dir
          (denote-scribe--directory git-dir denote-scribe-git-directory))
         (git-root (and magit-available
                        (ignore-errors (skill-git-root target-git-dir))))
         (errors nil))
    (unless (file-directory-p target-dir)
      (push (format "Notes directory does not exist: %s" target-dir) errors))
    (unless denote-available
      (push "Denote is not available in this Emacs session" errors))
    (unless (file-directory-p target-hywiki-dir)
      (push (format "HyWiki directory does not exist: %s" target-hywiki-dir)
            errors))
    (unless hywiki-available
      (push "HyWiki is not available in this Emacs session" errors))
    (unless magit-available
      (push "Magit is not available in this Emacs session" errors))
    (unless git-root
      (push (format "Not inside a Git repository: %s" target-git-dir) errors))
    (list :notes-directory target-dir
          :notes-directory-exists (file-directory-p target-dir)
          :denote-available (and denote-available t)
          :hywiki-directory target-hywiki-dir
          :hywiki-directory-exists (file-directory-p target-hywiki-dir)
          :hywiki-available (and hywiki-available t)
          :git-directory target-git-dir
          :git-root git-root
          :magit-available (and magit-available t)
          :errors (nreverse errors))))

(defun denote-scribe--git-root (&optional git-dir)
  "Return the Magit repository root for GIT-DIR or signal an error."
  (skill-git-root
   (denote-scribe--directory git-dir denote-scribe-git-directory)))

(defun denote-scribe--git-review-marker-commit (root)
  "Return the newest AI-review commit in ROOT."
  (let ((default-directory root))
    (magit-git-string
     "log" "-1" "--perl-regexp"
     (concat "--grep=^[^\\n]*" denote-scribe-review-commit-marker)
     "--format=%H")))

(defun denote-scribe-git-review-state (&optional git-dir)
  "Return AI-review commit cadence state for GIT-DIR.

The returned plist contains :marker-commit, :existing-distance,
:pending-distance, :due, and :bootstrap.  The pending distance includes the
Denote commit that has not yet been created."
  (let* ((root (denote-scribe--git-root git-dir))
         (default-directory root)
         (marker (denote-scribe--git-review-marker-commit root))
         (existing-distance
          (when marker
            (string-to-number
             (magit-git-string "rev-list" "--count"
                               (concat marker "..HEAD")))))
         (pending-distance (and existing-distance (1+ existing-distance)))
         (bootstrap (null marker))
         (due (or bootstrap
                  (>= pending-distance denote-scribe-review-commit-interval))))
    (list :git-root root
          :marker-commit marker
          :review-marker-commit marker
          :existing-distance existing-distance
          :pending-distance pending-distance
          :due due
          :review-due due
          :bootstrap bootstrap)))

(define-obsolete-function-alias
  'denote-scribe-git-hywiki-state
  #'denote-scribe-git-review-state "2026-07-16")

;;;###autoload
(defun denote-scribe-git-commit
    (title paths review-completed &optional kind git-dir)
  "Commit explicit PATHS with TITLE through noninteractive Magit APIs.

REVIEW-COMPLETED non-nil inserts `denote-scribe-review-commit-marker' in the
subject.  It means an AI review completed, whether or not it promoted a HyWiki
page.  KIND defaults to \"feat\" and may be \"feat\" or \"fix\".  Return a
plist containing the new commit hash, subject, and committed relative paths."
  (unless (and (stringp title) (not (string-empty-p title))
               (not (string-match-p "[\n\r]" title)))
    (error "TITLE must be non-empty and contain no newline"))
  (setq kind (or kind "feat"))
  (unless (member kind '("feat" "fix"))
    (error "KIND must be feat or fix: %S" kind))
  (unless (and (listp paths) paths)
    (error "PATHS must be a non-empty list"))
  (let* ((root (denote-scribe--git-root git-dir))
         (subject
          (format "%s(notes): %s%s"
                  kind
                  (if review-completed
                      (concat denote-scribe-review-commit-marker " ")
                    "")
                  title))
         (result
          (skill-git-commit-paths
           root subject paths
           (lambda (relative)
             (string-match-p
              "\\`\\(?:notes\\|hywiki\\)/[^/]+\\.org\\'" relative))
           "notes/*.org or hywiki/*.org")))
    (append result (list :review-completed (and review-completed t)))))

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

(defun denote-scribe--filename-keywords (file)
  "Return Denote keywords encoded in FILE's base name."
  (let ((base (file-name-base file)))
    (when (string-match "__\\(.+\\)\\'" base)
      (split-string (match-string 1 base) "_" t))))

(defun denote-scribe-list-notes (start end &optional notes-dir keywords)
  "List Denote Org files from inclusive START through END.

START and END use YYYY-MM-DD or YYYYMMDD.  When both are nil, list the full
Denote corpus.  Supplying only one date is an error.  NOTES-DIR defaults to
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
    (seq-filter
     (lambda (file)
       (let* ((base (file-name-nondirectory file))
              (date-id (substring base 0 8))
              (file-keywords (denote-scribe--filename-keywords file)))
         (and (or (null start-id)
                  (and (not (string< date-id start-id))
                       (not (string> date-id end-id))))
              (seq-every-p (lambda (keyword)
                             (member keyword file-keywords))
                           keywords))))
     (directory-files
      target-dir t
      "\\`[0-9]\\{8\\}T[0-9]\\{6\\}--.+\\.org\\'"))))

(defalias 'denote-scribe-list-reports #'denote-scribe-list-notes)

;;;###autoload
(defun denote-scribe-create (title body-file &optional keywords notes-dir signature date)
  "Create an Org Denote report with TITLE and insert BODY-FILE.

KEYWORDS is a list of strings.  When nil, do not add keywords.
NOTES-DIR overrides `denote-scribe-notes-directory'.
SIGNATURE and DATE are passed to Denote when non-nil.

Return the created file path."
  (unless (and (stringp title) (not (string= title "")))
    (error "TITLE must be a non-empty string"))
  (unless (and (stringp body-file) (file-readable-p body-file))
    (error "BODY-FILE is not readable: %S" body-file))
  (denote-scribe--validate-critical-body body-file)
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
(defun denote-scribe-hywiki-create
    (page-name body-file &optional replace hywiki-dir)
  "Create HyWiki PAGE-NAME from BODY-FILE and return a result plist.

Refuse to replace an existing non-empty page unless REPLACE is non-nil.
HYWIKI-DIR overrides `denote-scribe-hywiki-directory'.  PAGE-NAME must be a
plain HyWikiWord without a section suffix."
  (unless (and (stringp page-name) (not (string-empty-p page-name)))
    (error "PAGE-NAME must be a non-empty string"))
  (unless (and (stringp body-file) (file-readable-p body-file))
    (error "BODY-FILE is not readable: %S" body-file))
  (denote-scribe--validate-hywiki-body body-file)
  (unless (require 'hywiki nil t)
    (error "HyWiki is not available in this Emacs session"))
  (unless (and (hywiki-word-is-p page-name)
               (not (string-match-p "#" page-name)))
    (error "Invalid HyWiki PAGE-NAME (uppercase initial and letters only): %S"
           page-name))
  (let* ((target-dir
          (denote-scribe--directory hywiki-dir
                                    denote-scribe-hywiki-directory))
         (hywiki-directory target-dir)
         (existing (hywiki-get-existing-page-file page-name))
         (existing-nonempty
          (and existing (> (file-attribute-size (file-attributes existing)) 0))))
    (unless (file-directory-p target-dir)
      (error "HyWiki directory does not exist: %s" target-dir))
    (when (and existing-nonempty (not replace))
      (error "Refusing to replace non-empty HyWiki page: %s" existing))
    ;; Programmatic creation is already authorized by this helper call.  Binding
    ;; `noninteractive' avoids HyWiki's special prompt for the very first page.
    (let* ((noninteractive t)
           (page-file (cdr (hywiki-add-page page-name (and replace t)))))
      (unless page-file
        (error "HyWiki did not create or return page: %s" page-name))
      (with-current-buffer (find-file-noselect page-file)
        (insert-file-contents body-file nil nil nil t)
        (denote-scribe--fill-org-buffer)
        (save-buffer))
      (list :page-name page-name
            :file page-file
            :status (if existing-nonempty 'replaced 'created)))))

(provide 'denote-scribe)

;;; denote-scribe.el ends here
