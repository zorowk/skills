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

(defun skill-runtime--well-formed-plist-p (value)
  "Return non-nil when VALUE is an even plist with keyword keys."
  (and
   (listp value)
   (condition-case nil
       (and
        (zerop (% (length value) 2))
        (let ((tail value)
              (valid t))
          (while tail
            (unless (keywordp (car tail))
              (setq valid nil
                    tail nil))
            (when tail
              (setq tail (cddr tail))))
          valid))
     (error nil))))

(defun skill-runtime--field-active-p (value field)
  "Return non-nil when FIELD is present and non-nil in plist VALUE."
  (and (plist-member value field) (plist-get value field)))

(defun skill-runtime--constraint-groups (value label)
  "Return normalized field groups from VALUE for constraint LABEL."
  (cond
   ((null value) nil)
   ((and (listp value) (keywordp (car value)))
    (list value))
   ((and (listp value)
         (seq-every-p
          (lambda (group)
            (and (listp group) group (seq-every-p #'keywordp group)))
          value))
    value)
   (t (error "%s must contain keyword field groups: %S" label value))))

(defun skill-runtime--validate-cardinality (operation schema value path)
  "Validate cross-field cardinality in VALUE against SCHEMA at PATH."
  (dolist (group
           (skill-runtime--constraint-groups
            (plist-get schema :exactly-one-of) ":exactly-one-of"))
    (let ((count
           (length
            (seq-filter
             (lambda (field) (skill-runtime--field-active-p value field))
             group))))
      (unless (= count 1)
        (error "%S %s requires exactly one of %S" operation path group))))
  (dolist (group
           (skill-runtime--constraint-groups
            (plist-get schema :mutually-exclusive) ":mutually-exclusive"))
    (let ((count
           (length
            (seq-filter
             (lambda (field) (skill-runtime--field-active-p value field))
             group))))
      (when (> count 1)
        (error "%S %s fields are mutually exclusive: %S"
               operation path group)))))

(defun skill-runtime--validate-dependencies (operation schema value path)
  "Validate dependent fields in VALUE against SCHEMA at PATH."
  (dolist (spec (plist-get schema :requires))
    (unless (and (listp spec) (> (length spec) 1)
                 (seq-every-p #'keywordp spec))
      (error ":requires entries must contain a trigger and dependent fields: %S"
             spec))
    (when (skill-runtime--field-active-p value (car spec))
      (dolist (dependent (cdr spec))
        (unless (skill-runtime--field-active-p value dependent)
          (error "%S %s %S requires non-nil %S"
                 operation path (car spec) dependent))))))

(defun skill-runtime--validate-custom (operation path value validator)
  "Validate VALUE with named VALIDATOR for OPERATION at PATH."
  (unless (and (symbolp validator) (fboundp validator))
    (error "Unknown schema validator: %S" validator))
  (condition-case error-data
      (unless (funcall validator value)
        (error "validator returned nil"))
    (error
     (error "%S %s failed validator %S: %s"
            operation path validator (error-message-string error-data)))))

(defun skill-runtime--validate-type (operation path value type)
  "Validate VALUE as TYPE for OPERATION at PATH."
  (cond
   ((symbolp type)
    (unless
        (pcase type
          ('string (stringp value))
          ('non-empty-string
           (and (stringp value) (not (string-empty-p value))))
          ('non-empty-string-list
           (and (listp value)
                value
                (seq-every-p
                 (lambda (item)
                   (and (stringp item) (not (string-empty-p item))))
                 value)))
          ('integer (integerp value))
          ('boolean (or (null value) (eq value t)))
          ('symbol (symbolp value))
          ('path
           (and (stringp value) (not (string-empty-p value))))
          ('absolute-path
           (and (stringp value) (not (string-empty-p value))
                (file-name-absolute-p value)))
          ('existing-file
           (and (stringp value) (not (string-empty-p value))
                (file-regular-p (expand-file-name value))))
          ('plist (skill-runtime--well-formed-plist-p value))
          ('list-of-plists
           (and (listp value)
                (seq-every-p #'skill-runtime--well-formed-plist-p value)))
          (_ (error "Unknown schema field type: %S" type)))
      (error "%S %s must be %S" operation path type)))
   ((and (listp type) (eq (car type) 'integer))
    (let ((options (cdr type)))
      (unless (and (integerp value)
                   (or (not (plist-member options :min))
                       (>= value (plist-get options :min)))
                   (or (not (plist-member options :max))
                       (<= value (plist-get options :max))))
        (error "%S %s must satisfy %S" operation path type))))
   ((and (listp type) (eq (car type) 'string))
    (let ((options (cdr type)))
      (unless
          (and
           (stringp value)
           (or (not (plist-member options :length))
               (= (length value) (plist-get options :length)))
           (or (not (plist-member options :min-length))
               (>= (length value) (plist-get options :min-length)))
           (or (not (plist-member options :max-length))
               (<= (length value) (plist-get options :max-length))))
        (error "%S %s must satisfy %S" operation path type))))
   ((and (listp type) (eq (car type) 'list-of))
    (let ((item-type (cadr type))
          (options (cddr type)))
      (unless (listp value)
        (error "%S %s must satisfy %S" operation path type))
      (when (and (plist-member options :min-items)
                 (< (length value) (plist-get options :min-items)))
        (error "%S %s must satisfy %S" operation path type))
      (when (and (plist-member options :max-items)
                 (> (length value) (plist-get options :max-items)))
        (error "%S %s must satisfy %S" operation path type))
      (let ((index 0))
        (dolist (item value)
          (skill-runtime--validate-type
           operation (format "%s[%d]" path index) item item-type)
          (setq index (1+ index))))))
   ((and (listp type) (eq (car type) 'plist))
    (unless (skill-runtime--well-formed-plist-p value)
      (error "%S %s must be a well-formed plist" operation path))
    (skill-runtime--validate-plist-schema operation (cdr type) value path))
   ((and (listp type) (eq (car type) 'custom))
    (skill-runtime--validate-custom operation path value (cadr type)))
   (t (error "Unknown schema field type: %S" type))))

(defun skill-runtime--validate-field-types (operation schema value path)
  "Validate present fields in VALUE declared by SCHEMA for OPERATION at PATH."
  (dolist (spec (plist-get schema :types))
    (let ((field (car spec))
          (type (cadr spec)))
      (when (skill-runtime--field-active-p value field)
        (skill-runtime--validate-type
         operation (format "%s.%s" path field)
         (plist-get value field) type)))))

(defun skill-runtime--validate-field-choices (operation schema value path)
  "Validate present VALUE fields with enumerated SCHEMA choices at PATH."
  (dolist (spec (plist-get schema :choices))
    (let ((field (car spec))
          (choices (cdr spec)))
      (when (and (skill-runtime--field-active-p value field)
                 (not (member (plist-get value field) choices)))
        (error "%S %s.%s must be one of %S: %S"
               operation path field choices (plist-get value field))))))

(defun skill-runtime--validate-field-validators (operation schema value path)
  "Run named field validators declared by SCHEMA against VALUE at PATH."
  (dolist (spec (plist-get schema :validators))
    (let ((field (car spec))
          (validator (cadr spec)))
      (when (skill-runtime--field-active-p value field)
        (skill-runtime--validate-custom
         operation (format "%s.%s" path field)
         (plist-get value field) validator)))))

(defun skill-runtime--declared-fields (schema)
  "Return fields declared anywhere in SCHEMA."
  (delete-dups
   (append
    '(:operation)
    (plist-get schema :required)
    (plist-get schema :optional)
    (plist-get schema :required-one-of)
    (apply #'append
           (skill-runtime--constraint-groups
            (plist-get schema :exactly-one-of) ":exactly-one-of"))
    (apply #'append
           (skill-runtime--constraint-groups
            (plist-get schema :mutually-exclusive) ":mutually-exclusive"))
    (apply #'append (plist-get schema :requires))
    (mapcar #'car (plist-get schema :types))
    (mapcar #'car (plist-get schema :choices))
    (mapcar #'car (plist-get schema :validators)))))

(defun skill-runtime--validate-plist-schema (operation schema value path)
  "Validate plist VALUE against SCHEMA for OPERATION at PATH."
  (dolist (field (plist-get schema :required))
    (unless (skill-runtime--field-active-p value field)
      (error "%S %s requires non-nil %S" operation path field)))
  (when-let* ((fields (plist-get schema :required-one-of)))
    (unless (seq-some
             (lambda (field) (skill-runtime--field-active-p value field))
             fields)
      (error "%S %s requires one of %S" operation path fields)))
  (skill-runtime--validate-cardinality operation schema value path)
  (skill-runtime--validate-dependencies operation schema value path)
  (skill-runtime--validate-field-types operation schema value path)
  (skill-runtime--validate-field-choices operation schema value path)
  (skill-runtime--validate-field-validators operation schema value path)
  (when (plist-get schema :closed)
    (let ((allowed (skill-runtime--declared-fields schema))
          (tail value))
      (while tail
        (unless (memq (car tail) allowed)
          (error "%S %s does not allow field %S" operation path (car tail)))
        (setq tail (cddr tail)))))
  value)

(defun skill-runtime-validate-request (schemas request)
  "Validate REQUEST against operation SCHEMAS and return REQUEST.

Require a known :operation and validate the selected declarative contract.
Schemas may declare required fields, structural types, choices, cross-field
cardinality, dependencies, closed plists, and named custom validators.  Other
operation-specific validation remains the facade's responsibility."
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
    (skill-runtime--validate-plist-schema
     operation schema request (symbol-name operation))))

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
