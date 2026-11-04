;;; denote-scribe-tests.el --- Split skill tests -*- lexical-binding: t; -*-

;;; Code:

(require 'test-helper)
(defvar denote-after-new-note-hook)

(skill-tests-load-many
 '(
   "common/scripts/skill-runtime.el"
   "common/scripts/skill-git.el"
   "denote-scribe/scripts/denote-scribe.el"))

(ert-deftest denote-create-writes-only-to-the-selected-notes-directory ()
  (let* ((denote-after-new-note-hook nil)
         (root (make-temp-file "denote-create-" t))
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
  (cl-letf (((symbol-function 'denote-scribe-create)
             (lambda (&rest _)
               "/tmp/created.org")))
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
    (cl-letf (((symbol-function 'denote-scribe-create)
               (lambda (&rest _) (setq called t))))
      (dolist (request '((:operation template :kind script :language zh)
                         (:operation capture :kind script :title "Old script"
                          :body-file "/tmp/body.org" :authorization explicit)))
        (skill-contract-tests-assert-failure
         (denote-scribe-run request) 'needs-input 'invalid-request))
      (should-not called))))

(ert-deftest denote-gtd-backlinks-support-freeform-notes ()
  (let* ((root (make-temp-file "denote-gtd-link-" t))
         (notes (expand-file-name "notes" root))
         (note (expand-file-name
                "20260723T120000--linked-research.org" notes))
         (tasks
          '((:id "task-one" :title "Trace action mapping")
            (:id "task-two" :title "Build a minimal client")
            (:id "task-three" :title "Verify behavior")
            (:id "task-four" :title "Review result"))))
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

(ert-deftest denote-preflight-requires-neither-git-nor-wiki ()
  (let* ((root (make-temp-file "denote-preflight-" t))
         (original-require (symbol-function 'require)))
    (unwind-protect
        (cl-letf (((symbol-function 'require)
                   (lambda (feature &optional file noerror)
                     (when (memq feature '(hywiki hyperbole magit))
                       (ert-fail "Denote must not load Magit or wiki packages"))
                     (if (eq feature 'denote) t
                       (funcall original-require feature file noerror)))))
          (let ((result (denote-scribe-run
                         (list :operation 'preflight :notes-dir root))))
            (should (eq (plist-get result :status) 'ok))
            (should-not (plist-get (plist-get result :data) :errors))))
      (delete-directory root t))))

(ert-deftest denote-removed-wiki-operations-reject-without-side-effects ()
  (dolist (request '((:operation hywiki :page-name "Concept" :body-file "/tmp/body.org"
                     :authorization explicit)
                    (:operation template :kind hywiki :language en)))
    (skill-contract-tests-assert-failure
     (denote-scribe-run request) 'needs-input 'invalid-request)))

(ert-deftest denote-removed-review-and-commit-operations-reject ()
  (dolist (operation '(review summarize commit))
    (skill-contract-tests-assert-failure
     (denote-scribe-run (list :operation operation))
     'needs-input 'invalid-request)))

(ert-deftest denote-freeform-body-validation ()
  (let ((note (make-temp-file "denote-body-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file note (insert "A concise answer without headings."))
          (should (progn (denote-scribe--validate-note-body note) t))
          (with-temp-file note (insert "  \n"))
          (should-error (denote-scribe--validate-note-body note)))
      (delete-file note))))

(ert-deftest denote-signed-notes-and-prefix-task-ids-are-preserved ()
  (let* ((root (make-temp-file "denote-signed-" t))
         (note (expand-file-name "20261104T120000==research--note__test.org" root)))
    (unwind-protect
        (progn
          (with-temp-file note (insert "A note.\n"))
          (should (equal (denote-scribe-list-notes nil nil root) (list note)))
          (denote-scribe-link-gtd note '((:id "task-one-long" :title "Long")) root)
          (denote-scribe-link-gtd note '((:id "task-one" :title "Short")) root)
          (denote-scribe-link-gtd note '((:id "task-one" :title "Short")) root)
          (with-temp-buffer
            (insert-file-contents note)
            (should (= (how-many (regexp-quote "[[id:task-one][")
                                 (point-min) (point-max)) 1))
            (should (= (how-many (regexp-quote "[[id:task-one-long][")
                                 (point-min) (point-max)) 1))))
      (when-let* ((buffer (get-file-buffer note))) (kill-buffer buffer))
      (delete-directory root t))))

(ert-deftest denote-native-discovery-respects-components-exclusions-and-dates ()
  (require 'denote)
  (let* ((root (make-temp-file "denote-native-" t))
         (nested (expand-file-name "nested" root))
         (denote-excluded-files-regexp "excluded")
         (denote-excluded-directories-regexp "ignored")
         (first (expand-file-name "20261103T235959==sig--first__research.org" root))
         (second (expand-file-name "20261104T000000==sig--second__research_test.org" nested))
         (third (expand-file-name "20261104T235959--third__other.org" root)))
    (unwind-protect
        (progn
          (make-directory nested)
          (make-directory (expand-file-name "ignored" root))
          (dolist (file (list first second third
                             (expand-file-name "20261104T120000--excluded__research.org" root)
                             (expand-file-name "ignored/20261104T120000--note__research.org" root)
                             (expand-file-name "plain.org" root)))
            (with-temp-file file (insert "A note.\n")))
          (make-directory (expand-file-name "20261104T120000--directory.org" root))
          (should (equal (sort (denote-scribe-list-notes nil nil root) #'string<)
                         (sort (list first second third) #'string<)))
          (should (equal (denote-scribe-list-notes "2026-11-04" "20261104" root
                                                   '("research" "test"))
                         (list second)))
          (should (equal (denote-scribe-list-notes "20261103" "20261103" root)
                         (list first)))
          (should-error (denote-scribe-list-notes "20261104" nil root))
          (should-error (denote-scribe-list-notes "20261105" "20261104" root)))
      (delete-directory root t))))

(ert-deftest denote-capture-failure-exposes-the-created-buffer-without-retrying ()
  (let* ((root (make-temp-file "denote-partial-" t))
         (notes (expand-file-name "notes" root))
         (body (expand-file-name "body.org" root))
         (denote-after-new-note-hook nil))
    (unwind-protect
        (progn
          (make-directory notes)
          (with-temp-file body (insert "Completed reasoning.\n"))
          (cl-letf (((symbol-function 'denote-scribe--fill-org-buffer)
                     (lambda () (signal 'void-function '(missing-fill-helper)))))
            (let* ((result (denote-scribe-run
                            (list :operation 'capture :title "Partial note" :body-file body
                                  :notes-dir notes :authorization 'explicit)))
                   (file (plist-get (plist-get result :data) :file)))
              (skill-contract-tests-assert-failure result 'partial 'partial-failure)
              (should (eq (plist-get (plist-get result :error) :retry) 'never))
              (should (eq (car (plist-get (plist-get result :error) :cause)) 'void-function))
              (should (get-file-buffer file))
              (should (plist-get (plist-get result :effects) :buffer-exists))
              (should-not (plist-get (plist-get (plist-get result :verification) :artifact)
                                     :body-verified)))))
      (dolist (buffer (buffer-list))
        (when-let* ((file (buffer-file-name buffer)))
          (when (file-in-directory-p file root)
            (with-current-buffer buffer (set-buffer-modified-p nil))
            (kill-buffer buffer))))
      (delete-directory root t))))

(provide 'denote-scribe-tests)

;;; denote-scribe-tests.el ends here
