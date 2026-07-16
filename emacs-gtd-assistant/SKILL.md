---
name: emacs-gtd-assistant
description: "Use when an AI assistant should manage the user's Emacs Org GTD tasks through the running Emacs server: list agenda items, add or reschedule tasks, set deadlines, mark tasks done/cancelled, delete/archive chosen tasks, or manage items in `~/Dropbox/brain/gtd.org`."
---

# Emacs GTD Assistant

Manage GTD through the running Emacs server. Load
`scripts/emacs-gtd-assistant.el` from this skill directory and call
`emacs-gtd-preflight`; report exact failures.
Treat bundled scripts as executable implementations: during normal use, load and
call documented entry points without reading source. Inspect source only when
debugging, modifying a script, or resolving undocumented behavior.

## Workflow

- List agenda/tasks: call `emacs-gtd-list`; summarize date, todo state, priority, and title. Hide IDs/lines unless needed.
- Add a task with `emacs-gtd-add-task`. Use `Personal` for personal tasks and
  `Deepin` for work unless the user chooses another heading.
- Modify existing item: list/find candidates first; if ambiguous, ask. If the chosen item has no ID, call `emacs-gtd-ensure-id-at-line`, then mutate by ID.
- Delete/archive only on explicit user request. Prefer `DONE` when the user says they finished something.

Mutation helpers are `emacs-gtd-set-state`, `emacs-gtd-reschedule`,
`emacs-gtd-set-deadline`, `emacs-gtd-delete`, and `emacs-gtd-archive`.

Keep IDs internal unless needed to resolve ambiguity. Do not edit the Org file
directly or perform destructive actions without clear authorization.
