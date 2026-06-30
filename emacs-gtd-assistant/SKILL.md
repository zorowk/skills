---
name: emacs-gtd-assistant
description: Manage the user's Emacs Org GTD tasks and schedule through the running Emacs server. Use when the user asks to list current agenda items, add a schedule/task, delete a task, mark a task done/cancelled, archive a task, or manage GTD items in ~/Dropbox/brain/gtd.org using Org mode.
---

# Emacs GTD Assistant

## User Setup

The user's Org GTD configuration is in Emacs:

- `org-agenda-dir`: `~/Dropbox/brain/`
- GTD file: `~/Dropbox/brain/gtd.org`
- Notes file: `~/Dropbox/brain/notes.org`
- Code snippet file: `~/Dropbox/brain/snippet.org`
- `org-agenda-files`: `("~/Dropbox/brain/")`

Relevant capture templates:

- `t`: Todo under `gtd.org` headline `Personal`
  - Template: `* TODO [#B] ...`
- `w`: work under `gtd.org` headline `Deepin`
  - Template: `* TODO [#A] ...`
- `n`: notes under `notes.org` headline `Quick notes`
- `l`: Learn under `notes.org` headline `Learning`

This skill uses `scripts/emacs-gtd-assistant.el` and the running Emacs server rather than editing Org files directly with shell commands.

## Calling The Helper

Load the helper before calling its functions:

```elisp
(load-file "/path/to/emacs-gtd-assistant/scripts/emacs-gtd-assistant.el")
```

From Codex:

```bash
emacsclient --eval '(progn
  (load-file "/path/to/emacs-gtd-assistant/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-list))'
```

## AI Workflow

For "目前有哪些行程" or similar:

1. Call `emacs-gtd-list`.
2. Summarize active items by date, todo state, priority, and headline.
3. Do not show `id` values by default; keep them for internal follow-up operations.
4. Show `id` or `line` only when the user asks for technical details or when ambiguity makes it necessary.
5. If `id` is nil, use `line` internally for disambiguation and call `emacs-gtd-ensure-id-at-line` only after the user chooses that item for modification.

For adding a task or schedule:

1. Infer whether it is personal or work.
2. Use headline `Personal` for personal items and `Deepin` for work items.
3. Call `emacs-gtd-add-task`.
4. Report the created item with its `id`.

For deleting, completing, cancelling, or archiving:

1. If the user did not provide an `id`, call `emacs-gtd-list` and identify likely matches.
2. If there is more than one plausible match, ask a short clarification.
3. If the chosen item has no `id`, call `emacs-gtd-ensure-id-at-line` with its `line`.
4. Call the relevant function with the item `id`.
5. Report the changed item and file.

## Function Reference

`(emacs-gtd-list &optional include-done)`

- Return GTD items from `~/Dropbox/brain/gtd.org`.
- Each item is an alist containing `id`, `todo`, `priority`, `title`, `scheduled`, `deadline`, `tags`, `file`, `line`, and `outline`.
- By default, omit `DONE` and `CANCELLED`.
- This is read-only and does not create IDs.

`(emacs-gtd-find-by-title QUERY &optional include-done)`

- Return items whose title matches regexp `QUERY`.
- Use this to narrow candidates before asking the user to choose.
- This is read-only and does not create IDs.

`(emacs-gtd-ensure-id-at-line LINE)`

- Ensure the GTD item at `LINE` has an ID and return the item.
- Use only after the user chooses a specific item that has no `id`.

`(emacs-gtd-add-task TITLE &optional PLIST)`

- Add a task to the GTD file.
- `PLIST` supports:
  - `:headline` target headline, default `Personal`
  - `:todo` todo keyword, default `TODO`
  - `:priority` priority string like `"A"` or `"B"`
  - `:scheduled` Org timestamp string like `"<2026-07-01 Wed 10:00>"`
  - `:deadline` Org timestamp string
  - `:body` extra body text
  - `:tags` list of tag strings

`(emacs-gtd-set-state ID STATE)`

- Set item state, e.g. `"DONE"`, `"CANCELLED"`, `"STARTED"`, `"WAITING"`.

`(emacs-gtd-delete ID)`

- Delete the task identified by `ID`.
- Use only when the user explicitly asks to delete/remove an item.

`(emacs-gtd-archive ID)`

- Archive the task identified by `ID` using Org's archive behavior.

`(emacs-gtd-reschedule ID TIMESTAMP)`

- Set or replace `SCHEDULED` timestamp.

`(emacs-gtd-set-deadline ID TIMESTAMP)`

- Set or replace `DEADLINE` timestamp.

## Safety Rules

- Do not delete or archive without a specific user request.
- Prefer marking `DONE` over deleting when the user says they finished something.
- If matching by title is ambiguous, ask for clarification before destructive changes.
- Preserve Org syntax; use helper functions instead of ad hoc text editing.
- Query functions must stay read-only.
- Keep IDs and line numbers available internally, but hide them from normal user-facing summaries.
- Return exact IDs only when the user asks for them or when needed to resolve an ambiguous operation.
