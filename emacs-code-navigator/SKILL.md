---
name: emacs-code-navigator
description: "Use when an AI assistant should treat the user's running Emacs as a source of capabilities and targeted code context: discover functions, commands, variables, and libraries; read Help documentation; locate definitions; or inspect project files, imenu, xref, Eldoc/Eglot, Flymake, and current buffer state."
---

# Emacs Code Navigator

Use the running Emacs session for compact context, including unsaved buffers. Load
`scripts/emacs-code-navigator.el` from this skill directory. If the server is
unavailable, report the error and fall back to disk tools.

Call `emacs-code-navigator-query` as the primary interface. Start compact; pass
`:full t` only when bounded Help or context is insufficient. Discover capabilities
before guessing an API or reimplementing it in the shell.

Use exact disk reads for generated files, logs, configuration, or when saved state
matters. Do not request project-wide diagnostics by default on large projects.
