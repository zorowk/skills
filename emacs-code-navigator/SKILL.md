---
name: emacs-code-navigator
description: "Use when an AI assistant should treat the user's running Emacs as a source of capabilities and targeted code context: discover functions, commands, variables, and libraries; read Help documentation; locate definitions; or inspect project files, imenu, xref, Eldoc/Eglot, Flymake, and current buffer state."
---

# Emacs Code Navigator

Use the running Emacs session for compact context, including unsaved buffers. Load
`scripts/emacs-code-navigator.el` from this skill directory. If the server is
unavailable, report the error and fall back to disk-based tools.
Use the public `emacs-code-navigator-` functions and their docstrings as the
interface; inspect source only to debug or modify it.

Treat the session as a capability registry. Call `emacs-code-navigator-discover`
before guessing an Emacs API or reimplementing it in the shell; use the library
entry point when the relevant unit is a library.

For project code, locate a line with the project search or Imenu entry points, then
call `emacs-code-navigator-context-at-line`. Use line-based xref for relationships
and read-region only for a block already identified. Request project-wide
diagnostics only when visiting many files is justified.

Do not use for simple non-code reads, exact path inspection, generated files, logs, JSON/YAML config, or cases where shell tools return a smaller answer. Do not run project-wide diagnostics by default on large projects.

Open Emacs buffers may include unsaved edits. Use shell reads when disk state is required.
