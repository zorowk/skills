;;; skill-runtime.el --- Compact contracts shared by local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst skill-runtime-metrics-version 1
  "Schema version for metrics returned by `skill-runtime-measure'.")

(defun skill-runtime--printed-length (value)
  "Return the deterministic printed character length of VALUE."
  (let ((print-circle t)
        (print-length nil)
        (print-level nil))
    (length (prin1-to-string value))))

(defun skill-runtime--plist-value (value key)
  "Return KEY from plist VALUE, or nil when VALUE is not a plist."
  (and (listp value) (keywordp (car value)) (plist-get value key)))

(defun skill-runtime-measure (request function)
  "Call FUNCTION and append privacy-safe call metrics for REQUEST.

Measure serialized character counts rather than claiming exact model-token
usage.  Preserve existing errors and avoid retaining request or result content."
  (let ((started (float-time)))
    (let* ((result (funcall function))
           (elapsed-ms (max 0 (round (* 1000 (- (float-time) started)))))
           (data (plist-get result :data))
           (page (plist-get result :page))
           (provenance (plist-get result :provenance))
           (metrics
            (list :metrics-version skill-runtime-metrics-version
                  :elapsed-ms elapsed-ms
                  :request-characters (skill-runtime--printed-length request)
                  :request-field-count (/ (length request) 2)
                  :payload-characters (skill-runtime--printed-length data)
                  :base-response-characters
                  (skill-runtime--printed-length result)
                  :result-count (or (plist-get result :count) 0)
                  :truncated
                  (and (or (skill-runtime--plist-value page :truncated)
                           (skill-runtime--plist-value data :truncated))
                       t)
                  :degraded
                  (and (or (skill-runtime--plist-value result :degraded)
                           (skill-runtime--plist-value provenance :degraded))
                       t)
                  :resolved-source
                  (skill-runtime--plist-value provenance :resolved-source))))
      (append result (list :metrics metrics)))))

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
