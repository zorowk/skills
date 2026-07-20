---
name: denote-scribe
description: >-
  Save completed technical or research conversations as Denote reasoning notes, review them,
  promote mature HyWiki knowledge, and commit generated files through Emacs.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

Resolve bundled paths from this skill directory, not the working directory. Load
`scripts/denote-scribe.el` and call `denote-scribe-run`. Read
`references/hywiki-denote-interface.md` only when integration details are needed.

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
