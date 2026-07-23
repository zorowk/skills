;;; skill-contract-tests.el --- Contract tests for local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'xref)

(defvar emacs-code-navigator-documentation-maximum-characters)
(defvar emacs-code-navigator-symbol-batch-limit)
(defvar emacs-code-navigator-agent-shell-context-enabled)
(defvar emacs-code-navigator-agent-shell-context-maximum-characters)
(defvar emacs-code-navigator-agent-shell-context-radius)
(defvar emacs-code-navigator-agent-shell-diagnostic-limit)
(defvar emacs-code-navigator-agent-shell-last-context-metrics)
(defvar emacs-code-navigator-agent-shell-semantic-level)
(defvar emacs-code-navigator-agent-shell-definition-limit)
(defvar emacs-code-navigator-agent-shell-semantic-timeout-ms)
(defvar skill-agent-shell-context-maximum-characters)
(defvar skill-agent-shell-context-providers)
(defvar skill-agent-shell-turn-actions)
(defvar skill-agent-shell-last-context-metrics)
(defvar skill-agent-shell--turn-state)
(defvar skill-agent-shell--last-completed-turn)
(defvar skill-agent-shell--available-actions)
(defvar skill-agent-shell-minimum-version)
(defvar agent-shell--version)
(defvar agent-shell-gtd-capture--suppress-count)
(defvar agent-shell-denote-capture--suppress-count)
(defvar agent-shell-skill-usage-review--suppress-count)
(defvar emacs-gtd-capture-task-limit)
(defvar ai-git-commit-include-validation-in-message)
(defvar emacs-code-navigator-semantic-buffer-policy)
(defvar emacs-code-navigator-semantic-buffer-limit)
(defvar emacs-code-navigator--semantic-buffers)
(defvar agent-shell-context-sources)
(defvar agent-shell-mode-hook)
(defvar emacs-gtd-directory)
(defvar emacs-gtd-file)
(defvar ai-git-commit-untracked-file-maximum-characters)
(defvar ai-git-commit-untracked-maximum-characters)
(defvar magit-display-buffer-noselect)
(defvar magit-process-popup-time)
(defvar org-blog-exporter-setupfile)
(defvar org-id-locations-file)
(defvar skill-git--body-label-regexp)
(defvar skill-runtime-envelope-version)
(defvar skill-runtime-metrics-version)

(declare-function skill-runtime-result "../common/scripts/skill-runtime"
                  (operation data &optional count status page effects error
                             verification))
(declare-function skill-runtime-measure "../common/scripts/skill-runtime"
                  (request function))
(declare-function skill-runtime-signal "../common/scripts/skill-runtime"
                  (condition message &rest properties))
(declare-function skill-runtime-page "../common/scripts/skill-runtime"
                  (items offset limit total))
(declare-function skill-runtime-truncate "../common/scripts/skill-runtime"
                  (text maximum label))
(declare-function skill-runtime-validate-request "../common/scripts/skill-runtime"
                  (schemas request))
(declare-function emacs-code-navigator-query
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (request))
(declare-function emacs-code-navigator--compact-facet
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (info))
(declare-function emacs-code-navigator-symbols
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (names &optional full))
(declare-function emacs-code-navigator-search
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (directory regexp &optional limit glob literal))
(declare-function emacs-code-navigator-workspace-symbol
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (file pattern &optional limit))
(declare-function emacs-code-navigator--semantic-xref-backend
                  "../emacs-code-navigator/scripts/emacs-code-navigator" ())
(declare-function emacs-code-navigator-context-at-line
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (file line &optional radius include-defun include-eldoc
                        include-diagnostics diagnostic-radius column
                        include-definitions definition-limit semantic-timeout-ms))
(declare-function emacs-code-navigator-semantic-at-position
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (file line column include-definitions definition-limit
                        include-eldoc timeout-ms))
(declare-function emacs-code-navigator-close-semantic-buffers
                  "../emacs-code-navigator/scripts/emacs-code-navigator" ())

(defun skill-contract-test-even-integer-p (value)
  "Return non-nil when VALUE is an even integer."
  (and (integerp value) (zerop (% value 2))))

(defun skill-contract-tests-assert-failure (result status code)
  "Assert RESULT is a structured failure with STATUS and CODE."
  (should (= (plist-get result :protocol-version) 2))
  (should (eq (plist-get result :status) status))
  (should (eq (plist-get (plist-get result :error) :code) code))
  (should (plist-member result :effects))
  (should (plist-get result :metrics))
  result)
(declare-function emacs-code-navigator-agent-shell-context
                  "../emacs-code-navigator/scripts/agent-shell-code-context" ())
(declare-function emacs-code-navigator-agent-shell-enable
                  "../emacs-code-navigator/scripts/agent-shell-code-context" ())
(declare-function skill-agent-shell-context
                  "../common/scripts/agent-shell-bridge" ())
(declare-function skill-agent-shell-compatibility
                  "../common/scripts/agent-shell-bridge" ())
(declare-function skill-agent-shell--assert-compatible
                  "../common/scripts/agent-shell-bridge" ())
(declare-function skill-agent-shell-register-context-provider
                  "../common/scripts/agent-shell-bridge" (id &rest arguments))
(declare-function skill-agent-shell-register-turn-action
                  "../common/scripts/agent-shell-bridge" (id &rest arguments))
(declare-function skill-agent-shell--handle-event
                  "../common/scripts/agent-shell-bridge" (shell-buffer event))
(declare-function skill-agent-shell-current-turn-paths
                  "../common/scripts/agent-shell-bridge"
                  (&optional shell-buffer))
(declare-function skill-agent-shell-turn-action-menu
                  "../common/scripts/agent-shell-bridge"
                  (&optional shell-buffer))
(declare-function agent-shell-git-review--request-text
                  "../git-commit/scripts/agent-shell-git-review"
                  (shell-buffer action))
(declare-function emacs-gtd-execute
                  "../emacs-gtd-assistant/scripts/emacs-gtd-assistant"
                  (request))
(declare-function agent-shell-gtd-capture--prompt
                  "../emacs-gtd-assistant/scripts/agent-shell-gtd-capture" ())
(declare-function agent-shell-gtd-capture--applicable-p
                  "../emacs-gtd-assistant/scripts/agent-shell-gtd-capture"
                  (shell-buffer state))
(declare-function denote-scribe-run
                  "../denote-scribe/scripts/denote-scribe" (request))
(declare-function denote-scribe-create
                  "../denote-scribe/scripts/denote-scribe"
                  (title body-file &optional keywords notes-dir signature date))
(declare-function denote-scribe-git-commit
                  "../denote-scribe/scripts/denote-scribe"
                  (title paths review-completed &optional kind git-dir))
(declare-function denote-scribe-link-gtd
                  "../denote-scribe/scripts/denote-scribe"
                  (file tasks &optional notes-dir))
(declare-function agent-shell-denote-capture--prompt
                  "../denote-scribe/scripts/agent-shell-denote-capture" ())
(declare-function agent-shell-denote-capture--applicable-p
                  "../denote-scribe/scripts/agent-shell-denote-capture"
                  (shell-buffer state))
(declare-function agent-shell-skill-usage-review--prompt
                  "../skill-usage-review/scripts/agent-shell-skill-usage-review"
                  ())
(declare-function agent-shell-skill-usage-review--applicable-p
                  "../skill-usage-review/scripts/agent-shell-skill-usage-review"
                  (shell-buffer state))
(declare-function agent-shell-skill-usage-review
                  "../skill-usage-review/scripts/agent-shell-skill-usage-review"
                  (&optional shell-buffer))
(declare-function agent-shell-skill-usage-review-enable
                  "../skill-usage-review/scripts/agent-shell-skill-usage-review"
                  ())
(declare-function org-blog-exporter-run
                  "../org-blog-exporter/scripts/org-blog-exporter" (request))
(declare-function org-blog-exporter--finish-publish
                  "../org-blog-exporter/scripts/org-blog-exporter"
                  (repository exported title))
(declare-function org-blog-exporter--effects
                  "../org-blog-exporter/scripts/org-blog-exporter"
                  (operation result))
(declare-function ai-git-commit-run
                  "../git-commit/scripts/ai-git-commit" (request))
(declare-function ai-git-commit-format
                  "../git-commit/scripts/ai-git-commit" (spec))
(declare-function ai-git-commit--wait-for-process
                  "../git-commit/scripts/ai-git-commit" (process))
(declare-function ai-git-commit--ensure-magit
                  "../git-commit/scripts/ai-git-commit" ())
(declare-function ai-git-commit--head-message
                  "../git-commit/scripts/ai-git-commit" ())
(declare-function ai-git-commit--normalize-paths
                  "../git-commit/scripts/ai-git-commit" (root paths))
(declare-function ai-git-commit--untracked-diff
                  "../git-commit/scripts/ai-git-commit" (&optional scope-paths))

(defconst skill-contract-tests-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(dolist (relative
         '("common/scripts/skill-runtime.el"
           "common/scripts/skill-git.el"
           "common/scripts/agent-shell-bridge.el"
           "emacs-code-navigator/scripts/emacs-code-navigator.el"
           "emacs-code-navigator/scripts/agent-shell-code-context.el"
           "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
           "emacs-gtd-assistant/scripts/agent-shell-gtd-capture.el"
           "denote-scribe/scripts/denote-scribe.el"
           "denote-scribe/scripts/agent-shell-denote-capture.el"
           "skill-usage-review/scripts/agent-shell-skill-usage-review.el"
           "org-blog-exporter/scripts/org-blog-exporter.el"
           "git-commit/scripts/ai-git-commit.el"
           "git-commit/scripts/agent-shell-git-review.el"))
  (load (expand-file-name relative skill-contract-tests-root) nil nil t))

(defconst skill-contract-tests-message-spec
  '(:type "refactor"
    :scope "skills"
    :summary "standardize compact contracts"
    :risk low
    :context "Skill facades need one predictable result shape for efficient AI calls."
    :changes ("Return data, paging metadata, and effects through shared helpers.")
    :reason "One protocol removes skill-specific parsing and unnecessary retries."
    :validation "Validated formatter, pagination, schema, and authorization contracts."
    :boundary
    "Domain capabilities remain available and external actions still require authorization.")
  "Reusable structured evidence for formatter tests.")

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

(ert-deftest facade-schemas-expose-high-value-value-constraints ()
  (let* ((navigator
          (plist-get
           (plist-get
            (emacs-code-navigator-query
             '(:operation describe :target locate))
            :data)
           :schema))
         (commit
          (plist-get
           (plist-get
            (ai-git-commit-run '(:operation describe :target commit))
            :data)
           :schema))
         (template
          (plist-get
           (plist-get
            (denote-scribe-run '(:operation describe :target template))
            :data)
           :schema)))
    (should (assq :kind (plist-get navigator :choices)))
    (should (assq :risk (plist-get commit :choices)))
    (should (assq :validation (plist-get commit :types)))
    (should (assq :language (plist-get template :choices)))))

(ert-deftest navigator-schema-validates-numeric-boolean-and-exclusive-fields ()
  (let* ((description
          (emacs-code-navigator-query
           '(:operation describe :target context)))
         (schema (plist-get (plist-get description :data) :schema))
         (types (plist-get schema :types)))
    (should (equal (cadr (assq :line types)) '(integer :min 1)))
    (should (eq (cadr (assq :definitions types)) 'boolean)))
  (dolist
      (request
       '((:operation context :file "/tmp/example.el" :line "1")
         (:operation context :file "/tmp/example.el" :line 1
                     :definitions yes)
         (:operation locate-many :query "value"
                     :directories ("/a" "/b" "/c" "/d" "/e" "/f"))
         (:operation diagnostics :file "/tmp/example.el"
                     :directory "/tmp")))
    (skill-contract-tests-assert-failure
     (emacs-code-navigator-query request)
     'needs-input 'invalid-request)))

(ert-deftest skill-facades-describe-with-standard-envelope ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let ((result (funcall call '(:operation describe))))
      (should (eq (plist-get result :status) 'ok))
      (should (eq (plist-get result :operation) 'describe))
      (should (plist-member result :data))
      (should (plist-member result :metrics))
      (should (natnump
               (plist-get (plist-get result :metrics) :elapsed-ms)))
      (should (plist-get (plist-get result :data) :operations)))))

(ert-deftest skill-facades-return-structured-invalid-requests ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let ((result (funcall call '(:operation unknown))))
      (skill-contract-tests-assert-failure
       result 'needs-input 'invalid-request)
      (should (equal
               (plist-get (plist-get result :error) :field-path)
               '(:operation))))))

(ert-deftest facade-operation-schemas-carry-elisp-owned-guidance ()
  (dolist (call (list #'emacs-code-navigator-query
                      #'emacs-gtd-execute
                      #'denote-scribe-run
                      #'org-blog-exporter-run
                      #'ai-git-commit-run))
    (let* ((description
            (plist-get (funcall call '(:operation describe)) :data))
           (operations (plist-get description :operations))
           (catalog (plist-get description :catalog)))
      (should (equal operations (mapcar (lambda (item)
                                          (plist-get item :operation))
                                        catalog)))
      (should (seq-every-p
               (lambda (item) (stringp (plist-get item :summary)))
               catalog))
      (dolist (operation operations)
        (let* ((result
                (funcall call
                         (list :operation 'describe :target operation)))
               (schema
                (plist-get (plist-get result :data) :schema)))
          (should (stringp (plist-get schema :summary))))))))

(ert-deftest navigator-workspace-symbol-stays-in-requested-project ()
  (let* ((root (make-temp-file "navigator-project-" t))
         (other-root (make-temp-file "navigator-installed-" t))
         (source (expand-file-name "sample.el" root))
         (other (expand-file-name "sample.el" other-root)))
    (unwind-protect
        (progn
          (with-temp-file source (insert "(defun sample-symbol () t)\n"))
          (with-temp-file other (insert "(defun sample-symbol () nil)\n"))
          (cl-letf (((symbol-function
                      'emacs-code-navigator--semantic-xref-backend)
                     (lambda () 'test-backend))
                    ((symbol-function 'emacs-code-navigator-project-root)
                     (lambda (_directory) root))
                    ((symbol-function 'xref-backend-apropos)
                     (lambda (_backend _pattern)
                       (list
                        (xref-make
                         "sample-symbol"
                         (xref-make-file-location other 1 0))
                        (xref-make
                         "sample-symbol"
                         (xref-make-file-location source 1 0))))))
            (let* ((noninteractive nil)
                   (matches
                    (emacs-code-navigator-workspace-symbol
                     source "sample-symbol" 10)))
              (should (= (length matches) 1))
              (should (equal (caar matches) source)))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t)
      (delete-directory other-root t))))

(ert-deftest navigator-locate-prefers-the-requested-file-imenu ()
  (let* ((root (make-temp-file "navigator-imenu-" t))
         (source (expand-file-name "sample.el" root)))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(defun requested-symbol () t)\n"))
          (cl-letf (((symbol-function
                      'emacs-code-navigator-workspace-symbol)
                     (lambda (&rest _)
                       '(("/tmp/installed/sample.el" 1 "requested-symbol")))))
            (let* ((result
                    (emacs-code-navigator-query
                     (list :operation 'locate :query "requested-symbol"
                           :file source :limit 3)))
                   (data (plist-get result :data)))
              (should (eq (plist-get data :strategy) 'imenu))
              (should (equal (caar (plist-get data :matches)) source)))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-facade-mutates-only-the-configured-file ()
  (let* ((root (make-temp-file "gtd-facade-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root)))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Personal\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (let* ((inhibit-message t)
                 (message-log-max nil)
                 (added
                  (emacs-gtd-execute
                   '(:operation add :title "Temporary task"
                     :headline "Personal")))
                 (id (plist-get (plist-get added :data) :id))
                 (listed
                  (emacs-gtd-execute
                   '(:operation list :query "Temporary task" :limit 5))))
            (should (stringp id))
            (should (= (plist-get listed :count) 1))
            (should
             (eq (plist-get
                  (emacs-gtd-execute
                   (list :operation 'delete :id id
                         :authorization 'explicit))
                  :status)
                 'ok))
            (should (= (plist-get
                        (emacs-gtd-execute
                         '(:operation list :query "Temporary task" :limit 5))
                        :count)
                       0))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-mutations-structure-missing-and-ambiguous-targets ()
  (let* ((root (make-temp-file "gtd-target-failures-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root)))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* Personal\n"
                    "** TODO Duplicate task\n"
                    "** TODO Duplicate task\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (let* ((missing-id
                  (emacs-gtd-execute
                   '(:operation set-state :id "missing-id" :state "DONE")))
                 (missing-title
                  (emacs-gtd-execute
                   '(:operation set-state :query "Absent task"
                     :state "DONE")))
                 (ambiguous
                  (emacs-gtd-execute
                   '(:operation set-state :query "Duplicate task"
                     :state "DONE"))))
            (skill-contract-tests-assert-failure
             missing-id 'needs-input 'not-found)
            (should
             (eq (plist-get (plist-get missing-id :error) :target-type)
                 'gtd-id))
            (skill-contract-tests-assert-failure
             missing-title 'needs-input 'not-found)
            (should (= (plist-get missing-title :count) 0))
            (skill-contract-tests-assert-failure
             ambiguous 'needs-input 'ambiguous)
            (should (= (plist-get ambiguous :count) 2))
            (should
             (= (length
                 (plist-get (plist-get ambiguous :data) :matches))
                2))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-conversation-capture-requires-confirmation-and-writes-structure ()
  (let* ((root (make-temp-file "gtd-capture-" t))
         (file (expand-file-name "gtd.org" root))
         (emacs-gtd-directory root)
         (emacs-gtd-file "gtd.org")
         (org-id-locations-file (expand-file-name "org-id-locations" root))
         (request
          '(:operation add-many
            :tasks
            ((:title "Trace drop action mapping"
              :headline "Deepin"
              :priority "B"
              :tags ("research" "wayland")
              :context-notes "Find the cursor update boundary."
              :properties (("SOURCE" . "agent-shell")
                           ("PROJECT" . "qt6-wayland"))
              :links
              ((:target "https://wayland.app/protocols/wayland"
                :description "Wayland protocol")
               (:target "file:/tmp/drag.cpp::42"
                :description "Drag implementation")))))))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* Personal\n* Deepin\n"))
          (with-temp-file org-id-locations-file (insert "()\n"))
          (skill-contract-tests-assert-failure
           (emacs-gtd-execute request)
           'needs-input 'authorization-required)
          (let ((result
                 (emacs-gtd-execute
                  (append request '(:authorization explicit)))))
            (should (= (plist-get result :count) 1))
            (with-temp-buffer
              (insert-file-contents file)
              (let ((text (buffer-string)))
                (should (string-match-p
                         "\\*\\* TODO \\[#B\\] Trace drop action mapping"
                         text))
                (should (string-match-p ":SOURCE:.*agent-shell" text))
                (should (string-match-p ":CONTEXT:" text))
                (should (string-match-p ":RESOURCES:" text))
                (should (string-match-p "Wayland protocol" text))))))
      (when-let* ((buffer (get-file-buffer file))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest gtd-add-many-schema-exposes-and-enforces-task-shape ()
  (let* ((description
          (emacs-gtd-execute '(:operation describe :target add-many)))
         (schema (plist-get (plist-get description :data) :schema))
         (tasks-type (cadr (assq :tasks (plist-get schema :types))))
         (task-type (cadr tasks-type)))
    (should (eq (car tasks-type) 'list-of))
    (should (eq (car task-type) 'plist))
    (should (plist-get (cdr task-type) :closed))
    (should (assq :tasks (plist-get schema :validators))))
  (let* ((result
          (emacs-gtd-execute
           '(:operation add-many :authorization explicit
             :tasks ((:title "Task" :priority "AB")))))
         (error-data (plist-get result :error)))
    (skill-contract-tests-assert-failure
     result 'needs-input 'invalid-request)
    (should (string-match-p "tasks\\[0\\]"
                            (plist-get error-data :message))))
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many :authorization explicit
      :tasks ((:title "Task" :unknown t))))
   'needs-input 'invalid-request)
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many :authorization explicit
      :tasks ((:title "Task" :context someday))))
   'needs-input 'invalid-request)
  (let ((emacs-gtd-capture-task-limit 1))
    (skill-contract-tests-assert-failure
     (emacs-gtd-execute
      '(:operation add-many :authorization explicit
        :tasks ((:title "One") (:title "Two"))))
     'needs-input 'invalid-request)))

(ert-deftest gtd-capture-prompt-is-read-only-and-suppresses-loops ()
  (let ((prompt (agent-shell-gtd-capture--prompt)))
    (should (string-match-p "Do not write to gtd.org yet" prompt))
    (should (string-match-p ":operation add-many" prompt))
    (should (string-match-p ":authorization explicit" prompt))
    (should (string-match-p ":context work" prompt)))
  (with-temp-buffer
    (setq agent-shell-gtd-capture--suppress-count 1)
    (should-not
     (agent-shell-gtd-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))
    (should
     (agent-shell-gtd-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))))

(ert-deftest gtd-capture-rejects-executable-org-links ()
  (skill-contract-tests-assert-failure
   (emacs-gtd-execute
    '(:operation add-many
      :authorization explicit
      :tasks
      ((:title "Unsafe link"
        :links ((:target "elisp:(message \"unsafe\")"))))))
   'needs-input 'invalid-request))

(ert-deftest blog-facade-exports-into-an-isolated-directory ()
  (let* ((root (make-temp-file "blog-facade-" t))
         (notes (expand-file-name "notes" root))
         (output (expand-file-name "output" root))
         (source (expand-file-name "sample.org" notes))
         (setupfile (expand-file-name "setupfile.org" notes))
         (org-blog-exporter-setupfile setupfile))
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory output)
          (with-temp-file setupfile (insert "#+options: toc:nil\n"))
          (with-temp-file source
            (insert "#+title: Temporary article\n\n* Body\nTemporary text.\n"))
          (let ((result
                 (org-blog-exporter-run
                  (list :operation 'export :files (list source)
                        :notes-dir notes :output-dir output
                        :setupfile setupfile :full t))))
            (should (eq (plist-get result :status) 'ok))
            (should (equal (plist-get result :effects)
                           '(:exported-count 1)))
            (should (file-exists-p
                     (car (plist-get (plist-get result :data) :exported))))))
      (when-let* ((buffer (get-file-buffer source))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest blog-partial-results-expose-retryable-failure-details ()
  (let ((partial
         '(:scope all
           :candidate-count 2
           :exported-count 1
           :exported ("/tmp/one.html")
           :error-count 1
           :errors (("/tmp/two.org" "Export failed"))
           :output-directory "/tmp/output")))
    (cl-letf (((symbol-function 'org-blog-exporter-export)
               (lambda (&rest _) partial)))
      (dolist (request
               '((:operation export)
                 (:operation export :full t)))
        (let* ((result (org-blog-exporter-run request))
               (error-data (plist-get result :error)))
          (skill-contract-tests-assert-failure
           result 'partial 'partial-failure)
          (should (= (plist-get error-data :failure-count) 1))
          (should (equal (plist-get error-data :causes)
                         '(("/tmp/two.org" "Export failed"))))
          (should (equal (plist-get result :effects)
                         '(:exported-count 1)))
          (should (equal (plist-get
                          (plist-get result :data) :exported)
                         '("/tmp/one.html"))))))))

(ert-deftest denote-create-writes-only-to-the-selected-notes-directory ()
  (let* ((root (make-temp-file "denote-create-" t))
         (notes (expand-file-name "notes" root))
         (sentinel (expand-file-name "outside.txt" root))
         (body (expand-file-name
                "denote-scribe/assets/critical-note-template.org"
                skill-contract-tests-root))
         (created (expand-file-name "20260720T120000--test-note.org" notes))
         (original-require (symbol-function 'require)))
    (unwind-protect
        (progn
          (make-directory notes)
          (with-temp-file sentinel (insert "unchanged"))
          (cl-letf (((symbol-function 'require)
                     (lambda (feature &optional filename noerror)
                       (if (eq feature 'denote)
                           t
                         (funcall original-require feature filename noerror))))
                    ((symbol-function 'denote)
                     (lambda (_title _keywords _file-type directory &rest _)
                       (should
                        (equal (file-name-as-directory
                                (file-truename directory))
                               (file-name-as-directory
                                (file-truename notes))))
                       (with-temp-file created (insert "#+title: Test note\n"))
                       created)))
            (should
             (equal
              (denote-scribe-create "Test note" body nil notes)
              created)))
          (should (file-in-directory-p (file-truename created)
                                       (file-truename notes)))
          (should (string-match-p
                   "\\* Question"
                   (with-temp-buffer
                     (insert-file-contents created)
                     (buffer-string))))
          (should
           (equal
            (with-temp-buffer
              (insert-file-contents sentinel)
              (buffer-string))
            "unchanged")))
      (when-let* ((buffer (get-file-buffer created))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest denote-conversation-capture-requires-explicit-authorization ()
  (let ((request
         '(:operation capture :title "Research note"
           :body-file "/tmp/body.org")))
    (cl-letf (((symbol-function 'denote-scribe-create-with-review-context)
               (lambda (&rest _)
                 '(:file "/tmp/created.org" :review-state (:review-due nil)))))
      (skill-contract-tests-assert-failure
       (denote-scribe-run request)
       'needs-input 'authorization-required)
      (let ((result
             (denote-scribe-run
              (append request '(:authorization explicit)))))
        (should (equal (plist-get (plist-get result :data) :file)
                       "/tmp/created.org"))
        (should (equal (plist-get result :effects) '(:created t)))))))

(ert-deftest denote-gtd-backlinks-preserve-critical-top-level-structure ()
  (let* ((root (make-temp-file "denote-gtd-link-" t))
         (notes (expand-file-name "notes" root))
         (note (expand-file-name
                "20260723T120000--linked-research.org" notes))
         (template (expand-file-name
                    "denote-scribe/assets/critical-note-template.org"
                    skill-contract-tests-root))
         (tasks
          '((:id "task-one" :title "Trace action mapping")
            (:id "task-two" :title "Build a minimal client"))))
    (unwind-protect
        (progn
          (make-directory notes)
          (with-temp-file note
            (insert-file-contents template))
          (skill-contract-tests-assert-failure
           (denote-scribe-run
            (list :operation 'link-gtd :file note :tasks tasks
                  :notes-dir notes))
           'needs-input 'authorization-required)
          (denote-scribe-run
           (list :operation 'link-gtd :file note :tasks tasks
                 :notes-dir notes :authorization 'explicit))
          (denote-scribe-run
           (list :operation 'link-gtd :file note :tasks tasks
                 :notes-dir notes :authorization 'explicit))
          (with-temp-buffer
            (insert-file-contents note)
            (let ((text (buffer-string)))
              (should (string-match-p
                       "\\* Open Questions\\(?:.\\|\n\\)*\\*\\* Related GTD"
                       text))
              (should (= (how-many "id:task-one" (point-min) (point-max)) 1))
              (should (= (how-many "id:task-two" (point-min) (point-max)) 1))))
          (with-temp-buffer
            (insert-file-contents note)
            (delay-mode-hooks (org-mode))
            (should
             (equal
              (denote-scribe--top-level-headings
               (denote-scribe--org-tree))
              denote-scribe-critical-headings))))
      (when-let* ((buffer (get-file-buffer note))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest denote-capture-prompt-links-gtd-in-both-directions ()
  (let ((prompt (agent-shell-denote-capture--prompt)))
    (should (string-match-p "Do not create or modify any file yet" prompt))
    (should (string-match-p ":operation capture" prompt))
    (should (string-match-p ":operation add-many" prompt))
    (should (string-match-p ":operation link-gtd" prompt))
    (should (string-match-p "file:' resource link" prompt))
    (should (string-match-p "id:' links" prompt)))
  (with-temp-buffer
    (setq agent-shell-denote-capture--suppress-count 1)
    (should-not
     (agent-shell-denote-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))
    (should
     (agent-shell-denote-capture--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))))

(ert-deftest skill-usage-review-action-is-read-only-and-tool-gated ()
  (let ((prompt (agent-shell-skill-usage-review--prompt)))
    (should (string-match-p "\\$skill-usage-review" prompt))
    (should (string-match-p "Do not rerun" prompt))
    (should (string-match-p "modify files" prompt))
    (should (string-match-p "rather than exact token usage" prompt)))
  (with-temp-buffer
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer) '(:stop-reason "end_turn")))
    (should
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "cancelled" :tool-call-ids ("call-1"))))
    (setq agent-shell-skill-usage-review--suppress-count 1)
    (should-not
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))
    (should
     (agent-shell-skill-usage-review--applicable-p
      (current-buffer)
      '(:stop-reason "end_turn" :tool-call-ids ("call-1"))))))

(ert-deftest skill-usage-review-registers-one-english-prompt-action ()
  (let ((skill-agent-shell-turn-actions nil)
        inserted)
    (cl-letf (((symbol-function 'skill-agent-shell-bridge-enable)
               #'ignore)
              ((symbol-function 'agent-shell-insert)
               (lambda (&rest arguments) (setq inserted arguments))))
      (agent-shell-skill-usage-review-enable)
      (let ((action
             (seq-find
              (lambda (entry)
                (eq (plist-get entry :id) 'skill-usage-review))
              skill-agent-shell-turn-actions)))
        (should (equal (plist-get action :label) "Review skill usage"))
        (should (= (plist-get action :priority) 10)))
      (with-temp-buffer
        (agent-shell-skill-usage-review (current-buffer))
        (should (eq (plist-get inserted :submit) t))
        (should (eq (plist-get inserted :shell-buffer) (current-buffer)))
        (should
         (equal (plist-get inserted :text)
                (agent-shell-skill-usage-review--prompt)))))))

(ert-deftest denote-hywiki-create-and-replace-stay-in-the-selected-directory ()
  (let* ((root (make-temp-file "denote-hywiki-" t))
         (hywiki (expand-file-name "hywiki" root))
         (sentinel (expand-file-name "outside.txt" root))
         (page (expand-file-name "TestConcept.org" hywiki))
         (body (expand-file-name
                "denote-scribe/assets/hywiki-concept-template.org"
                skill-contract-tests-root))
         (original-require (symbol-function 'require)))
    (unwind-protect
        (progn
          (make-directory hywiki)
          (with-temp-file sentinel (insert "unchanged"))
          (cl-letf (((symbol-function 'require)
                     (lambda (feature &optional filename noerror)
                       (if (eq feature 'hywiki)
                           t
                         (funcall original-require feature filename noerror))))
                    ((symbol-function 'hywiki-word-is-p)
                     (lambda (name) (string= name "TestConcept")))
                    ((symbol-function 'hywiki-get-existing-page-file)
                     (lambda (_name) (and (file-exists-p page) page)))
                    ((symbol-function 'hywiki-add-page)
                     (lambda (_name &optional _force)
                       (unless (file-exists-p page)
                         (with-temp-file page))
                       (cons 'page page))))
            (let ((created
                   (denote-scribe-run
                    (list :operation 'hywiki :page-name "TestConcept"
                          :body-file body :hywiki-dir hywiki))))
              (should (eq (plist-get (plist-get created :data) :status)
                          'created)))
            (skill-contract-tests-assert-failure
             (denote-scribe-run
              (list :operation 'hywiki :page-name "TestConcept"
                    :body-file body :hywiki-dir hywiki :replace t))
             'needs-input 'authorization-required)
            (let ((replaced
                   (denote-scribe-run
                    (list :operation 'hywiki :page-name "TestConcept"
                          :body-file body :hywiki-dir hywiki :replace t
                          :authorization 'explicit))))
              (should (eq (plist-get (plist-get replaced :data) :status)
                          'replaced))))
          (should (file-in-directory-p (file-truename page)
                                       (file-truename hywiki)))
          (should
           (equal
            (with-temp-buffer
              (insert-file-contents sentinel)
              (buffer-string))
            "unchanged")))
      (when-let* ((buffer (get-file-buffer page))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest facade-schemas-expose-migrated-core-operations ()
  (let ((navigator
         (plist-get
          (plist-get
           (emacs-code-navigator-query '(:operation describe)) :data)
          :operations))
        (denote
         (plist-get
          (plist-get (denote-scribe-run '(:operation describe)) :data)
          :operations))
        (gtd
         (plist-get
          (plist-get (emacs-gtd-execute '(:operation describe)) :data)
          :operations))
        (git-commit
         (plist-get
          (plist-get (ai-git-commit-run '(:operation describe)) :data)
          :operations)))
    (dolist (operation
             '(symbols region imenu file-state workspace-symbol xref locate locate-many
                       diagnostics))
      (should (memq operation navigator)))
    (should (memq 'preflight denote))
    (should (memq 'preflight gtd))
    (should (memq 'commit git-commit))
    (should (memq 'amend git-commit))))

(ert-deftest navigator-region-and-imenu-use-the-facade ()
  (let* ((file (expand-file-name "common/scripts/skill-runtime.el"
                                 skill-contract-tests-root))
         (region
          (emacs-code-navigator-query
           (list :operation 'region :file file :start-line 1 :end-line 3)))
         (imenu
          (emacs-code-navigator-query
           (list :operation 'imenu :file file))))
    (should (string-match-p "skill-runtime.el" (plist-get region :data)))
    (should (listp (plist-get imenu :data)))))

(ert-deftest navigator-source-provenance-distinguishes-live-and-disk ()
  (let* ((root (make-temp-file "navigator-source-" t))
         (file (expand-file-name "sample.el" root))
         live-buffer)
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "disk-value\n"))
          (setq live-buffer (find-file-noselect file))
          (with-current-buffer live-buffer
            (goto-char (point-max))
            (insert "live-value\n"))
          (let* ((live
                  (emacs-code-navigator-query
                   (list :operation 'region :file file :start-line 1
                         :end-line 2 :source 'live)))
                 (disk
                  (emacs-code-navigator-query
                   (list :operation 'region :file file :start-line 1
                         :end-line 2 :source 'disk)))
                 (state
                  (plist-get
                   (emacs-code-navigator-query
                    (list :operation 'file-state :file file))
                   :data)))
            (should (string-match-p "live-value" (plist-get live :data)))
            (should-not (string-match-p "live-value" (plist-get disk :data)))
            (should (eq (plist-get (plist-get live :provenance)
                                   :resolved-source)
                        'live))
            (should (eq (plist-get (plist-get disk :provenance)
                                   :resolved-source)
                        'disk))
            (should (eq (plist-get (plist-get disk :provenance) :session)
                        'batch))
            (should (eq (plist-get (plist-get disk :provenance) :degraded)
                        t))
            (should (eq (plist-get state :buffer-modified) t))
            (should (eq (plist-get state :diverged) t))))
      (when (buffer-live-p live-buffer)
        (with-current-buffer live-buffer
          (set-buffer-modified-p nil))
        (kill-buffer live-buffer))
      (delete-directory root t))))

(ert-deftest navigator-disk-source-rejects-live-semantic-queries ()
  (let* ((result
          (emacs-code-navigator-query
           '(:operation workspace-symbol :file "/tmp/sample.el"
             :pattern "sample" :source disk)))
         (error-data (plist-get result :error)))
    (skill-contract-tests-assert-failure
     result 'blocked 'unavailable)
    (should (equal (plist-get error-data :capability)
                   "Workspace-symbol queries"))
    (should (eq (plist-get error-data :actual-source) 'disk))
    (should (equal (plist-get error-data :required-source)
                   '(auto live)))))

(ert-deftest navigator-search-honors-global-limit-and-glob ()
  (let ((matches
         (emacs-code-navigator-search
          skill-contract-tests-root "emacs-code-navigator" 2 "*.el" t)))
    (should (= (length matches) 2))
    (should (seq-every-p
             (lambda (match) (string-suffix-p ".el" (car match)))
             matches))))

(ert-deftest navigator-default-context-does-not-trigger-expensive-providers ()
  (let ((file (expand-file-name "common/scripts/skill-runtime.el"
                                skill-contract-tests-root)))
    (cl-letf (((symbol-function 'emacs-code-navigator-defun-at-line)
               (lambda (&rest _) (ert-fail "defun should be opt-in")))
              ((symbol-function 'emacs-code-navigator-eldoc-at-line)
               (lambda (&rest _) (ert-fail "Eldoc should be opt-in")))
              ((symbol-function 'emacs-code-navigator-diagnostics-at-line)
               (lambda (&rest _) (ert-fail "Flymake should be opt-in"))))
      (let ((context (emacs-code-navigator-context-at-line file 3 1)))
        (should (plist-get context :symbol))
        (should (stringp (plist-get context :region)))
        (should-not (plist-member context :defun))
        (should-not (plist-member context :eldoc))
        (should-not (plist-member context :diagnostics))))))

(ert-deftest navigator-agent-shell-context-is-live-bounded-and-cheap ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "(message sample-symbol)\n")
    (goto-char (point-min))
    (search-forward "sample-symbol")
    (backward-char 1)
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 180)
          (emacs-code-navigator-agent-shell-context-radius 2)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0)
          (emacs-code-navigator-agent-shell-semantic-level 'definitions)
          request)
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (value)
                   (setq request value)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("message" (1 2 1 9) emacs-lisp-mode nil 1)
                            :region "1:(message sample-symbol)")
                     :provenance (:session live :resolved-source live
                                  :buffer-modified t :disk-diverged t)))))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "\\[live-emacs-code-context\\]" context))
          (should (string-match-p "symbol: sample-symbol" context))
          (should (<= (length context) 180))
          (should (= (plist-get
                      emacs-code-navigator-agent-shell-last-context-metrics
                      :characters)
                     (length context)))
          (should-not
           (plist-member emacs-code-navigator-agent-shell-last-context-metrics
                         :context))
          (should (eq (plist-get request :operation) 'context))
          (should (eq (plist-get request :source) 'live))
          (should (eq (plist-get request :definitions) t))
          (should (= (plist-get request :column) 21))
          (should (= (plist-get request :radius) 2)))))))

(ert-deftest navigator-agent-shell-context-formats-bounded-semantics ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample-symbol\n")
    (goto-char (point-min))
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 1200)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0)
          (emacs-code-navigator-agent-shell-semantic-level 'definitions))
      (cl-letf (((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:project-root "/tmp/"
                            :scope "Sample::method"
                            :symbol ("sample-symbol" nil emacs-lisp-mode t nil)
                            :region "1:sample-symbol"
                            :semantic
                            (:status ok :provider eglot
                             :definitions
                             (("/tmp/definition.el" 7 "sample definition"))
                             :eldoc ("sample-signature")))
                     :provenance (:session live :resolved-source live))))
                ((symbol-function 'flymake-diagnostics) (lambda (&rest _) nil)))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "scope: Sample::method" context))
          (should (string-match-p "provider=eglot" context))
          (should (string-match-p "definition.el:7" context))
          (should (string-match-p "signature: sample-signature" context)))))))

(ert-deftest navigator-agent-shell-context-falls-through-when-inapplicable ()
  (with-temp-buffer
    (should-not (emacs-code-navigator-agent-shell-context)))
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (cl-letf (((symbol-function 'emacs-code-navigator-query)
               (lambda (&rest _) (error "unavailable"))))
      (should-not (emacs-code-navigator-agent-shell-context)))))

(ert-deftest navigator-agent-shell-context-honors-tiny-hard-budget ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample")
    (let ((emacs-code-navigator-agent-shell-context-maximum-characters 8)
          (emacs-code-navigator-agent-shell-diagnostic-limit 0))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("sample" nil emacs-lisp-mode nil nil)
                            :region "1:sample")
                     :provenance (:session live :resolved-source live)))))
        (should (= (length (emacs-code-navigator-agent-shell-context)) 8))))))

(ert-deftest navigator-agent-shell-context-reads-existing-diagnostics-only ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-agent-shell.el")
    (insert "sample\n")
    (let ((flymake-mode t)
          (emacs-code-navigator-agent-shell-context-maximum-characters 1200)
          (emacs-code-navigator-agent-shell-diagnostic-limit 1))
      (cl-letf (((symbol-function 'project-current) (lambda (&rest _) nil))
                ((symbol-function 'emacs-code-navigator-query)
                 (lambda (&rest _)
                   '(:status ok :operation context :count 1
                     :data (:symbol ("sample" nil emacs-lisp-mode nil nil)
                            :region "1:sample")
                     :provenance (:session live :resolved-source live))))
                ((symbol-function 'flymake-diagnostics)
                 (lambda (&rest _) '(first second)))
                ((symbol-function 'flymake-diagnostic-beg)
                 (lambda (&rest _) (point-min)))
                ((symbol-function 'flymake-diagnostic-end)
                 (lambda (&rest _) (point-max)))
                ((symbol-function 'flymake-diagnostic-type)
                 (lambda (&rest _) 'warning))
                ((symbol-function 'flymake-diagnostic-text)
                 (lambda (diagnostic) (format "%s diagnostic" diagnostic)))
                ((symbol-function 'flymake-start)
                 (lambda (&rest _) (ert-fail "Flymake must not be started"))))
        (let ((context (emacs-code-navigator-agent-shell-context)))
          (should (string-match-p "first diagnostic" context))
          (should-not (string-match-p "second diagnostic" context)))))))

(ert-deftest navigator-agent-shell-enable-preserves-explicit-priority ()
  (let ((agent-shell-context-sources
         '(files region error emacs-code-navigator-agent-shell-context
                 line custom-source))
        (skill-agent-shell-context-providers nil))
    (cl-letf (((symbol-function 'featurep)
               (lambda (feature)
                 (eq feature 'agent-shell)))
              ((symbol-function 'skill-agent-shell--assert-compatible)
               #'ignore))
      (emacs-code-navigator-agent-shell-enable)
      (emacs-code-navigator-agent-shell-enable))
    (should
     (equal agent-shell-context-sources
            '(region error skill-agent-shell-context
                     files line custom-source)))
    (should (= (length skill-agent-shell-context-providers) 1))
    (should (eq (plist-get (car skill-agent-shell-context-providers) :id)
                'emacs-code-navigator))))

(ert-deftest agent-shell-bridge-reports-version-and-api-compatibility ()
  (let ((agent-shell--version skill-agent-shell-minimum-version)
        (agent-shell-context-sources '(files region error line))
        (agent-shell-mode-hook nil))
    (cl-letf (((symbol-function 'agent-shell-subscribe-to) #'ignore)
              ((symbol-function 'agent-shell-unsubscribe) #'ignore))
      (let ((diagnostics (skill-agent-shell-compatibility)))
        (should (plist-get diagnostics :compatible))
        (should-not (plist-get diagnostics :missing)))
      (let ((agent-shell--version "0.63.2"))
        (should-error (skill-agent-shell--assert-compatible)
                      :type 'user-error))
      (let ((original-fboundp (symbol-function 'fboundp)))
        (cl-letf (((symbol-function 'fboundp)
                   (lambda (symbol)
                     (and (not (eq symbol 'agent-shell-unsubscribe))
                          (funcall original-fboundp symbol)))))
          (let ((diagnostics (skill-agent-shell-compatibility)))
            (should-not (plist-get diagnostics :compatible))
            (should
             (memq 'agent-shell-unsubscribe
                   (plist-get diagnostics :missing)))))))))

(ert-deftest agent-shell-bridge-shares-one-hard-context-budget ()
  (let ((skill-agent-shell-context-providers nil)
        (skill-agent-shell-context-maximum-characters 12))
    (skill-agent-shell-register-context-provider
     'first :function (lambda () "abcdefgh") :priority 20)
    (skill-agent-shell-register-context-provider
     'broken :function (lambda () (error "unavailable")) :priority 15)
    (skill-agent-shell-register-context-provider
     'second :function (lambda () "ijklmnop") :priority 10)
    (let ((context (skill-agent-shell-context)))
      (should (= (length context) 12))
      (should (string-prefix-p "abcdefgh" context))
      (should (= (length
                  (plist-get skill-agent-shell-last-context-metrics
                             :providers))
                 3))
      (should-not
       (string-match-p "unavailable"
                       (prin1-to-string
                        skill-agent-shell-last-context-metrics))))))

(ert-deftest agent-shell-bridge-tracks-structured-turn-paths ()
  (with-temp-buffer
    (let ((skill-agent-shell-turn-actions nil)
          observed)
      (setq default-directory "/tmp/")
      (skill-agent-shell-register-turn-action
       'observe
       :function (lambda (_buffer state) (setq observed state))
       :command (lambda (&rest _) nil)
       :label "Observe turn")
      (skill-agent-shell--handle-event
       (current-buffer) '((:event . input-submitted)))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . file-write)
         (:data . ((:path . "one.el")))))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . tool-call-update)
         (:data
          . ((:tool-call
              . ((:diffs
                  . (((:file . "/tmp/two.el"))
                     ((:file . "/tmp/one.el"))))))))))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . turn-complete)
         (:data . ((:stop-reason . "end_turn")))))
      (should observed)
      (should
       (equal (skill-agent-shell-current-turn-paths (current-buffer))
              '("/tmp/one.el" "/tmp/two.el")))
      (should (equal (plist-get observed :stop-reason) "end_turn")))))

(ert-deftest agent-shell-bridge-offers-english-actions-without-file-writes ()
  (with-temp-buffer
    (let ((skill-agent-shell-turn-actions nil)
          (skill-agent-shell-notify-turn-actions nil))
      (skill-agent-shell-register-turn-action
       'capture
       :command (lambda (&rest _) nil)
       :label "Capture as GTD")
      (skill-agent-shell--handle-event
       (current-buffer) '((:event . input-submitted)))
      (skill-agent-shell--handle-event
       (current-buffer)
       '((:event . turn-complete)
         (:data . ((:stop-reason . "end_turn")))))
      (should
       (equal (mapcar (lambda (entry) (plist-get entry :label))
                      skill-agent-shell--available-actions)
              '("Capture as GTD"))))))

(ert-deftest navigator-semantic-context-uses-the-exact-column-and-limit ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (setq buffer-file-name "/tmp/navigator-semantic.el")
    (insert "alpha beta\n")
    (let (seen-identifier)
      (cl-letf (((symbol-function 'emacs-code-navigator--require-live-semantic)
                 (lambda (&rest _) t))
                ((symbol-function 'emacs-code-navigator--file-buffer)
                 (lambda (&rest _) (current-buffer)))
                ((symbol-function 'emacs-code-navigator--semantic-xref-backend)
                 (lambda () 'test-backend))
                ((symbol-function 'xref-backend-definitions)
                 (lambda (_backend identifier)
                   (setq seen-identifier identifier)
                   '(first second third)))
                ((symbol-function 'emacs-code-navigator--xref-location-data)
                 (lambda (item) (list "/tmp/definition.el" 1 (format "%s" item))))
                ((symbol-function 'emacs-code-navigator-eldoc-at-line)
                 (lambda (&rest _) '("beta-signature"))))
        (let ((semantic
               (emacs-code-navigator-semantic-at-position
                buffer-file-name 1 7 t 2 t 200)))
          (should (equal seen-identifier "beta"))
          (should (eq (plist-get semantic :status) 'ok))
          (should (= (length (plist-get semantic :definitions)) 2))
          (should (equal (plist-get semantic :eldoc) '("beta-signature"))))))))

(ert-deftest navigator-semantic-buffer-policy-opens-and-safely-cleans-anchor ()
  (let* ((root (make-temp-file "navigator-semantic-root-" t))
         (file (expand-file-name "anchor.cpp" root))
         (emacs-code-navigator-semantic-buffer-policy 'open-on-demand)
         (emacs-code-navigator-semantic-buffer-limit 1)
         (emacs-code-navigator--semantic-buffers nil))
    (unwind-protect
        (progn
          (with-temp-file file (insert "void sample();\n"))
          (cl-letf (((symbol-function 'emacs-code-navigator-project-root)
                     (lambda (&rest _) root))
                    ((symbol-function 'emacs-code-navigator-search)
                     (lambda (&rest _) (list (list file 1 "sample")))))
            (let* ((anchor
                    (emacs-code-navigator--semantic-anchor root "sample"))
                   (buffer (plist-get anchor :buffer)))
              (should (eq (plist-get anchor :origin) 'navigator-opened))
              (should (buffer-live-p buffer))
              (with-current-buffer buffer (set-buffer-modified-p t))
              (should (= (emacs-code-navigator-close-semantic-buffers) 0))
              (should (buffer-live-p buffer))
              (with-current-buffer buffer (set-buffer-modified-p nil))
              (should (= (emacs-code-navigator-close-semantic-buffers) 1))
              (should-not (buffer-live-p buffer)))))
      (dolist (buffer emacs-code-navigator--semantic-buffers)
        (when (buffer-live-p buffer) (kill-buffer buffer)))
      (delete-directory root t))))

(ert-deftest navigator-locate-many-preserves-order-and-isolates-errors ()
  (cl-letf (((symbol-function 'emacs-code-navigator--locate-many-project)
             (lambda (directory &rest _)
               (if (string-match-p "broken" directory)
                   (error "broken project")
                 (list :directory directory :strategy 'text
                       :matches (list directory))))))
    (let* ((result
            (emacs-code-navigator-query
             '(:operation locate-many :query "drag"
               :directories ("/tmp/one" "/tmp/broken" "/tmp/three"))))
           (projects (plist-get result :data)))
      (should (equal (mapcar (lambda (item) (plist-get item :directory)) projects)
                     '("/tmp/one" "/tmp/broken" "/tmp/three")))
      (should (eq (plist-get (nth 1 projects) :status) 'error))
      (should (equal (plist-get (nth 2 projects) :matches)
                     '("/tmp/three"))))))

(ert-deftest navigator-locate-many-falls-back-to-bounded-disk-search ()
  (let ((emacs-code-navigator-semantic-buffer-policy 'existing-only))
    (cl-letf (((symbol-function 'emacs-code-navigator-project-root)
               (lambda (directory) (file-name-as-directory directory)))
              ((symbol-function 'emacs-code-navigator--semantic-anchor)
               (lambda (directory _query)
                 (list :origin 'none :project-root directory)))
              ((symbol-function 'emacs-code-navigator--locate-request)
               (lambda (request)
                 (should (eq (plist-get request :kind) 'text))
                 (list :strategy 'text :matches '(("drag.cpp" 4 "drag"))))))
      (let ((project
             (emacs-code-navigator--locate-many-project
              "/tmp/project" "drag" 'auto 3 nil nil 'auto)))
        (should (eq (plist-get project :source) 'disk))
        (should (eq (plist-get project :strategy) 'text))
        (should (= (length (plist-get project :matches)) 1))))))

(ert-deftest navigator-semantic-backend-runs-only-eglot-deferred-hook ()
  (require 'eglot)
  (with-temp-buffer
    (let ((unrelated-hook-ran nil)
          (eglot-hook-ran nil))
      (setq buffer-file-name "/tmp/navigator-eglot.el")
      (setq-local post-command-hook
                  (list (lambda () (setq unrelated-hook-ran t))))
      (cl-letf (((symbol-function 'eglot-managed-p) (lambda () nil))
                ((symbol-function 'eglot-ensure)
                 (lambda ()
                   (add-hook
                    'post-command-hook
                    (lambda () (setq eglot-hook-ran t))
                    'append t)))
                ((symbol-function 'xref-find-backend)
                 (lambda () (and eglot-hook-ran 'semantic-backend))))
        (should
         (eq (emacs-code-navigator--semantic-xref-backend)
             'semantic-backend))
        (should eglot-hook-ran)
        (should-not unrelated-hook-ran)))))

(ert-deftest navigator-locate-prefers-workspace-symbol-and-falls-back-to-text ()
  (let ((symbol-match '(("symbol.cpp" 4 "Widget")))
        (text-match '(("usage.cpp" 9 "Widget widget;"))))
    (cl-letf (((symbol-function 'emacs-code-navigator-workspace-symbol)
               (lambda (&rest _) symbol-match))
              ((symbol-function 'emacs-code-navigator-search)
               (lambda (&rest _) (ert-fail "text fallback should not run"))))
      (let ((result
             (plist-get
              (emacs-code-navigator-query
               '(:operation locate :query "Widget" :file "/tmp/context.cpp"))
              :data)))
        (should (eq (plist-get result :strategy) 'workspace-symbol))
        (should (equal (plist-get result :matches) symbol-match))))
    (cl-letf (((symbol-function 'emacs-code-navigator-workspace-symbol)
               (lambda (&rest _) nil))
              ((symbol-function 'emacs-code-navigator-search)
               (lambda (&rest _) text-match)))
      (let ((result
             (plist-get
              (emacs-code-navigator-query
               '(:operation locate :query "Widget" :file "/tmp/context.cpp"))
              :data)))
        (should (eq (plist-get result :strategy) 'text-fallback))
        (should (equal (plist-get result :matches) text-match))))))

(ert-deftest preflight-operations-return-standard-envelopes ()
  (dolist (result
           (list (denote-scribe-run '(:operation preflight))
                 (emacs-gtd-execute '(:operation preflight))))
    (should (memq (plist-get result :status) '(ok blocked)))
    (should (eq (plist-get result :operation) 'preflight))
    (should (plist-member result :data))))

(ert-deftest removed-compatibility-symbols-stay-absent ()
  (dolist (symbol '(treeland-commit-context treeland-commit-format
                    treeland-commit-run denote-scribe-git-hywiki-state))
    (should-not (fboundp symbol)))
  (dolist (symbol '(treeland-commit-fill-column
                    treeland-commit-maximum-column
                    treeland-commit-context-maximum-characters
                    treeland-commit-compact-maximum-characters
                    denote-scribe-hywiki-commit-interval
                    denote-scribe-hywiki-commit-marker))
    (should-not (boundp symbol)))
  (should-not (featurep 'treeland-commit)))

(ert-deftest navigator-reports-documentation-truncation ()
  (let* ((emacs-code-navigator-documentation-maximum-characters 3)
         (facet (emacs-code-navigator--compact-facet
                 '(:symbol "sample" :kinds (function)
                   :documentation "abcdef" :source nil))))
    (should (equal (plist-get facet :documentation) "abc"))
    (should (eq (plist-get facet :documentation-truncated) t))
    (should (= (plist-get facet :documentation-original-length) 6))))

(ert-deftest navigator-batches-known-and-missing-symbols-in-order ()
  (let* ((missing "emacs-code-navigator-test-missing-symbol")
         (noninteractive nil)
         (result
          (emacs-code-navigator-query
           (list :operation 'symbols :names (list 'car missing 'user-init-file))))
         (data (plist-get result :data))
         (provenance (plist-get result :provenance)))
    (should (= (plist-get result :count) 3))
    (should (equal (mapcar (lambda (item) (plist-get item :symbol)) data)
                   (list "car" missing "user-init-file")))
    (should (eq (plist-get (nth 0 data) :found) t))
    (should-not (plist-get (nth 1 data) :found))
    (should (stringp (plist-get (nth 1 data) :error)))
    (should (eq (plist-get (nth 2 data) :found) t))
    (should (eq (plist-get provenance :session) 'live))
    (should (eq (plist-get provenance :resolved-source) 'session))))

(ert-deftest navigator-batch-symbol-limit-is-enforced ()
  (let ((emacs-code-navigator-symbol-batch-limit 2))
    (should-error
     (emacs-code-navigator-symbols '(car cdr cons)))))

(ert-deftest git-message-auto-compacts-low-risk-work ()
  (let ((message (ai-git-commit-format skill-contract-tests-message-spec)))
    (should-not (string-match-p "Domain capabilities" message))
    (should-not (string-match-p skill-git--body-label-regexp message))
    (should (seq-every-p
             (lambda (line) (<= (string-width line) 100))
             (split-string message "\n")))))

(ert-deftest git-message-full-preserves-boundary ()
  (let ((message
         (ai-git-commit-format
          (plist-put (copy-sequence skill-contract-tests-message-spec)
                     :detail 'full))))
    (should (string-match-p "Domain capabilities" message))))

(ert-deftest git-message-keeps-validation-internal-by-default ()
  (let ((ai-git-commit-include-validation-in-message nil)
        (message
         (ai-git-commit-format
          (plist-put (copy-sequence skill-contract-tests-message-spec)
                     :detail 'full))))
    (should-not (string-match-p "Validated formatter" message))
    (should (string-match-p "Domain capabilities" message)))
  (let ((ai-git-commit-include-validation-in-message t))
    (should
     (string-match-p
      "Validated formatter"
      (ai-git-commit-format
       (plist-put (copy-sequence skill-contract-tests-message-spec)
                  :detail 'full))))))

(ert-deftest agent-shell-git-request-preserves-advisory-boundary ()
  (with-temp-buffer
    (setq-local skill-agent-shell--last-completed-turn
                '(:paths (("/tmp/repository/one.el" . file-write))))
    (cl-letf (((symbol-function 'agent-shell-git-review--root)
               (lambda (_path) "/tmp/repository/")))
      (let ((text
             (agent-shell-git-review--request-text
              (current-buffer) 'commit)))
        (should (string-match-p "re-read actual Git/Magit" text))
        (should (string-match-p "/tmp/repository/one.el" text))
        (should (string-match-p "omit test results" text))))))

(ert-deftest git-message-auto-compacts-routine-medium-risk-work ()
  (let* ((spec (copy-sequence skill-contract-tests-message-spec))
         (spec (plist-put spec :risk 'medium))
         (spec (plist-put spec :changes
                          '("Add bounded untracked-file evidence."
                            "Stage an explicit path set."
                            "Document the compact workflow.")))
         (message (ai-git-commit-format spec)))
    (should-not (string-match-p "Domain capabilities" message))))

(ert-deftest git-context-collects-bounded-untracked-diffs ()
  (let ((ai-git-commit-untracked-file-maximum-characters 24))
    (cl-letf (((symbol-function 'magit-git-lines)
               (lambda (&rest _) '("new.el")))
              ((symbol-function 'magit-git-insert)
               (lambda (&rest _)
                 (insert "diff --git a/new.el b/new.el\n+some long new content\n")
                 1)))
      (let ((result (ai-git-commit--untracked-diff)))
        (should (equal (plist-get result :files) '("new.el")))
        (should (string-prefix-p "diff --git" (plist-get result :text)))
        (should (eq (plist-get result :truncated) t))))))

(ert-deftest git-context-paths-hide-global-status-names ()
  (let ((original-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &rest arguments)
                 (if (eq feature 'magit)
                     t
                   (apply original-require feature arguments))))
              ((symbol-function 'magit-toplevel) (lambda (&rest _) "/repo/"))
              ((symbol-function 'ai-git-commit--normalize-paths)
               (lambda (&rest _) '("target.el")))
              ((symbol-function 'ai-git-commit--git-output)
               (lambda (&rest _)
                 " M target.el\n?? unrelated-secret.el"))
              ((symbol-function 'ai-git-commit--git-output-for-paths)
               (lambda (arguments _paths)
                 (if (equal (car arguments) "status") " M target.el" "")))
              ((symbol-function 'ai-git-commit--untracked-diff)
               (lambda (&rest _)
                 '(:text "" :files nil :truncated nil)))
              ((symbol-function 'magit-git-success) (lambda (&rest _) t)))
      (let ((data
             (ai-git-commit-context "/repo/" t '("target.el"))))
        (should (equal (plist-get data :status) " M target.el"))
        (should (= (plist-get data :change-count) 1))
        (should (= (plist-get data :excluded-change-count) 1))
        (should-not
         (string-match-p "unrelated-secret.el"
                         (plist-get data :status)))))))

(ert-deftest git-context-paths-exclude-unrelated-untracked-content ()
  (unless (require 'magit nil t)
    (ert-skip "Magit is unavailable in the pure -Q contract environment"))
  (let* ((root (make-temp-file "git-context-scope-" t))
         (default-directory root)
         (target (expand-file-name "target.el" root))
         (new (expand-file-name "new.el" root))
         (unrelated (expand-file-name "unrelated-secret.el" root)))
    (unwind-protect
        (progn
          (should (zerop (call-process "git" nil nil nil "init" "-q")))
          (with-temp-file target (insert "baseline\n"))
          (should (zerop (call-process "git" nil nil nil "add" "target.el")))
          (should
           (zerop
            (call-process "git" nil nil nil
                          "-c" "user.name=Skill Test"
                          "-c" "user.email=skill@example.invalid"
                          "commit" "-q" "-m" "baseline")))
          (with-temp-file target (insert "changed target\n"))
          (with-temp-file new (insert "new scoped content\n"))
          (with-temp-file unrelated (insert "UNRELATED-SECRET-CONTENT\n"))
          (let* ((result
                  (ai-git-commit-run
                   (list :operation 'context :directory root
                         :paths '("target.el" "new.el"))))
                 (data (plist-get result :data))
                 (diff (plist-get data :diff)))
            (should (equal (plist-get data :diff-scope)
                           '("target.el" "new.el")))
            (should (= (plist-get data :change-count) 2))
            (should (= (plist-get data :excluded-change-count) 1))
            (should (equal (plist-get data :status)
                           (plist-get data :scoped-status)))
            (should-not (string-match-p "unrelated-secret.el"
                                        (plist-get data :status)))
            (should-not (string-match-p "UNRELATED-SECRET-CONTENT" diff))
            (should (string-match-p "changed target" diff))
            (should (string-match-p "new scoped content" diff))))
      (delete-directory root t))))

(ert-deftest git-path-validation-allows-tracked-deletions-and-rejects-escape ()
  (let ((root (make-temp-file "git-commit-paths-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'magit-git-lines)
                   (lambda (&rest _) '("gone.el"))))
          (should (equal (ai-git-commit--normalize-paths
                          root '("gone.el" "gone.el"))
                         '("gone.el")))
          (should-error
           (ai-git-commit--normalize-paths root '("../outside.el"))))
      (delete-directory root t))))

(ert-deftest git-message-rejects-labels-and-missing-evidence ()
  (should-error
   (ai-git-commit-format
    (plist-put (copy-sequence skill-contract-tests-message-spec)
               :context "Context: redundant label")))
  (should-error
   (ai-git-commit-format '(:type "fix" :summary "reject incomplete input"))))

(ert-deftest destructive-facades-require-authorization-before-effects ()
  (dolist
      (result
       (list
        (emacs-gtd-execute '(:operation delete :id "sample"))
        (denote-scribe-run
         '(:operation commit :title "Review note" :paths ("note.org")))
        (org-blog-exporter-run '(:operation publish))
        (ai-git-commit-run
         (append '(:operation commit) skill-contract-tests-message-spec))))
    (skill-contract-tests-assert-failure
     result 'needs-input 'authorization-required)
    (should-not (plist-get result :effects))))

(ert-deftest git-commit-facade-uses-one-headless-magit-message-argument ()
  (let (captured)
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'ai-git-commit--ensure-magit)
               (lambda () t))
              ((symbol-function 'magit-commit-create)
               (lambda (arguments)
                 (should (= magit-process-popup-time -1))
                 (should (eq magit-display-buffer-noselect t))
                 (should (eq inhibit-message t))
                 (should (null message-log-max))
                 (setq captured arguments)
                 'fake-process))
              ((symbol-function 'ai-git-commit--wait-for-process)
               (lambda (process)
                 (should (eq process 'fake-process))
                 (should (= magit-process-popup-time -1))
                 (should (eq magit-display-buffer-noselect t))
                 (should (eq inhibit-message t))
                 (should (null message-log-max))
                 0))
              ((symbol-function 'ai-git-commit--head-message)
               (lambda () (concat (nth 2 captured) "\n")))
              ((symbol-function 'magit-rev-parse)
               (lambda (&rest _) "abc123")))
      (let* ((request
              (append '(:operation commit :authorization explicit)
                      skill-contract-tests-message-spec))
             (expected (ai-git-commit-format request))
             (result (ai-git-commit-run request)))
        (should (equal captured
                       (list "--cleanup=verbatim" "-m" expected)))
        (should (equal (plist-get (plist-get result :data) :commit) "abc123"))
        (should (equal (plist-get result :effects)
                       '(:committed t :amended nil)))))))

(ert-deftest git-commit-facade-stages-and-commits-only-explicit-paths ()
  (let (commit-arguments stage-arguments)
    (cl-letf (((symbol-function 'magit-toplevel)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'ai-git-commit--ensure-magit)
               (lambda () t))
              ((symbol-function 'ai-git-commit--normalize-paths)
               (lambda (_root _paths) '("new.el" "gone.el")))
              ((symbol-function 'magit-call-git)
               (lambda (&rest arguments)
                 (setq stage-arguments arguments)
                 0))
              ((symbol-function 'magit-commit-create)
               (lambda (arguments)
                 (setq commit-arguments arguments)
                 'fake-process))
              ((symbol-function 'ai-git-commit--wait-for-process)
               (lambda (_) 0))
              ((symbol-function 'ai-git-commit--head-message)
               (lambda () (concat (nth 2 commit-arguments) "\n")))
              ((symbol-function 'magit-rev-parse)
               (lambda (&rest _) "abc123")))
      (let* ((request
              (append '(:operation commit :authorization explicit
                        :paths ("new.el" "gone.el"))
                      skill-contract-tests-message-spec))
             (result (ai-git-commit-run request)))
        (should (equal stage-arguments
                       '("add" "--" "new.el" "gone.el")))
        (should (equal (last commit-arguments 4)
                       '("--only" "--" "new.el" "gone.el")))
        (should (equal (plist-get (plist-get result :data) :paths)
                       '("new.el" "gone.el")))))))

(ert-deftest git-amend-facade-verifies-committed-message ()
  (cl-letf (((symbol-function 'magit-toplevel)
             (lambda (&optional _) "/tmp/repository/"))
            ((symbol-function 'ai-git-commit--ensure-magit)
             (lambda () t))
            ((symbol-function 'magit-commit-amend)
             (lambda (_arguments) 'fake-process))
            ((symbol-function 'ai-git-commit--wait-for-process)
             (lambda (_) 0))
            ((symbol-function 'ai-git-commit--head-message)
             (lambda () "different message\n"))
            ((symbol-function 'magit-rev-parse)
             (lambda (&rest _) "abc123")))
    (should-error
     (ai-git-commit-run
      (append '(:operation amend :authorization explicit)
              skill-contract-tests-message-spec))
     :type 'error)))

(ert-deftest git-commit-head-message-keeps-the-complete-body ()
  (cl-letf (((symbol-function 'magit-rev-insert-format)
             (lambda (&rest _)
               (insert "subject\n\nbody\n")
               0)))
    (should (equal (ai-git-commit--head-message)
                   "subject\n\nbody\n"))))

(ert-deftest denote-internal-commit-uses-shared-full-message ()
  (let (captured)
    (cl-letf (((symbol-function 'denote-scribe--git-root)
               (lambda (&optional _) "/tmp/repository/"))
              ((symbol-function 'skill-git-commit-paths)
               (lambda (_root message _paths &rest _)
                 (setq captured message)
                 '(:commit "abc123"))))
      (denote-scribe-git-commit "record result" '("note.org") nil))
    (should (string-prefix-p "feat(notes): record result" captured))
    (should (string-match-p "\n\n" captured))
    (should-not (string-match-p skill-git--body-label-regexp captured))))

(ert-deftest blog-internal-commit-uses-shared-full-message ()
  (let (captured)
    (cl-letf (((symbol-function 'skill-git-relative-path)
               (lambda (_root path &rest _) path))
              ((symbol-function 'skill-git-status)
               (lambda (&rest _) " M page.html"))
              ((symbol-function 'skill-git-commit-paths)
               (lambda (_root message _paths &rest _)
                 (setq captured message)
                 '(:commit "abc123")))
              ((symbol-function 'skill-git-assert-clean) (lambda (_) t))
              ((symbol-function 'skill-git-push)
               (lambda (_) '(:commit "abc123"))))
      (org-blog-exporter--finish-publish
       '(:git-root "/tmp/repository/") '("page.html") "publish page"))
    (should (string-prefix-p "chore(blog): publish page" captured))
    (should (string-match-p "\n\n" captured))
    (should-not (string-match-p skill-git--body-label-regexp captured))))

(ert-deftest blog-effects-report-export-and-publish-mutations ()
  (should
   (equal (org-blog-exporter--effects
           'export '(:exported ("one.html" "two.html")))
          '(:exported-count 2)))
  (should
   (equal (org-blog-exporter--effects
           'publish '(:exported-count 1 :changed t :commit "abc" :push t))
          '(:exported-count 1 :changed t :commit "abc" :push t))))

(provide 'skill-contract-tests)

;;; skill-contract-tests.el ends here
