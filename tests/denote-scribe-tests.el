;;; denote-scribe-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "denote-scribe/scripts/denote-scribe.el"))

(defvar denote-scribe-review-commit-marker)
(defvar skill-git--body-label-regexp)

(ert-deftest denote-incremental-review-includes-modified-notes-with-special-names ()
  (skill-tests-require-git)
  (skill-tests-require-magit)
  (skill-tests-with-git-repository
    (make-directory "notes")
    (let ((old (expand-file-name "notes/20260101T000000--中文.org"))
          (new (expand-file-name "notes/20260102T000000--new.org")))
      (with-temp-file old (insert "* Old\n"))
      (skill-tests-git "add" ".")
      (skill-tests-git "commit" "-qm" "review")
      (let ((marker (skill-tests-git "rev-parse" "HEAD")))
        (with-temp-file old (insert "* Updated\n"))
        (with-temp-file "notes/ignored.txt" (insert "not a note"))
        (skill-tests-git "add" ".")
        (skill-tests-git "commit" "-qm" "update")
        (with-temp-file new (insert "* New\n"))
        (should (equal (denote-scribe--review-files
                        new (list :git-root root :marker-commit marker)
                        (expand-file-name "notes"))
                       (list old new)))))))

(defun skill-contract-tests-review-verification (review-files)
  "Return completed note review evidence for tests."
  (list :artifact (list :review-files review-files :templates-valid 'valid :provenance-valid 'valid)
        :workflow (list :pages-reviewed 1 :page-total 1
                        :items-reviewed (length review-files) :item-total (length review-files)
                        :completion 'complete)
        :note-assessment (list :outcome 'reviewed
                               :summary "Checked evidence and conclusions; unresolved questions remain explicit.")))

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

(ert-deftest denote-create-and-capture-share-authorized-facade-behavior ()
  (cl-letf (((symbol-function 'denote-scribe-create-with-review-context)
             (lambda (&rest _)
               '(:file "/tmp/created.org" :review-state (:review-due nil)))))
    (dolist (operation '(create capture))
      (let ((request
             (list :operation operation :title "Research note"
                   :body-file "/tmp/body.org")))
        (skill-contract-tests-assert-failure
         (denote-scribe-run request)
         'needs-input 'authorization-required)
        (let ((result
               (denote-scribe-run
                (append request '(:authorization explicit)))))
          (should (equal (plist-get (plist-get result :data) :file)
                         "/tmp/created.org"))
          (should (equal (plist-get result :effects) '(:created t))))))))

(ert-deftest denote-script-templates-are-bilingual-and-validated ()
  (dolist (language '(en zh))
    (let ((template (denote-scribe-template-file 'script language)))
      (should (file-readable-p template))
      (should (progn (denote-scribe--validate-script-body template) t))))
  (let ((invalid (make-temp-file "denote-script-invalid-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file invalid
            (insert "* Purpose\n* When to Use\n* Prerequisites\n"
                    "* Inputs and Side Effects\n* Script\n* How to Run\n"
                    "* Verification and Recovery\n* Maintenance Notes\n* Provenance\n"))
          (should-error (denote-scribe--validate-script-body invalid)))
      (delete-file invalid))))

(ert-deftest denote-script-validation-enforces-execution-without-tangling ()
  (let ((template (denote-scribe-template-file 'script 'en)))
    (dolist (replacement '("" ":eval query :tangle /tmp/generated.sh"))
      (let ((body (make-temp-file "denote-script-policy-" nil ".org")))
        (unwind-protect
            (progn
              (with-temp-file body
                (insert-file-contents template)
                (goto-char (point-min))
                (search-forward "#+begin_src shell :eval query")
                (replace-match
                 (string-trim-right
                  (concat "#+begin_src shell " replacement))
                 t t))
              (should-error (denote-scribe--validate-script-body body)))
          (delete-file body))))))

(ert-deftest denote-capture-forwards-script-kind ()
  (let (received-kind)
    (cl-letf (((symbol-function 'denote-scribe-create-with-review-context)
               (lambda (&rest args)
                 (setq received-kind (car (last args)))
                 '(:file "/tmp/script.org" :review-state (:review-due nil)))))
      (let ((result
             (denote-scribe-run
              '(:operation capture :kind script :title "Contextual script"
                :body-file "/tmp/body.org" :keywords ("script")
                :authorization explicit))))
        (should (eq received-kind 'script))
        (should (equal (plist-get (plist-get result :data) :file)
                       "/tmp/script.org"))))))

(ert-deftest denote-review-separates-delivery-from-note-assessment ()
  (let ((summary
         '(:file "/tmp/reviewed.org"
           :title "Reviewed"
           :sections
           ((:heading "Evidence" :text "bounded" :truncated t)))))
    (cl-letf (((symbol-function 'denote-scribe-review-context)
               (lambda (&rest _)
                 (list :count 2 :offset 0 :limit 1
                       :truncated t :next-offset 1
                       :summaries (list summary)))))
      (let* ((result
              (denote-scribe-run
               '(:operation review
                 :file "/tmp/new.org"
                 :review-state (:review-due t))))
             (verification (plist-get result :verification))
             (artifact (plist-get verification :artifact))
             (workflow (plist-get verification :workflow))
             (assessment
              (plist-get verification :note-assessment)))
        (should (equal (plist-get artifact :review-files)
                       '("/tmp/reviewed.org")))
        (should (equal (plist-get artifact :truncated-files)
                       '("/tmp/reviewed.org")))
        (should (= (plist-get workflow :item-total) 2))
        (should (= (plist-get workflow :next-offset) 1))
        (should-not (plist-get workflow :all-pages-returned))
        (should (eq (plist-get workflow :completion)
                    'pending-assessment))
        (should (eq (plist-get assessment :outcome) 'pending))))))

(ert-deftest denote-commit-rejects-bare-or-incomplete-review-completion ()
  (skill-contract-tests-assert-failure
   (denote-scribe-run
    '(:operation commit :title "Review"
      :paths ("/tmp/note.org")
      :authorization explicit
      :review-completed t))
   'needs-input 'invalid-request)
  (let* ((root (make-temp-file "denote-review-invalid-" t))
         (note (expand-file-name "note.org" root))
         (verification
          (skill-contract-tests-review-verification
           (list note))))
    (unwind-protect
        (progn
          (with-temp-file note (insert "#+title: Note\n"))
          (setf (plist-get
                 (plist-get verification :workflow)
                 :item-total)
                2)
          (skill-contract-tests-assert-failure
           (denote-scribe-run
            (list :operation 'commit :title "Review"
                  :paths (list note)
                  :authorization 'explicit
                  :review-verification verification))
           'needs-input 'invalid-request))
      (delete-directory root t))))

(ert-deftest denote-review-completion-records-note-assessment-and-restricts-paths ()
  (let* ((root (make-temp-file "denote-review-" t))
         (notes (expand-file-name "notes" root))
         (note (expand-file-name "one.org" notes))
         message-text)
    (unwind-protect
        (progn
          (make-directory notes)
          (with-temp-file note (insert "#+title: Test\n"))
          (cl-letf (((symbol-function 'denote-scribe--git-root) (lambda (&optional _) root))
                    ((symbol-function 'skill-git-commit-paths)
                     (lambda (_root message paths predicate &rest _)
                       (should (funcall predicate "notes/one.org"))
                       (should-not (funcall predicate "hywiki/Concept.org"))
                       (should-not (funcall predicate "brain/gtd.org"))
                       (setq message-text message)
                       (list :commit "abc123" :paths paths))))
            (let* ((result (denote-scribe-run
                            (list :operation 'commit :title "Review notes" :paths (list note)
                                  :authorization 'explicit :review-verification
                                  (skill-contract-tests-review-verification (list note)))))
                   (verification (plist-get result :verification)))
              (should (eq (plist-get result :status) 'ok))
              (should (eq (plist-get (plist-get verification :note-assessment) :outcome) 'reviewed))
              (should (plist-get (plist-get verification :workflow) :review-completed))
              (should (string-match-p (regexp-quote denote-scribe-review-commit-marker) message-text)))))
      (delete-directory root t))))

(ert-deftest denote-review-rejects-empty-assessment-and-duplicate-coverage ()
  (let ((note (make-temp-file "denote-assessment-" nil ".org")))
    (unwind-protect
        (let ((verification (skill-contract-tests-review-verification (list note))))
          (setf (plist-get (plist-get verification :note-assessment) :summary) "   ")
          (should-error (denote-scribe--valid-review-verification-p verification))
          (setq verification (skill-contract-tests-review-verification (list note note)))
          (should-error (denote-scribe--valid-review-verification-p verification)))
      (delete-file note))))

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

(ert-deftest denote-preflight-does-not-load-or-require-hywiki ()
  (let* ((root (make-temp-file "denote-preflight-" t))
         (original-require (symbol-function 'require)))
    (unwind-protect
        (cl-letf (((symbol-function 'require)
                   (lambda (feature &optional file noerror)
                     (when (memq feature '(hywiki hyperbole))
                       (ert-fail "Denote must not load Hyperbole or HyWiki"))
                     (if (memq feature '(denote magit)) t
                       (funcall original-require feature file noerror))))
                  ((symbol-function 'skill-git-root) (lambda (_) root)))
          (let ((result (denote-scribe-run
                         (list :operation 'preflight :notes-dir root :git-dir root))))
            (should (eq (plist-get result :status) 'ok))
            (should-not (plist-get (plist-get result :data) :errors))))
      (delete-directory root t))))

(ert-deftest denote-removed-wiki-operations-reject-without-side-effects ()
  (dolist (request '((:operation hywiki :page-name "Concept" :body-file "/tmp/body.org"
                     :authorization explicit)
                    (:operation template :kind hywiki :language en)))
    (skill-contract-tests-assert-failure
     (denote-scribe-run request) 'needs-input 'invalid-request)))

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

(provide 'denote-scribe-tests)

;;; denote-scribe-tests.el ends here
