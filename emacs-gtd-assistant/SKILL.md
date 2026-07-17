---
name: emacs-gtd-assistant
description: >-
  Query or manage Org GTD tasks through the running Emacs: list, add, reschedule, set deadlines or
  states, delete, or archive items in the configured GTD file.
---

# Emacs GTD Assistant

Manage GTD through the running Emacs server. Load
`scripts/emacs-gtd-assistant.el`, then call `emacs-gtd-execute`. Start with filtered,
bounded `list` or `resolve`; use `:id` or a unique `:query` for mutations.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Read `:data` and follow `:page :next-offset`. Use `describe` only when a request
schema is unclear.

Present matches when ambiguous. Delete or archive only after explicit user
authorization and pass `:authorization explicit`. Prefer `DONE` for completed work.
Keep IDs internal and do not edit the Org file directly.
