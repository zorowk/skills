---
name: denote-scribe
description: >-
  Capture confirmed technical or research conversations as Denote reasoning notes, preserve
  executable scripts with their purpose and operating context in Org Babel notes, optionally link
  follow-up Org GTD tasks, review existing notes, and promote mature HyWiki knowledge. Use when the
  user explicitly asks to record, review, or promote persistent Denote knowledge or contextual scripts.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

```text
kind      := technical reasoning -> critical
             contextual executable code -> script
             stable reusable knowledge -> hywiki
reusable? := useful beyond one incident AND likely to answer future questions
promote?  := reusable? AND clear scope AND traceable evidence
```

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

The facade owns request validation, authorization, effects, and recovery metadata.
Read `references/hywiki-denote-interface.md` only for HyWiki integration.

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

## Promotion and review

```text
promote? := reusable? AND user can explain it
            AND (independent supporting notes >= 2
                 OR investigation status is supported|stable)
```

Reject bare terms, transient fixes, reference material, and unresolved questions.
Merge aliases, deduplicate, preserve provenance, and allow no-promotion. Never push,
promote, commit, or create GTD tasks without explicit user intent.
