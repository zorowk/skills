---
name: denote-scribe
description: Save completed AI troubleshooting, coding, or research conversations as critical-thinking Denote Org notes, periodically consolidate concepts into HyWiki, and commit generated files through noninteractive Magit.
---

# Denote Scribe

Treat Denote as reasoning history and HyWiki as stable knowledge.

## Setup

Load `scripts/denote-scribe.el`, then call `denote-scribe-preflight`. Preserve
generated content and report exact errors. Read
`references/hywiki-denote-interface.md` only when integration details are needed.

## Workflow

1. Summarize a completed conversation or useful checkpoint with
   `assets/critical-note-template.org`. Keep evidence separate from inference;
   compare alternatives and counter-evidence; state uncertainty honestly.
2. Choose a concrete title in the conversation language. Preserve useful commands,
   paths, errors, identifiers, measurements, and links.
3. Call `denote-scribe-create`, then `denote-scribe-git-hywiki-state`.
4. When `:due` is non-nil, consolidate concepts. On `:bootstrap`, scan the full
   corpus; otherwise scan from the marker through the new note. Merge aliases and
   promote only reusable concepts with evidence and clear boundaries. Use
   `assets/hywiki-concept-template.org`; prefer English canonical technical names.
   Preserve existing page content and provenance, deduplicate, and skip unchanged
   pages.
5. Call `denote-scribe-git-commit` with the new Denote and only HyWiki pages changed
   by this run. Pass a true HyWiki flag only after a successful extraction pass,
   including a valid no-candidate result. On failure, commit the Denote with a
   false flag so the next run retries.

Before writing, inspect `~/Dropbox` status. Never include a pre-existing dirty
path, directory, wildcard, or unrelated staged change. Do not push.

For an explicit period or full review, use `denote-scribe-list-notes`; use
`denote-scribe-hywiki-create` for confirmed pages. Older unstructured notes remain
valid sources, but missing evidence lowers confidence.
