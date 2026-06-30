;;; emacs-code-navigator.el --- Emacs helpers for Codex code reading -*- lexical-binding: t; -*-

;;; Code:

(require 'project)
(require 'xref)
(require 'imenu)
(require 'cl-lib)
(require 'subr-x)
(require 'thingatpt)

(defun emacs-code-navigator--project (directory)
  "Return the project for DIRECTORY, or nil."
  (project-current nil (file-name-as-directory (expand-file-name directory))))

(defun emacs-code-navigator-project-root (directory)
  "Return the project root for DIRECTORY."
  (let ((project (emacs-code-navigator--project directory)))
    (if project
        (expand-file-name (project-root project))
      (file-name-as-directory (expand-file-name directory)))))

(defun emacs-code-navigator-project-files (directory &optional limit)
  "Return project files for DIRECTORY, capped at LIMIT."
  (let* ((project (emacs-code-navigator--project directory))
         (root (emacs-code-navigator-project-root directory))
         (max-count (or limit 500))
         (files (if project
                    (project-files project)
                  (directory-files-recursively root ".*" nil)))
         (relative-files (mapcar (lambda (file) (file-relative-name file root)) files)))
    (cl-subseq relative-files 0 (min max-count (length relative-files)))))

(defun emacs-code-navigator--project-file-list (directory)
  "Return absolute project file names for DIRECTORY."
  (let* ((project (emacs-code-navigator--project directory))
         (root (emacs-code-navigator-project-root directory)))
    (if project
        (project-files project)
      (directory-files-recursively root ".*" nil))))

(defun emacs-code-navigator-read-region (file start-line &optional end-line)
  "Return FILE lines from START-LINE to END-LINE with line numbers."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (save-restriction
        (widen)
        (let* ((start (max 1 start-line))
               (end (or end-line start))
               (result nil))
          (goto-char (point-min))
          (forward-line (1- start))
          (while (and (<= start end) (not (eobp)))
            (push (format "%d:%s"
                          start
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position)))
                  result)
            (setq start (1+ start))
            (forward-line 1))
          (string-join (nreverse result) "\n"))))))

(defun emacs-code-navigator--flatten-imenu (items &optional prefix)
  "Flatten IMENU ITEMS with optional PREFIX."
  (let (result)
    (dolist (item items)
      (cond
       ((imenu--subalist-p item)
        (setq result
              (append result
                      (emacs-code-navigator--flatten-imenu
                       (cdr item)
                       (if prefix
                           (format "%s/%s" prefix (car item))
                         (car item))))))
       ((consp item)
        (push (list (if prefix
                        (format "%s/%s" prefix (car item))
                      (car item))
                    (if (markerp (cdr item))
                        (line-number-at-pos (marker-position (cdr item)))
                      (line-number-at-pos (cdr item))))
              result))))
    (nreverse result)))

(defun emacs-code-navigator-imenu (file)
  "Return flattened imenu entries for FILE."
  (with-current-buffer (find-file-noselect file)
    (imenu--make-index-alist t)
    (emacs-code-navigator--flatten-imenu imenu--index-alist)))

(defun emacs-code-navigator--xref-location-data (xref)
  "Return a compact location list for XREF."
  (let* ((location (xref-item-location xref))
         (marker (condition-case nil
                     (xref-location-marker location)
                   (error nil)))
         (file (or (xref-location-group location)
                   (and marker (buffer-file-name (marker-buffer marker)))))
         (line (and marker
                    (with-current-buffer (marker-buffer marker)
                      (line-number-at-pos marker))))
         (summary (substring-no-properties (xref-item-summary xref))))
    (list file line summary)))

(defun emacs-code-navigator-search (directory regexp &optional limit)
  "Search DIRECTORY project files for REGEXP using `xref-matches-in-files'.

Return at most LIMIT matches as (file line summary).  Emacs chooses the
actual search backend through `xref-search-program'."
  (let* ((files (cl-remove-if-not #'file-regular-p
                                  (emacs-code-navigator--project-file-list directory)))
         (matches (xref-matches-in-files regexp files))
         (max-count (or limit 100)))
    (mapcar #'emacs-code-navigator--xref-location-data
            (cl-subseq matches 0 (min max-count (length matches))))))

(defun emacs-code-navigator--xref-at-identifier (file identifier fn)
  "Visit FILE, search IDENTIFIER, and call xref function FN."
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-min))
    (unless (search-forward identifier nil t)
      (error "Identifier not found in file: %s" identifier))
    (goto-char (match-beginning 0))
    (let ((backend (xref-find-backend)))
      (unless backend
        (error "No xref backend available for %s" file))
      (mapcar #'emacs-code-navigator--xref-location-data
              (funcall fn backend identifier)))))

(defun emacs-code-navigator-xref-definitions (file identifier)
  "Return xref definitions for IDENTIFIER from FILE context."
  (emacs-code-navigator--xref-at-identifier file identifier #'xref-backend-definitions))

(defun emacs-code-navigator-xref-references (file identifier)
  "Return xref references for IDENTIFIER from FILE context."
  (emacs-code-navigator--xref-at-identifier file identifier #'xref-backend-references))

(defun emacs-code-navigator-eglot-managed-p (file)
  "Return non-nil if FILE is managed by Eglot."
  (with-current-buffer (find-file-noselect file)
    (and (fboundp 'eglot-managed-p)
         (eglot-managed-p))))

(defun emacs-code-navigator-symbol-at-line (file line)
  "Return context data for the symbol at LINE in FILE.

The result is (symbol bounds major-mode eglot-managed defun-line)."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (back-to-indentation)
      (unless (thing-at-point 'symbol t)
        (when (re-search-forward "\\(\\sw\\|\\s_\\)+" (line-end-position) t)
          (goto-char (match-beginning 0))))
      (let* ((line-end (line-end-position))
             (line-symbols nil)
             (scan-start (line-beginning-position)))
        (save-excursion
          (goto-char scan-start)
          (while (re-search-forward "\\(\\sw\\|\\s_\\)+" line-end t)
            (push (list (match-string-no-properties 0)
                        (match-beginning 0)
                        (match-end 0))
                  line-symbols)))
        (setq line-symbols (nreverse line-symbols))
        (when (and (member (caar line-symbols)
                           '("defun" "cl-defun" "defmacro" "defvar" "defconst" "defcustom"))
                   (cadr line-symbols))
          (goto-char (cadr (cadr line-symbols))))
      (let* ((symbol (thing-at-point 'symbol t))
             (bounds (bounds-of-thing-at-point 'symbol))
             (eglot-managed (and (fboundp 'eglot-managed-p)
                                 (eglot-managed-p)))
             (defun-line (save-excursion
                           (condition-case nil
                               (progn
                                 (beginning-of-defun)
                                 (line-number-at-pos))
                             (error nil)))))
        (list symbol
              (and bounds
                   (list (line-number-at-pos (car bounds))
                         (1+ (- (car bounds) (line-beginning-position)))
                         (line-number-at-pos (cdr bounds))
                         (1+ (- (cdr bounds) (line-beginning-position)))))
              major-mode
              eglot-managed
              defun-line))))))

(defun emacs-code-navigator-defun-at-line (file line)
  "Return the top-level form around LINE in FILE with line numbers."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (let ((end nil)
            (start-line nil)
            (result nil))
        (end-of-defun)
        (setq end (point))
        (beginning-of-defun)
        (setq start-line (line-number-at-pos))
        (while (< (point) end)
          (push (format "%d:%s"
                        (line-number-at-pos)
                        (buffer-substring-no-properties
                         (line-beginning-position)
                         (line-end-position)))
                result)
          (forward-line 1))
        (list start-line (line-number-at-pos end) (string-join (nreverse result) "\n"))))))

(defun emacs-code-navigator-flymake-diagnostics (file)
  "Return Flymake diagnostics for FILE as (beg-line end-line type text)."
  (with-current-buffer (find-file-noselect file)
    (when (fboundp 'flymake-mode)
      (flymake-mode 1))
    (when (fboundp 'flymake-start)
      (ignore-errors (flymake-start t)))
    (if (not (fboundp 'flymake-diagnostics))
        nil
      (mapcar
       (lambda (diag)
         (list (line-number-at-pos (flymake-diagnostic-beg diag))
               (line-number-at-pos (flymake-diagnostic-end diag))
               (flymake-diagnostic-type diag)
               (flymake-diagnostic-text diag)))
       (flymake-diagnostics)))))

(defun emacs-code-navigator-project-diagnostics (directory &optional limit)
  "Return Flymake diagnostics for project files under DIRECTORY.

The result entries are (file beg-line end-line type text).  LIMIT defaults
to 200.  Diagnostics are whatever Flymake/Eglot currently knows after
visiting the files."
  (let ((max-count (or limit 200))
        (results nil))
    (catch 'done
      (dolist (file (emacs-code-navigator--project-file-list directory))
        (when (file-regular-p file)
          (dolist (diag (emacs-code-navigator-flymake-diagnostics file))
            (push (cons file diag) results)
            (when (>= (length results) max-count)
              (throw 'done nil))))))
    (nreverse results)))

(defun emacs-code-navigator-eldoc-at-line (file line)
  "Return Eldoc documentation strings at LINE in FILE.

This calls buffer-local `eldoc-documentation-functions' and collects
plain strings delivered synchronously through their callbacks."
  (with-current-buffer (find-file-noselect file)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- line))
      (back-to-indentation)
      (let ((docs nil))
        (dolist (fn eldoc-documentation-functions)
          (condition-case nil
              (funcall fn
                       (lambda (doc &rest _)
                         (when (stringp doc)
                           (push (string-trim (substring-no-properties doc)) docs))))
            (wrong-number-of-arguments
             (let ((doc (ignore-errors (funcall fn))))
               (when (stringp doc)
                 (push (string-trim (substring-no-properties doc)) docs))))
            (error nil)))
        (delete-dups (nreverse (cl-remove-if #'string-empty-p docs)))))))

(provide 'emacs-code-navigator)

;;; emacs-code-navigator.el ends here
