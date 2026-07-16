;;; org-blog-exporter.el --- Export Org notes to the user's HTML blog -*- lexical-binding: t; -*-

;;; Code:

(require 'org)
(require 'ox-html)
(require 'cl-lib)
(require 'subr-x)

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

(defun org-blog-exporter--setupfile-keyword (keyword &optional setupfile)
  "Return KEYWORD value from SETUPFILE, or nil when absent."
  (let ((file (org-blog-exporter--setupfile setupfile))
        (case-fold-search t))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (when (re-search-forward
               (format "^#\\+%s:[ \t]*\\(.+?\\)[ \t]*$" (regexp-quote keyword))
               nil t)
          (string-trim (match-string-no-properties 1)))))))

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
        (string-prefix-p "#" name)
        (string-suffix-p "~" name))))

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

(defun org-blog-exporter--local-link-target-p (target)
  "Return non-nil when TARGET looks like a local file link."
  (and (stringp target)
       (not (string-empty-p target))
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

(defun org-blog-exporter--target-file (org-file &optional output-dir notes-dir setupfile)
  "Return the HTML target path for ORG-FILE."
  (let* ((relative (org-blog-exporter--relative-to-notes org-file notes-dir))
         (html-relative (concat (file-name-sans-extension relative) ".html")))
    (expand-file-name html-relative
                      (org-blog-exporter--output-directory output-dir setupfile))))

(defun org-blog-exporter--has-setupfile-p ()
  "Return non-nil when current buffer already has a setupfile directive."
  (save-excursion
    (goto-char (point-min))
    (re-search-forward "^#\\+SETUPFILE:" nil t)))

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
            label separator (org-blog-exporter--html-escape value))))
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

(defun org-blog-exporter-export-file (org-file &optional output-dir setupfile)
  "Export ORG-FILE to HTML and return the exported path."
  (let* ((source (expand-file-name org-file))
         (setup (org-blog-exporter--setupfile setupfile))
         (target (org-blog-exporter--target-file source output-dir nil setup))
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
      (org-blog-exporter--insert-assessment-summaries)
      (org-blog-exporter--insert-setupfile-if-missing setup)
      (let ((exported (org-export-to-file 'html target nil nil nil nil nil)))
        (unless (and exported (file-exists-p exported))
          (error "Export did not create HTML for %s" source))
        exported))))

(defun org-blog-exporter-export-files (org-files &optional output-dir setupfile)
  "Export ORG-FILES and return exported HTML paths."
  (mapcar (lambda (file)
            (org-blog-exporter-export-file file output-dir setupfile))
          org-files))

(defun org-blog-exporter-export-all (&optional notes-dir output-dir setupfile)
  "Export all candidate Org files under NOTES-DIR and return a plist summary."
  (let* ((root (org-blog-exporter--notes-directory notes-dir))
         (files (org-blog-exporter-list-candidates root))
         (exported nil)
         (errors nil))
    (dolist (file files)
      (condition-case err
          (push (org-blog-exporter-export-file file output-dir setupfile) exported)
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

(defun org-blog-exporter--file-keyword (file keyword)
  "Return FILE's first Org KEYWORD value, ignoring case."
  (let ((case-fold-search t))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward
             (format "^#\\+%s:[ \\t]*\\(.+?\\)[ \\t]*$"
                     (regexp-quote keyword))
             nil t)
        (string-trim (match-string-no-properties 1))))))

(defun org-blog-exporter--post-date (org-file)
  "Return ORG-FILE's publication date as YYYY-MM-DD."
  (let ((declared (org-blog-exporter--file-keyword org-file "DATE"))
        (base (file-name-base org-file)))
    (cond
     ((and declared
           (string-match
            "[<[]\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" declared))
      (match-string 1 declared))
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

(defun org-blog-exporter--html-unescape (text)
  "Decode the small HTML entity set used in generated index TEXT."
  (let ((value text))
    (dolist (pair '(("&quot;" . "\"") ("&gt;" . ">") ("&lt;" . "<")
                    ("&amp;" . "&")))
      (setq value (string-replace (car pair) (cdr pair) value)))
    value))

(defun org-blog-exporter--html-escape (text)
  "Escape TEXT for generated HTML content and attributes."
  (let ((value text))
    (dolist (pair '(("&" . "&amp;") ("<" . "&lt;") (">" . "&gt;")
                    ("\"" . "&quot;")))
      (setq value (string-replace (car pair) (cdr pair) value)))
    value))

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
                      :href (org-blog-exporter--html-unescape
                             (match-string-no-properties 2))
                      :title (org-blog-exporter--html-unescape
                              (match-string-no-properties 3)))
                entries))))
    (nreverse entries)))

(defun org-blog-exporter--post-entry (org-file output-dir setupfile)
  "Return the homepage entry for ORG-FILE."
  (let* ((target
          (org-blog-exporter--target-file org-file output-dir nil setupfile))
         (relative
          (file-relative-name target
                              (org-blog-exporter--output-directory
                               output-dir setupfile))))
    (list :date (org-blog-exporter--post-date org-file)
          :href (concat "./" relative)
          :title (or (org-blog-exporter--file-keyword org-file "TITLE")
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
    (org-files &optional output-dir setupfile)
  "Update index.html with ORG-FILES and return its absolute path."
  (let* ((output (org-blog-exporter--output-directory output-dir setupfile))
         (index-file (expand-file-name "index.html" output))
         (entries
          (org-blog-exporter--merge-index-entries
           (org-blog-exporter--index-entries index-file)
           (mapcar (lambda (file)
                     (org-blog-exporter--post-entry file output setupfile))
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
                   (org-blog-exporter--html-escape (plist-get entry :href))
                   (org-blog-exporter--html-escape (plist-get entry :title))))))
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

(defun org-blog-exporter--html-relative-path-p (relative)
  "Return non-nil when RELATIVE names an HTML file."
  (string-match-p "\\.html\\'" relative))

(defun org-blog-exporter--finish-publish (repository exported subject)
  "Commit EXPORTED files in REPOSITORY with SUBJECT, then push."
  (let* ((root (plist-get repository :git-root))
         (relative-paths
          (mapcar (lambda (path)
                    (skill-git-relative-path
                     root path #'org-blog-exporter--html-relative-path-p
                     "exported HTML files"))
                  exported))
         (status (skill-git-status root relative-paths)))
    (if (string-empty-p status)
        (append repository
                (list :changed nil :exported exported :commit nil :push nil))
      (let ((commit
             (skill-git-commit-paths
              root subject exported #'org-blog-exporter--html-relative-path-p
              "exported HTML files")))
        (skill-git-assert-clean root)
        (append repository
                (list :changed t
                      :exported exported
                      :commit commit
                      :push (skill-git-push root)))))))

;;;###autoload
(defun org-blog-exporter-publish-files
    (org-files &optional title repository-dir setupfile)
  "Export ORG-FILES, commit changed HTML, and push the blog repository.

TITLE is used in the commit subject and defaults to `Publish Org HTML'.
Read repository defaults from SETUPFILE and clone when absent."
  (unless (and (listp org-files) org-files)
    (error "ORG-FILES must be a non-empty list"))
  (let* ((repository
          (org-blog-exporter--prepare-publish-repository
           repository-dir setupfile))
         (root (plist-get repository :git-root))
         (exported (org-blog-exporter-export-files org-files root setupfile))
         (index-file
          (org-blog-exporter-update-index org-files root setupfile))
         (subject (format "chore(blog): %s" (or title "Publish Org HTML"))))
    (append (org-blog-exporter--finish-publish
             repository (append exported (list index-file)) subject)
            (list :index index-file))))

;;;###autoload
(defun org-blog-exporter-publish-all
    (&optional title notes-dir repository-dir setupfile)
  "Export all public notes, commit changed HTML, and push the blog repository.

TITLE is used in the commit subject and defaults to `Publish Org HTML'.
Read repository defaults from SETUPFILE and clone when absent."
  (let* ((repository
          (org-blog-exporter--prepare-publish-repository
           repository-dir setupfile))
         (root (plist-get repository :git-root))
         (summary (org-blog-exporter-export-all notes-dir root setupfile)))
    (unless (zerop (plist-get summary :error-count))
      (error "Blog export failed: %S" (plist-get summary :errors)))
    (let ((index-file
           (org-blog-exporter-update-index
            (plist-get summary :candidates) root setupfile)))
      (append
       summary
       (org-blog-exporter--finish-publish
        repository (append (plist-get summary :exported) (list index-file))
        (format "chore(blog): %s" (or title "Publish Org HTML")))
       (list :index index-file)))))

(provide 'org-blog-exporter)

;;; org-blog-exporter.el ends here
