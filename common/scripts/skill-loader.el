;;; skill-loader.el --- Load matching support code for self-loading facades -*- lexical-binding: t; -*-

;;; Commentary:
;; `require'/`featurep' alone cannot establish that an already loaded library
;; implements the contract needed by a freshly loaded facade.  Always load the
;; exact support source and check its API marker.  Never unload features or
;; reset session state to refresh code.

;;; Code:

(defun skill-loader-load (file api-symbol minimum)
  "Load exact source FILE and require API-SYMBOL to be at least MINIMUM.
Clear the marker first so an old file cannot inherit a newer library's marker.
Native `load', `defvar' and `defcustom' retain existing session configuration."
  (set api-symbol nil)
  (load file nil t t)
  (let ((actual (and (boundp api-symbol) (symbol-value api-symbol))))
    (unless (and (integerp actual) (>= actual minimum))
      (error "Incompatible shared library %s: %S must be at least %d, got %S"
             file api-symbol minimum actual))))

(provide 'skill-loader)

;;; skill-loader.el ends here
