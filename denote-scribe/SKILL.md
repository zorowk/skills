---
name: denote-scribe
description: Use when an AI assistant should save, export, or summarize a completed troubleshooting, coding, research, or problem-solving conversation as a Denote Org report in `~/Dropbox/notes` through the running Emacs server.
---

# Denote Scribe

## Purpose

Turn a completed AI problem-solving conversation into a concise Org Denote report. The assistant writes the report body; Emacs/Denote creates the note with correct filename and metadata.

## Load Helper

Load the helper before calling `denote-scribe-preflight` or
`denote-scribe-create`; the functions are not available until the script is
loaded into the running Emacs server.

```elisp
(let ((skill-root (or (getenv "SKILL_ROOT")
                      (expand-file-name "~/Documents/Code/skills/denote-scribe"))))
  (load-file (expand-file-name "scripts/denote-scribe.el" skill-root)))
```

If the skill is installed somewhere else, set `SKILL_ROOT` to this skill's
directory before evaluating the load form.

## Preflight

Call `denote-scribe-preflight` or verify `~/Dropbox/notes`, `emacsclient`, helper loading, and Denote availability. If a prerequisite fails, keep any generated Org body file and report the exact error.

## Workflow

1. Confirm the user wants a Denote report, not ordinary note-taking.
2. Extract problem, context, key investigation, decisions, solution/result, verification, and follow-ups.
3. Generate a concrete title from the solved topic.
4. Write a clean Org body to a temporary `.org` file.
5. Call `denote-scribe-create`.
6. Report the created Denote file path.

## Title

- Same language as conversation.
- Concrete topic, not "AI chat/report".
- Chinese: 6-14 chars when practical. English: 3-8 words.
- Omit dates, serial numbers, `ai`, `report`, and Denote keywords.

## Default Report Shape

```org
* 摘要
* 背景
* 处理过程
* 关键决策
* 结果
* 验证
* 后续事项
```

## Helpers

- `(denote-scribe-preflight &optional NOTES-DIR)`: check notes directory and Denote availability.
- `(denote-scribe-create TITLE BODY-FILE &optional KEYWORDS NOTES-DIR SIGNATURE DATE)`: create note; default keywords `("ai" "report")`.

Preserve exact commands, paths, errors, and identifiers where useful.
