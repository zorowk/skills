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
         (body (make-temp-file "denote-body-" nil ".org" "A direct answer with supporting evidence.\n"))
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
                   "A direct answer with supporting evidence"
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
      (delete-file body)
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

(ert-deftest denote-removed-script-workflow-rejects-without-side-effects ()
  (let (called)
    (cl-letf (((symbol-function 'denote-scribe-create-with-review-context)
               (lambda (&rest _) (setq called t))))
      (dolist (request '((:operation template :kind script :language zh)
                         (:operation capture :kind script :title "Old script"
                          :body-file "/tmp/body.org" :authorization explicit)))
        (skill-contract-tests-assert-failure
         (denote-scribe-run request) 'needs-input 'invalid-request))
      (should-not called))))

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

(ert-deftest denote-gtd-backlinks-support-freeform-notes ()
  (let* ((root (make-temp-file "denote-gtd-link-" t))
         (notes (expand-file-name "notes" root))
         (note (expand-file-name
                "20260723T120000--linked-research.org" notes))
         (tasks
          '((:id "task-one" :title "Trace action mapping")
            (:id "task-two" :title "Build a minimal client"))))
    (unwind-protect
        (progn
          (make-directory notes)
          (with-temp-file note
            (insert "A direct answer.\n* Supporting observations\nEvidence.\n"))
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
              '( "Supporting observations" "Open Questions")))))
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

(ert-deftest denote-freeform-bodies-and-summaries-preserve-all-content ()
  (let ((note (make-temp-file "denote-freeform-" nil ".org")))
    (unwind-protect
        (progn
          (dolist (body '("A concise answer without headings."
                          "Opening judgment.\n* Why this happens\nEvidence.\n** Detail\nTrace.\n* Limits\nUncertainty."))
            (with-temp-file note (insert body))
            (should (progn (denote-scribe--validate-note-body note) t))
            (let* ((summary (denote-scribe-note-summary note 1000))
                   (sections (plist-get summary :sections)))
              (should (equal (plist-get (car sections) :text)
                             (car (split-string body "\n"))))
              (when (string-match-p "Why this happens" body)
                (should (equal (mapcar (lambda (section) (plist-get section :heading))
                                      sections)
                               '(nil "Why this happens" "Limits")))
                (should (string-match-p "Trace" (plist-get (cadr sections) :text)))))
            (should (plist-get
                     (car (plist-get (denote-scribe-note-summary note 5) :sections))
                     :truncated)))
          (with-temp-file note (insert "  \n"))
          (should-error (denote-scribe--validate-note-body note)))
      (delete-file note))))

(provide 'denote-scribe-tests)

;;; denote-scribe-tests.el ends here
