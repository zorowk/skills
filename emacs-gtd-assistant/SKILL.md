---
name: emacs-gtd-assistant
description: >-
  Query or manage Org GTD tasks through the running Emacs: list, add, reschedule, set deadlines or
  states, delete, or archive items in the configured GTD file.
---

# Emacs GTD Assistant

Load `scripts/emacs-gtd-assistant.el` and call `emacs-gtd-execute` through the
running Emacs server.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Present matches instead of guessing when resolution is ambiguous. Treat delete and
archive as authorized only when the user explicitly requested them. Prefer `DONE`
for completed work. Keep IDs internal and never bypass the facade by editing the
Org file directly.
