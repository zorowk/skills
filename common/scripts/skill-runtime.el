;;; skill-runtime.el --- Compact contracts shared by local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'seq)
(require 'subr-x)

(defconst skill-runtime-envelope-version 2
  "Version of the public skill result envelope.")

(defconst skill-runtime-metrics-version 1
  "Schema version for metrics returned by `skill-runtime-measure'.")

(define-error 'skill-runtime-public-error "Public skill failure")
(define-error 'skill-runtime-invalid-request "Invalid skill request"
  'skill-runtime-public-error)
(define-error 'skill-runtime-authorization-required "Skill authorization required"
  'skill-runtime-public-error)
(define-error 'skill-runtime-permission-denied "Skill permission denied"
  'skill-runtime-public-error)
(define-error 'skill-runtime-not-found "Skill target not found"
  'skill-runtime-public-error)
(define-error 'skill-runtime-ambiguous "Skill target is ambiguous"
  'skill-runtime-public-error)
(define-error 'skill-runtime-conflict "Skill state conflict"
  'skill-runtime-public-error)
(define-error 'skill-runtime-unavailable "Skill environment unavailable"
  'skill-runtime-public-error)
(define-error 'skill-runtime-stale-context "Skill context is stale"
  'skill-runtime-public-error)
(define-error 'skill-runtime-partial-failure "Skill operation partially failed"
  'skill-runtime-public-error)
(define-error 'skill-runtime-internal-error "Skill internal failure"
  'skill-runtime-public-error)

(defconst skill-runtime--public-error-defaults
  '((skill-runtime-public-error
     :status failed :code public-error :retry never
     :required-action inspect-failure)
    (skill-runtime-invalid-request
     :status needs-input :code invalid-request :retry after-input
     :required-action revise-request)
    (skill-runtime-authorization-required
     :status needs-input :code authorization-required :retry after-input
     :required-action confirm)
    (skill-runtime-permission-denied
     :status blocked :code permission-denied :retry after-permission-change
     :required-action grant-permission)
    (skill-runtime-not-found
     :status needs-input :code not-found :retry after-input
     :required-action select-target)
    (skill-runtime-ambiguous
     :status needs-input :code ambiguous :retry after-input
     :required-action disambiguate)
    (skill-runtime-conflict
     :status blocked :code conflict :retry after-refresh
     :required-action refresh-state)
    (skill-runtime-unavailable
     :status blocked :code unavailable :retry after-environment-change
     :required-action restore-environment)
    (skill-runtime-stale-context
     :status blocked :code stale-context :retry after-refresh
     :required-action refresh-context)
    (skill-runtime-partial-failure
     :status partial :code partial-failure :retry selective
     :required-action inspect-failures)
    (skill-runtime-internal-error
     :status failed :code internal-error :retry never
     :required-action inspect-implementation))
  "Default recovery metadata for structured public conditions.")

(defun skill-runtime--printed-length (value)
  "Return the deterministic printed character length of VALUE."
  (let ((print-circle t)
        (print-length nil)
        (print-level nil))
    (length (prin1-to-string value))))

(defun skill-runtime--plist-value (value key)
  "Return KEY from plist VALUE, or nil when VALUE is not a plist."
  (and (listp value) (keywordp (car value)) (plist-get value key)))

(defun skill-runtime-signal (condition message &rest properties)
  "Signal public CONDITION with MESSAGE and structured PROPERTIES."
  (unless (memq 'skill-runtime-public-error
                (get condition 'error-conditions))
    (error "Not a public skill condition: %S" condition))
  (unless (stringp message)
    (error "Public skill condition message must be a string: %S" message))
  (unless (zerop (% (length properties) 2))
    (error "Public skill condition properties must be a plist: %S" properties))
  (signal condition (list (append (list :message message) properties))))

(defun skill-runtime-reject-request (message &rest properties)
  "Signal an invalid public request with MESSAGE and PROPERTIES."
  (apply #'skill-runtime-signal
         'skill-runtime-invalid-request message properties))

(defun skill-runtime--plist-without (plist keys)
  "Return PLIST without any entries whose key is in KEYS."
  (let ((tail plist)
        result)
    (while tail
      (unless (memq (car tail) keys)
        (setq result (append result (list (car tail) (cadr tail)))))
      (setq tail (cddr tail)))
    result))

(defun skill-runtime-failure-result
    (operation status error &optional data count effects verification)
  "Return a versioned failure envelope for OPERATION.

STATUS is one of the public lifecycle states.  ERROR is a structured plist.
DATA, COUNT, EFFECTS, and VERIFICATION describe partial evidence, actual side
effects, and completed checks."
  (let ((result
         (skill-runtime-result
          (or operation 'unknown) data (or count 0) status nil effects error
          verification)))
    (if effects result (append result '(:effects nil)))))

(defun skill-runtime--public-error-result (request error-data)
  "Convert typed ERROR-DATA raised for REQUEST into a failure envelope."
  (let* ((condition (car error-data))
         (payload (or (cadr error-data) nil))
         (defaults
          (or (cdr (assq condition skill-runtime--public-error-defaults))
              (cdr (assq 'skill-runtime-public-error
                         skill-runtime--public-error-defaults))))
         (combined (append defaults payload))
         (status (plist-get combined :status))
         (data (plist-get combined :data))
         (count (plist-get combined :count))
         (effects (plist-get combined :effects))
         (verification (plist-get combined :verification))
         (error
          (skill-runtime--plist-without
           combined '(:status :data :count :effects :verification)))
         (operation
          (condition-case nil
              (and (listp request) (plist-get request :operation))
            (error nil))))
    (skill-runtime-failure-result
     operation status error data count effects verification)))

(defun skill-runtime--request-field-count (request)
  "Return REQUEST plist field count, or zero for malformed input."
  (condition-case nil
      (if (and (listp request) (zerop (% (length request) 2)))
          (/ (length request) 2)
        0)
    (error 0)))

(defun skill-runtime-measure (request function)
  "Call FUNCTION and append privacy-safe call metrics for REQUEST.

Measure serialized character counts rather than claiming exact model-token
usage.  Convert typed public conditions into failure envelopes while preserving
unexpected Lisp errors.  Avoid retaining request or result content."
  (let ((started (float-time)))
    (let* ((result
            (condition-case error-data
                (funcall function)
              (skill-runtime-public-error
               (skill-runtime--public-error-result request error-data))))
           (elapsed-ms (max 0 (round (* 1000 (- (float-time) started)))))
           (data (plist-get result :data))
           (page (plist-get result :page))
           (provenance (plist-get result :provenance))
           (metrics
            (list :metrics-version skill-runtime-metrics-version
                  :elapsed-ms elapsed-ms
                  :request-characters (skill-runtime--printed-length request)
                  :request-field-count
                  (skill-runtime--request-field-count request)
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

(defun skill-runtime-result
    (operation data &optional count status page effects error verification)
  "Return a compact standard envelope for OPERATION and DATA.

COUNT defaults to zero for nil DATA and one otherwise.
STATUS defaults to `ok'.  Include PAGE, EFFECTS, ERROR, and VERIFICATION when
non-nil."
  (let ((result
         (list :protocol-version skill-runtime-envelope-version
               :status (or status 'ok)
               :operation operation
               :count (or count (if (null data) 0 1))
               :data data)))
    (when page
      (setq result (append result (list :page page))))
    (when effects
      (setq result (append result (list :effects effects))))
    (when error
      (setq result (append result (list :error error))))
    (when verification
      (setq result (append result (list :verification verification))))
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
    (skill-runtime-signal
     'skill-runtime-authorization-required
     (format "%s requires :authorization `explicit'" action)
     :field-path '(:authorization)
     :expected 'explicit
     :actual (plist-get request :authorization)))
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
        (skill-runtime-reject-request
         (format "%S %s requires exactly one of %S" operation path group)
         :field-path path :expected (list :exactly-one-of group)
         :actual count))))
  (dolist (group
           (skill-runtime--constraint-groups
            (plist-get schema :mutually-exclusive) ":mutually-exclusive"))
    (let ((count
           (length
            (seq-filter
             (lambda (field) (skill-runtime--field-active-p value field))
             group))))
      (when (> count 1)
        (skill-runtime-reject-request
         (format "%S %s fields are mutually exclusive: %S"
                 operation path group)
         :field-path path :expected (list :at-most-one-of group)
         :actual count)))))

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
          (skill-runtime-reject-request
           (format "%S %s %S requires non-nil %S"
                   operation path (car spec) dependent)
           :field-path (list path dependent)
           :required-by (car spec)))))))

(defun skill-runtime--validate-custom (operation path value validator)
  "Validate VALUE with named VALIDATOR for OPERATION at PATH."
  (unless (and (symbolp validator) (fboundp validator))
    (error "Unknown schema validator: %S" validator))
  (condition-case error-data
      (unless (funcall validator value)
        (error "validator returned nil"))
    (error
     (skill-runtime-reject-request
      (format "%S %s failed validator %S: %s"
              operation path validator (error-message-string error-data))
      :field-path path :validator validator))))

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
      (skill-runtime-reject-request
       (format "%S %s must be %S" operation path type)
       :field-path path :expected type :actual value)))
   ((and (listp type) (eq (car type) 'integer))
    (let ((options (cdr type)))
      (unless (and (integerp value)
                   (or (not (plist-member options :min))
                       (>= value (plist-get options :min)))
                   (or (not (plist-member options :max))
                       (<= value (plist-get options :max))))
        (skill-runtime-reject-request
         (format "%S %s must satisfy %S" operation path type)
         :field-path path :expected type :actual value))))
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
        (skill-runtime-reject-request
         (format "%S %s must satisfy %S" operation path type)
         :field-path path :expected type :actual value))))
   ((and (listp type) (eq (car type) 'list-of))
    (let ((item-type (cadr type))
          (options (cddr type)))
      (unless (listp value)
        (skill-runtime-reject-request
         (format "%S %s must satisfy %S" operation path type)
         :field-path path :expected type :actual value))
      (when (and (plist-member options :min-items)
                 (< (length value) (plist-get options :min-items)))
        (skill-runtime-reject-request
         (format "%S %s must satisfy %S" operation path type)
         :field-path path :expected type :actual value))
      (when (and (plist-member options :max-items)
                 (> (length value) (plist-get options :max-items)))
        (skill-runtime-reject-request
         (format "%S %s must satisfy %S" operation path type)
         :field-path path :expected type :actual value))
      (let ((index 0))
        (dolist (item value)
          (skill-runtime--validate-type
           operation (format "%s[%d]" path index) item item-type)
          (setq index (1+ index))))))
   ((and (listp type) (eq (car type) 'plist))
    (unless (skill-runtime--well-formed-plist-p value)
      (skill-runtime-reject-request
       (format "%S %s must be a well-formed plist" operation path)
       :field-path path :expected 'plist :actual value))
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
        (if (eq field :authorization)
            (skill-runtime-signal
             'skill-runtime-authorization-required
             (format "%S requires authorized %S to be one of %S"
                     operation field choices)
             :field-path '(:authorization)
             :expected choices
             :actual (plist-get value field))
          (skill-runtime-reject-request
           (format "%S %s.%s must be one of %S: %S"
                   operation path field choices (plist-get value field))
           :field-path (list path field)
           :expected choices
           :actual (plist-get value field)))))))

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
      (if (eq field :authorization)
          (skill-runtime-signal
           'skill-runtime-authorization-required
           (format "%S requires :authorization `explicit'" operation)
           :field-path '(:authorization)
           :expected 'explicit
           :actual (plist-get value field))
        (skill-runtime-reject-request
         (format "%S %s requires non-nil %S" operation path field)
         :field-path (list path field)
         :expected 'non-nil))))
  (when-let* ((fields (plist-get schema :required-one-of)))
    (unless (seq-some
             (lambda (field) (skill-runtime--field-active-p value field))
             fields)
      (skill-runtime-reject-request
       (format "%S %s requires one of %S" operation path fields)
       :field-path path :expected (list :at-least-one-of fields))))
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
          (skill-runtime-reject-request
           (format "%S %s does not allow field %S"
                   operation path (car tail))
           :field-path (list path (car tail))
           :expected allowed))
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
    (skill-runtime-reject-request
     "REQUEST must be a well-formed plist"
     :field-path nil :expected 'plist :actual request))
  (let* ((operation (plist-get request :operation))
         (schema (alist-get operation schemas)))
    (unless schema
      (skill-runtime-reject-request
       (format "Unknown operation %S; expected %S"
               operation (mapcar #'car schemas))
       :field-path '(:operation)
       :expected (mapcar #'car schemas)
       :actual operation))
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
          (skill-runtime-reject-request
           (format "Unknown operation for describe: %S" target)
           :field-path '(:target)
           :expected (mapcar #'car schemas)
           :actual target))
        (list :operation target :schema schema))
    (list :operations (mapcar #'car schemas)
          :catalog (mapcar #'skill-runtime--catalog-entry schemas))))

(provide 'skill-runtime)

;;; skill-runtime.el ends here
