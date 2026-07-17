---
name: denote-scribe
description: Save completed AI troubleshooting, coding, or research conversations as critical-thinking Denote Org notes, periodically review questions and concept candidates, promote mature knowledge into HyWiki, and commit generated files through noninteractive Magit.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

Load `scripts/denote-scribe.el` and use its public function docstrings and errors as
the interface. Inspect source only to debug or modify it. Read
`references/hywiki-denote-interface.md` only when integration details are needed.

1. Fill the language-matching `critical` template returned by
   `denote-scribe-template-file`. Use a concrete title in the conversation language.
   Separate evidence from inference, compare alternatives and counter-evidence,
   state uncertainty, and preserve useful commands, paths, errors, identifiers,
   measurements, and links.
2. Call `denote-scribe-create-with-review-context`. When `:review-files` is non-nil,
   review those files, covering new, unresolved, and resolved questions before
   evaluating concepts.
3. Promote a concept only when all are true: it can be explained in the user's own
   model, has traceable evidence or reasoning, and has reusable value with a clear
   boundary. It must also appear in two independent notes or be established by one
   deep `supported`/`stable` investigation. Frequency is evidence of maturity, not
   a hard quota. Reject bare terms, transient fixes, generic reference material,
   and unresolved questions.
4. Merge aliases and fill the language-matching `hywiki` template; prefer English
   canonical technical names. Preserve content and provenance, deduplicate, and
   skip unchanged pages. A valid review may create no HyWiki page.
5. Call `denote-scribe-git-commit` with the new Denote and only HyWiki pages changed
   by this run. Pass a true review flag only after the AI Review completes,
   including a valid no-promotion result. On failure, pass false so the next run
   retries.

During Review, keep non-actionable open questions in Denote. Suggest GTD only when
a question has a concrete next action and warrants deliberate investment; do not
create GTD items without authorization. Use `denote-scribe-list-notes` only for an
explicit period or full review. Do not push. Older unstructured notes remain valid
sources, but missing evidence lowers confidence.
