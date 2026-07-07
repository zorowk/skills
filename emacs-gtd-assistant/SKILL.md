---
name: emacs-gtd-assistant
description: "Use when Codex should manage the user's Emacs Org GTD tasks through the running Emacs server: list agenda items, add or reschedule tasks, set deadlines, mark tasks done/cancelled, delete/archive chosen tasks, or manage items in `~/Dropbox/brain/gtd.org`."
---

# Emacs GTD Assistant

## Purpose

Manage the user's Org GTD file through Emacs, not ad hoc text edits. Defaults: GTD file `~/Dropbox/brain/gtd.org`, agenda dir `~/Dropbox/brain/`. Use `Personal` for personal tasks and `Deepin` for work tasks unless the user says otherwise.

Load the helper before calling any GTD function; the functions are not available until the script is loaded into the running Emacs server.
For the installed Codex skill:

```elisp
(load-file (expand-file-name "~/.codex/skills/emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"))
```

When working from this source repository instead:

```elisp
(load-file (expand-file-name "~/Documents/Code/skills/emacs-gtd-assistant/scripts/emacs-gtd-assistant.el"))
```

## Preflight

Before any write operation:

1. Confirm `~/Dropbox/brain/gtd.org` exists.
2. Confirm `emacsclient` can reach the running Emacs server.
3. Load the helper.
4. If any step fails, report the exact error and stop before changing files.

## Workflow

- List agenda/tasks: call `emacs-gtd-list`; summarize date, todo state, priority, and title. Hide IDs/lines unless needed.
- Add task/schedule: normalize user dates with `emacs-gtd-normalize-timestamp` when needed, then call `emacs-gtd-add-task`.
- Modify existing item: list/find candidates first; if ambiguous, ask. If the chosen item has no ID, call `emacs-gtd-ensure-id-at-line`, then mutate by ID.
- Delete/archive only on explicit user request. Prefer `DONE` when the user says they finished something.

## Key Helpers

| Need | Call |
|---|---|
| List active items | `emacs-gtd-list` |
| Find by title | `emacs-gtd-find-by-title` |
| Ensure ID | `emacs-gtd-ensure-id-at-line` |
| Parse date | `emacs-gtd-normalize-timestamp` |
| Add task | `emacs-gtd-add-task` |
| Set state | `emacs-gtd-set-state` |
| Reschedule/deadline | `emacs-gtd-reschedule`, `emacs-gtd-set-deadline` |
| Delete/archive | `emacs-gtd-delete`, `emacs-gtd-archive` |

`emacs-gtd-add-task` supports `:headline`, `:todo`, `:priority`, `:scheduled`, `:deadline`, `:body`, and `:tags`.

## Safety

- Query helpers stay read-only.
- Preserve Org syntax by using helpers.
- Keep IDs internal unless ambiguity requires showing them.
- Ask before destructive changes when matching is unclear.
