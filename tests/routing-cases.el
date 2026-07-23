;;; routing-cases.el --- Versioned skill routing review cases -*- lexical-binding: t; -*-

;;; Commentary:

;; These cases are inputs for human review or a separately versioned model
;; evaluation.  They do not claim that ERT can predict a model router.

;;; Code:

(defconst skill-routing-review-cases
  '((:id navigator-unsaved-buffer
     :request "这里的函数为什么报错，buffer 还没保存"
     :expected (emacs-code-navigator)
     :excluded ()
     :reason "The answer depends on live unsaved buffer state.")
    (:id navigator-general-xref-explanation
     :request "给我解释一下 xref 是什么"
     :expected ()
     :excluded (emacs-code-navigator)
     :reason "A general concept explanation does not require live editor evidence.")
    (:id gtd-possible-next-step
     :request "接下来可以研究 Eglot"
     :expected ()
     :excluded (emacs-gtd-assistant)
     :reason "A possible next step is not confirmation to create a persistent task.")
    (:id gtd-confirmed-capture
     :request "把刚才三项加入任务"
     :expected (emacs-gtd-assistant)
     :excluded ()
     :reason "The user explicitly confirms persistent task capture.")
    (:id blog-explicit-publish
     :request "发布这篇 Org 笔记到博客"
     :expected (org-blog-exporter)
     :excluded (denote-scribe)
     :reason "The request explicitly asks for blog publication.")
    (:id blog-possible-future-writing
     :request "以后也许可以把这个整理成博客"
     :expected ()
     :excluded (org-blog-exporter)
     :reason "Speculation about a future blog post is not an export or publish request.")
    (:id denote-confirmed-conversation-note
     :request "把刚才完成的研究保存为 Denote 推理笔记"
     :expected (denote-scribe)
     :excluded ()
     :reason "The user explicitly requests persistent conversation capture as a note.")
    (:id git-explicit-commit
     :request "把这三个已经验证的文件提交"
     :expected (git-commit)
     :excluded ()
     :reason "The request explicitly asks for a Git commit over a bounded file set.")
    (:id usage-review-after-tools
     :request "评价本轮 skills 使用情况"
     :expected (skill-usage-review)
     :excluded ()
     :reason "The user asks for a post-task review of visible skill calls.")
    (:id constitution-rigorous-high-impact-review
     :request "这个高风险迁移请严格核对证据、边界和可逆性"
     :expected (ai-constitution)
     :excluded ()
     :reason "The request is explicitly rigorous and high impact."))
  "Prompts and expected routing boundaries for manual or model evaluation.")

(provide 'routing-cases)

;;; routing-cases.el ends here
