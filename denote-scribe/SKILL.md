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
run?       := explicit record, review, or promotion request
kind       := technical reasoning -> critical
              contextual executable code -> script
              stable reusable knowledge -> hywiki
mutate?    := explicit authorization AND unambiguous target
reusable?  := useful beyond one incident AND likely to answer future questions
promote?   := reusable? AND clear scope AND traceable evidence
done?      := requested effects exist AND completion verification passes
```

Invoke the facade with one self-loading expression; `REQUEST` is a plist beginning
with `:operation`:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

## Execution and recovery

```text
known schema       -> call operation directly
unknown schema     -> describe(target), then call
invalid-request #1 -> describe(target), revise once
invalid-request #2 -> stop
partial            -> preserve evidence/effects; retry only the safe remainder
stop               -> report observed effects and the remaining goal; no more facade calls
```

Send only schema-declared fields. Inspect the script only if the entry point fails.
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
script safety := exact language AND :eval query AND no :tangle AND no separate script file

conversation capture:
  propose note + 0..3 valuable GTD candidates -> no mutation
  explicit confirmation -> capture(authorization=explicit)
  confirmed GTD task created -> link-gtd(authorization=explicit)
```

Read full notes only for truncated or disputed evidence. Put GTD backlinks below
Open Questions or 开放问题 in critical notes. Never create unconfirmed tasks.

## Promotion and review

```text
promote? := reusable? AND user can explain it
            AND (independent supporting notes >= 2
                 OR investigation status is supported|stable)
review_done? := every page/item reviewed
                AND truncated/disputed sources read
                AND assessment is promoted|no-promotion
                AND artifacts/templates/provenance verified
                AND each promotion records criteria, rationale, support, and same-commit HyWiki page
```

Reject bare terms, transient fixes, reference material, and unresolved questions.
Merge aliases, deduplicate, preserve provenance, and allow no-promotion. Review
delivery is never completion: pass complete `:review-verification`, not a boolean.
Commit only files from this run when explicitly requested. Never push, promote, or
create GTD tasks without explicit user intent.
