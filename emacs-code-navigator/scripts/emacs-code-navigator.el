;;; emacs-code-navigator.el --- Emacs helpers for compact code reading -*- lexical-binding: t; -*-

;;; Code:

(require 'project)
(require 'xref)
(require 'imenu)
(require 'apropos)
(require 'find-func)
(require 'help-fns)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'thingatpt)
(require 'flymake nil t)

(unless (featurep 'skill-runtime)
  (load (expand-file-name "../../common/scripts/skill-runtime.el"
                          (file-name-directory
                           (or load-file-name buffer-file-name)))
        nil nil t))

(declare-function skill-runtime-describe "../../common/scripts/skill-runtime"
                  (schemas &optional target))
(declare-function skill-runtime-result "../../common/scripts/skill-runtime"
                  (operation data &optional count status page effects))
(declare-function skill-runtime-truncate "../../common/scripts/skill-runtime"
                  (text maximum label))

(defgroup emacs-code-navigator nil
  "Compact access to live Emacs code context."
  :group 'tools)

(defcustom emacs-code-navigator-documentation-maximum-characters 1200
  "Maximum documentation characters returned by compact symbol queries."
  :type 'positive-integer
  :group 'emacs-code-navigator)

(defconst emacs-code-navigator-ignored-directories
  '(".git" "node_modules" "target" "build" "dist" ".cache" ".venv" "vendor" "__pycache__")
  "Directory names skipped by fallback recursive file discovery.")

(defconst emacs-code-navigator-symbol-kinds
  '(function command macro variable user-option)
  "Symbol kinds accepted by Emacs introspection entry points.")

(defconst emacs-code-navigator--schemas
  '((capability :required (:pattern) :optional (:kind :limit :documentation :full))
    (symbol :required (:name) :optional (:full))
    (library :required (:name))
    (search :required (:directory :regexp) :optional (:limit :glob :literal))
    (files :required (:directory) :optional (:limit))
    (region :required (:file :start-line) :optional (:end-line))
    (imenu :required (:file))
    (workspace-symbol :required (:file :pattern) :optional (:limit))
    (xref :required (:file) :required-one-of (:identifier :line)
          :optional (:kind :identifier :line))
    (locate :required (:query) :required-one-of (:file :directory)
            :optional (:line :kind :limit :glob :regexp))
    (diagnostics :required-one-of (:file :directory)
                 :optional (:line :radius :limit :file-limit))
    (context :required (:file :line)
             :optional (:radius :defun :eldoc :diagnostics :diagnostic-radius))
    (describe :optional (:target)))
  "Compact request schemas for `emacs-code-navigator-query'.")

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

(defun emacs-code-navigator--compact-facet (info)
  "Return compact Help facet INFO."
  (when info
    (let* ((documentation (plist-get info :documentation))
           (bounded
            (and documentation
                 (skill-runtime-truncate
                  documentation
                  emacs-code-navigator-documentation-maximum-characters
                  'documentation)))
           (result
           (list :symbol (plist-get info :symbol)
                 :kinds (plist-get info :kinds))))
      (dolist (key '(:arguments :interactive :autoload :buffer-local))
        (when (plist-member info key)
          (setq result (append result (list key (plist-get info key))))))
      (append
       result
       (list :documentation (and bounded (plist-get bounded :text))
             :source (plist-get info :source))
       (and (plist-get bounded :truncated)
            (list :documentation-truncated t
                  :documentation-original-length
                  (plist-get bounded :original-length)))))))

(defun emacs-code-navigator-symbol-summary (name)
  "Return token-bounded Help and source information for symbol NAME."
  (let ((info (emacs-code-navigator-symbol-info name)))
    (list :symbol (plist-get info :symbol)
          :function
          (emacs-code-navigator--compact-facet (plist-get info :function))
          :variable
          (emacs-code-navigator--compact-facet (plist-get info :variable)))))

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
    (pattern &optional kind limit documentation compact)
  "Discover and, when unambiguous, expand an Emacs capability.

PATTERN, KIND, LIMIT, and DOCUMENTATION have the same meaning as in
`emacs-code-navigator-apropos'.  Return a plist containing compact :matches.
When PATTERN names an available match exactly, or the search has exactly one
result, also return complete Help and source data as :selected.  When COMPACT
is non-nil, return token-bounded Help instead."
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
               (funcall (if compact
                            #'emacs-code-navigator-symbol-summary
                          #'emacs-code-navigator-symbol-info)
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

(defun emacs-code-navigator--semantic-xref-backend ()
  "Return the current semantic xref backend, activating deferred hooks once.

`eglot-ensure' deliberately connects from `post-command-hook'.  Navigator
queries visit files noninteractively, so no editor command would otherwise run
that hook.  Run it once before choosing a semantic backend, matching what Emacs
would do after an interactive file visit."
  (unless (and (fboundp 'eglot-managed-p) (eglot-managed-p))
    (when (local-variable-p 'post-command-hook)
      (run-hooks 'post-command-hook)))
  (xref-find-backend))

(defun emacs-code-navigator--glob-list (glob)
  "Normalize GLOB to a list of ripgrep glob strings."
  (cond
   ((null glob) nil)
   ((stringp glob) (list glob))
   ((and (listp glob) (seq-every-p #'stringp glob)) glob)
   (t (error "GLOB must be a string or list of strings: %S" glob))))

(defun emacs-code-navigator--ripgrep-event (line root)
  "Convert one ripgrep JSON LINE under ROOT to compact location data."
  (condition-case nil
      (let* ((event (json-parse-string line :object-type 'plist
                                       :array-type 'list
                                       :null-object nil
                                       :false-object nil))
             (data (and (equal (plist-get event :type) "match")
                        (plist-get event :data)))
             (path-data (and data (plist-get data :path)))
             (lines-data (and data (plist-get data :lines)))
             (path (and path-data (plist-get path-data :text)))
             (summary (and lines-data (plist-get lines-data :text)))
             (line-number (and data (plist-get data :line_number))))
        (when (and path line-number summary)
          (list (expand-file-name path root)
                line-number
                (string-trim-right
                 (replace-regexp-in-string "[\n\r]+" " " summary)))))
    (error nil)))

(defun emacs-code-navigator--ripgrep-search
    (directory regexp limit glob literal)
  "Search DIRECTORY with ripgrep, stopping after LIMIT matches.

GLOB is a string or list of ripgrep globs.  When LITERAL is non-nil, treat
REGEXP as fixed text.  Return `(:available t :matches MATCHES)' even when there
are no matches.  Return nil when ripgrep is unavailable or DIRECTORY is remote."
  (let ((program (executable-find "rg"))
        (root (emacs-code-navigator-project-root directory)))
    (when (and program (not (file-remote-p root)))
      (let* ((max-count (or limit 100))
             (stderr (generate-new-buffer " *navigator-rg-error*"))
             (pending "")
             (matches nil)
             (stopped-early nil)
             (command
              (append
               (list program "--json" "--line-number" "--no-messages"
                     "--color=never")
               (and literal (list "--fixed-strings"))
               (apply #'append
                      (mapcar (lambda (item) (list "--glob" item))
                              (emacs-code-navigator--glob-list glob)))
               (apply #'append
                      (mapcar
                       (lambda (name)
                         (list "--glob" (format "!**/%s/**" name)))
                       emacs-code-navigator-ignored-directories))
               (list "--regexp" regexp ".")))
             process)
        (unwind-protect
            (let ((default-directory root))
              (setq process
                    (make-process
                     :name "emacs-code-navigator-ripgrep"
                     :command command
                     :connection-type 'pipe
                     :noquery t
                     :stderr stderr
                     :filter
                     (lambda (proc chunk)
                       (setq pending (concat pending chunk))
                       (let ((newline nil))
                         (while (and (< (length matches) max-count)
                                     (setq newline (string-search "\n" pending)))
                           (let* ((line (substring pending 0 newline))
                                  (match
                                   (emacs-code-navigator--ripgrep-event line root)))
                             (setq pending (substring pending (1+ newline)))
                             (when match (push match matches))))
                         (when (and (>= (length matches) max-count)
                                    (process-live-p proc))
                           (setq stopped-early t)
                           (delete-process proc))))))
              (while (process-live-p process)
                (accept-process-output process 0.05))
              (unless (or stopped-early
                          (memq (process-exit-status process) '(0 1)))
                (error "Ripgrep failed: %s"
                       (with-current-buffer stderr
                         (string-trim (buffer-string)))))
              (list :available t :matches (nreverse matches)))
          (when (and process (process-live-p process)) (delete-process process))
          (kill-buffer stderr))))))

(defun emacs-code-navigator-search
    (directory regexp &optional limit glob literal)
  "Search DIRECTORY project files for REGEXP, bounded by LIMIT.

Use ripgrep when available so the search process stops as soon as LIMIT
matches have arrived.  Fall back to `xref-matches-in-files' for remote files
or systems without ripgrep.  GLOB narrows ripgrep files; LITERAL requests a
fixed-string search.  Results are (file line summary)."
  (let* ((max-count (or limit 100))
         (ripgrep-result
          (emacs-code-navigator--ripgrep-search
           directory regexp max-count glob literal)))
    (if (plist-get ripgrep-result :available)
        (plist-get ripgrep-result :matches)
      (let ((files (seq-filter #'file-regular-p
                               (emacs-code-navigator--project-file-list directory))))
        (if (null files)
            nil
          (mapcar #'emacs-code-navigator--xref-location-data
                  (seq-take (xref-matches-in-files regexp files) max-count)))))))

(defun emacs-code-navigator-workspace-symbol (file pattern &optional limit)
  "Find symbols matching PATTERN from FILE's xref workspace backend.

For an Eglot-managed C or C++ buffer this uses LSP `workspace/symbol', which
clangd answers from its project index.  Return at most LIMIT compact locations."
  (unless (and (stringp pattern) (not (string-empty-p pattern)))
    (error "PATTERN must be a non-empty string"))
  (with-current-buffer (find-file-noselect file)
    (let ((backend (emacs-code-navigator--semantic-xref-backend)))
      (unless backend
        (error "No xref backend available for %s" file))
      (condition-case error-data
          (mapcar #'emacs-code-navigator--xref-location-data
                  (seq-take (xref-backend-apropos backend pattern)
                            (or limit 50)))
        (cl-no-applicable-method
         (error "Xref backend %S has no workspace-symbol support" backend))
        (error
         (error "Workspace-symbol query failed through %S: %s"
                backend (error-message-string error-data)))))))

(defun emacs-code-navigator--xref-at-identifier (file identifier fn)
  "Visit FILE, search IDENTIFIER, and call xref function FN."
  (with-current-buffer (find-file-noselect file)
    (let ((backend (emacs-code-navigator--semantic-xref-backend)))
      (unless backend
        (error "No xref backend available for %s" file))
      (goto-char (point-min))
    (let ((regexp (format "\\_<%s\\_>" (regexp-quote identifier)))
          found)
      (while (and (not found) (re-search-forward regexp nil t))
        (unless (nth 8 (syntax-ppss (match-beginning 0)))
          (setq found (match-beginning 0))))
      (unless found
        (error "Code identifier not found in file: %s" identifier))
      (goto-char found))
      (let ((backend-identifier
             (or (and (fboundp 'xref-backend-identifier-at-point)
                      (condition-case nil
                          (xref-backend-identifier-at-point backend)
                        (error nil)))
                 identifier)))
        (mapcar #'emacs-code-navigator--xref-location-data
                (funcall fn backend backend-identifier))))))

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
    (let* ((backend (emacs-code-navigator--semantic-xref-backend))
           (symbol (emacs-code-navigator--goto-symbol-at-line line identifier)))
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

(defun emacs-code-navigator-context-at-line
    (file line &optional radius include-defun include-eldoc
          include-diagnostics diagnostic-radius)
  "Return bounded live-buffer context for FILE at LINE.

RADIUS defaults to 5 source lines on each side.  INCLUDE-DEFUN,
INCLUDE-ELDOC, and INCLUDE-DIAGNOSTICS opt into progressively more expensive
data.  In particular, Flymake is never started by the default context query."
  (let* ((distance (or radius 5))
         (_ (unless (and (integerp distance) (>= distance 0))
              (error "RADIUS must be a non-negative integer: %S" radius)))
         (result
          (list :symbol (emacs-code-navigator-symbol-at-line file line)
                :region
                (emacs-code-navigator-read-region
                 file (max 1 (- line distance)) (+ line distance)))))
    (when include-defun
      (setq result
            (append result
                    (list :defun
                          (emacs-code-navigator-defun-at-line file line)))))
    (when include-eldoc
      (setq result
            (append result
                    (list :eldoc
                          (emacs-code-navigator-eldoc-at-line file line)))))
    (when include-diagnostics
      (setq result
            (append result
                    (list :diagnostics
                          (emacs-code-navigator-diagnostics-at-line
                           file line diagnostic-radius)))))
    result))

(defun emacs-code-navigator--xref-request (request)
  "Return xref data selected by compact REQUEST."
  (let ((file (plist-get request :file))
        (line (plist-get request :line))
        (identifier (plist-get request :identifier))
        (kind (or (plist-get request :kind) 'references)))
    (unless (memq kind '(definitions references))
      (error "Xref KIND must be definitions or references: %S" kind))
    (unless (or line identifier)
      (error "Xref requires :line or :identifier"))
    (if line
        (funcall (if (eq kind 'definitions)
                     #'emacs-code-navigator-xref-definitions-at-line
                   #'emacs-code-navigator-xref-references-at-line)
                 file line identifier)
      (funcall (if (eq kind 'definitions)
                   #'emacs-code-navigator-xref-definitions
                 #'emacs-code-navigator-xref-references)
               file identifier))))

(defun emacs-code-navigator--locate-result (strategy matches)
  "Return a compact locate result for STRATEGY and MATCHES."
  (list :strategy strategy :matches matches))

(defun emacs-code-navigator--locate-request (request)
  "Route a compact locate REQUEST to the cheapest suitable backend."
  (let* ((query (plist-get request :query))
         (file (plist-get request :file))
         (directory (or (plist-get request :directory)
                        (and file (file-name-directory file))))
         (line (plist-get request :line))
         (kind (or (plist-get request :kind) 'auto))
         (limit (plist-get request :limit))
         (glob (plist-get request :glob))
         (regexp (plist-get request :regexp)))
    (unless (and (stringp query) (not (string-empty-p query)))
      (error "Locate QUERY must be a non-empty string"))
    (unless (memq kind '(auto text symbol definitions references))
      (error "Locate KIND must be auto, text, symbol, definitions, or references: %S"
             kind))
    (cond
     ((eq kind 'text)
      (emacs-code-navigator--locate-result
       'text
       (emacs-code-navigator-search
        directory query limit glob (not regexp))))
     ((memq kind '(definitions references))
      (unless file
        (error "Locate %S requires :file context" kind))
      (emacs-code-navigator--locate-result
       kind
       (emacs-code-navigator--xref-request
        (list :file file :line line :identifier query :kind kind))))
     ((eq kind 'symbol)
      (unless file
        (error "Locate symbol requires :file context"))
      (emacs-code-navigator--locate-result
       'workspace-symbol
       (emacs-code-navigator-workspace-symbol file query limit)))
     (line
      (unless file
        (error "Locate with :line requires :file context"))
      (emacs-code-navigator--locate-result
       'definitions
       (emacs-code-navigator--xref-request
        (list :file file :line line :identifier query :kind 'definitions))))
     (file
      (let ((symbols
             (condition-case nil
                 (emacs-code-navigator-workspace-symbol file query limit)
               (error nil))))
        (if symbols
            (emacs-code-navigator--locate-result 'workspace-symbol symbols)
          (emacs-code-navigator--locate-result
           'text-fallback
           (emacs-code-navigator-search
            directory query limit glob (not regexp))))))
     (t
      (emacs-code-navigator--locate-result
       'text
       (emacs-code-navigator-search
        directory query limit glob (not regexp)))))))

(defun emacs-code-navigator--diagnostics-request (request)
  "Return file or project diagnostics selected by compact REQUEST."
  (let ((file (plist-get request :file))
        (directory (plist-get request :directory))
        (line (plist-get request :line)))
    (cond
     ((and file directory)
      (error "Diagnostics accepts :file or :directory, not both"))
     (directory
      (emacs-code-navigator-project-diagnostics
       directory (plist-get request :limit) (plist-get request :file-limit)))
     ((and file line)
      (emacs-code-navigator-diagnostics-at-line
       file line (plist-get request :radius)))
     (file (emacs-code-navigator-flymake-diagnostics file))
     (t (error "Diagnostics requires :file or :directory")))))

;;;###autoload
(defun emacs-code-navigator-query (request)
  "Execute compact code-navigation REQUEST and return a standard plist.

Use :operation `describe' to request operation schemas only when needed."
  (unless (listp request)
    (error "REQUEST must be a plist"))
  (let* ((operation (plist-get request :operation))
         (result
          (pcase operation
            ('capability
             (emacs-code-navigator-discover
              (plist-get request :pattern)
              (plist-get request :kind)
              (plist-get request :limit)
              (plist-get request :documentation)
              (not (plist-get request :full))))
            ('symbol
             (funcall (if (plist-get request :full)
                          #'emacs-code-navigator-symbol-info
                        #'emacs-code-navigator-symbol-summary)
                      (plist-get request :name)))
            ('library
             (emacs-code-navigator-library-info
              (plist-get request :name)))
            ('search
             (emacs-code-navigator-search
              (plist-get request :directory)
              (plist-get request :regexp)
              (plist-get request :limit)
              (plist-get request :glob)
              (plist-get request :literal)))
            ('files
             (emacs-code-navigator-project-files
              (plist-get request :directory)
              (plist-get request :limit)))
            ('region
             (emacs-code-navigator-read-region
              (plist-get request :file)
              (plist-get request :start-line)
              (plist-get request :end-line)))
            ('imenu
             (emacs-code-navigator-imenu (plist-get request :file)))
            ('workspace-symbol
             (emacs-code-navigator-workspace-symbol
              (plist-get request :file)
              (plist-get request :pattern)
              (plist-get request :limit)))
            ('xref (emacs-code-navigator--xref-request request))
            ('locate (emacs-code-navigator--locate-request request))
            ('diagnostics
             (emacs-code-navigator--diagnostics-request request))
            ('context
             (emacs-code-navigator-context-at-line
              (plist-get request :file)
              (plist-get request :line)
              (plist-get request :radius)
              (plist-get request :defun)
              (plist-get request :eldoc)
              (plist-get request :diagnostics)
              (plist-get request :diagnostic-radius)))
            ('describe
             (skill-runtime-describe
              emacs-code-navigator--schemas (plist-get request :target)))
            (_ (error "Unknown navigator operation: %S" operation)))))
    (skill-runtime-result
     operation result
     (cond
      ((and (listp result) (plist-member result :matches))
       (length (plist-get result :matches)))
      ((memq operation '(search files imenu workspace-symbol xref diagnostics))
       (length result))
      (t 1)))))

(provide 'emacs-code-navigator)

;;; emacs-code-navigator.el ends here
