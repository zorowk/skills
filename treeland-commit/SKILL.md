---
name: treeland-commit
description: >-
  Use when an AI assistant must generate a Treeland-style commit message: the user explicitly asks
  for Treeland format, names the Treeland commit convention, or the active Treeland project context
  clearly requires the fixed `Log`/`PMS`/`Influence` fields. Do not use for ordinary commit-message
  requests outside Treeland context.
---

# Treeland Commit

Load `scripts/treeland-commit.el` from this skill directory. Use
`treeland-commit-run`: request compact `context`, derive fields from the evidence and
conversation, then request `format`. Use full context only when the bounded diff is
insufficient.

Do not invent issue IDs, tests, products, or impact. Ask when unrelated changes do
not fit one truthful message. Default to `fix` when evidence supports no better type.
Return the formatted string without a Markdown fence unless requested.
