---
name: denote-scribe
description: >-
  Capture confirmed technical or research conversations as Denote reasoning notes, preserve
  executable scripts with their purpose and operating context in Org Babel notes, optionally link
  follow-up Org GTD tasks, and review existing notes. Use when the user explicitly asks to record
  or review persistent Denote knowledge or contextual scripts.
---

# Denote Scribe

Use Denote for durable reasoning notes and contextual executable scripts.
Project-specific requirements and architecture belong in the project repository;
implementation tasks and progress belong in Org, linked to the relevant documents.
Capture cross-project knowledge in Denote when the user wants to preserve it.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

The facade owns request validation, authorization, effects, and recovery metadata.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Capture and quality

Create a readable `:body-file` from the matching language template. Pass `:kind
critical|script` (`critical` is the default), a concrete title, and string keywords.

```text
critical := evidence separate from inference + counter-evidence + uncertainty + exact artifacts
script   := purpose + boundary + prerequisites + inputs/side-effects + invocation
            + Org Babel executable + verification/recovery + maintenance + provenance

conversation capture:
  propose note + 0..3 valuable GTD candidates -> no mutation
  explicit confirmation -> capture(authorization=explicit)
  confirmed GTD task created -> link-gtd(authorization=explicit)
```

Read full notes only for truncated or disputed evidence. Propose GTD candidates only
when the conversation reveals valuable follow-up; never create unconfirmed tasks.

## Review

Review notes for evidence, conclusions, unresolved questions, and useful links.
Read full notes for truncated or disputed evidence. Complete every review page
before marking a review complete; returning summaries alone is not assessment.

When explicitly asked to commit a completed review, supply `:review-verification`
with artifact/template/provenance checks, complete pagination and item coverage,
and `:note-assessment` containing `:outcome reviewed` and a substantive `:summary`.
Use the facade's `describe` operation for the exact schema when needed.

Preserve provenance and existing note links. Do not create a separate wiki or
copy notes into another knowledge system. Never commit, push, or create GTD tasks
without explicit user intent.
