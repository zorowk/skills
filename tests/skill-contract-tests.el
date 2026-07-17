;;; skill-contract-tests.el --- Contract tests for local skills -*- lexical-binding: t; -*-

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(defvar emacs-code-navigator-documentation-maximum-characters)
(defvar skill-git--body-label-regexp)

(declare-function skill-runtime-result "../common/scripts/skill-runtime"
                  (operation data &optional count status page effects))
(declare-function skill-runtime-page "../common/scripts/skill-runtime"
                  (items offset limit total))
(declare-function skill-runtime-truncate "../common/scripts/skill-runtime"
                  (text maximum label))
(declare-function emacs-code-navigator-query
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (request))
(declare-function emacs-code-navigator--compact-facet
                  "../emacs-code-navigator/scripts/emacs-code-navigator"
                  (info))
(declare-function emacs-gtd-execute
                  "../emacs-gtd-assistant/scripts/emacs-gtd-assistant"
                  (request))
(declare-function denote-scribe-run
                  "../denote-scribe/scripts/denote-scribe" (request))
(declare-function denote-scribe-git-commit
                  "../denote-scribe/scripts/denote-scribe"
                  (title paths review-completed &optional kind git-dir))
(declare-function org-blog-exporter-run
                  "../org-blog-exporter/scripts/org-blog-exporter" (request))
(declare-function org-blog-exporter--finish-publish
                  "../org-blog-exporter/scripts/org-blog-exporter"
                  (repository exported title))
(declare-function ai-git-commit-run
                  "../git-commit/scripts/ai-git-commit" (request))
(declare-function ai-git-commit-format
                  "../git-commit/scripts/ai-git-commit" (spec))
(declare-function treeland-commit-format
                  "../git-commit/scripts/ai-git-commit"
                  (type module summary body log &optional pms influence))

(defconst skill-contract-tests-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(dolist (relative
         '("common/scripts/skill-runtime.el"
           "common/scripts/skill-git.el"
           "emacs-code-navigator/scripts/emacs-code-navigator.el"
           "emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"
           "denote-scribe/scripts/denote-scribe.el"
           "org-blog-exporter/scripts/org-blog-exporter.el"
           "git-commit/scripts/ai-git-commit.el"))
  (load (expand-file-name relative skill-contract-tests-root) nil nil t))

(defconst skill-contract-tests-message-spec
  '(:type "refactor"
    :scope "skills"
    :summary "standardize compact contracts"
    :risk low
    :context "Skill facades need one predictable result shape for efficient AI calls."
    :changes ("Return data, paging metadata, and effects through shared helpers.")
    :reason "One protocol removes skill-specific parsing and unnecessary retries."
    :validation "Validated formatter, pagination, schema, and compatibility contracts."
    :boundary
    "Legacy public functions remain callable and external actions still require authorization.")
  "Reusable structured evidence for formatter tests.")

(ert-deftest skill-runtime-standard-envelope ()
  (should
   (equal (skill-runtime-result 'list '(a b) 2 'ok '(:truncated nil))
          '(:status ok :operation list :count 2 :data (a b)
                    :page (:truncated nil)))))

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
      (should (plist-get (plist-get result :data) :operations)))))

(ert-deftest navigator-reports-documentation-truncation ()
  (let* ((emacs-code-navigator-documentation-maximum-characters 3)
         (facet (emacs-code-navigator--compact-facet
                 '(:symbol "sample" :kinds (function)
                   :documentation "abcdef" :source nil))))
    (should (equal (plist-get facet :documentation) "abc"))
    (should (eq (plist-get facet :documentation-truncated) t))
    (should (= (plist-get facet :documentation-original-length) 6))))

(ert-deftest git-message-auto-compacts-low-risk-work ()
  (let ((message (ai-git-commit-format skill-contract-tests-message-spec)))
    (should-not (string-match-p "Legacy public functions" message))
    (should-not (string-match-p skill-git--body-label-regexp message))
    (should (seq-every-p
             (lambda (line) (<= (string-width line) 100))
             (split-string message "\n")))))

(ert-deftest git-message-full-preserves-boundary ()
  (let ((message
         (ai-git-commit-format
          (plist-put (copy-sequence skill-contract-tests-message-spec)
                     :detail 'full))))
    (should (string-match-p "Legacy public functions" message))))

(ert-deftest git-message-rejects-labels-and-missing-evidence ()
  (should-error
   (ai-git-commit-format
    (plist-put (copy-sequence skill-contract-tests-message-spec)
               :context "Context: redundant label")))
  (should-error
   (ai-git-commit-format '(:type "fix" :summary "reject incomplete input"))))

(ert-deftest treeland-compatibility-preserves-trailer-order ()
  (let* ((message
          (treeland-commit-format
           "fix" "skills" "preserve callers" "Keep the old API available."
           "Compatibility" "PMS-1" "Legacy only"))
         (log (string-match "^Log:" message))
         (pms (string-match "^PMS:" message))
         (influence (string-match "^Influence:" message)))
    (should (< log pms influence))))

(ert-deftest destructive-facades-require-authorization-before-effects ()
  (should-error (emacs-gtd-execute '(:operation delete :id "sample")))
  (should-error (denote-scribe-run '(:operation commit)))
  (should-error (org-blog-exporter-run '(:operation publish))))

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

(provide 'skill-contract-tests)

;;; skill-contract-tests.el ends here
