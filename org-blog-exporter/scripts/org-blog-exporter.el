;;; org-blog-exporter.el --- Export Org notes to the user's HTML blog -*- lexical-binding: t; -*-

;;; Code:

(require 'org)
(require 'ox-html)
(require 'ox-publish)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'xml)

(unless (featurep 'skill-git)
  (let* ((script-directory
          (file-name-directory (or load-file-name buffer-file-name)))
         (shared-file
          (expand-file-name "../../common/scripts/skill-git.el"
                            script-directory)))
    (unless (file-readable-p shared-file)
      (error "Shared Git helper is not readable: %s" shared-file))
    (load shared-file nil nil t)))

(defgroup org-blog-exporter nil
  "Export Org notes to a static HTML blog."
  :group 'org)

(declare-function skill-git-assert-clean
                  "../../common/scripts/skill-git" (root))
(declare-function skill-git-commit-paths
                  "../../common/scripts/skill-git"
                  (root subject paths &optional predicate description))
(declare-function skill-git-ensure-repository
                  "../../common/scripts/skill-git" (remote-url directory))
(declare-function skill-git-pull-ff-only
                  "../../common/scripts/skill-git" (root))
(declare-function skill-git-push
                  "../../common/scripts/skill-git" (root))
(declare-function skill-git-relative-path
                  "../../common/scripts/skill-git"
                  (root path &optional predicate description))
(declare-function skill-git-status
                  "../../common/scripts/skill-git" (root &optional paths))
(declare-function skill-git-upstream-ahead-count
                  "../../common/scripts/skill-git" (root))

(defcustom org-blog-exporter-notes-directory "~/Dropbox/notes/"
  "Directory containing source Org notes."
  :type 'directory
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-output-directory "~/Documents/zorowk.github.io/"
  "Fallback directory where exported HTML files are written.

When `org-blog-exporter-setupfile' contains a BLOG_EXPORT_DIR,
BLOG_OUTPUT_DIR, BLOG_DIR, or BLOG_DIRECTORY keyword, that value is used
instead."
  :type 'directory
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-repository-url
  "https://github.com/zorowk/zorowk.github.io.git"
  "Fallback Git repository used when the setupfile does not configure one."
  :type 'string
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-setupfile "~/Dropbox/notes/setupfile.org"
  "Org setupfile containing blog HTML export configuration."
  :type 'file
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-assets-directory-name "image"
  "Repository directory used for local resources during publishing."
  :type 'string
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-asset-extensions
  '("png" "jpg" "jpeg" "gif" "webp" "svg" "avif" "bmp" "ico"
    "mp4" "webm" "ogv" "mov" "m4v"
    "mp3" "ogg" "oga" "wav" "flac" "m4a"
    "pdf" "zip" "gz" "tar" "csv" "json")
  "Local resource extensions copied during explicit publishing."
  :type '(repeat string)
  :group 'org-blog-exporter)

(defcustom org-blog-exporter-result-limit 20
  "Default maximum paths returned by compact export and publish results."
  :type 'positive-integer
  :group 'org-blog-exporter)

(defconst org-blog-exporter--excluded-directories
  '(".git" ".stversions" "archive" "archives" "attach" "attachments"
    "assets" "auto" "backup" "backups" "draft" "drafts" "private" "tmp" "trash"))

(defconst org-blog-exporter--excluded-tags
  '("noexport" "private" "draft"))

(defconst org-blog-exporter--output-directory-keywords
  '("BLOG_EXPORT_DIR" "BLOG_OUTPUT_DIR" "BLOG_DIR" "BLOG_DIRECTORY"))

(defconst org-blog-exporter--repository-url-keywords
  '("BLOG_REPOSITORY_URL" "BLOG_REPO_URL"))

(defconst org-blog-exporter--assessment-properties
  '(("STATUS" "Status" "状态")
    ("CREDIBILITY" "Credibility" "可信度")
    ("MATURITY" "Maturity" "成熟度")
    ("HYWIKI_CANDIDATE" "HyWiki candidate" "HyWiki 候选")
    ("REVIEW_PERIOD" "Review period" "审查周期")
    ("QUESTION_STATUS" "Question status" "问题状态")
    ("REVIEW_DATE" "Review date" "复查日期"))
  "Org properties rendered as assessment summaries during HTML export.")

(defun org-blog-exporter--expand-directory (directory)
  "Return DIRECTORY as an absolute directory name."
  (file-name-as-directory (expand-file-name directory)))

(defun org-blog-exporter--notes-directory (&optional notes-dir)
  "Return the absolute notes directory."
  (org-blog-exporter--expand-directory
   (or notes-dir org-blog-exporter-notes-directory)))

(defun org-blog-exporter--buffer-keyword (keyword)
  "Return the first value of Org KEYWORD in the current buffer."
  (let ((name (upcase keyword)))
    (cdr (assoc name (org-collect-keywords (list name) (list name))))))

(defun org-blog-exporter--file-keyword (file keyword)
  "Return FILE's first Org KEYWORD value."
  (let ((source (expand-file-name file)))
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source
            default-directory (file-name-directory source))
      (delay-mode-hooks (org-mode))
      (org-blog-exporter--buffer-keyword keyword))))

(defun org-blog-exporter--setupfile-keyword (keyword &optional setupfile)
  "Return KEYWORD value from SETUPFILE, or nil when absent."
  (let ((file (org-blog-exporter--setupfile setupfile)))
    (when (file-readable-p file)
      (org-blog-exporter--file-keyword file keyword))))

(defun org-blog-exporter--configured-output-directory (&optional setupfile)
  "Return the blog output directory declared in SETUPFILE, or nil."
  (cl-some (lambda (keyword)
             (org-blog-exporter--setupfile-keyword keyword setupfile))
           org-blog-exporter--output-directory-keywords))

(defun org-blog-exporter--repository-url (&optional setupfile)
  "Return the repository URL declared in SETUPFILE, or the fallback value."
  (or (cl-some (lambda (keyword)
                 (org-blog-exporter--setupfile-keyword keyword setupfile))
               org-blog-exporter--repository-url-keywords)
      org-blog-exporter-repository-url))

(defun org-blog-exporter--output-directory (&optional output-dir setupfile)
  "Return the absolute blog output directory."
  (org-blog-exporter--expand-directory
   (or output-dir
       (org-blog-exporter--configured-output-directory setupfile)
       org-blog-exporter-output-directory)))

(defun org-blog-exporter-preflight (&optional notes-dir output-dir setupfile)
  "Return a plist describing whether blog export prerequisites are available."
  (let* ((notes (org-blog-exporter--notes-directory notes-dir))
         (setup (org-blog-exporter--setupfile setupfile))
         (output (org-blog-exporter--output-directory output-dir setupfile))
         (errors nil)
         (candidates nil))
    (unless (file-directory-p notes)
      (push (format "Notes directory does not exist: %s" notes) errors))
    (unless (file-readable-p setup)
      (push (format "Setupfile is not readable: %s" setup) errors))
    (unless (file-directory-p output)
      (push (format "Output directory does not exist: %s" output) errors))
    (when (file-directory-p notes)
      (setq candidates
            (condition-case err
                (org-blog-exporter-list-candidates notes)
              (error
               (push (format "Candidate scan failed: %s"
                             (error-message-string err))
                     errors)
               nil))))
    (list :notes-directory notes
          :notes-directory-exists (file-directory-p notes)
          :setupfile setup
          :setupfile-readable (file-readable-p setup)
          :output-directory output
          :output-directory-exists (file-directory-p output)
          :repository-url (org-blog-exporter--repository-url setupfile)
          :repository-clone-required (not (file-exists-p output))
          :candidate-count (length candidates)
          :errors (nreverse errors))))

(defun org-blog-exporter--setupfile (&optional setupfile)
  "Return the absolute setupfile path."
  (expand-file-name (or setupfile org-blog-exporter-setupfile)))

(defun org-blog-exporter--relative-to-notes (file &optional notes-dir)
  "Return FILE path relative to NOTES-DIR."
  (file-relative-name (expand-file-name file)
                      (org-blog-exporter--notes-directory notes-dir)))

(defun org-blog-exporter--excluded-directory-p (file &optional notes-dir)
  "Return non-nil when FILE is under an excluded directory."
  (let* ((relative (org-blog-exporter--relative-to-notes file notes-dir))
         (parts (split-string relative "/" t)))
    (cl-intersection parts org-blog-exporter--excluded-directories
                     :test #'string=)))

(defun org-blog-exporter--backup-or-hidden-p (file)
  "Return non-nil when FILE looks like an editor backup or hidden file."
  (let ((name (file-name-nondirectory file)))
    (or (string-prefix-p "." name)
        (auto-save-file-name-p name)
        (backup-file-name-p name))))

(defun org-blog-exporter--filetags (file)
  "Return FILE-level Org tags declared in FILE."
  (with-temp-buffer
    (insert-file-contents file nil 0 4096)
    (org-mode)
    (let* ((keywords (org-collect-keywords '("FILETAGS")))
           (values (cdr (assoc "FILETAGS" keywords)))
           (tags (and values
                      (split-string (string-join values " ") "[: \t]+" t))))
      (delete-dups (mapcar #'downcase tags)))))

(defun org-blog-exporter--excluded-tags-p (file)
  "Return non-nil when FILE declares an excluded file tag."
  (cl-intersection (org-blog-exporter--filetags file)
                   org-blog-exporter--excluded-tags
                   :test #'string=))

(defun org-blog-exporter-exportable-file-p (file &optional notes-dir)
  "Return non-nil when FILE should be exported."
  (let ((expanded (expand-file-name file)))
    (and (file-regular-p expanded)
         (string= (file-name-extension expanded) "org")
         (not (string= (file-truename expanded)
                       (file-truename (org-blog-exporter--setupfile))))
         (not (org-blog-exporter--backup-or-hidden-p expanded))
         (not (org-blog-exporter--excluded-directory-p expanded notes-dir))
         (not (org-blog-exporter--excluded-tags-p expanded)))))

(defun org-blog-exporter-list-candidates (&optional notes-dir)
  "Return exportable Org files under NOTES-DIR."
  (let ((root (org-blog-exporter--notes-directory notes-dir)))
    (cl-remove-if-not
     (lambda (file)
       (org-blog-exporter-exportable-file-p file root))
     (directory-files-recursively root "\\.org\\'"))))

(defun org-blog-exporter--validated-files (org-files &optional notes-dir)
  "Return absolute exportable ORG-FILES below NOTES-DIR or signal an error."
  (unless (and (listp org-files) org-files)
    (error "ORG-FILES must be a non-empty list"))
  (let ((root (org-blog-exporter--notes-directory notes-dir)))
    (mapcar
     (lambda (file)
       (let ((source (expand-file-name file)))
         (unless (file-in-directory-p source root)
           (error "Org file is outside the configured notes directory: %s"
                  source))
         (unless (org-blog-exporter-exportable-file-p source root)
           (error "Org file is not an exportable public note: %s" source))
         source))
     org-files)))

(defun org-blog-exporter--local-link-target-p (target)
  "Return non-nil when TARGET looks like a local file link."
  (and (stringp target)
       (not (string-empty-p target))
       (not (file-remote-p target))
       (not (string-match-p "\\`[a-zA-Z][a-zA-Z0-9+.-]*:" target))
       (not (string-prefix-p "#" target))))

(defun org-blog-exporter--asset-path (target org-file)
  "Return absolute path for local link TARGET in ORG-FILE."
  (expand-file-name target (file-name-directory (expand-file-name org-file))))

(defun org-blog-exporter-local-assets (org-file)
  "Return local assets referenced by ORG-FILE.

Each result entry is (raw-link absolute-path exists)."
  (let ((source (expand-file-name org-file))
        (assets nil))
    (with-temp-buffer
      (insert-file-contents source)
      (org-mode)
      (org-element-map (org-element-parse-buffer) 'link
        (lambda (link)
          (let ((raw (org-element-property :raw-link link))
                (type (org-element-property :type link))
                (path (org-element-property :path link)))
            (when (and (string= type "file")
                       (org-blog-exporter--local-link-target-p path))
              (let ((absolute (org-blog-exporter--asset-path path source)))
                (push (list raw absolute (file-exists-p absolute)) assets)))))))
    (nreverse assets)))

(defun org-blog-exporter--assets-directory (repository-root)
  "Return the local-resource directory below REPOSITORY-ROOT."
  (let ((name org-blog-exporter-assets-directory-name))
    (unless (and (stringp name)
                 (string-match-p "\\`[^/\\\\.][^/\\\\]*\\'" name)
                 (not (member name '("." ".."))))
      (error "Invalid blog assets directory name: %S" name))
    (file-name-as-directory (expand-file-name name repository-root))))

(defun org-blog-exporter--supported-asset-p (file)
  "Return non-nil when FILE has a configured resource extension."
  (let ((extension (file-name-extension file)))
    (and extension
         (member (downcase extension)
                 (mapcar #'downcase org-blog-exporter-asset-extensions)))))

(defun org-blog-exporter--file-digest (file)
  "Return a SHA-256 digest for FILE contents."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun org-blog-exporter--same-file-contents-p (left right)
  "Return non-nil when LEFT and RIGHT have identical contents."
  (or (file-equal-p left right)
      (and (= (file-attribute-size (file-attributes left))
              (file-attribute-size (file-attributes right)))
           (string= (org-blog-exporter--file-digest left)
                    (org-blog-exporter--file-digest right)))))

(defun org-blog-exporter--asset-plan (org-files repository-root)
  "Validate resources in ORG-FILES and return their publication plan.

Each plan entry is a plist with :source and :target.  Resources are flattened
into the configured assets directory, so conflicting basenames are rejected."
  (let ((directory (org-blog-exporter--assets-directory repository-root))
        (by-target (make-hash-table :test #'equal))
        plan)
    (dolist (org-file org-files)
      (dolist (asset (org-blog-exporter-local-assets org-file))
        (let ((source (expand-file-name (nth 1 asset))))
          ;; Org-to-Org links are page navigation, not static resources.
          (unless (string= (downcase (or (file-name-extension source) "")) "org")
            (let* ((target (expand-file-name (file-name-nondirectory source)
                                             directory))
                   (previous (gethash target by-target)))
              (unless (file-regular-p source)
                (error "Local blog resource is missing or not a file: %s" source))
              (unless (file-readable-p source)
                (error "Local blog resource is not readable: %s" source))
              (unless (org-blog-exporter--supported-asset-p source)
                (error "Unsupported local blog resource type: %s" source))
              (when (and previous
                         (not (org-blog-exporter--same-file-contents-p
                               source previous)))
                (error "Conflicting blog resources share basename %s: %s and %s"
                       (file-name-nondirectory source) previous source))
              (when (and (file-exists-p target)
                         (not (file-regular-p target)))
                (error "Blog resource target is not a regular file: %s" target))
              (when (and (file-regular-p target)
                         (not (org-blog-exporter--same-file-contents-p
                               source target)))
                (error "Refusing to overwrite different blog resource: %s"
                       target))
              (unless previous
                (puthash target source by-target)
                (push (list :source source :target target) plan)))))))
    (nreverse plan)))

(defun org-blog-exporter--asset-targets (plan)
  "Return a source-to-target alist derived from PLAN."
  (mapcar (lambda (entry)
            (cons (plist-get entry :source) (plist-get entry :target)))
          plan))

(defun org-blog-exporter--copy-assets (plan)
  "Copy resources in PLAN and return all target paths."
  (let (targets)
    (dolist (entry plan)
      (let ((source (plist-get entry :source))
            (target (plist-get entry :target)))
        (make-directory (file-name-directory target) t)
        (unless (and (file-regular-p target)
                     (org-blog-exporter--same-file-contents-p source target))
          (org-publish-attachment nil source (file-name-directory target)))
        (push target targets)))
    (nreverse targets)))

(defun org-blog-exporter--rewrite-asset-links (source target asset-targets)
  "Rewrite local links in current buffer using ASSET-TARGETS.

SOURCE is the Org file and TARGET is its HTML output path.  Only this temporary
export buffer is changed."
  (let (replacements)
    (org-element-map (org-element-parse-buffer) 'link
      (lambda (link)
        (let ((type (org-element-property :type link))
              (path (org-element-property :path link))
              (raw (org-element-property :raw-link link)))
          (when (and (string= type "file")
                     (org-blog-exporter--local-link-target-p path))
            (let* ((absolute (org-blog-exporter--asset-path path source))
                   (published (cdr (assoc absolute asset-targets))))
              (when published
                (push (list (org-element-property :begin link)
                            (org-element-property :end link)
                            raw
                            (concat "file:"
                                    (file-relative-name
                                     published (file-name-directory target))))
                      replacements)))))))
    (dolist (replacement (sort replacements (lambda (a b) (> (car a) (car b)))))
      (goto-char (nth 0 replacement))
      (unless (search-forward (nth 2 replacement) (nth 1 replacement) t)
        (error "Could not rewrite local resource link: %s" (nth 2 replacement)))
      (replace-match (nth 3 replacement) t t))))

(defun org-blog-exporter--target-file (org-file &optional output-dir notes-dir setupfile)
  "Return the HTML target path for ORG-FILE."
  (let* ((relative (org-blog-exporter--relative-to-notes org-file notes-dir))
         (html-relative (concat (file-name-sans-extension relative) ".html")))
    (expand-file-name html-relative
                      (org-blog-exporter--output-directory output-dir setupfile))))

(defun org-blog-exporter--has-setupfile-p ()
  "Return non-nil when current buffer already has a setupfile directive."
  (org-blog-exporter--buffer-keyword "SETUPFILE"))

(defun org-blog-exporter--insert-setupfile-if-missing (setupfile)
  "Insert SETUPFILE directive when current buffer lacks one."
  (unless (org-blog-exporter--has-setupfile-p)
    (goto-char (point-min))
    (insert "#+SETUPFILE: " (expand-file-name setupfile) "\n")))

(defun org-blog-exporter--chinese-text-p (text)
  "Return non-nil when TEXT contains a common Chinese character."
  (and text (string-match-p "[一-龥]" text)))

(defun org-blog-exporter--assessment-items ()
  "Return configured assessment properties at the current Org heading."
  (delq nil
        (mapcar
         (lambda (spec)
           (let ((value (org-entry-get nil (car spec) nil)))
             (when (and value (not (string-empty-p (string-trim value))))
               (list spec (string-trim value)))))
         org-blog-exporter--assessment-properties)))

(defun org-blog-exporter--assessment-summary-html (items chinese)
  "Return an HTML assessment summary for ITEMS.

Use Chinese labels when CHINESE is non-nil."
  (let ((separator (if chinese "：" ": ")))
    (format
     (concat "<p class=\"assessment-summary\"><strong>%s%s</strong> %s</p>")
     (if chinese "评估" "Assessment") separator
     (string-join
      (mapcar
       (lambda (item)
         (let* ((spec (car item))
                (value (cadr item))
                (label (if chinese (nth 2 spec) (nth 1 spec))))
           (format
            "<span class=\"assessment-item\"><strong>%s%s</strong>%s</span>"
            label separator (xml-escape-string value))))
       items)
      " <span aria-hidden=\"true\">·</span> "))))

(defun org-blog-exporter--insert-assessment-summaries ()
  "Render assessment properties as visible summaries in the export buffer."
  (let (headings)
    (save-restriction
      (widen)
      (goto-char (point-min))
      (org-map-entries (lambda () (push (point) headings)) nil nil))
    (dolist (position (sort headings #'>))
      (goto-char position)
      (let ((items (org-blog-exporter--assessment-items)))
        (when items
          (let* ((heading (org-get-heading t t t t))
                 (values (mapconcat #'cadr items " "))
                 (chinese
                  (or (org-blog-exporter--chinese-text-p heading)
                      (org-blog-exporter--chinese-text-p values))))
            (org-end-of-meta-data t)
            (insert "#+begin_export html\n"
                    (org-blog-exporter--assessment-summary-html items chinese)
                    "\n#+end_export\n\n")))))))

(defun org-blog-exporter-export-file
    (org-file &optional output-dir setupfile asset-targets notes-dir)
  "Export ORG-FILE to HTML and return the exported path."
  (let* ((source (car (org-blog-exporter--validated-files
                       (list org-file) notes-dir)))
         (setup (org-blog-exporter--setupfile setupfile))
         (target (org-blog-exporter--target-file
                  source output-dir notes-dir setup))
         (default-directory (file-name-directory source))
         (org-export-use-babel nil)
         (org-export-allow-bind-keywords t))
    (unless (file-readable-p setup)
      (error "Setupfile is not readable: %s" setup))
    (make-directory (file-name-directory target) t)
    (with-temp-buffer
      (insert-file-contents source)
      (setq buffer-file-name source)
      (delay-mode-hooks (org-mode))
      (when asset-targets
        (org-blog-exporter--rewrite-asset-links source target asset-targets))
      (org-blog-exporter--insert-assessment-summaries)
      (org-blog-exporter--insert-setupfile-if-missing setup)
      (let ((exported (org-export-to-file 'html target nil nil nil nil nil)))
        (unless (and exported (file-exists-p exported))
          (error "Export did not create HTML for %s" source))
        exported))))

(defun org-blog-exporter-export-files
    (org-files &optional output-dir setupfile asset-targets notes-dir)
  "Export ORG-FILES and return exported HTML paths."
  (mapcar (lambda (file)
            (org-blog-exporter-export-file
             file output-dir setupfile asset-targets notes-dir))
          org-files))

(defun org-blog-exporter-export-all
    (&optional notes-dir output-dir setupfile asset-targets)
  "Export all candidate Org files under NOTES-DIR and return a plist summary."
  (let* ((root (org-blog-exporter--notes-directory notes-dir))
         (files (org-blog-exporter-list-candidates root))
         (exported nil)
         (errors nil))
    (dolist (file files)
      (condition-case err
          (push (org-blog-exporter-export-file
                 file output-dir setupfile asset-targets root)
                exported)
        (error
         (push (list file (error-message-string err)) errors))))
    (list :notes-directory root
          :output-directory (org-blog-exporter--output-directory output-dir setupfile)
          :candidate-count (length files)
          :candidates files
          :exported-count (length exported)
          :exported (nreverse exported)
          :error-count (length errors)
          :errors (nreverse errors))))

;;;###autoload
(defun org-blog-exporter-export
    (&optional org-files output-dir setupfile notes-dir)
  "Export selected ORG-FILES, or every public note when ORG-FILES is nil.

Return a consistent summary plist containing :scope, :candidates, :exported,
and error counts.  Selected-file export validates the complete selection before
starting; all-file export preserves per-file error reporting."
  (if org-files
      (let* ((files (org-blog-exporter--validated-files org-files notes-dir))
             (exported (org-blog-exporter-export-files
                        files output-dir setupfile nil notes-dir)))
        (list :scope 'files
              :notes-directory (org-blog-exporter--notes-directory notes-dir)
              :output-directory
              (org-blog-exporter--output-directory output-dir setupfile)
              :candidate-count (length files)
              :candidates files
              :exported-count (length exported)
              :exported exported
              :error-count 0
              :errors nil))
    (append (list :scope 'all)
            (org-blog-exporter-export-all notes-dir output-dir setupfile))))

(defun org-blog-exporter--post-date (org-file)
  "Return ORG-FILE's publication date as YYYY-MM-DD."
  (let ((declared (org-blog-exporter--file-keyword org-file "DATE"))
        (base (file-name-base org-file)))
    (cond
     ((and declared
           (condition-case nil
               (format-time-string
                "%Y-%m-%d" (org-time-string-to-time declared))
             (error nil))))
     ((string-match
       "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T" base)
      (format "%s-%s-%s"
              (match-string 1 base)
              (match-string 2 base)
              (match-string 3 base)))
     (t
      (format-time-string "%Y-%m-%d"
                          (file-attribute-modification-time
                           (file-attributes org-file)))))))

(defun org-blog-exporter--index-entries (index-file)
  "Return existing blog entries parsed from INDEX-FILE."
  (let ((entries nil))
    (when (file-readable-p index-file)
      (with-temp-buffer
        (insert-file-contents index-file)
        (goto-char (point-min))
        (while (re-search-forward
                (concat
                 "<li><time datetime=\\\"\\([^\\\"]+\\)\\\">[^<]*</time>"
                 "<a href=\\\"\\([^\\\"]+\\)\\\">\\([^<]+\\)</a></li>")
                nil t)
          (push (list :date (match-string-no-properties 1)
                      :href (xml-substitute-special
                             (match-string-no-properties 2))
                      :title (xml-substitute-special
                              (match-string-no-properties 3)))
                entries))))
    (nreverse entries)))

(defun org-blog-exporter--post-entry
    (org-file output-dir setupfile &optional notes-dir)
  "Return the homepage entry for ORG-FILE."
  (let* ((target
          (org-blog-exporter--target-file
           org-file output-dir notes-dir setupfile))
         (relative
          (file-relative-name target
                              (org-blog-exporter--output-directory
                               output-dir setupfile))))
    (list :date (org-blog-exporter--post-date org-file)
          :href (concat "./" relative)
          :title (or (org-get-title org-file)
                     (file-name-base org-file)))))

(defun org-blog-exporter--merge-index-entries (existing updates)
  "Merge UPDATES into EXISTING entries by href and sort newest first."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (entry existing)
      (puthash (plist-get entry :href) entry table))
    (dolist (entry updates)
      (puthash (plist-get entry :href) entry table))
    (let (merged)
      (maphash (lambda (_href entry) (push entry merged)) table)
      (sort merged
            (lambda (left right)
              (let ((left-date (plist-get left :date))
                    (right-date (plist-get right :date)))
                (if (string= left-date right-date)
                    (string< (plist-get left :title)
                             (plist-get right :title))
                  (string> left-date right-date))))))))

(defun org-blog-exporter-update-index
    (org-files &optional output-dir setupfile notes-dir)
  "Update index.html with ORG-FILES and return its absolute path."
  (let* ((output (org-blog-exporter--output-directory output-dir setupfile))
         (index-file (expand-file-name "index.html" output))
         (entries
          (org-blog-exporter--merge-index-entries
           (org-blog-exporter--index-entries index-file)
           (mapcar (lambda (file)
                     (org-blog-exporter--post-entry
                      file output setupfile notes-dir))
                   org-files)))
         (system-time-locale "C"))
    (make-directory output t)
    (with-temp-file index-file
      (insert "<!doctype html>\n<html lang=\"en-US\">\n<head>\n"
              "<meta charset=\"utf-8\"/>\n"
              "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"/>\n"
              "<title>Home</title>\n"
              "<link rel=\"stylesheet\" href=\"/style.css\"/>\n"
              "</head>\n<body>\n"
              "<header><nav><a href=\"/\">Home</a></nav></header>\n"
              "<main>\n<ul class=\"blog-posts\">\n")
      (dolist (entry entries)
        (let* ((date (plist-get entry :date))
               (time (date-to-time (concat date " 00:00:00"))))
          (insert (format
                   "<li><time datetime=\"%s\">%s</time><a href=\"%s\">%s</a></li>\n"
                   date (format-time-string "%d %b, %Y" time)
                   (xml-escape-string (plist-get entry :href))
                   (xml-escape-string (plist-get entry :title))))))
      (insert "</ul>\n</main>\n<footer></footer>\n</body>\n</html>\n"))
    index-file))

(defun org-blog-exporter--prepare-publish-repository
    (&optional repository-dir setupfile)
  "Prepare REPOSITORY-DIR for a safe publish using SETUPFILE configuration."
  (let* ((directory
          (org-blog-exporter--output-directory repository-dir setupfile))
         (repository-url (org-blog-exporter--repository-url setupfile))
         (repository
          (skill-git-ensure-repository
           repository-url directory))
         (root (plist-get repository :git-root)))
    (skill-git-assert-clean root)
    (skill-git-pull-ff-only root)
    (skill-git-assert-clean root)
    (let ((ahead (skill-git-upstream-ahead-count root)))
      (unless (zerop ahead)
        (error "Refusing to publish %d pre-existing local commit(s)" ahead)))
    repository))

(defun org-blog-exporter--published-relative-path-p (relative)
  "Return non-nil when RELATIVE is publishable HTML or a copied resource."
  (or (string-match-p "\\.html\\'" relative)
      (string-match-p
       (format "\\`%s/[^/]+\\'"
               (regexp-quote org-blog-exporter-assets-directory-name))
       relative)))

(defun org-blog-exporter--finish-publish (repository exported subject)
  "Commit EXPORTED files in REPOSITORY with SUBJECT, then push."
  (let* ((root (plist-get repository :git-root))
         (relative-paths
          (mapcar (lambda (path)
                    (skill-git-relative-path
                     root path #'org-blog-exporter--published-relative-path-p
                     "published blog files"))
                  exported))
         (status (skill-git-status root relative-paths)))
    (if (string-empty-p status)
        (append repository
                (list :changed nil :exported exported :commit nil :push nil))
      (let ((commit
             (skill-git-commit-paths
              root subject exported
              #'org-blog-exporter--published-relative-path-p
              "published blog files")))
        (skill-git-assert-clean root)
        (append repository
                (list :changed t
                      :exported exported
                      :commit commit
                      :push (skill-git-push root)))))))

;;;###autoload
(defun org-blog-exporter-publish-files
    (org-files &optional title repository-dir setupfile notes-dir)
  "Publish ORG-FILES and their local resources to the blog repository.

TITLE is used in the commit subject and defaults to `Publish Org HTML'.
Read repository defaults from SETUPFILE and clone when absent.  Validate and
copy referenced resources, rewrite their exported links, update index.html,
commit only generated paths, and push."
  (unless (and (listp org-files) org-files)
    (error "ORG-FILES must be a non-empty list"))
  (setq org-files (org-blog-exporter--validated-files org-files notes-dir))
  (let* ((repository
          (org-blog-exporter--prepare-publish-repository
           repository-dir setupfile))
         (root (plist-get repository :git-root))
         (asset-plan (org-blog-exporter--asset-plan org-files root))
         (asset-targets (org-blog-exporter--asset-targets asset-plan))
         (exported (org-blog-exporter-export-files
                    org-files root setupfile asset-targets notes-dir))
         (index-file
          (org-blog-exporter-update-index
           org-files root setupfile notes-dir))
         (assets (org-blog-exporter--copy-assets asset-plan))
         (subject (format "chore(blog): %s" (or title "Publish Org HTML"))))
    (append (org-blog-exporter--finish-publish
             repository (append exported (list index-file) assets) subject)
            (list :index index-file :assets assets))))

;;;###autoload
(defun org-blog-exporter-publish-all
    (&optional title notes-dir repository-dir setupfile)
  "Publish all public notes and their local resources to the blog repository.

TITLE is used in the commit subject and defaults to `Publish Org HTML'.
Read repository defaults from SETUPFILE and clone when absent.  Validate and
copy referenced resources, rewrite their exported links, update index.html,
commit only generated paths, and push."
  (let* ((repository
          (org-blog-exporter--prepare-publish-repository
           repository-dir setupfile))
         (root (plist-get repository :git-root))
         (files (org-blog-exporter-list-candidates notes-dir))
         (asset-plan (org-blog-exporter--asset-plan files root))
         (asset-targets (org-blog-exporter--asset-targets asset-plan))
         (summary (org-blog-exporter-export-all
                   notes-dir root setupfile asset-targets)))
    (unless (zerop (plist-get summary :error-count))
      (error "Blog export failed: %S" (plist-get summary :errors)))
    (let ((index-file
           (org-blog-exporter-update-index
            (plist-get summary :candidates) root setupfile notes-dir))
          (assets (org-blog-exporter--copy-assets asset-plan)))
      (append
       summary
       (org-blog-exporter--finish-publish
        repository
        (append (plist-get summary :exported) (list index-file) assets)
        (format "chore(blog): %s" (or title "Publish Org HTML")))
       (list :index index-file :assets assets)))))

;;;###autoload
(defun org-blog-exporter-publish
    (&optional org-files title notes-dir repository-dir setupfile)
  "Publish selected ORG-FILES, or every public note when ORG-FILES is nil.

TITLE, NOTES-DIR, REPOSITORY-DIR, and SETUPFILE match the specialized publish
entry points.  Calling this function performs the full clone/pull, export,
index, resource, commit, and push workflow; callers must establish explicit
publishing authorization before invoking it."
  (if org-files
      (org-blog-exporter-publish-files
       (org-blog-exporter--validated-files org-files notes-dir)
       title repository-dir setupfile notes-dir)
    (org-blog-exporter-publish-all
     title notes-dir repository-dir setupfile)))

(defun org-blog-exporter--compact-result (operation result &optional limit)
  "Return token-bounded standard RESULT for blog OPERATION."
  (let* ((maximum (or limit org-blog-exporter-result-limit))
         (exported (plist-get result :exported))
         (assets (plist-get result :assets))
         (errors (plist-get result :errors))
         (error-count (or (plist-get result :error-count) 0)))
    (unless (and (integerp maximum) (> maximum 0))
      (error "LIMIT must be a positive integer: %S" maximum))
    (list :status (if (zerop error-count) 'ok 'partial)
          :operation operation
          :scope (plist-get result :scope)
          :candidate-count (plist-get result :candidate-count)
          :exported-count (or (plist-get result :exported-count)
                              (length exported))
          :exported (seq-take exported maximum)
          :assets-count (length assets)
          :assets (seq-take assets maximum)
          :error-count error-count
          :errors (seq-take errors maximum)
          :truncated
          (or (> (length exported) maximum)
              (> (length assets) maximum)
              (> (length errors) maximum))
          :output-directory (plist-get result :output-directory)
          :changed (plist-get result :changed)
          :commit (plist-get result :commit)
          :push (plist-get result :push)
          :index (plist-get result :index))))

;;;###autoload
(defun org-blog-exporter-run (request)
  "Execute blog REQUEST through one compact public entry point.

Use :operation `export', `publish', or `preflight'.  Export and publish accept
:files (nil means all), directories, setupfile, and :limit.  Publish requires
:authorization `explicit'.  Pass :full non-nil only when complete path lists
are required."
  (unless (listp request)
    (error "REQUEST must be a plist"))
  (let* ((operation (plist-get request :operation))
         (result
          (pcase operation
            ('preflight
             (org-blog-exporter-preflight
              (plist-get request :notes-dir)
              (plist-get request :output-dir)
              (plist-get request :setupfile)))
            ('export
             (org-blog-exporter-export
              (plist-get request :files)
              (plist-get request :output-dir)
              (plist-get request :setupfile)
              (plist-get request :notes-dir)))
            ('publish
             (unless (eq (plist-get request :authorization) 'explicit)
               (error "Publish requires :authorization `explicit'"))
             (append
              (list :scope (if (plist-get request :files) 'files 'all))
              (org-blog-exporter-publish
               (plist-get request :files)
               (plist-get request :title)
               (plist-get request :notes-dir)
               (plist-get request :repository-dir)
               (plist-get request :setupfile))))
            (_ (error "Unknown blog operation: %S" operation)))))
    (cond
     ((plist-get request :full)
      (list :status (if (zerop (or (plist-get result :error-count) 0))
                        'ok
                      'partial)
            :operation operation :result result))
     ((eq operation 'preflight)
      (list :status (if (plist-get result :errors) 'blocked 'ok)
            :operation operation :result result))
     (t
      (org-blog-exporter--compact-result
       operation result (plist-get request :limit))))))

(provide 'org-blog-exporter)

;;; org-blog-exporter.el ends here
