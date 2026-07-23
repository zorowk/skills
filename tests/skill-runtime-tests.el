;;; skill-runtime-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"))

(defvar skill-runtime-envelope-version)
(defvar skill-runtime-metrics-version)

(defconst skill-runtime-test-public-failures
  '((skill-runtime-invalid-request
     needs-input invalid-request after-input revise-request)
    (skill-runtime-authorization-required
     needs-input authorization-required after-input confirm)
    (skill-runtime-permission-denied
     blocked permission-denied after-permission-change grant-permission)
    (skill-runtime-not-found
     needs-input not-found after-input select-target)
    (skill-runtime-ambiguous
     needs-input ambiguous after-input disambiguate)
    (skill-runtime-conflict
     blocked conflict after-refresh refresh-state)
    (skill-runtime-unavailable
     blocked unavailable after-environment-change restore-environment)
    (skill-runtime-stale-context
     blocked stale-context after-refresh refresh-context)
    (skill-runtime-partial-failure
     partial partial-failure selective inspect-failures)
    (skill-runtime-internal-error
     failed internal-error never inspect-implementation))
  "Stable lifecycle mapping for every typed public runtime failure.")

(defun skill-contract-test-even-integer-p (value)
  "Return non-nil when VALUE is an even integer."
  (and (integerp value) (zerop (% value 2))))

(ert-deftest skill-runtime-standard-envelope ()
  (should
   (equal (skill-runtime-result
           'list '(a b) 2 'ok '(:truncated nil) nil nil
           '(:artifact (:checked t)))
          '(:protocol-version 2
            :status ok :operation list :count 2 :data (a b)
            :page (:truncated nil)
            :verification (:artifact (:checked t))))))

(ert-deftest skill-runtime-measures-calls-without-retaining-content ()
  (let ((times '(10.0 10.042)))
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _) (pop times))))
      (let* ((request '(:operation sample :name "private request"))
             (result
              (skill-runtime-measure
               request
               (lambda ()
                 (skill-runtime-result 'sample '(:value "private result") 1))))
             (metrics (plist-get result :metrics)))
        (should (= (plist-get metrics :metrics-version) 1))
        (should (= (plist-get metrics :elapsed-ms) 42))
        (should (= (plist-get metrics :request-characters)
                   (length (prin1-to-string request))))
        (should (= (plist-get metrics :request-field-count) 2))
        (should (= (plist-get metrics :payload-characters)
                   (length (prin1-to-string '(:value "private result")))))
        (should (= (plist-get metrics :result-count) 1))
        (should-not (plist-get metrics :truncated))
        (should-not (string-match-p
                     "private"
                     (prin1-to-string metrics)))))))

(ert-deftest skill-runtime-measures-structured-public-failures ()
  (let* ((result
          (skill-runtime-measure
           '(:operation commit)
           (lambda ()
             (skill-runtime-signal
              'skill-runtime-authorization-required
              "Commit requires explicit authorization."
              :field-path '(:authorization)
              :verification '(:workflow (:authorization-checked t))))))
         (error-data (plist-get result :error)))
    (should (= (plist-get result :protocol-version) 2))
    (should (eq (plist-get result :status) 'needs-input))
    (should (eq (plist-get result :operation) 'commit))
    (should (zerop (plist-get result :count)))
    (should-not (plist-get result :data))
    (should (plist-member result :effects))
    (should-not (plist-get result :effects))
    (should (eq (plist-get error-data :code) 'authorization-required))
    (should (eq (plist-get error-data :retry) 'after-input))
    (should (equal (plist-get error-data :field-path) '(:authorization)))
    (should
     (equal (plist-get result :verification)
            '(:workflow (:authorization-checked t))))
    (should (plist-get result :metrics))))

(ert-deftest skill-runtime-public-failure-matrix-is-stable ()
  (dolist (case skill-runtime-test-public-failures)
    (pcase-let ((`(,condition ,status ,code ,retry ,required-action)
                 case))
      (let* ((partial (eq condition 'skill-runtime-partial-failure))
             (properties
              (and partial
                   '(:data (:completed ("one"))
                     :count 1
                     :effects (:mutated-count 1))))
             (result
              (skill-runtime-measure
               '(:operation sample)
               (lambda ()
                 (apply #'skill-runtime-signal
                        condition "Expected public failure." properties))))
             (error-data (plist-get result :error)))
        (skill-contract-tests-assert-failure result status code)
        (should (stringp (plist-get error-data :message)))
        (should (eq (plist-get error-data :retry) retry))
        (should (eq (plist-get error-data :required-action)
                    required-action))
        (if partial
            (progn
              (should (equal (plist-get result :data)
                             '(:completed ("one"))))
              (should (= (plist-get result :count) 1))
              (should (equal (plist-get result :effects)
                             '(:mutated-count 1))))
          (should-not (plist-get result :effects)))))))

(ert-deftest skill-runtime-preserves-unexpected-lisp-errors ()
  (should-error
   (skill-runtime-measure
    '(:operation sample)
    (lambda () (error "unexpected implementation failure")))))

(ert-deftest skill-runtime-pagination-exposes-next-offset ()
  (let ((page (skill-runtime-page '(a b c d) 1 2 4)))
    (should (equal (plist-get page :items) '(b c)))
    (should (eq (plist-get (plist-get page :page) :truncated) t))
    (should (= (plist-get (plist-get page :page) :next-offset) 3))))

(ert-deftest skill-runtime-truncation-is-machine-readable ()
  (let ((bounded (skill-runtime-truncate "abcdef" 3 'sample)))
    (should (equal (plist-get bounded :text) "abc"))
    (should (eq (plist-get bounded :truncated) t))
    (should (= (plist-get bounded :original-length) 6))))

(ert-deftest skill-runtime-validates-required-request-fields ()
  (let ((schemas
         '((sample :summary "Validate a sample request."
                   :required (:name)
                   :required-one-of (:file :directory)))))
    (should
     (equal
      (skill-runtime-validate-request
       schemas '(:operation sample :name "item" :file "/tmp/item"))
      '(:operation sample :name "item" :file "/tmp/item")))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :file "/tmp/item")))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :name "item")))
    (should-error
     (skill-runtime-validate-request schemas '(:operation unknown)))))

(ert-deftest skill-runtime-validates-declared-types-and-choices ()
  (let ((schemas
         '((sample :summary "Validate compact constraints."
                   :required (:name :items)
                   :optional (:mode)
                   :types ((:name non-empty-string)
                           (:items non-empty-string-list))
                   :choices ((:mode compact full))))))
    (should
     (equal
      (skill-runtime-validate-request
       schemas '(:operation sample :name "item" :items ("one")
                           :mode compact))
      '(:operation sample :name "item" :items ("one") :mode compact)))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :name symbol :items ("one"))))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :name "item" :items (""))))
    (should-error
     (skill-runtime-validate-request
      schemas '(:operation sample :name "item" :items ("one")
                          :mode verbose)))))

(ert-deftest skill-runtime-validates-parameterized-and-path-types ()
  (let* ((file (make-temp-file "skill-runtime-contract-"))
         (schemas
          '((sample
             :summary "Validate richer primitive types."
             :required (:count :enabled :kind :root :file)
             :types
             ((:count (integer :min 1 :max 3))
              (:enabled boolean)
              (:kind symbol)
              (:root absolute-path)
              (:file existing-file))))))
    (unwind-protect
        (progn
          (should
           (equal
            (skill-runtime-validate-request
             schemas
             `(:operation sample :count 2 :enabled t :kind compact
                          :root ,temporary-file-directory :file ,file))
            `(:operation sample :count 2 :enabled t :kind compact
                         :root ,temporary-file-directory :file ,file)))
          (should-error
           (skill-runtime-validate-request
            schemas
            `(:operation sample :count 4 :enabled t :kind compact
                         :root ,temporary-file-directory :file ,file)))
          (should-error
           (skill-runtime-validate-request
            schemas
            `(:operation sample :count 2 :enabled yes :kind compact
                         :root ,temporary-file-directory :file ,file))))
      (delete-file file))))

(ert-deftest skill-runtime-validates-nested-and-relational-contracts ()
  (let ((schemas
         '((sample
            :summary "Validate nested and dependent fields."
            :required (:tasks :count)
            :optional (:file :directory :left :right :replace :authorization)
            :exactly-one-of (:file :directory)
            :mutually-exclusive (:left :right)
            :requires ((:replace :authorization))
            :types
            ((:count integer)
             (:tasks
              (list-of
               (plist
                :required (:title)
                :optional (:priority)
                :types ((:title non-empty-string)
                        (:priority (string :length 1)))
                :closed t)
               :min-items 1 :max-items 2)))
            :validators
            ((:count skill-contract-test-even-integer-p
                     "Count must be even."))))))
    (should
     (equal
      (skill-runtime-validate-request
       schemas
       '(:operation sample :file "/tmp/input" :count 2
                    :tasks ((:title "One" :priority "A"))))
      '(:operation sample :file "/tmp/input" :count 2
                   :tasks ((:title "One" :priority "A")))))
    (should-error
     (skill-runtime-validate-request
      schemas
      '(:operation sample :file "/tmp/input" :directory "/tmp"
                   :count 2 :tasks ((:title "One")))))
    (should-error
     (skill-runtime-validate-request
      schemas
      '(:operation sample :file "/tmp/input" :left t :right t
                   :count 2 :tasks ((:title "One")))))
    (should-error
     (skill-runtime-validate-request
      schemas
      '(:operation sample :file "/tmp/input" :replace t
                   :count 2 :tasks ((:title "One")))))
    (should-error
     (skill-runtime-validate-request
      schemas
      '(:operation sample :file "/tmp/input" :count 3
                   :tasks ((:title "One")))))
    (should-error
     (skill-runtime-validate-request
      schemas
      '(:operation sample :file "/tmp/input" :count 2
                   :tasks ((:title "One" :unknown t)))))))

(provide 'skill-runtime-tests)

;;; skill-runtime-tests.el ends here
