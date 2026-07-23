---
name: denote-scribe
description: >-
  Save confirmed technical or research conversations as Denote reasoning notes, optionally link
  follow-up Org GTD tasks in both directions, review notes, promote mature HyWiki knowledge, and
  commit generated files through Emacs.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

Resolve bundled paths from this skill directory, not the working directory. Load
`scripts/denote-scribe.el` and call `denote-scribe-run`. Read
`references/hywiki-denote-interface.md` only when integration details are needed.
Call documented script entry points directly. If a facade schema is unclear, use
its `describe` operation. Do not inspect script implementations unless the
documented entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Match the critical template to the conversation language and use a concrete title.
Separate evidence from inference, include counter-evidence and uncertainty, and
preserve useful exact artifacts. Read full notes only for truncated or disputed
evidence.

Promote only reusable, bounded concepts with traceable support that the user can
explain: require two independent notes or one deep `supported`/`stable`
investigation. Reject bare terms, transient fixes, reference material, and unresolved
questions. Merge aliases, preserve provenance, deduplicate, and allow no-promotion.

Commit only files from this run when explicitly requested; mark review complete only
after every page is reviewed, including a valid no-promotion result. Do not push or
create GTD tasks without explicit user intent.

Treat review delivery and review completion as different states. Each `review`
response exposes pending `:verification`: artifact identifies delivered and truncated
summaries, workflow exposes continuation, and knowledge-assessment remains pending.
Read every page and every truncated or disputed source before completion.

To record a completed review, pass `:review-verification` to `commit`; never use a
bare completion boolean. Artifact must identify reviewed files and valid templates
and provenance. Workflow must prove complete page and item coverage. Knowledge
assessment must choose `promoted` or `no-promotion`, record each promotion criterion
and rationale, and include the supporting notes and promoted pages when applicable.
Treat a complete no-promotion assessment as valid; do not equate it with an incomplete
review. Require every promoted HyWiki page to be included in the same commit.

For agent-shell capture, first present an editable note proposal and zero to three
optional GTD candidates without mutation. After explicit confirmation, use
`capture` with `:authorization explicit`; add each confirmed GTD task with the
created Denote file as a structured `file:` resource, then use `link-gtd` with
the returned task IDs and `:authorization explicit`. Backlinks belong below
Open Questions or 开放问题 so required top-level headings remain unchanged.
Report partial state if cross-file linking fails. Do not promote HyWiki, commit,
push, or create unconfirmed tasks as part of capture.

For the English agent-shell action, load
`scripts/agent-shell-denote-capture.el` and call
`agent-shell-denote-capture-enable`. It registers `Capture as Denote`, uses the
same conversation context, and suppresses recursive capture suggestions.
