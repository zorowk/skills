;;; skill-runtime.el --- Compact contracts shared by local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'seq)
(require 'subr-x)

(defun skill-runtime-result (operation data &optional count status page effects)
  "Return a compact standard envelope for OPERATION and DATA.

COUNT defaults to zero for nil DATA and one otherwise.
STATUS defaults to `ok'.  Include PAGE and EFFECTS only when non-nil."
  (let ((result
         (list :status (or status 'ok)
               :operation operation
               :count (or count (if (null data) 0 1))
               :data data)))
    (when page
      (setq result (append result (list :page page))))
    (when effects
      (setq result (append result (list :effects effects))))
    result))

(defun skill-runtime-page-metadata (offset limit total returned)
  "Return validated page metadata for OFFSET, LIMIT, TOTAL, and RETURNED."
  (unless (and (integerp offset) (>= offset 0))
    (error "OFFSET must be a non-negative integer: %S" offset))
  (unless (and (integerp limit) (> limit 0))
    (error "LIMIT must be a positive integer: %S" limit))
  (unless (and (integerp total) (>= total 0))
    (error "TOTAL must be a non-negative integer: %S" total))
  (unless (and (integerp returned) (>= returned 0) (<= returned limit))
    (error "RETURNED must be between zero and LIMIT: %S" returned))
  (let* ((next (+ offset returned))
         (truncated (< next total)))
    (list :offset offset
          :limit limit
          :total total
          :truncated truncated
          :next-offset (and truncated next))))

(defun skill-runtime-page (items offset limit total)
  "Return a validated page of ITEMS starting at OFFSET with LIMIT and TOTAL."
  (skill-runtime-page-metadata offset limit total 0)
  (let ((page-items (seq-take (nthcdr offset items) limit)))
    (list :items page-items
          :page (skill-runtime-page-metadata
                 offset limit total (length page-items)))))

(defun skill-runtime-truncate (text maximum label)
  "Return TEXT and explicit truncation metadata bounded by MAXIMUM for LABEL."
  (unless (and (integerp maximum) (> maximum 0))
    (error "MAXIMUM must be a positive integer: %S" maximum))
  (let* ((value (or text ""))
         (original-length (length value))
         (truncated (> original-length maximum)))
    (list :text (if truncated (substring value 0 maximum) value)
          :truncated truncated
          :original-length original-length
          :label label)))

(defun skill-runtime-require-authorization (request action)
  "Require explicit authorization in REQUEST for ACTION."
  (unless (eq (plist-get request :authorization) 'explicit)
    (error "%s requires :authorization `explicit'" action))
  t)

(defun skill-runtime-validate-request (schemas request)
  "Validate REQUEST against operation SCHEMAS and return REQUEST.

Require a known :operation, every field named by :required, and at least one
non-nil field named by :required-one-of.  Optional and operation-specific value
validation remains the facade's responsibility."
  (unless (and (listp request)
               (condition-case nil
                   (zerop (% (length request) 2))
                 (error nil)))
    (error "REQUEST must be a well-formed plist"))
  (let* ((operation (plist-get request :operation))
         (schema (alist-get operation schemas)))
    (unless schema
      (error "Unknown operation %S; expected %S"
             operation (mapcar #'car schemas)))
    (dolist (field (plist-get schema :required))
      (unless (and (plist-member request field) (plist-get request field))
        (error "%S requires non-nil %S" operation field)))
    (when-let* ((fields (plist-get schema :required-one-of)))
      (unless (seq-some (lambda (field)
                          (and (plist-member request field)
                               (plist-get request field)))
                        fields)
        (error "%S requires one of %S" operation fields)))
    request))

(defun skill-runtime--catalog-entry (entry)
  "Return compact discovery metadata for schema ENTRY."
  (let* ((operation (car entry))
         (schema (cdr entry))
         (result (list :operation operation
                       :summary (plist-get schema :summary))))
    (when-let* ((effects (plist-get schema :effects)))
      (setq result (append result (list :effects effects))))
    result))

(defun skill-runtime-describe (schemas &optional target)
  "Describe operation SCHEMAS, optionally restricted to TARGET.

SCHEMAS is an alist whose entries are (OPERATION . PLIST)."
  (if target
      (let ((schema (alist-get target schemas)))
        (unless schema
          (error "Unknown operation for describe: %S" target))
        (list :operation target :schema schema))
    (list :operations (mapcar #'car schemas)
          :catalog (mapcar #'skill-runtime--catalog-entry schemas))))

(provide 'skill-runtime)

;;; skill-runtime.el ends here
