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

Every request is one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/denote-scribe.el")
  (denote-scribe-run REQUEST))
```

Replace `<skill-dir>` with this skill's directory and uppercase names with real
Elisp values. `REQUEST` is a plist beginning with `:operation`. Query exact
parameters before an unfamiliar operation:

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

```text
known documented operation       -> call directly
schema unknown or version unsure -> describe, then call
first invalid-request            -> describe, revise, retry once
second invalid-request           -> report rejected fields; stop
status=partial                    -> inspect effects and verification;
                                     preserve completed effects;
                                     retry only the safe remainder
```

Treat `stop` as no further facade calls for the blocked goal in this turn,
especially no effectful calls. If safe partial recovery is unclear, enumerate
observed effects and the remaining goal, then stop.

Use only fields returned by `describe`. Do not inspect the script unless the entry
point fails. Read `references/hywiki-denote-interface.md` only for integration
details.

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
