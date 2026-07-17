---
name: denote-scribe
description: >-
  Save completed technical or research conversations as Denote reasoning notes, review them,
  promote mature HyWiki knowledge, and commit generated files through Emacs.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

Load `scripts/denote-scribe.el` and call `denote-scribe-run`. Read
`references/hywiki-denote-interface.md` only when integration details are needed.
Read standard `:data`, `:page`, and `:effects` fields; call `describe` only for an
unclear operation schema.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Fill the language-matching critical template with a concrete title. Separate evidence
from inference, include counter-evidence and uncertainty, and preserve useful exact
artifacts. After `create`, consume every paged compact `review` result; read full
notes only for truncated or disputed evidence.

Promote only reusable, bounded concepts with traceable support that the user can
explain: require two independent notes or one deep `supported`/`stable`
investigation. Reject bare terms, transient fixes, reference material, and unresolved
questions. Merge aliases, preserve provenance, deduplicate, and allow no-promotion.

Commit only files from this run through the shared Git formatter after explicit
authorization; mark review complete only after every page is reviewed, including
valid no-promotion. Do not push or create GTD tasks without authorization.
