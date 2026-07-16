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
`treeland-commit-format` to produce the final message; return its string without a
Markdown fence unless requested. Treat its docstring and validation errors as the
interface; inspect source only to debug or modify it.

## Workflow

1. Inspect changes: `git status --short`, `git diff --stat`, relevant `git diff`, and
   `git diff --cached` when staged changes exist.
2. Combine diff evidence with recent conversation context.
3. Derive the type, English module scope, behavior-level summary, rationale, and
   fields from known evidence. Do not invent issue IDs, tests, products, or impact.
4. Ask for direction when unrelated changes cannot be represented truthfully by one
   message; otherwise call `treeland-commit-format`.

Use `fix` when the evidence does not justify another type.
