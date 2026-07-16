---
name: treeland-commit
description: >-
  Use when an AI assistant must generate a Treeland-style commit message: the user explicitly asks
  for Treeland format, names the Treeland commit convention, or the active Treeland project context
  clearly requires the fixed `Log`/`PMS`/`Influence` fields. Do not use for ordinary commit-message
  requests outside Treeland context.
---

# Treeland Commit

## When To Use

Use only when Treeland context is explicit. Do not use for generic "生成 commit", "写 commit", or
"commit说明" unless the user also mentions Treeland, asks for Treeland format, or the repository or
conversation clearly uses `Log`/`PMS`/`Influence`.

## Required Output

Output exactly one message in this shape:

```text
type(module): summary

Explain the important changes and why they were needed.
For multiple fix or feat items, list the significant behaviors:
- First behavior-level change.
- Second behavior-level change.

Log: concise one-line summary
PMS:
Influence:
```

No Markdown fence unless the user asks for one.

## Workflow

1. Confirm Treeland context.
2. Inspect changes: `git status --short`, `git diff --stat`, relevant `git diff`, and
   `git diff --cached` when staged changes exist.
3. Combine diff evidence with recent conversation context.
4. Choose an English module scope from paths/context, e.g. `build`, `window`, `input`, `config`, `docs`, `treeland`.
5. Write behavior-level summary under 72 chars when practical.
6. Use the body to explain what changed and why. For `fix` or `feat`, list multiple significant
   fixes or capabilities instead of hiding them in prose.
7. Fill `Log`, `PMS`, and `Influence` only from known information. Leave `PMS:` empty if no ID is
   known.

## Rules

- Keep `fix` by default unless the user requests another type.
- Put important change details and rationale in the body, not in `Log`.
- Keep `Log` to one short summary line; do not repeat the body or include implementation details.
- For `feat`, list significant new user-visible or system capabilities when there is more than one.
- For `fix`, list significant behavioral fixes when there is more than one.
- Prefer wrapping body and field text at 100 columns.
- Never let a generated line exceed 120 columns; indent continuation lines by two spaces.
- Do not output placeholders like `修复的模块`, `摘要`, or `详细描述`.
- Do not invent issue IDs, test results, product names, or impact.
- If unrelated changes would make one commit misleading, ask a short clarification.

## Example

```text
feat(output): add configurable output management

Add output management so users can keep display behavior consistent:
- Apply per-output scale and transform settings.
- Restore saved settings when outputs reconnect.

Log: Add configurable output management
PMS:
Influence: Affects output configuration and restore behavior
```
