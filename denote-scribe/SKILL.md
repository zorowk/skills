---
name: denote-scribe
description: Convert a completed AI troubleshooting, coding, research, or problem-solving conversation into a concise Denote note in Org mode under the user's notes directory. Use when the user says phrases like "输出denote报告", "生成denote报告", "save this as a Denote report", "write a Denote note", or asks to summarize the just-finished AI chat into ~/Dropbox/notes using Emacs Denote.
---

# Denote Scribe

## Purpose

Create an Org-mode Denote report from the current AI conversation after the problem is solved. The default target directory is `~/Dropbox/notes`, and the implementation is the bundled Emacs Lisp file `scripts/denote-scribe.el`, which defines `denote-scribe-create` for the user's running Emacs/Denote session.

## Workflow

1. Confirm that the user is asking for a Denote report of the just-completed conversation. Do not use this skill for ordinary note-taking unless the user asks for Denote output.
2. Extract the useful content from the conversation:
   - Problem statement and context
   - Key investigation steps
   - Important commands, files, errors, and decisions
   - Final solution or result
   - Verification performed
   - Follow-up items or residual risks, if any
3. Generate a short Denote title from the actual solved problem.
4. Write a clean Org document body. Keep it as a report, not a transcript.
5. Save that body to a temporary `.org` file.
6. Load `scripts/denote-scribe.el` in the running Emacs session and call `denote-scribe-create` with the generated title and the temporary body file.
7. Report the created Denote file path to the user.

## Title Rules

Generate the `--title` value yourself from the conversation. Do not use generic titles such as `问题处理报告`, `AI聊天记录`, or `Denote报告`.

Rules:

- Use the same language as the conversation; prefer Chinese for Chinese conversations.
- Keep Chinese titles within 6 to 14 characters when practical, and never exceed 24 Chinese characters.
- Keep English titles within 3 to 8 words when practical.
- Describe the solved topic, not the reporting action.
- Omit dates, serial numbers, `ai`, `report`, and Denote keywords from the title.
- Prefer concrete nouns and verbs from the task, such as `Denote技能改造`, `Emacsclient调用`, or `登录错误修复`.

## Report Format

Use this structure unless the user asks for another format:

```org
* 摘要

* 背景

* 处理过程

* 关键决策

* 结果

* 验证

* 后续事项
```

Keep headings in Chinese by default when the conversation is in Chinese. Preserve exact commands, file paths, error messages, and code identifiers in monospace or source blocks where useful.

## Calling Emacs Lisp

The Elisp file path is relative to this skill directory. Call it through `emacsclient --eval` or from inside Emacs:

```elisp
(progn
  (load-file "/path/to/denote-scribe/scripts/denote-scribe.el")
  (denote-scribe-create
   "Denote技能改造"
   "/tmp/denote-report.org"
   '("ai" "report")
   "~/Dropbox/notes/"))
```

Function:

- `(denote-scribe-create TITLE BODY-FILE &optional KEYWORDS NOTES-DIR SIGNATURE DATE)`
- `TITLE`: Denote title. Generate it from the solved problem.
- `BODY-FILE`: UTF-8 Org body file created from the conversation summary.
- `KEYWORDS`: List of Denote keywords. Use `("ai" "report")` by default.
- `NOTES-DIR`: Denote directory. Default: `~/Dropbox/notes/`.
- `SIGNATURE`: Optional Denote signature.
- `DATE`: Optional Denote date passed to Denote.

## Failure Handling

If `emacsclient` connects but Denote is unavailable, diagnose whether it is connected to the same Emacs session the user is using. Ask the user to evaluate `(list (emacs-pid) server-name (fboundp 'denote) (locate-library "denote"))` inside their Emacs, then rerun `emacsclient` with the correct socket/server if needed.

If `emacsclient` cannot connect to a running Emacs server, tell the user to start the server with `(server-start)` or run Emacs as a daemon, then keep the generated Org body available so they can retry. Do not silently create a non-Denote filename unless the user asks for a fallback.

If Denote raises an argument/signature error, adjust `scripts/denote-scribe.el` for the installed Denote version. The current implementation targets Denote 4.x with the signature `denote TITLE KEYWORDS FILE-TYPE DIRECTORY DATE TEMPLATE SIGNATURE IDENTIFIER`.
