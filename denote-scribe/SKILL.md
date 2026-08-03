---
name: denote-scribe
description: >-
  Capture confirmed technical or research conversations as Denote reasoning notes, optionally link
  follow-up Org GTD tasks, review existing notes, and promote mature HyWiki knowledge. Use when the
  user explicitly asks to record, review, or promote persistent Denote knowledge.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

## Decision summary

```text
run?     := explicit record, review, or promotion request
mutate?  := explicit authorization AND unambiguous target
promote? := reusable knowledge AND clear scope AND traceable evidence
done?    := requested effects are present AND completion verification passes
```

## Semantic predicates

```text
reusable? := useful beyond the current incident
             AND likely to answer more than one future question
```

A general explanation supported by several investigations is reusable. A
one-off command that only repairs the current machine state is not.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

Replace `<skill-dir>` and uppercase placeholders with real Elisp values.
`REQUEST` is a plist beginning with `:operation`. Describe an unknown operation:

```elisp
(denote-scribe-run
 (list :operation (quote describe) :target (quote capture)))
```

Confirmed conversation capture:

```elisp
(denote-scribe-run
 (list :operation (quote capture) :title TITLE :body-file BODY_FILE
       :authorization (quote explicit)))
```

## Execution and recovery

Call documented operations directly. Use `describe` only when the schema is
unknown or after the first `invalid-request`; revise and retry once. A second
invalid request stops the goal. On `partial`, preserve returned evidence and
effects, then retry only the safe remainder.

`stop` means no further facade calls for the blocked goal in this turn. If safe
recovery is unclear, report observed effects and the remaining goal, then stop.

When `describe` is used, send only fields declared by the returned schema. Inspect
the script only if the entry point fails. Read
`references/hywiki-denote-interface.md` only for integration details.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

Match the critical template to the conversation language and use a concrete title.
Separate evidence from inference, include counter-evidence and uncertainty, and
preserve useful exact artifacts. Read full notes only for truncated or disputed
evidence.

Promote only when:

```text
promote only if:
  concept is reusable
  AND scope is clear
  AND evidence is traceable
  AND the user can explain it
  AND (independent supporting notes >= 2
       OR investigation status is supported or stable)
```

Reject bare terms, transient fixes, reference material, and unresolved questions.
Merge aliases, preserve provenance, deduplicate, and allow no-promotion.

Commit only files from this run when explicitly requested; mark review complete only
after every page is reviewed, including a valid no-promotion result. Do not push or
create GTD tasks without explicit user intent.

Treat review delivery and review completion as different states. Each `review`
response exposes pending `:verification`: artifact identifies delivered and truncated
summaries, workflow exposes continuation, and knowledge-assessment remains pending.
Read every page and every truncated or disputed source before completion.

To record completion, pass `:review-verification` to `commit`, never a bare boolean:

```text
review_done :=
  artifacts identify files, templates, and provenance
  AND workflow covers every page and item
  AND assessment is promoted or no-promotion
  AND every promotion records criteria, rationale, and supporting notes
  AND every promoted HyWiki page is in the same commit
```

A complete `no-promotion` assessment is valid.

For agent-shell capture:

```text
propose note + 0..3 GTD candidates -> no mutation
explicit confirmation             -> capture(authorization=explicit)
confirmed GTD candidate            -> add task with Denote file: resource
task created                       -> link-gtd(authorization=explicit)
link failure                       -> report partial state
```

Put backlinks below Open Questions or 开放问题. Do not promote HyWiki, commit,
push, or create unconfirmed tasks during capture.

When capturing the current conversation, propose GTD candidates only when the
extracted evidence reveals valuable actionable follow-up.
