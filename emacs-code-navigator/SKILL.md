---
name: emacs-code-navigator
description: >-
  Query the running Emacs for capabilities, Help, definitions, live buffers, project code, Imenu,
  xref, Eldoc/Eglot, or Flymake context.
---

# Emacs Code Navigator

Load `scripts/emacs-code-navigator.el` and call
`emacs-code-navigator-query` through the running Emacs session.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Prefer live Emacs state for unsaved buffers and semantic context. Use exact disk
reads when saved bytes matter, especially for generated files, logs, or
configuration. Request diagnostics only when they are relevant to the question;
they are evidence, not a code-search backend.
