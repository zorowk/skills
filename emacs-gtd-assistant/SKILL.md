---
name: emacs-gtd-assistant
description: "Use when an AI assistant should manage the user's Emacs Org GTD tasks through the running Emacs server: list agenda items, add or reschedule tasks, set deadlines, mark tasks done/cancelled, delete/archive chosen tasks, or manage items in `~/Dropbox/brain/gtd.org`."
---

# Emacs GTD Assistant

Manage GTD through the running Emacs server. Load
`scripts/emacs-gtd-assistant.el`, then call `emacs-gtd-execute`. Start with filtered,
bounded `list` or `resolve`; use `:id` or a unique `:query` for mutations.

Present matches when ambiguous. Delete or archive only after explicit user
authorization and pass `:authorization explicit`. Prefer `DONE` for completed work.
Keep IDs internal and do not edit the Org file directly.
