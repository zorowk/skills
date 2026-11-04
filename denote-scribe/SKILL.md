---
name: denote-scribe
description: >-
  Capture confirmed technical or research conversations as Denote reasoning notes, optionally
  link follow-up Org GTD tasks, and review existing notes. Use when the user explicitly asks
  to record or review persistent Denote knowledge.
---

# Denote Scribe

Use Denote for durable reasoning notes.
Project-specific requirements and architecture belong in the project repository;
implementation tasks and progress belong in Org, linked to the relevant documents.
Capture cross-project knowledge in Denote when the user wants to preserve it.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Capture and quality

Create an Org `:body-file` with a concrete title and string keywords.
Apply critical thinking: distinguish evidence from inference, consider material
counter-evidence and alternatives, and qualify conclusions by uncertainty and scope.
Keep sources traceable. Choose a readable structure for the content; no fixed
headings, mandatory concept extraction, or full deliberation transcript.

Propose the note before capture; explicit confirmation permits
`capture(authorization=explicit)`. Do not proactively suggest GTD tasks.
When the user explicitly requests task creation or association, use
`emacs-gtd-assistant`; use `link-gtd` only for requested Denote backlinks.

## Review

Review notes for evidence, conclusions, unresolved questions, and useful links.
Read full notes for truncated or disputed evidence. Complete every review page
before marking a review complete; returning summaries alone is not assessment.

When explicitly asked to commit a completed review, supply `:review-verification`
with body/provenance checks (`:templates-valid` means body validation), complete coverage,
and `:note-assessment` containing `:outcome reviewed` and a substantive `:summary`.
Use the facade's `describe` operation for the exact schema when needed.

Preserve provenance and existing note links. Do not create a separate wiki or
copy notes into another knowledge system. Never commit, push, or create GTD tasks
without explicit user intent.
