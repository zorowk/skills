;;; denote-scribe-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "common/scripts/agent-shell-bridge.el"
   "denote-scribe/scripts/denote-scribe.el"
   "denote-scribe/scripts/agent-shell-denote-capture.el"))

(defvar agent-shell-denote-capture--suppress-count)
(defvar denote-scribe-review-commit-marker)
(defvar skill-git--body-label-regexp)

(defun skill-contract-tests-review-verification
    (review-files outcome &optional promoted-pages evidence-basis)
  "Return completed Denote review evidence for tests."
  (let ((promoted (eq outcome 'promoted)))
    (list
     :artifact
     (list :review-files review-files
           :hywiki-files promoted-pages
           :templates-valid 'valid
           :provenance-valid 'valid)
     :workflow
     (list :pages-reviewed 1 :page-total 1
           :items-reviewed (length review-files)
           :item-total (length review-files)
           :completion 'complete)
     :knowledge-assessment
     (append
      (list
       :outcome outcome
       :criteria
       (list :explainable-model (if promoted 'passed 'not-passed)
             :traceable-support (if promoted 'passed 'not-passed)
             :reuse-value (if promoted 'passed 'not-passed)
             :clear-boundary (if promoted 'passed 'not-passed)
             :deep-stable
             (if (eq evidence-basis 'deep-stable)
                 'passed 'not-applicable))
       :supporting-notes review-files
       :promoted-pages promoted-pages
       :rationale
       (if promoted
           "The bounded concept satisfies every promotion criterion."
         "No reviewed concept currently satisfies every promotion criterion."))
      (and evidence-basis (list :evidence-basis evidence-basis))))))

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

(ert-deftest denote-review-separates-delivery-from-knowledge-assessment ()
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
              (plist-get verification :knowledge-assessment)))
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
           (list note) 'no-promotion)))
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

(ert-deftest denote-review-completion-distinguishes-valid-outcomes ()
  (let* ((root (make-temp-file "denote-review-outcomes-" t))
         (notes (expand-file-name "notes" root))
         (hywiki (expand-file-name "hywiki" root))
         (note-one (expand-file-name "one.org" notes))
         (note-two (expand-file-name "two.org" notes))
         (page (expand-file-name "Concept.org" hywiki))
         messages)
    (unwind-protect
        (progn
          (make-directory notes)
          (make-directory hywiki)
          (dolist (file (list note-one note-two page))
            (with-temp-file file (insert "#+title: Test\n")))
          (cl-letf
              (((symbol-function 'denote-scribe--git-root)
                (lambda (&optional _) root))
               ((symbol-function 'skill-git-commit-paths)
                (lambda (_root message paths &rest _)
                  (push message messages)
                  (list
                   :commit "abc123"
                   :paths
                   (mapcar
                    (lambda (path)
                      (file-relative-name path root))
                    paths)))))
            (let* ((no-promotion
                    (skill-contract-tests-review-verification
                     (list note-one) 'no-promotion))
                   (no-promotion-result
                    (denote-scribe-run
                     (list :operation 'commit
                           :title "Complete review"
                           :paths (list note-one)
                           :authorization 'explicit
                           :review-verification no-promotion)))
                   (promotion
                    (skill-contract-tests-review-verification
                     (list note-one note-two) 'promoted
                     (list page) 'independent-notes))
                   (promotion-result
                    (denote-scribe-run
                     (list :operation 'commit
                           :title "Promote concept"
                           :paths (list note-one note-two page)
                           :authorization 'explicit
                           :review-verification promotion))))
              (should
               (eq
                (plist-get
                 (plist-get
                  (plist-get no-promotion-result :verification)
                  :knowledge-assessment)
                 :outcome)
                'no-promotion))
              (should
               (eq
                (plist-get
                 (plist-get
                  (plist-get promotion-result :verification)
                  :knowledge-assessment)
                 :outcome)
                'promoted))
              (dolist (result (list no-promotion-result promotion-result))
                (should
                 (eq
                  (plist-get
                   (plist-get
                    (plist-get result :verification) :workflow)
                   :review-completed)
                  t)))
              (should
               (seq-every-p
                (lambda (message)
                  (string-match-p
                   (regexp-quote denote-scribe-review-commit-marker)
                   message))
                messages)))))
      (delete-directory root t))))

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
