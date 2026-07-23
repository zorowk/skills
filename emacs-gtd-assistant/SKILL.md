---
name: emacs-gtd-assistant
description: >-
  Query or manage Org GTD tasks through the running Emacs, including capturing confirmed follow-up
  work from agent-shell conversations with priorities, tags, context, properties, and resource
  links; also list, add, reschedule, set deadlines or states, delete, or archive tasks.
---

# Emacs GTD Assistant

Resolve `scripts/emacs-gtd-assistant.el` from this skill directory, not the working
directory; load it and call `emacs-gtd-execute` through the running Emacs
server.

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

For conversation capture, first present one to three editable candidates without
mutation. Use priority B for valuable research by default, A only for blocking or
time-sensitive work, and C for optional exploration. After the user explicitly
confirms the selected candidates, call `add-many` with `:authorization explicit`.
Store short research background in `:context-notes`, queryable metadata in
`:properties`, and HTTP, documentation, or file references in structured
`:links`; never save the full transcript or raw Org drawer text.

For the English agent-shell action, load
`scripts/agent-shell-gtd-capture.el` and call
`agent-shell-gtd-capture-enable`. The action asks the same Agent to extract from
its previous answer, suppresses follow-up capture loops, and never writes before
confirmation.
