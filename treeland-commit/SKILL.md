---
name: treeland-commit
description: >-
  Use when an AI assistant must generate a Treeland-style commit message: the user explicitly asks
  for Treeland format, names the Treeland commit convention, or the active Treeland project context
  clearly requires the fixed `Log`/`PMS`/`Influence` fields. Do not use for ordinary commit-message
  requests outside Treeland context.
---

# Treeland Commit

Use only when Treeland context is explicit. Do not use for generic "生成 commit", "写 commit", or
"commit说明" unless the user also mentions Treeland, asks for Treeland format, or the repository or
conversation clearly uses `Log`/`PMS`/`Influence`.

Load `scripts/treeland-commit.el` from this skill directory. Use
`treeland-commit-format` to produce the final message; return its string without a
Markdown fence unless requested.
Treat bundled scripts as executable implementations: during normal use, load and
call documented entry points without reading source. Inspect source only when
debugging, modifying a script, or resolving undocumented behavior.

## Workflow

1. Inspect changes: `git status --short`, `git diff --stat`, relevant `git diff`, and
   `git diff --cached` when staged changes exist.
2. Combine diff evidence with recent conversation context.
3. Choose an English module scope from paths and project terminology.
4. Write a behavior-level summary and explain what changed and why. For `fix` or `feat`, list multiple significant
   fixes or capabilities instead of hiding them in prose.
5. Supply `Log`, `PMS`, and `Influence` only from known information. Pass nil for an
   unknown PMS value.

Use `fix` when the evidence does not justify another type. Do not invent issue
IDs, tests, products, or impact. Ask when unrelated changes prevent one truthful
commit message.
