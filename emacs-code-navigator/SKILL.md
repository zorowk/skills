---
name: emacs-code-navigator
description: >-
  Query the running Emacs for capabilities, Help, definitions, live buffers, project code, Imenu,
  xref, Eldoc/Eglot, or Flymake context.
---

# Emacs Code Navigator

Use the running Emacs session for compact context, including unsaved buffers. Load
`scripts/emacs-code-navigator.el` from this skill directory. If the server is
unavailable, report the error and fall back to disk tools.

Call `emacs-code-navigator-query` as the primary interface. Start compact; pass
`:full t` only when bounded Help or context is insufficient. Discover capabilities
before guessing an API or reimplementing it in the shell.

Read `:data` from the standard result. Use `describe` only when an operation schema
is unclear; inspect explicit truncation metadata before requesting full output.

Use exact disk reads for generated files, logs, configuration, or when saved state
matters. Do not request project-wide diagnostics by default on large projects.
