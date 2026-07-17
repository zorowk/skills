---
name: denote-scribe
description: Save completed AI troubleshooting, coding, or research conversations as critical-thinking Denote Org notes, periodically review questions and concept candidates, promote mature knowledge into HyWiki, and commit generated files through noninteractive Magit.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

Load `scripts/denote-scribe.el` and call `denote-scribe-run`. Read
`references/hywiki-denote-interface.md` only when integration details are needed.

Fill the language-matching critical template with a concrete title. Separate evidence
from inference, include counter-evidence and uncertainty, and preserve useful exact
artifacts. After `create`, consume every paged compact `review` result; read full
notes only for truncated or disputed evidence.

Promote only reusable, bounded concepts with traceable support that the user can
explain: require two independent notes or one deep `supported`/`stable`
investigation. Reject bare terms, transient fixes, reference material, and unresolved
questions. Merge aliases, preserve provenance, deduplicate, and allow no-promotion.

Commit only files from this run after explicit authorization; mark review complete
only after every page is reviewed, including valid no-promotion. Do not push or
create GTD tasks without authorization.
