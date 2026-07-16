---
name: denote-scribe
description: Save completed AI troubleshooting, coding, or research conversations as critical-thinking Denote Org notes, periodically review questions and concept candidates, promote mature knowledge into HyWiki, and commit generated files through noninteractive Magit.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

## Setup

Load `scripts/denote-scribe.el`; it loads the sibling
`common/scripts/skill-git.el` helper. Then call `denote-scribe-preflight`.
Treat bundled scripts as executable implementations: during normal use, load and
call documented entry points without reading source. Inspect source only when
debugging, modifying a script, or resolving undocumented behavior.
Preserve generated content and report exact errors. Read
`references/hywiki-denote-interface.md` only when integration details are needed.

## Workflow

1. Summarize a completed conversation or useful checkpoint with
   `assets/critical-note-template.org`, or use
   `assets/critical-note-template-zh.org` when the conversation is primarily in
   Chinese. Keep evidence separate from inference; compare alternatives and
   counter-evidence; state uncertainty honestly.
   Store compact assessment metadata in Org properties: `STATUS` and
   `CREDIBILITY` for conclusions, and `MATURITY` and `HYWIKI_CANDIDATE` for
   extracted concepts. Keep answers, decisions, evidence, boundaries, and reuse
   value visible in the body.
2. Choose a concrete title in the conversation language. Preserve useful commands,
   paths, errors, identifiers, measurements, and links.
3. Call `denote-scribe-create`, then `denote-scribe-git-review-state`.
4. When `:review-due` is non-nil, run an AI Review. On `:bootstrap`, scan the full
   corpus; otherwise scan notes since the marker through the new note. Review new,
   unresolved, and resolved questions before evaluating concept candidates.
5. Promote a concept only when all are true: it can be explained in the user's own
   model, has traceable evidence or reasoning, and has reusable value with a clear
   boundary. It must also appear in two independent notes or be established by one
   deep `supported`/`stable` investigation. Frequency is evidence of maturity, not
   a hard quota. Reject bare terms, transient fixes, generic reference material,
   and unresolved questions.
6. Merge aliases and write qualifying concepts with
   `assets/hywiki-concept-template.org`, or use
   `assets/hywiki-concept-template-zh.org` for a primarily Chinese conversation;
   prefer English canonical technical names. Preserve existing content and
   provenance, deduplicate, and skip unchanged pages. A valid review may create no
   HyWiki page.
   Store `CREDIBILITY` and `REVIEW_PERIOD` in the Provenance property drawer, but
   keep Denote source links visible.
7. Call `denote-scribe-git-commit` with the new Denote and only HyWiki pages changed
   by this run. Pass a true review flag only after the AI Review completes,
   including a valid no-promotion result. On failure, pass false so the next run
   retries.

Before writing, inspect `~/Dropbox` status. Never include a pre-existing dirty
path, directory, wildcard, or unrelated staged change. Do not push.

During Review, keep non-actionable open questions in Denote. Suggest GTD only when
a question has a concrete next action and warrants deliberate investment; do not
create GTD items without authorization. For an explicit period or full review, use
`denote-scribe-list-notes`; use `denote-scribe-hywiki-create` for qualifying pages.
Older unstructured notes remain valid sources, but missing evidence lowers
confidence.
