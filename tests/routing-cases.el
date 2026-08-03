;;; routing-cases.el --- Versioned skill routing review cases -*- lexical-binding: t; -*-

;;; Commentary:

;; These cases are inputs for human review or a separately versioned model
;; evaluation.  They do not claim that ERT can predict a model router.

;;; Code:

(defconst skill-routing-review-cases
  '((:id navigator-unsaved-buffer
     :case-class positive
     :request "Why is this function failing? The buffer has not been saved yet."
     :expected (emacs-code-navigator)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The answer depends on live unsaved buffer state.")
    (:id navigator-general-xref-explanation
     :case-class negative
     :request "Explain what xref is."
     :expected ()
     :excluded (emacs-code-navigator)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A general concept explanation does not require live editor evidence.")
    (:id gtd-possible-next-step
     :case-class negative
     :request "We could investigate Eglot next."
     :expected ()
     :excluded (emacs-gtd-assistant)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A possible next step is not confirmation to create a persistent task.")
    (:id gtd-confirmed-capture
     :case-class positive
     :request "Add the three items we just discussed to my task list."
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operation add-many
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The user explicitly confirms persistent task capture.")
    (:id blog-explicit-publish
     :case-class positive
     :request "Publish this Org note to the blog."
     :expected (org-blog-exporter)
     :excluded (denote-scribe)
     :expected-operation publish
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The request explicitly asks for blog publication.")
    (:id blog-possible-future-writing
     :case-class negative
     :request "Maybe we could turn this into a blog post someday."
     :expected ()
     :excluded (org-blog-exporter)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "Speculation about a future blog post is not an export or publish request.")
    (:id denote-confirmed-conversation-note
     :case-class positive
     :request "Save the research we just completed as a Denote reasoning note."
     :expected (denote-scribe)
     :excluded ()
     :expected-operation capture
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The user explicitly requests persistent conversation capture as a note.")
    (:id git-explicit-commit
     :case-class positive
     :request "Commit these three validated files."
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation allowed
     :control execute
     :completion conditional
     :reason "The request explicitly asks for a Git commit over a bounded file set.")
    (:id git-explicit-review
     :case-class positive
     :request "Review this round of Git changes for problems."
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The user explicitly asks for evidence-backed review of Git changes.")
    (:id git-no-passive-review
     :case-class negative
     :request "The code changes are complete."
     :expected ()
     :excluded (git-commit)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A completed edit alone is not a request for Git review or commit.")
    (:id denote-no-persistence-request
     :case-class negative
     :request "Summarize what we just discussed."
     :expected ()
     :excluded (denote-scribe)
     :expected-operation nil
     :mutation forbidden
     :control answer-without-skill
     :completion allowed
     :reason "A conversational summary is not a request to persist a Denote note.")
    (:id usage-review-after-tools
     :case-class positive
     :request "Evaluate how the skills were used in this turn."
     :expected (skill-usage-review)
     :excluded ()
     :expected-operation nil
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The user asks for a post-task review of visible skill calls.")
    (:id constitution-rigorous-high-impact-review
     :case-class positive
     :request "Strictly verify the evidence, boundaries, and reversibility of this high-risk migration."
     :expected (ai-constitution)
     :excluded ()
     :expected-operation nil
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "The request is explicitly rigorous and high impact.")
    (:id git-unrelated-changes-ambiguous
     :case-class ambiguous
     :request "Commit this round of changes; the repository also contains unrelated changes."
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "The authorized path set and truthful split must be resolved first.")
    (:id git-review-without-mutation-authorization
     :case-class unauthorized
     :request "Review the changes and suggest a commit message, but do not commit."
     :expected (git-commit)
     :excluded ()
     :expected-operation context
     :mutation forbidden
     :control execute
     :completion allowed
     :reason "Review is authorized while commit mutation is explicitly forbidden.")
    (:id gtd-ambiguous-task-target
     :case-class ambiguous
     :request "Mark the task with the duplicated name as done."
     :expected (emacs-gtd-assistant)
     :excluded ()
     :expected-operation set-state
     :mutation forbidden
     :control ask-and-stop
     :completion forbidden
     :reason "A non-unique task match requires user selection before mutation.")
    (:id blog-partial-publish-recovery
     :case-class partial-recovery
     :request "Publish returned partial: HTML was generated, but asset copying failed. Continue."
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operation publish
     :mutation conditional
     :control inspect-and-retry-selectively
     :completion forbidden
     :reason "Completed export effects must be preserved while only safe remaining work is retried.")
    (:id blog-invalid-request-schema-recovery
     :case-class schema-mismatch
     :request "The first publish call returned invalid-request, and the current schema version is uncertain."
     :expected (org-blog-exporter)
     :excluded ()
     :expected-operation describe
     :mutation forbidden
     :control describe-and-retry-once
     :completion forbidden
     :reason "One describe-guided retry is allowed before stopping.")
    (:id denote-link-partial-is-not-complete
     :case-class false-completion
     :request "The Denote note was created, but link-gtd failed. Is the request complete?"
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
