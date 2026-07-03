---
name: treeland-commit
description: "Use when Codex must generate a Treeland-style commit message: the user explicitly asks for Treeland format, names the Treeland commit convention, or the active Treeland project context clearly requires the fixed `Log`/`PMS`/`Influence` fields. Do not use for ordinary commit-message requests outside Treeland context."
---

# Treeland Commit

## When To Use

Use only when Treeland context is explicit. Do not use for generic "生成 commit", "写 commit", or "commit说明" unless the user also mentions Treeland, asks for Treeland format, or the repository/conversation clearly uses `Log`/`PMS`/`Influence`.

## Required Output

Output exactly one message in this shape:

```text
fix(module): summary

1 to 3 English sentences describing what changed and why.

Log:
PMS:
Influence:
```

No Markdown fence unless the user asks for one.

## Workflow

1. Confirm Treeland context.
2. Inspect changes: `git status --short`, `git diff --stat`, relevant `git diff`, and `git diff --cached` when staged changes exist.
3. Combine diff evidence with recent conversation context.
4. Choose an English module scope from paths/context, e.g. `build`, `window`, `input`, `config`, `docs`, `treeland`.
5. Write behavior-level summary under 72 chars when practical.
6. Fill `Log`, `PMS`, and `Influence` only from known information. Leave `PMS:` empty if no ID is known.

## Rules

- Keep `fix` by default unless the user requests another type.
- Do not output placeholders like `修复的模块`, `摘要`, or `详细描述`.
- Do not invent issue IDs, test results, product names, or impact.
- If unrelated changes would make one commit misleading, ask a short clarification.

## Example

```text
fix(build): handle optional dependency detection

Adjust dependency detection so missing optional components do not stop compilation. This keeps the default build flow working when optional features are unavailable.

Log: Fix optional dependency detection in the build flow
PMS:
Influence: Affects build-time dependency detection
```
