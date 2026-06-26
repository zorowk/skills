---
name: treeland-commit
description: Generate Treeland project commit messages from the current conversation and git changes. Use when the user says "生成commit", "生成 commit", "写commit", "commit说明", or asks for a Treeland-style commit message based on modified files, diffs, and recent problem-solving context.
---

# Treeland Commit

## Purpose

Generate a commit message in the Treeland format from the current git changes and the recent AI conversation. Output only the commit message unless the user asks for explanation.

## Required Format

Use this exact structure. The labels and punctuation are fixed, but the placeholder words must be replaced with English content inferred from the diff and conversation:

```text
fix(修复的模块): 摘要

详细描述

Log:
PMS:
Influence:
```

Keep the blank lines as shown. Do not use Markdown fences in the final output unless the user asks for a code block.

## Template Meaning

The format has five parts:

1. `fix(` is fixed text. Use `fix` by default.
2. `修复的模块` is a placeholder. Replace it with a short English module name, such as `build`, `window`, `input`, `config`, `docs`, or `treeland`. Do not literally output `修复的模块`.
3. `摘要` is a placeholder. Replace it with a short English one-line summary. Do not literally output `摘要`.
4. `详细描述` is a placeholder. Replace it with 1 to 3 English sentences explaining what changed and why. Do not literally output `详细描述`.
5. `Log:`, `PMS:`, and `Influence:` are fixed field labels. Keep these labels exactly as written. Fill text after the colon only when there is known information. `PMS:` may remain empty if no PMS ID is known.

For example, if the modified files are only under documentation, the first line may be:

```text
fix(docs): clarify commit format rules
```

If the changed module is unclear, choose the closest component from the file paths or conversation instead of using a generic placeholder.

## Workflow

1. Inspect the repository changes before writing the message:
   - `git status --short`
   - `git diff --stat`
   - `git diff -- <relevant-files>`
   - `git diff --cached` if staged changes exist
2. Combine the git changes with the recent conversation context.
3. Identify the changed module for the scope in `fix(module)`.
4. Write a concise summary after the colon.
5. Write a concrete detailed description of what changed and why.
6. Fill `Log`, `PMS`, and `Influence` based on available information.

## Field Rules

`fix(修复的模块): 摘要`

- Keep `fix` as the default type unless the user explicitly requests another type.
- Use a short English module scope, such as `treeland`, `build`, `window`, `input`, `config`, `docs`, or the closest changed component.
- Keep the summary under 72 characters when practical.
- The summary should describe the user-visible or behavior-level fix, not the file operation.

`详细描述`

- Use 1 to 3 concise English sentences.
- Mention the core cause and implementation when the diff supports it.
- Do not invent issue IDs, test results, or product names.

`Log:`

- Use a short log-style sentence for the main change.
- If the project convention expects an ID and none is available, leave it empty after `Log:`.

`PMS:`

- Put the PMS/task/bug ID only if it appears in the conversation, branch name, diff, or user request.
- If no PMS value is available, leave it empty after `PMS:`.

`Influence:`

- State the affected area or risk in English.
- Prefer concrete influence, such as `Affects window switching logic` or `Affects Denote report generation`.
- If the change is documentation-only, use `Documentation only`.
- If the impact is unclear, use `Limited to the modified module`.

## Output Guidelines

- Output one commit message only.
- Do not include analysis, bullets, or alternative versions by default.
- Preserve the exact labels `Log:`, `PMS:`, and `Influence:`.
- Use English for the module scope, summary, detailed description, `Log:`, and `Influence:`.
- If there are unrelated changes, generate the commit message only for the changes the user likely wants. Ask a short clarification only when unrelated changes make a single commit message misleading.

## Example

```text
fix(build): handle optional dependency detection

Adjust dependency detection in the build script so missing optional components do not stop compilation. This keeps the default build flow working when optional features are unavailable.

Log: Fix optional dependency detection in the build flow
PMS:
Influence: Affects build-time dependency detection
```
