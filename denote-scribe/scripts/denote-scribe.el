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
                  (operation data &optional count status page effects))
(declare-function skill-runtime-validate-request
                  "../../common/scripts/skill-runtime" (schemas request))

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

(defcustom denote-scribe-review-commit-interval 5
  "Number of repository commits between AI reviews."
  :type 'positive-integer
  :group 'denote-scribe)

(defcustom denote-scribe-fill-column 100
  "Column used to fill prose paragraphs in generated Org files."
  :type 'positive-integer
  :group 'denote-scribe)

(defcustom denote-scribe-summary-section-maximum-characters 500
  "Maximum characters returned for each section in compact note summaries."
  :type 'positive-integer
  :group 'denote-scribe)

(defcustom denote-scribe-review-summary-limit 8
  "Default notes returned in each compact AI-review summary page."
  :type 'positive-integer
  :group 'denote-scribe)

(defconst denote-scribe-review-commit-marker "🔒"
  "Literal commit-subject marker for a completed AI review.")

(defvar denote-directory)
(defvar denote-save-buffers)
(defvar hywiki-directory)
(declare-function denote "denote")
(declare-function hywiki-add-page "hywiki" (page-name &optional force-flag))
(declare-function hywiki-get-existing-page-file "hywiki" (reference))
(declare-function hywiki-word-is-p "hywiki" (word))
(declare-function magit-git-lines "magit-git" (&rest args))
(declare-function magit-git-string "magit-git" (&rest args))
(declare-function skill-git-commit-paths
                  "../../common/scripts/skill-git"
                  (root message paths &optional predicate description))
(declare-function skill-git-format-message
                  "../../common/scripts/skill-git" (spec))
(declare-function skill-git-directory
                  "../../common/scripts/skill-git" (directory))
(declare-function skill-git-root
                  "../../common/scripts/skill-git" (directory))

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

(defconst denote-scribe-review-summary-headings
  '("Question" "Evidence" "Conclusion" "Open Questions" "Extract Concepts"
    "核心问题" "证据" "结论" "开放问题" "提取概念")
  "Critical-note headings included in compact AI-review summaries.")

(defconst denote-scribe--schemas
  '((preflight :summary "Validate Denote, HyWiki, and repository configuration."
               :optional (:notes-dir :hywiki-dir :git-dir))
    (template :summary "Return the exact critical-note or HyWiki template."
              :required (:kind :language)
              :choices ((:kind critical hywiki) (:language en zh)))
    (create :summary "Create one Denote note from a completed body file."
            :required (:title :body-file)
            :optional (:keywords :notes-dir :signature :date :git-dir)
            :effects (:created))
    (review :summary "Return one bounded review page with continuation metadata."
            :required (:file :review-state)
            :optional (:notes-dir :offset :limit :section-maximum))
    (summarize :summary "Extract bounded critical sections from one note."
               :required (:file) :optional (:section-maximum))
    (list :summary "Return a filtered page of Denote notes."
          :optional (:start :end :notes-dir :keywords :offset :limit))
    (hywiki :summary "Create a HyWiki page; replacement requires authorization."
            :required (:page-name :body-file)
            :optional (:replace :authorization :hywiki-dir)
            :choices ((:authorization explicit))
            :effects (:mutated))
    (commit :summary "Commit only supplied run files after explicit authorization."
            :required (:title :paths :authorization)
            :optional (:review-completed :kind :git-dir)
            :types ((:title non-empty-string)
                    (:paths non-empty-string-list))
            :choices ((:authorization explicit) (:kind feat fix))
            :effects (:committed))
    (describe :summary "Return operation names or one complete schema."
              :optional (:target)))
  "Compact request schemas for `denote-scribe-run'.")

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

(defun denote-scribe--review-files (new-note state &optional notes-dir)
  "Return the Denote files to review for NEW-NOTE according to STATE."
  (let* ((root (plist-get state :git-root))
         (notes-root
          (file-name-as-directory
           (file-truename
            (denote-scribe--directory
             notes-dir denote-scribe-notes-directory))))
         (marker (plist-get state :marker-commit))
         (notes-relative (file-relative-name notes-root root))
         (_ (when (or (string= notes-relative "../")
                      (string-prefix-p "../" notes-relative))
              (error "Notes directory is outside the Git repository: %s"
                     notes-root)))
         (files
          (if (plist-get state :bootstrap)
              (denote-scribe-list-notes nil nil notes-root)
            (let ((default-directory root))
              (mapcar
               (lambda (relative) (expand-file-name relative root))
               (magit-git-lines
                "diff" "--name-only" "--diff-filter=ACMRT"
                (concat marker "..HEAD") "--"
                (concat notes-relative "*.org"))))))
         (candidate-files (delete-dups (append files (list new-note)))))
    (seq-filter
     (lambda (file)
       (and (file-regular-p file)
            (file-in-directory-p (file-truename file) notes-root)))
     candidate-files)))

(defun denote-scribe--truncate-summary (text maximum)
  "Return trimmed TEXT capped at MAXIMUM characters."
  (let ((clean (string-trim
                (substring-no-properties (or text "")))))
    (if (<= (length clean) maximum)
        (list :text clean :truncated nil)
      (list :text (concat (substring clean 0 maximum)
                          "\n[section truncated]")
            :truncated t))))

(defun denote-scribe-note-summary (file &optional section-maximum)
  "Return compact critical-review sections from Org FILE.

SECTION-MAXIMUM defaults to
`denote-scribe-summary-section-maximum-characters'.  Read the full file only
when a returned section is truncated or requires deeper evidence checking."
  (unless (and (stringp file) (file-readable-p file))
    (error "Review note is not readable: %S" file))
  (let ((maximum (or section-maximum
                     denote-scribe-summary-section-maximum-characters)))
    (unless (and (integerp maximum) (> maximum 0))
      (error "SECTION-MAXIMUM must be a positive integer: %S" maximum))
    (with-temp-buffer
      (insert-file-contents file)
      (delay-mode-hooks (org-mode))
      (let* ((tree (org-element-parse-buffer))
             (sections
              (org-element-map
                  tree 'headline
                (lambda (headline)
                  (let ((heading (org-element-property :raw-value headline)))
                    (when (and (= (org-element-property :level headline) 1)
                               (member heading
                                       denote-scribe-review-summary-headings))
                      (let ((summary
                             (denote-scribe--truncate-summary
                              (org-element-interpret-data
                               (org-element-contents headline))
                              maximum)))
                        (list :heading heading
                              :text (plist-get summary :text)
                              :truncated
                              (plist-get summary :truncated)))))))))
        (list :file (expand-file-name file)
              :title (or (org-get-title (current-buffer))
                         (file-name-base file))
              :sections sections)))))

(defun denote-scribe-review-summaries
    (files &optional offset limit section-maximum)
  "Return one bounded page of compact summaries for review FILES."
  (unless (listp files)
    (error "FILES must be a list"))
  (let* ((start (or offset 0))
         (page-size (or limit denote-scribe-review-summary-limit))
         (count (length files)))
    (unless (and (integerp start) (>= start 0))
      (error "OFFSET must be a non-negative integer: %S" start))
    (unless (and (integerp page-size) (> page-size 0))
      (error "LIMIT must be a positive integer: %S" page-size))
    (let* ((page (seq-take (nthcdr start files) page-size))
           (next (+ start (length page)))
           (truncated (< next count)))
      (list :count count
            :offset start
            :limit page-size
            :truncated truncated
            :next-offset (and truncated next)
            :summaries
            (mapcar (lambda (file)
                      (denote-scribe-note-summary file section-maximum))
                    page)))))

(defun denote-scribe-review-context
    (new-note state &optional notes-dir offset limit section-maximum)
  "Return a paged compact AI-review context for NEW-NOTE and cadence STATE."
  (if (not (plist-get state :review-due))
      (list :count 0 :offset 0 :limit (or limit 0)
            :truncated nil :summaries nil)
    (denote-scribe-review-summaries
     (denote-scribe--review-files new-note state notes-dir)
     offset limit section-maximum)))

;;;###autoload
(defun denote-scribe-create-with-review-context
    (title body-file &optional keywords notes-dir signature date git-dir)
  "Create a Denote report and return its complete AI-review context.

The creation arguments match `denote-scribe-create'; GIT-DIR selects the
repository used for review cadence.  Return :file, :review-state, and, only
when review is due, :review-files.  A bootstrap review includes the full
Denote corpus; later reviews include notes changed since the last completed
review plus the newly created report."
  (let* ((state (denote-scribe-git-review-state git-dir))
         (file (denote-scribe-create
                title body-file keywords notes-dir signature date)))
    (let ((review-files
           (and (plist-get state :review-due)
                (denote-scribe--review-files file state notes-dir))))
      (list :file file
            :review-state state
            :review-files review-files
            :review
            (and review-files
                 (denote-scribe-review-summaries review-files))))))

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
         (summary
          (concat (if review-completed
                      (concat denote-scribe-review-commit-marker " ")
                    "")
                  title))
         (message
          (skill-git-format-message
           (list
            :type kind :scope "notes" :summary summary
            :risk 'low :detail 'compact
            :context
            (concat "This commit records durable reasoning or reviewed knowledge from an "
                    "authorized Denote Scribe run.")
            :changes
            (delq nil
                  (list
                   (format "Create or update %d path-scoped Denote or HyWiki Org file(s)."
                           (length paths))
                   (and review-completed
                        "Record that every due AI-review page was evaluated.")))
            :reason
            "Keeping generated reasoning and promoted knowledge together preserves traceability."
            :validation
            "Validated the explicit files and restricted the commit to notes/*.org or hywiki/*.org."
            :boundary
            "No unrelated repository paths are staged and this workflow never pushes.")))
         (result
          (skill-git-commit-paths
           root message paths
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

;;;###autoload
(defun denote-scribe--run (request)
  "Execute Denote Scribe REQUEST through one compact public entry point.

Use :operation `describe' to request operation schemas only when needed."
  (skill-runtime-validate-request denote-scribe--schemas request)
  (let ((operation (plist-get request :operation)))
    (pcase operation
      ('preflight
       (let ((data
              (denote-scribe-preflight
               (plist-get request :notes-dir)
               (plist-get request :hywiki-dir)
               (plist-get request :git-dir))))
         (skill-runtime-result
          operation data 1
          (if (plist-get data :errors) 'blocked 'ok))))
      ('describe
       (skill-runtime-result
        operation
        (skill-runtime-describe
         denote-scribe--schemas (plist-get request :target))))
      ('template
       (skill-runtime-result
        operation
        (denote-scribe-template-file
         (plist-get request :kind)
         (plist-get request :language))))
      ('create
       (let* ((created
               (denote-scribe-create-with-review-context
                (plist-get request :title)
                (plist-get request :body-file)
                (plist-get request :keywords)
                (plist-get request :notes-dir)
                (plist-get request :signature)
                (plist-get request :date)
                (plist-get request :git-dir))))
         (skill-runtime-result operation created 1 nil nil
                               (list :created t))))
      ('review
       (let ((review
              (denote-scribe-review-context
               (plist-get request :file)
               (plist-get request :review-state)
               (plist-get request :notes-dir)
               (plist-get request :offset)
               (plist-get request :limit)
               (plist-get request :section-maximum))))
         (skill-runtime-result
          operation (plist-get review :summaries) (plist-get review :count)
          'ok
          (list :offset (plist-get review :offset)
                :limit (plist-get review :limit)
                :total (plist-get review :count)
                :truncated (plist-get review :truncated)
                :next-offset (plist-get review :next-offset)))))
      ('summarize
       (skill-runtime-result
        operation
        (denote-scribe-note-summary
         (plist-get request :file)
         (plist-get request :section-maximum))))
      ('list
       (let* ((files
               (denote-scribe-list-notes
                (plist-get request :start)
                (plist-get request :end)
                (plist-get request :notes-dir)
                (plist-get request :keywords)))
              (offset (or (plist-get request :offset) 0))
              (limit (or (plist-get request :limit)
                         denote-scribe-review-summary-limit))
              (page (skill-runtime-page files offset limit (length files))))
         (skill-runtime-result
          operation (plist-get page :items) (length files) 'ok
          (plist-get page :page))))
      ('hywiki
       (when (plist-get request :replace)
         (skill-runtime-require-authorization request "HyWiki replacement"))
       (skill-runtime-result
        operation
        (denote-scribe-hywiki-create
         (plist-get request :page-name)
         (plist-get request :body-file)
         (plist-get request :replace)
         (plist-get request :hywiki-dir))
        1 nil nil (list :mutated t)))
      ('commit
       (skill-runtime-require-authorization request "Commit")
       (skill-runtime-result
        operation
        (denote-scribe-git-commit
         (plist-get request :title)
         (plist-get request :paths)
         (plist-get request :review-completed)
         (plist-get request :kind)
         (plist-get request :git-dir))
        1 nil nil (list :committed t)))
      (_ (error "Unknown Denote Scribe operation %S; expected %S"
                operation (mapcar #'car denote-scribe--schemas))))))

;;;###autoload
(defun denote-scribe-run (request)
  "Execute measured Denote Scribe REQUEST."
  (skill-runtime-measure request (lambda () (denote-scribe--run request))))

(provide 'denote-scribe)

;;; denote-scribe.el ends here
