---
name: emacs-gtd-assistant
description: "Use when an AI assistant should manage the user's Emacs Org GTD tasks through the running Emacs server: list agenda items, add or reschedule tasks, set deadlines, mark tasks done/cancelled, delete/archive chosen tasks, or manage items in `~/Dropbox/brain/gtd.org`."
---

# Emacs GTD Assistant

Manage GTD through the running Emacs server. Load
`scripts/emacs-gtd-assistant.el` from this skill directory. Use its public function
docstrings and validation errors as the interface; inspect source only to debug or
modify it.

- List tasks with `emacs-gtd-list`; summarize date, state, priority, and title.
- Add with `emacs-gtd-add-task`, selecting personal or work context unless the user
  chooses a specific heading.
- Before a title-based mutation, call `emacs-gtd-resolve-title`. Proceed only when
  it returns `:status resolved`; present returned matches when ambiguous.
- Delete or archive only with explicit authorization. Prefer `DONE` when the user
  says an item is finished.

Keep IDs internal unless needed to resolve ambiguity. Do not edit the Org file
directly or bypass a program validation error.
