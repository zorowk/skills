---
name: emacs-code-navigator
description: >-
  Query the running Emacs for capabilities, Help, definitions, live buffers, project code, Imenu,
  xref, Eldoc/Eglot, or Flymake context.
---

# Emacs Code Navigator

Resolve `scripts/emacs-code-navigator.el` from this skill directory, not the working
directory; load it and call `emacs-code-navigator-query` through the
running Emacs session.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Pass `:source live` for unsaved buffers and `:source disk` when saved contents
matter. Let `auto` retain the live-session default. Read each result's
`:provenance` before combining it with filesystem or batch evidence, and call
`file-state` when the live buffer may differ from disk.

Use `symbol` for one exact name and `symbols` for several exact names in one
request. The batch operation preserves input order and reports unknown names as
`:found nil`; pass `:full t` only when complete Help facets are needed. Use
`capability` instead when the name is uncertain or pattern discovery is needed.
Use `locate` first for project code when the appropriate backend is uncertain.

Do not run this facade in batch Emacs as a substitute for the user's session.
When the server is unavailable, use direct filesystem reads for `search`,
`files`, and saved `region` work. Report live Help, xref, workspace symbols,
Eldoc/Eglot, and Flymake as unavailable; never silently replace them with batch
results. Request diagnostics only when relevant because they are evidence, not
a code-search backend.
