;;; routing-cases.el --- Versioned skill routing review cases -*- lexical-binding: t; -*-

;;; Commentary:

;; These cases are inputs for human review or a separately versioned model
;; evaluation.  They do not claim that ERT can predict a model router.
;; :expected selects skills; :expected-operations maps skills to their next
;; facade call, not the eventual user goal.  Nil means no call at this decision.
;; :expected-arguments optionally constrains critical fields of those calls.
;; :control describes the continuation policy; ask-and-stop makes no call.
;; :mutation bounds the whole continuation, including an authorized retry.
;; :completion concerns claiming the whole request complete: allowed permits
;; an answer after any planned calls, forbidden requires stopping with it incomplete,
;; and conditional requires the explicit :completion-condition to be verified.
;; :history contains synthetic session messages supplied before :request in
;; independent evaluation.  Tool requests/results are inert fixture data;
;; their paths and session tokens must never be executed against a real facade.
;; Actual authorization, scope and recovery checks remain in the facades.

;;; Code:

(defconst skill-routing-review-cases
  '((:id navigator-unsaved-buffer
     :case-class positive
     :history
     ((:role user :content "Editor context: /fixture/project/sample.el, line 12, column 4, inside sample-function; the live buffer has unsaved edits. Project: /fixture/project."))
     :request "Why is this function failing? The buffer has not been saved yet."
     :expected (emacs-code-navigator)
     :excluded ()
     :expected-operations ((emacs-code-navigator . context))
     :expected-arguments ((emacs-code-navigator :file "/fixture/project/sample.el" :line 12 :column 4 :source live))
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The answer depends on live unsaved buffer state.")
    (:id navigator-general-xref-explanation
     :case-class negative
     :request "Explain what xref is."
     :expected ()
     :excluded (emacs-code-navigator)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A general concept explanation does not require live editor evidence.")
    (:id gtd-possible-next-step
     :case-class negative
     :request "We could investigate Eglot next."
     :expected ()
     :excluded (emacs-gtd-assistant)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A possible next step is not confirmation to create a persistent task.")
    (:id gtd-confirmed-capture
     :case-class positive
     :history
     ((:role assistant :content "Agreed next tasks: Inspect Eglot logs; reproduce the xref failure; verify the fix. Each is a personal task under Personal, without a deadline.")
      (:role user :content "These three items are correct and ready to capture."))
     :request "Add the three items we just discussed to my task list."
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operations ((emacs-gtd-assistant . add-many))
     :mutation allowed
     :control execute
     :completion conditional
     :completion-condition "All three requested tasks were created and verified."
     :reason "The user explicitly confirms persistent task capture.")
    (:id gtd-capture-without-discussion-context
     :case-class ambiguous
     :request "Add the three items we just discussed to my task list."
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operations nil
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "The three task contents are absent from this session; ask for them before capture.")
    (:id blog-explicit-publish
     :case-class positive
     :history
     ((:role user :content "The selected note is /fixture/notes/sample.org; the configured blog repository is /fixture/blog. Use this note for the following request."))
     :request "Publish this Org note to the blog."
     :expected (org-blog-exporter)
     :excluded (denote-scribe)
     :expected-operations ((org-blog-exporter . publish))
     :mutation allowed
     :control execute
     :completion conditional
     :completion-condition "Publication and its requested repository effects were verified."
     :reason "The request explicitly asks for blog publication.")
    (:id blog-possible-future-writing
     :case-class negative
     :request "Maybe we could turn this into a blog post someday."
     :expected ()
     :excluded (org-blog-exporter)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "Speculation about a future blog post is not an export or publish request.")
    (:id denote-confirmed-conversation-note
     :case-class positive
     :history
     ((:role assistant :content "Research conclusion: the stale xref result came from an unsaved buffer; reading live context resolves it. The proposed note is titled Live xref evidence, and its completed body is saved at /fixture/research.org.")
      (:role user :content "I approve that note proposal and body file."))
     :request "Save the research we just completed as a Denote reasoning note."
     :expected (denote-scribe)
     :excluded ()
     :expected-operations ((denote-scribe . capture))
     :mutation allowed
     :control execute
     :completion conditional
     :completion-condition "The requested Denote note was created and verified."
     :reason "The user explicitly requests persistent conversation capture as a note.")
    (:id git-explicit-commit
     :case-class positive
     :history
     ((:role user :content "In /fixture/project, this round consists of src/parser.el, tests/parser-tests.el and README.md. The focused tests passed. Those are the three files I want included."))
     :request "Commit these three validated files."
     :expected (git-commit)
     :excluded ()
     :expected-operations ((git-commit . context))
     :expected-arguments ((git-commit :directory "/fixture/project" :paths ("src/parser.el" "tests/parser-tests.el" "README.md")))
     :mutation allowed
     :control execute
     :completion conditional
     :completion-condition "The commit contains exactly the authorized files and was verified."
     :reason "The request explicitly asks for a Git commit over a bounded file set.")
    (:id git-explicit-review
     :case-class positive
     :history
     ((:role user :content "The repository for this review is /fixture/project. Review its current changes."))
     :request "Review this round of Git changes for problems."
     :expected (git-commit)
     :excluded ()
     :expected-operations ((git-commit . context))
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The user explicitly asks for evidence-backed review of Git changes.")
    (:id git-no-passive-review
     :case-class negative
     :request "The code changes are complete."
     :expected ()
     :excluded (git-commit)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A completed edit alone is not a request for Git review or commit.")
    (:id denote-no-persistence-request
     :case-class negative
     :history
     ((:role assistant :content "We found that xref must be checked against the current unsaved buffer. The disk version can differ from the function being evaluated."))
     :request "Summarize what we just discussed."
     :expected ()
     :excluded (denote-scribe)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A conversational summary is not a request to persist a Denote note.")
    (:id git-unrelated-changes-ambiguous
     :case-class ambiguous
     :history
     ((:role user :content "The repository is /fixture/project. Some edits belong to this round and others are personal experiments. I have not identified which paths or hunks belong to this round."))
     :request "Commit this round of changes; the repository also contains unrelated changes."
     :expected (git-commit)
     :excluded ()
     :expected-operations nil
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "The authorized path set and truthful split must be resolved first.")
    (:id git-review-without-mutation-authorization
     :case-class unauthorized
     :history
     ((:role user :content "The repository for this review is /fixture/project. Its current changes are the review scope."))
     :request "Review the changes and suggest a commit message, but do not commit."
     :expected (git-commit)
     :excluded ()
     :expected-operations ((git-commit . context))
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "Review is authorized while commit mutation is explicitly forbidden.")
    (:id gtd-ambiguous-task-target
     :case-class ambiguous
     :history
     ((:role user :content "Mark the task named Investigate xref as done.")
      (:role tool :skill emacs-gtd-assistant
       :request (:operation resolve :query "Investigate xref")
       :result (:protocol-version 2 :status ok :operation resolve :count 2
                :data (:status ambiguous
                       :matches ((:id "fixture-task-a" :title "Investigate xref")
                                 (:id "fixture-task-b" :title "Investigate xref"))))))
     :request "Mark the task with the duplicated name as done."
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operations nil
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "A non-unique task match requires user selection before mutation.")
    (:id blog-partial-publish-recovery
     :case-class partial-recovery
     :history
     ((:role user :content "Publish /fixture/notes/sample.org to /fixture/blog.")
      (:role tool :skill org-blog-exporter
       :request (:operation publish :files ("/fixture/notes/sample.org")
                 :repository-dir "/fixture/blog" :authorization explicit)
       :result (:protocol-version 2 :status partial :operation publish :count 1
                :data (:exported-count 1 :assets nil :error-count 1)
                :effects (:exported-count 1 :changed ("sample.html")
                          :commit nil :push nil)
                :verification
                (:artifact
                 (:source-output-map
                  ((:source "/fixture/notes/sample.org"
                    :output "/fixture/blog/sample.html"))
                  :outputs-exist t :public-policy-passed t :asset-links-verified t)
                 :workflow (:assets-planned 1 :assets-copied 0)
                 :repository (:commit-exists nil :push-succeeded nil))
                :error (:code partial-failure :stage assets :retry selective
                        :required-action inspect-failures
                        :message "Asset copy failed"
                        :recovery-token "fixture-publish-recovery-1"))))
     :request "Publish returned partial: HTML was generated, but asset copying failed. Continue."
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operations ((org-blog-exporter . resume))
     :expected-arguments ((org-blog-exporter :recovery-token "fixture-publish-recovery-1" :authorization explicit))
     :mutation conditional
     :control inspect-and-retry-selectively
     :completion conditional
     :completion-condition "Resume succeeded and all remaining publication postconditions were verified."
     :reason "Use the returned session recovery token to resume verified remaining work.")
    (:id navigator-chinese-unsaved-buffer
     :case-class positive
     :history
     ((:role user :content "编辑器上下文：/fixture/project/sample.el，第 12 行第 4 列，位于 sample-function，缓冲区有未保存修改；项目为 /fixture/project。"))
     :request "分析当前光标所在函数，缓冲区里有尚未保存的修改。"
     :expected (emacs-code-navigator)
     :excluded (denote-scribe emacs-gtd-assistant)
     :expected-operations ((emacs-code-navigator . context))
     :expected-arguments ((emacs-code-navigator :file "/fixture/project/sample.el" :line 12 :column 4 :source live))
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "Unsaved cursor context requires live editor evidence in either language.")
    (:id chinese-no-persistence-request
     :case-class negative
     :history
     ((:role assistant :content "当前问题与 Eglot 返回的定义位置有关，需要区分 live buffer 和磁盘内容。后续可以继续分析它的缓存更新机制。"))
     :request "总结刚才的分析，以后可以继续研究 Eglot。"
     :expected ()
     :excluded (denote-scribe emacs-gtd-assistant org-blog-exporter)
     :expected-operations nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A Chinese summary and possible next step do not request persistence.")
    (:id live-buffer-and-git-review
     :case-class positive
     :history
     ((:role user :content "编辑器上下文：/fixture/project/sample.el，第 12 行第 4 列，位于 sample-function，缓冲区有未保存修改；Git 仓库为 /fixture/project。"))
     :request "结合当前未保存的函数和 Git diff 审查问题，并说明哪些改动尚未进入磁盘。"
     :expected (emacs-code-navigator git-commit)
     :excluded (denote-scribe emacs-gtd-assistant)
     :expected-operations ((emacs-code-navigator . context) (git-commit . context))
     :expected-arguments ((emacs-code-navigator :file "/fixture/project/sample.el" :line 12 :column 4 :source live) (git-commit :directory "/fixture/project"))
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "Live unsaved evidence and repository evidence require both facades with provenance.")
    (:id blog-invalid-request-schema-recovery
     :case-class schema-mismatch
     :history
     ((:role user :content "Publish /fixture/notes/sample.org to /fixture/blog.")
      (:role tool :skill org-blog-exporter
       :request (:operation publish :files ("/fixture/notes/sample.org")
                 :repository-dir "/fixture/blog" :authorization explicit
                 :asset-mode copy)
       :result (:protocol-version 2 :status needs-input :operation publish
                :count 0 :data nil :effects nil
                :error (:code invalid-request :retry after-input
                        :required-action revise-request
                        :field-path ("publish" :asset-mode)
                        :message "publish does not allow field :asset-mode"))))
     :request "The first publish call returned invalid-request, and the current operation schema is uncertain."
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operations ((org-blog-exporter . describe))
     :mutation conditional
     :control describe-and-retry-once
     :completion conditional
     :completion-condition "The single schema-guided retry succeeded and publication was verified."
     :reason "Describe first; retry once only with valid arguments and publication authorization, then report the actual outcome.")
    (:id denote-link-partial-is-not-complete
     :case-class false-completion
     :history
     ((:role user
       :content "Save the research as a Denote note and link it to task fixture-task-1.")
      (:role tool :skill denote-scribe
       :request (:operation capture :title "Research"
                 :body-file "/fixture/research.org" :authorization explicit)
       :result (:protocol-version 2 :status ok :operation capture :count 1
                :data (:file "/fixture/notes/20261104T070000--research.org")
                :effects (:created t)))
      (:role tool :skill denote-scribe
       :request (:operation link-gtd
                 :file "/fixture/notes/20261104T070000--research.org"
                 :tasks ((:id "fixture-task-1" :title "Investigate")))
       :result (:protocol-version 2 :status needs-input :operation link-gtd
                :count 0 :data nil :effects nil
                :error (:code authorization-required :retry after-input
                        :required-action confirm
                        :field-path (:authorization)
                        :message "link-gtd requires :authorization explicit"))))
     :request "The Denote note was created, but link-gtd failed. Is the request complete?"
     :expected (denote-scribe)
     :excluded ()
     :expected-operations nil
     :mutation forbidden
     :control report-incomplete
     :completion forbidden
     :reason "A created note does not satisfy the requested linked capture postcondition."))
  "Prompts and expected routing boundaries for manual or model evaluation.")

(provide 'routing-cases)

;;; routing-cases.el ends here
