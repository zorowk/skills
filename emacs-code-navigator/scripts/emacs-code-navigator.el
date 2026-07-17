;;; emacs-code-navigator.el --- Emacs helpers for compact code reading -*- lexical-binding: t; -*-

;;; Code:

(require 'project)
(require 'xref)
(require 'imenu)
(require 'apropos)
(require 'find-func)
(require 'help-fns)
(require 'seq)
(require 'subr-x)
(require 'thingatpt)
(require 'flymake nil t)

(defconst emacs-code-navigator-ignored-directories
  '(".git" "node_modules" "target" "build" "dist" ".cache" ".venv" "vendor" "__pycache__")
  "Directory names skipped by fallback recursive file discovery.")

(defconst emacs-code-navigator-symbol-kinds
  '(function command macro variable user-option)
  "Symbol kinds accepted by Emacs introspection entry points.")

(defun emacs-code-navigator--symbol (value)
  "Return VALUE as an interned symbol or signal a validation error."
  (let ((symbol
         (cond
          ((symbolp value) value)
          ((and (stringp value) (not (string-empty-p value)))
           (intern-soft value))
          (t nil))))
    (unless symbol
      (error "Unknown or invalid Emacs symbol: %S" value))
    symbol))

(defun emacs-code-navigator--symbol-kind-p (symbol kind)
  "Return non-nil when SYMBOL has KIND."
  (pcase kind
    ('function (fboundp symbol))
    ('command (commandp symbol))
    ('macro (and (fboundp symbol) (macrop symbol)))
    ('variable (boundp symbol))
    ('user-option (custom-variable-p symbol))
    (_ (error "Unknown symbol kind: %S" kind))))

(defun emacs-code-navigator--symbol-kinds (symbol)
  "Return the Emacs capability kinds provided by SYMBOL."
  (seq-filter
   (lambda (kind) (emacs-code-navigator--symbol-kind-p symbol kind))
   emacs-code-navigator-symbol-kinds))

(defun emacs-code-navigator--documentation (symbol kind)
  "Return plain documentation for SYMBOL of KIND, or nil."
  (let ((doc
         (condition-case nil
             (if (memq kind '(function command macro))
                 (documentation symbol t)
               (documentation-property symbol 'variable-documentation t))
           (error nil))))
    (and (stringp doc) (substring-no-properties doc))))

(defun emacs-code-navigator--documentation-summary (symbol)
  "Return the first non-empty documentation line for SYMBOL."
  (let* ((kind (if (fboundp symbol) 'function 'variable))
         (doc (emacs-code-navigator--documentation symbol kind)))
    (when doc
      (seq-find (lambda (line) (not (string-empty-p line)))
                (mapcar #'string-trim (split-string doc "\n"))))))

(defun emacs-code-navigator--source-location (symbol kind)
  "Return the definition location for SYMBOL of KIND as a plist.

KIND may be `function' or `variable'.  This uses the same source lookup
machinery as `find-function' and `find-variable'."
  (condition-case error-data
      (let* ((location
              (if (eq kind 'variable)
                  (find-variable-noselect symbol)
                (find-function-noselect symbol)))
             (buffer (car location))
             (position (cdr location)))
        (with-current-buffer buffer
          (list :file (buffer-file-name buffer)
                :buffer (buffer-name buffer)
                :line (and position (line-number-at-pos position))
                :library (symbol-file symbol
                                      (and (eq kind 'variable) 'defvar)))))
    (error
     (list :file (symbol-file symbol
                              (and (eq kind 'variable) 'defvar))
           :error (error-message-string error-data)))))

(defun emacs-code-navigator-function-info (function)
  "Return structured Help and source information for FUNCTION.

FUNCTION may be a symbol or symbol-name string.  Documentation comes from
`documentation', arguments from `help-function-arglist', and source location
from `find-function-noselect'."
  (let ((symbol (emacs-code-navigator--symbol function)))
    (unless (fboundp symbol)
      (error "Not an available Emacs function: %S" symbol))
    (list :symbol (symbol-name symbol)
          :kinds (emacs-code-navigator--symbol-kinds symbol)
          :arguments (help-function-arglist symbol t)
          :interactive (and (commandp symbol) t)
          :autoload (autoloadp (symbol-function symbol))
          :documentation
          (emacs-code-navigator--documentation symbol 'function)
          :source
          (emacs-code-navigator--source-location symbol 'function))))

(defun emacs-code-navigator-variable-info (variable)
  "Return structured Help and source information for VARIABLE.

VARIABLE may be a symbol or symbol-name string.  The value is intentionally
not returned: callers can discover capabilities without exposing buffer-local,
large, or sensitive runtime state."
  (let ((symbol (emacs-code-navigator--symbol variable)))
    (unless (boundp symbol)
      (error "Not an available Emacs variable: %S" symbol))
    (list :symbol (symbol-name symbol)
          :kinds (emacs-code-navigator--symbol-kinds symbol)
          :buffer-local (local-variable-if-set-p symbol)
          :documentation
          (emacs-code-navigator--documentation symbol 'variable)
          :source
          (emacs-code-navigator--source-location symbol 'variable))))

(defun emacs-code-navigator-symbol-info (name)
  "Return every available function and variable facet of Emacs symbol NAME."
  (let* ((symbol (emacs-code-navigator--symbol name))
         (function-info
          (and (fboundp symbol)
               (emacs-code-navigator-function-info symbol)))
         (variable-info
          (and (boundp symbol)
               (emacs-code-navigator-variable-info symbol))))
    (unless (or function-info variable-info)
      (error "Emacs symbol has no function or variable definition: %S" symbol))
    (list :symbol (symbol-name symbol)
          :function function-info
          :variable variable-info)))

(defun emacs-code-navigator-apropos (pattern &optional kind limit documentation)
  "Discover Emacs capabilities matching PATTERN.

KIND is one of `function', `command', `macro', `variable', or `user-option'
and defaults to `function'.  LIMIT defaults to 50.  When DOCUMENTATION is
non-nil, search loaded documentation as well as symbol names.  Return compact
plists; pass a result to `emacs-code-navigator-symbol-info' for full Help and
source details."
  (unless (and (stringp pattern) (not (string-empty-p pattern)))
    (error "PATTERN must be a non-empty string"))
  (let* ((target-kind (or kind 'function))
         (max-count (or limit 50))
         (_ (unless (memq target-kind emacs-code-navigator-symbol-kinds)
              (error "Unknown symbol kind: %S" target-kind)))
         (predicate
          (lambda (symbol)
            (emacs-code-navigator--symbol-kind-p symbol target-kind)))
         (symbols
          (if documentation
              (delete-dups
               (mapcar #'car (apropos-documentation pattern t)))
            (apropos-internal pattern predicate))))
    (mapcar
     (lambda (symbol)
       (list :symbol (symbol-name symbol)
             :kinds (emacs-code-navigator--symbol-kinds symbol)
             :summary (emacs-code-navigator--documentation-summary symbol)
             :library (or (and (fboundp symbol) (symbol-file symbol))
                          (and (boundp symbol)
                               (symbol-file symbol 'defvar)))))
     (seq-take (seq-filter predicate symbols) max-count))))

(defun emacs-code-navigator-discover
    (pattern &optional kind limit documentation)
  "Discover and, when unambiguous, expand an Emacs capability.

PATTERN, KIND, LIMIT, and DOCUMENTATION have the same meaning as in
`emacs-code-navigator-apropos'.  Return a plist containing compact :matches.
When PATTERN names an available match exactly, or the search has exactly one
result, also return that symbol's full Help and source data as :selected.  This
is the preferred entry point when the caller does not yet know an exact Emacs
symbol name."
  (let* ((matches (emacs-code-navigator-apropos
                   pattern kind limit documentation))
         (exact (seq-find
                 (lambda (match)
                   (string= pattern (plist-get match :symbol)))
                 matches))
         (choice (or exact (and (= (length matches) 1) (car matches)))))
    (list :pattern pattern
          :kind (or kind 'function)
          :matches matches
          :selected
          (and choice
               (emacs-code-navigator-symbol-info
                (plist-get choice :symbol))))))

(defun emacs-code-navigator-library-info (library)
  "Return the source path for Emacs Lisp LIBRARY.

LIBRARY is a name such as \"help-fns\", with or without an extension.  This
uses `find-library-name', the noninteractive engine behind `find-library'."
  (unless (and (stringp library) (not (string-empty-p library)))
    (error "LIBRARY must be a non-empty string"))
  (let ((file (find-library-name library)))
    (unless file
      (error "Emacs library is not available: %S" library))
    (list :library library :file file)))

(defun emacs-code-navigator--ignored-directory-p (directory)
  "Return non-nil when DIRECTORY should be skipped during fallback traversal."
  (member (file-name-nondirectory (directory-file-name directory))
          emacs-code-navigator-ignored-directories))

(defun emacs-code-navigator--directory-files (directory)
  "Return regular files under DIRECTORY, skipping noisy generated directories."
  (directory-files-recursively
   directory "." nil
   (lambda (subdirectory)
     (not (emacs-code-navigator--ignored-directory-p subdirectory)))))

(defun emacs-code-navigator--project (directory)
  "Return the project for DIRECTORY, or nil."
  (condition-case nil
      (project-current nil
                       (file-name-as-directory (expand-file-name directory)))
    (error nil)))

(defun emacs-code-navigator-project-root (directory)
  "Return the project root for DIRECTORY."
  (let ((project (emacs-code-navigator--project directory)))
    (if project
        (expand-file-name (project-root project))
      (file-name-as-directory (expand-file-name directory)))))

(defun emacs-code-navigator-project-files (directory &optional limit)
  "Return project files for DIRECTORY, capped at LIMIT."
  (let* ((project (emacs-code-navigator--project directory))
         (project-files
          (and project
               (condition-case nil
                   (project-files project)
                 (error :unavailable))))
         (root (if (eq project-files :unavailable)
                   (file-name-as-directory (expand-file-name directory))
                 (emacs-code-navigator-project-root directory)))
         (max-count (or limit 500))
         (files (if (or (null project) (eq project-files :unavailable))
                    (emacs-code-navigator--directory-files root)
                  project-files))
         (relative-files (mapcar (lambda (file) (file-relative-name file root)) files)))
    (seq-take relative-files max-count)))

(defun emacs-code-navigator--project-file-list (directory)
  "Return absolute project file names for DIRECTORY."
  (let* ((project (emacs-code-navigator--project directory))
         (project-files
          (and project
               (condition-case nil
                   (project-files project)
                 (error :unavailable)))))
    (if (or (null project) (eq project-files :unavailable))
        (emacs-code-navigator--directory-files directory)
      project-files)))

(defun emacs-code-navigator-read-region (file start-line &optional end-line)
  "Return FILE lines from START-LINE to END-LINE with line numbers."
  (unless (and (integerp start-line) (> start-line 0))
    (error "START-LINE must be a positive integer: %S" start-line))
  (when (and end-line
             (not (and (integerp end-line) (>= end-line start-line))))
    (error "END-LINE must be an integer no smaller than START-LINE: %S"
           end-line))
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
         (line (or (condition-case nil
                       (xref-location-line location)
                     (error nil))
                   (and marker
                        (with-current-buffer (marker-buffer marker)
                          (line-number-at-pos marker)))))
         (summary (substring-no-properties (xref-item-summary xref))))
    (list file line summary)))

(defun emacs-code-navigator-search (directory regexp &optional limit)
  "Search DIRECTORY project files for REGEXP using `xref-matches-in-files'.

Return at most LIMIT matches as (file line summary).  Emacs chooses the
actual search backend through `xref-search-program'."
  (let* ((files (seq-filter #'file-regular-p
                            (emacs-code-navigator--project-file-list directory)))
         (matches (xref-matches-in-files regexp files))
         (max-count (or limit 100)))
    (mapcar #'emacs-code-navigator--xref-location-data
            (seq-take matches max-count))))

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

(defun emacs-code-navigator--goto-symbol-at-line (line &optional identifier)
  "Move point to IDENTIFIER on LINE, or to the best symbol on LINE.

When LINE starts with a defining form such as `defun' or `defconst', choose
the defined name instead of the defining keyword.  Return the symbol string at
point.  Signal an error when no matching symbol can be found."
  (goto-char (point-min))
  (forward-line (1- (max 1 line)))
  (let ((line-end (line-end-position)))
    (if identifier
        (progn
          (unless (search-forward identifier line-end t)
            (error "Identifier not found on line %s: %s" line identifier))
          (goto-char (match-beginning 0)))
      (let ((line-symbols nil)
            (scan-start (line-beginning-position)))
        (save-excursion
          (goto-char scan-start)
          (while (re-search-forward "\\(\\sw\\|\\s_\\)+" line-end t)
            (push (list (match-string-no-properties 0)
                        (match-beginning 0))
                  line-symbols)))
        (setq line-symbols (nreverse line-symbols))
        (cond
         ((and (member (caar line-symbols)
                       '("defun" "cl-defun" "defmacro" "defvar" "defconst" "defcustom"))
               (cadr line-symbols))
          (goto-char (cadr (cadr line-symbols))))
         ((car line-symbols)
          (goto-char (cadr (car line-symbols))))
         (t
          (error "No symbol found on line %s" line)))))
    (or (thing-at-point 'symbol t)
        (error "No symbol found on line %s" line))))

(defun emacs-code-navigator--xref-at-line (file line identifier fn)
  "Visit FILE, move to LINE/IDENTIFIER, and call xref function FN."
  (with-current-buffer (find-file-noselect file)
    (let* ((symbol (emacs-code-navigator--goto-symbol-at-line line identifier))
           (backend (xref-find-backend)))
      (unless backend
        (error "No xref backend available for %s" file))
      (mapcar #'emacs-code-navigator--xref-location-data
              (funcall fn backend symbol)))))

(defun emacs-code-navigator-xref-definitions-at-line (file line &optional identifier)
  "Return xref definitions for symbol at FILE LINE.

When IDENTIFIER is non-nil, use that identifier on LINE.  Otherwise use the
first symbol found at or after indentation on LINE."
  (emacs-code-navigator--xref-at-line
   file line identifier #'xref-backend-definitions))

(defun emacs-code-navigator-xref-references-at-line (file line &optional identifier)
  "Return xref references for symbol at FILE LINE.

When IDENTIFIER is non-nil, use that identifier on LINE.  Otherwise use the
first symbol found at or after indentation on LINE."
  (emacs-code-navigator--xref-at-line
   file line identifier #'xref-backend-references))

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

(defun emacs-code-navigator-flymake-diagnostics (file &optional start-line end-line)
  "Return Flymake diagnostics for FILE as (beg-line end-line type text).

When START-LINE and END-LINE are non-nil, ask Flymake only for diagnostics
intersecting that buffer range."
  (with-current-buffer (find-file-noselect file)
    (when (fboundp 'flymake-mode)
      (flymake-mode 1))
    (when (fboundp 'flymake-start)
      (ignore-errors (flymake-start t)))
    (if (not (fboundp 'flymake-diagnostics))
        nil
      (let* ((beg-pos (and start-line
                           (save-excursion
                             (goto-char (point-min))
                             (forward-line (1- start-line))
                             (line-beginning-position))))
             (end-pos (and end-line
                           (save-excursion
                             (goto-char (point-min))
                             (forward-line (1- end-line))
                             (line-end-position))))
             (diagnostics (if beg-pos
                              (flymake-diagnostics beg-pos end-pos)
                            (flymake-diagnostics))))
        (mapcar
         (lambda (diag)
           (list (line-number-at-pos (flymake-diagnostic-beg diag))
                 (line-number-at-pos (flymake-diagnostic-end diag))
                 (flymake-diagnostic-type diag)
                 (flymake-diagnostic-text diag)))
         diagnostics)))))

(defun emacs-code-navigator-diagnostics-at-line (file line &optional radius)
  "Return Flymake diagnostics near LINE in FILE.

RADIUS defaults to 0, meaning only diagnostics whose range contains LINE are
returned.  The result entries are (beg-line end-line type text)."
  (let ((distance (or radius 0))
        (start (max 1 (- line (or radius 0))))
        (end (+ line (or radius 0))))
    (seq-filter
     (lambda (diag)
       (let ((beg (nth 0 diag))
             (diag-end (nth 1 diag)))
         (and (<= beg end)
              (>= diag-end start)
              (<= (abs (- line beg)) (max distance (- diag-end beg))))))
     (emacs-code-navigator-flymake-diagnostics file start end))))

(defun emacs-code-navigator-project-diagnostics (directory &optional limit file-limit)
  "Return Flymake diagnostics for project files under DIRECTORY.

The result entries are (file beg-line end-line type text).  LIMIT defaults
to 200 diagnostics.  FILE-LIMIT defaults to 50 visited files to avoid opening
very large projects by accident.  Diagnostics are whatever Flymake/Eglot
currently knows after visiting the files."
  (let ((max-count (or limit 200))
        (max-files (or file-limit 50))
        (visited 0)
        (results nil))
    (catch 'done
      (dolist (file (emacs-code-navigator--project-file-list directory))
        (when (and (file-regular-p file)
                   (< visited max-files))
          (setq visited (1+ visited))
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
        (delete-dups (nreverse (seq-remove #'string-empty-p docs)))))))

(defun emacs-code-navigator-context-at-line (file line &optional diagnostic-radius)
  "Return compact Emacs context for FILE at LINE.

The result is a plist containing symbol data, surrounding defun, Eldoc strings,
and Flymake diagnostics near LINE.  DIAGNOSTIC-RADIUS defaults to 0."
  (list :symbol (emacs-code-navigator-symbol-at-line file line)
        :defun (emacs-code-navigator-defun-at-line file line)
        :eldoc (emacs-code-navigator-eldoc-at-line file line)
        :diagnostics (emacs-code-navigator-diagnostics-at-line
                      file line diagnostic-radius)))

(provide 'emacs-code-navigator)

;;; emacs-code-navigator.el ends here
