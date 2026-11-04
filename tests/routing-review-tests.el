;;; routing-review-tests.el --- Validate routing review fixtures -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)
(require 'routing-cases)
(require 'routing-evaluation)

(skill-tests-load-many
 '("emacs-code-navigator/scripts/emacs-code-navigator.el"
   "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
   "denote-scribe/scripts/denote-scribe.el"
   "org-blog-exporter/scripts/org-blog-exporter.el"
   "git-commit/scripts/ai-git-commit.el"))

(defconst skill-routing-review-test-schemas
  '((emacs-code-navigator . emacs-code-navigator--schemas)
    (emacs-gtd-assistant . emacs-gtd--schemas)
    (denote-scribe . denote-scribe--schemas)
    (org-blog-exporter . org-blog-exporter--schemas)
    (git-commit . ai-git-commit--schemas)))

(defconst skill-routing-review-test-case-classes
  '(positive negative ambiguous unauthorized partial-recovery schema-mismatch
             false-completion))

(defconst skill-routing-review-test-controls
  '(execute answer-without-skill ask-and-stop inspect-and-retry-selectively
            describe-and-retry-once report-incomplete))

(defun skill-routing-review-test-assert-case (case)
  "Assert the routing fixture CASE has explicit, consistent boundaries."
  (should (proper-list-p case))
  (should (zerop (% (length case) 2)))
  (let* ((required '(:id :case-class :request :expected :excluded
                    :expected-operations :mutation :control :completion :reason))
         (keys (cl-loop for (key _) on case by #'cddr collect key))
         (expected (plist-get case :expected))
         (excluded (plist-get case :excluded))
         (operations (plist-get case :expected-operations))
         (control (plist-get case :control))
         (completion (plist-get case :completion)))
    (should (equal keys (seq-uniq keys)))
    (dolist (key required)
      (should (plist-member case key)))
    (dolist (key keys)
      (should (memq key (append '(:completion-condition :history :expected-arguments)
                               required))))
    (should (plist-get case :id))
    (should (symbolp (plist-get case :id)))
    (dolist (key '(:request :reason))
      (should (stringp (plist-get case key)))
      (should-not (string-empty-p (string-trim (plist-get case key)))))
    (should (memq (plist-get case :case-class)
                  skill-routing-review-test-case-classes))
    (dolist (skills (list expected excluded))
      (should (proper-list-p skills))
      (should (equal skills (seq-uniq skills)))
      (dolist (skill skills)
        (should (assq skill skill-routing-review-test-schemas))
        (should (file-readable-p
                 (expand-file-name (format "%s/SKILL.md" skill)
                                   skill-contract-tests-root)))))
    (should (or expected excluded))
    (should-not (seq-intersection expected excluded))
    (should (memq (plist-get case :mutation) '(allowed forbidden conditional)))
    (should (memq control skill-routing-review-test-controls))
    (should (memq completion '(allowed forbidden conditional)))
    (if (eq completion 'conditional)
        (progn
          (should (stringp (plist-get case :completion-condition)))
          (should-not (string-empty-p
                       (string-trim (plist-get case :completion-condition)))))
      (should-not (plist-member case :completion-condition)))
    (should (proper-list-p operations))
    (dolist (entry operations)
      (should (consp entry))
      (should (memq (car entry) expected))
      (should (cdr entry))
      (should (symbolp (cdr entry)))
      (should (assq (cdr entry)
                    (symbol-value (alist-get (car entry)
                                             skill-routing-review-test-schemas)))))
    (should (equal (mapcar #'car operations)
                   (seq-uniq (mapcar #'car operations))))
    (let ((arguments (plist-get case :expected-arguments)))
      (should (proper-list-p arguments))
      (should (equal (mapcar #'car arguments) (seq-uniq (mapcar #'car arguments))))
      (dolist (entry arguments)
        (let* ((operation (cdr (assq (car entry) operations)))
               (schemas (symbol-value
                         (alist-get (car entry) skill-routing-review-test-schemas)))
               (fields (cdr entry)))
          (should operation)
          (should fields)
          (skill-runtime--validate-plist-keys fields nil)
          (while fields
            (should-not (eq (car fields) :operation))
            (should (memq (car fields)
                          (skill-runtime--declared-fields (alist-get operation schemas))))
            (setq fields (cddr fields))))))
    (when (memq control '(execute inspect-and-retry-selectively
                         describe-and-retry-once))
      (should expected)
      (should (= (length expected) (length operations))))
    (when (memq control '(answer-without-skill ask-and-stop report-incomplete))
      (should-not operations))
    (when (eq control 'answer-without-skill)
      (should-not expected)
      (should (eq (plist-get case :mutation) 'forbidden)))
    (when (memq control '(ask-and-stop report-incomplete))
      (should (eq (plist-get case :mutation) 'forbidden))
      (should (eq completion 'forbidden)))
    (when (eq control 'describe-and-retry-once)
      (should operations)
      (should (seq-every-p (lambda (entry) (eq (cdr entry) 'describe)) operations))
      (should (eq (plist-get case :mutation) 'conditional))
      (should (eq completion 'conditional)))
    (when (eq control 'inspect-and-retry-selectively)
      (should (eq (plist-get case :mutation) 'conditional))
      (should (eq completion 'conditional)))))

(defun skill-routing-review-test-assert-history (case)
  "Assert CASE includes the session evidence needed for a recovery decision."
  (let ((history (plist-get case :history)))
    (should (proper-list-p history))
    (when (memq (plist-get case :case-class)
                '(partial-recovery schema-mismatch false-completion))
      (should (eq (plist-get (car history) :role) 'user))
      (should (eq (plist-get (car (last history)) :role) 'tool)))
    (dolist (message history)
      (should (memq (plist-get message :role) '(user assistant tool)))
      (if (eq (plist-get message :role) 'tool)
          (let* ((request (plist-get message :request))
                 (result (plist-get message :result))
                 (operation (plist-get request :operation)))
            (should (assq (plist-get message :skill)
                          skill-routing-review-test-schemas))
            (should operation)
            (should (= (plist-get result :protocol-version) 2))
            (should (eq operation (plist-get result :operation)))
            (should (memq (plist-get result :status)
                          '(ok partial needs-input blocked failed)))
            (when (eq (plist-get result :status) 'partial)
              (should (plist-get result :effects))
              (should (plist-get result :verification))))
        (should (stringp (plist-get message :content)))
        (should-not (string-empty-p (plist-get message :content)))))
    (dolist (entry (plist-get case :expected-operations))
      (when (eq (cdr entry) 'resume)
        (let* ((latest (seq-find
                        (lambda (message)
                          (and (eq (plist-get message :role) 'tool)
                               (eq (plist-get message :skill) (car entry))))
                        (reverse history)))
               (result (plist-get latest :result))
               (token (plist-get (plist-get result :error) :recovery-token)))
          (should (eq (plist-get result :status) 'partial))
          (should (stringp token))
          (should-not (string-empty-p (string-trim token)))
          (when-let* ((arguments (alist-get (car entry)
                                           (plist-get case :expected-arguments))))
            (should (equal (plist-get arguments :recovery-token) token))))))))

(ert-deftest routing-review-cases-have-valid-skill-boundaries ()
  (let (ids)
    (dolist (case skill-routing-review-cases)
      (ert-info ((format "Routing case: %S" (plist-get case :id)))
        (skill-routing-review-test-assert-case case)
        (skill-routing-review-test-assert-history case)
        (should-not (memq (plist-get case :id) ids))
        (push (plist-get case :id) ids)))))

(ert-deftest routing-review-validator-rejects-invalid-boundaries ()
  (let ((valid (car skill-routing-review-cases)))
    (dolist (replacement
             '((:id nil)
               (:expected (emacs-code-navigator emacs-code-navigator))
               (:excluded (git-commit git-commit))
               (:expected-operations ((emacs-code-navigator . nonexistent)))
               (:expected-operations ((emacs-code-navigator . context)
                                      (emacs-code-navigator . context)))
               (:expected-operations ((git-commit . context)))
               (:expected-operations nil)
               (:control ask-and-stop)
               (:completion conditional)
               (:expected-operation context)))
      (ert-info ((format "Invalid replacement: %S" replacement))
        (should-error
         (skill-routing-review-test-assert-case
          (plist-put (copy-tree valid) (car replacement) (cadr replacement)))
         :type 'ert-test-failed)))
    (should-error
     (skill-routing-review-test-assert-case (cddr valid))
     :type 'ert-test-failed)
    (should-error
     (skill-routing-review-test-assert-case (append valid '(:id duplicate)))
     :type 'ert-test-failed)))

(ert-deftest routing-review-validator-rejects-unconditional-recovery ()
  (dolist (case skill-routing-review-cases)
    (when (memq (plist-get case :control)
                '(inspect-and-retry-selectively describe-and-retry-once))
      (dolist (replacement '((:mutation allowed)
                             (:completion allowed)
                             (:completion-condition " ")
                             (:expected-operations nil)))
        (ert-info ((format "Recovery case: %S, replacement: %S"
                           (plist-get case :id) replacement))
          (should-error
           (skill-routing-review-test-assert-case
            (plist-put (copy-tree case) (car replacement) (cadr replacement)))
           :type 'ert-test-failed))))))

(ert-deftest routing-review-independent-input-retains-evidence-without-oracle ()
  (dolist (case skill-routing-review-cases)
    (let* ((input (skill-routing-evaluation-input (plist-get case :id)))
           (messages (plist-get input :messages)))
      (should (equal (butlast messages) (plist-get case :history)))
      (should (equal (car (last messages))
                     (list :role 'user :content (plist-get case :request))))
      (dolist (field '(:expected :excluded :expected-operations :expected-arguments :reason
                       :control :mutation :completion :completion-condition))
        (should-not (plist-member input field)))))
  (should-error (skill-routing-evaluation-input 'unknown)))

(ert-deftest routing-review-recovery-history-cannot-be-omitted ()
  (dolist (case skill-routing-review-cases)
    (when (memq (plist-get case :case-class)
                '(partial-recovery schema-mismatch false-completion))
      (should-error
       (skill-routing-review-test-assert-history
        (plist-put (copy-tree case) :history nil))
       :type 'ert-test-failed)))
  (let* ((input (skill-routing-evaluation-input 'blog-partial-publish-recovery))
         (result (plist-get (cadr (plist-get input :messages)) :result)))
    (should (equal (plist-get (plist-get result :error) :recovery-token)
                   "fixture-publish-recovery-1"))
    (setf (plist-get (plist-get result :error) :recovery-token) nil)
    (should-error
     (skill-routing-review-test-assert-history
      (list :case-class 'partial-recovery
            :expected-operations '((org-blog-exporter . resume))
            :history (butlast (plist-get input :messages))))
     :type 'ert-test-failed)
    ;; Editing an exported evaluation input must leave the canonical fixture intact.
    (should
     (stringp
      (plist-get
       (plist-get
        (plist-get
         (cadr (plist-get (skill-routing-evaluation-input
                          'blog-partial-publish-recovery) :messages))
         :result)
        :error)
       :recovery-token)))))

(ert-deftest routing-review-partial-history-needs-token-only-for-resume ()
  (let* ((case (copy-tree
                (seq-find (lambda (case)
                            (eq (plist-get case :id) 'blog-partial-publish-recovery))
                          skill-routing-review-cases)))
         (failure (plist-get (cadr (plist-get case :history)) :result)))
    (setq case (plist-put case :expected-operations nil))
    (setf (plist-get (plist-get failure :error) :recovery-token) nil)
    (skill-routing-review-test-assert-history case)
    (setq case (plist-put case :expected-operations '((org-blog-exporter . resume))))
    (dolist (token '(nil "" " "))
      (setf (plist-get (plist-get failure :error) :recovery-token) token)
      (should-error (skill-routing-review-test-assert-history case)
                    :type 'ert-test-failed))))

(ert-deftest routing-review-context-dependent-calls-have-background ()
  (dolist (id '(navigator-unsaved-buffer navigator-chinese-unsaved-buffer
                gtd-confirmed-capture blog-explicit-publish
                denote-confirmed-conversation-note git-explicit-commit
                git-explicit-review git-review-without-mutation-authorization
                gtd-ambiguous-task-target live-buffer-and-git-review))
    (should (> (length (plist-get (skill-routing-evaluation-input id) :messages)) 1)))
  (let ((case (seq-find
               (lambda (case)
                 (eq (plist-get case :id) 'gtd-capture-without-discussion-context))
               skill-routing-review-cases)))
    (should-not (plist-get case :history))
    (should-not (plist-get case :expected-operations))
    (should (eq (plist-get case :control) 'ask-and-stop))))

(ert-deftest routing-review-critical-arguments-detect-wrong-token-scope-and-source ()
  (dolist (id '(navigator-unsaved-buffer git-explicit-commit
                blog-partial-publish-recovery live-buffer-and-git-review))
    (let* ((case (skill-routing-evaluation--case id))
           (calls (mapcar (lambda (entry)
                            (cons (car entry)
                                  (append (list :operation (cdr entry))
                                          (copy-tree
                                           (alist-get (car entry)
                                                      (plist-get case :expected-arguments))))))
                          (plist-get case :expected-operations)))
           (matched (skill-routing-evaluation-check-calls id calls)))
      (should (plist-get matched :operations-match))
      (should (plist-get matched :arguments-match))
      (let* ((first (car calls))
             (field (pcase id
                      ('navigator-unsaved-buffer :source)
                      ('git-explicit-commit :paths)
                      ('blog-partial-publish-recovery :recovery-token)
                      (_ :file)))
             (wrong (copy-tree calls)))
        (setcdr (car wrong) (plist-put (cdr first) field 'wrong))
        (let ((checked (skill-routing-evaluation-check-calls id wrong)))
          (should (plist-get checked :operations-match))
          (should-not (plist-get checked :arguments-match))
          (should (eq (plist-get (car (plist-get checked :mismatches)) :field) field))))))
  (let ((checked (skill-routing-evaluation-check-calls
                  'git-explicit-commit '((git-commit :operation context)))))
    (should (plist-get checked :operations-match))
    (should-not (plist-get checked :arguments-match))
    (should (eq (plist-get (car (plist-get checked :mismatches)) :actual) 'missing)))
  (should-not (plist-get (skill-routing-evaluation-check-calls
                          'git-explicit-commit '((git-commit :operation commit)))
                         :operations-match)))

(ert-deftest routing-review-cases-cover-control-failure-classes ()
  (dolist (case-class skill-routing-review-test-case-classes)
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :case-class) case-class))
      skill-routing-review-cases))))

(ert-deftest routing-review-cases-preserve-core-positive-and-negative-examples ()
  (dolist (id '(navigator-unsaved-buffer
                navigator-general-xref-explanation
                gtd-possible-next-step
                gtd-confirmed-capture
                git-explicit-review
                git-no-passive-review
                denote-no-persistence-request))
    (should
     (seq-find
      (lambda (case) (eq (plist-get case :id) id))
      skill-routing-review-cases))))

(provide 'routing-review-tests)

;;; routing-review-tests.el ends here
