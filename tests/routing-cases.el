;;; routing-cases.el --- Versioned skill routing review cases -*- lexical-binding: t; -*-

;;; Commentary:

;; These cases are inputs for human review or a separately versioned model
;; evaluation.  They do not claim that ERT can predict a model router.

;;; Code:

(defconst skill-routing-review-cases
  '((:id navigator-unsaved-buffer
     :case-class positive
     :request "这里的函数为什么报错，buffer 还没保存"
     :expected (emacs-code-navigator)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The answer depends on live unsaved buffer state.")
    (:id navigator-general-xref-explanation
     :case-class negative
     :request "给我解释一下 xref 是什么"
     :expected ()
     :excluded (emacs-code-navigator)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A general concept explanation does not require live editor evidence.")
    (:id gtd-possible-next-step
     :case-class negative
     :request "接下来可以研究 Eglot"
     :expected ()
     :excluded (emacs-gtd-assistant)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A possible next step is not confirmation to create a persistent task.")
    (:id gtd-confirmed-capture
     :case-class positive
     :request "把刚才三项加入任务"
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operation add-many
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The user explicitly confirms persistent task capture.")
    (:id blog-explicit-publish
     :case-class positive
     :request "发布这篇 Org 笔记到博客"
     :expected (org-blog-exporter)
     :excluded (denote-scribe)
     :expected-operation publish
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The request explicitly asks for blog publication.")
    (:id blog-possible-future-writing
     :case-class negative
     :request "以后也许可以把这个整理成博客"
     :expected ()
     :excluded (org-blog-exporter)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "Speculation about a future blog post is not an export or publish request.")
    (:id denote-confirmed-conversation-note
     :case-class positive
     :request "把刚才完成的研究保存为 Denote 推理笔记"
     :expected (denote-scribe)
     :excluded ()
     :expected-operation capture
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The user explicitly requests persistent conversation capture as a note.")
    (:id git-explicit-commit
     :case-class positive
     :request "把这三个已经验证的文件提交"
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The request explicitly asks for a Git commit over a bounded file set.")
    (:id git-explicit-review
     :case-class positive
     :request "检查一下这轮 Git 修改有没有问题"
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The user explicitly asks for evidence-backed review of Git changes.")
    (:id git-no-passive-review
     :case-class negative
     :request "代码已经修改完成"
     :expected ()
     :excluded (git-commit)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A completed edit alone is not a request for Git review or commit.")
    (:id denote-no-persistence-request
     :case-class negative
     :request "总结一下我们刚才讨论的内容"
     :expected ()
     :excluded (denote-scribe)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A conversational summary is not a request to persist a Denote note.")
    (:id usage-review-after-tools
     :case-class positive
     :request "评价本轮 skills 使用情况"
     :expected (skill-usage-review)
     :excluded ()
     :expected-operation nil
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The user asks for a post-task review of visible skill calls.")
    (:id constitution-rigorous-high-impact-review
     :case-class positive
     :request "这个高风险迁移请严格核对证据、边界和可逆性"
     :expected (ai-constitution)
     :excluded ()
     :expected-operation nil
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The request is explicitly rigorous and high impact.")
    (:id git-unrelated-changes-ambiguous
     :case-class ambiguous
     :request "提交这轮修改，仓库里还有一些不相关改动"
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "The authorized path set and truthful split must be resolved first.")
    (:id git-review-without-mutation-authorization
     :case-class unauthorized
     :request "检查修改并建议 commit message，但不要提交"
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "Review is authorized while commit mutation is explicitly forbidden.")
    (:id gtd-ambiguous-task-target
     :case-class ambiguous
     :request "把那个重复名称的任务标成完成"
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operation set-state
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "A non-unique task match requires user selection before mutation.")
    (:id blog-partial-publish-recovery
     :case-class partial-recovery
     :request "publish 返回 partial：HTML 已生成但资源复制失败，继续处理"
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operation publish
     :mutation conditional
     :control inspect-and-retry-selectively
     :completion forbidden
     :reason "Completed export effects must be preserved while only safe remaining work is retried.")
    (:id blog-invalid-request-schema-recovery
     :case-class schema-mismatch
     :request "第一次 publish 返回 invalid-request，当前 schema 版本不确定"
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operation describe
     :mutation forbidden
     :control describe-and-retry-once
     :completion forbidden
     :reason "One describe-guided retry is allowed before stopping.")
    (:id denote-link-partial-is-not-complete
     :case-class false-completion
     :request "Denote 笔记已创建，但 link-gtd 失败；现在算完成了吗？"
     :expected (denote-scribe)
     :excluded ()
     :expected-operation nil
     :mutation forbidden
     :control report-incomplete
     :completion forbidden
     :reason "A created note does not satisfy the requested linked capture postcondition."))
  "Prompts and expected routing boundaries for manual or model evaluation.")

(provide 'routing-cases)

;;; routing-cases.el ends here
