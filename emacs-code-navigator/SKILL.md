---
name: emacs-code-navigator
description: "Use when an AI assistant needs targeted code context from the user's running Emacs server: project files, imenu symbols, exact-line xref definitions/references, Eldoc/Eglot hints, Flymake diagnostics, or current Emacs buffer state instead of broad file reads."
---

# Emacs Code Navigator

Use the running Emacs session for compact context, including unsaved buffers. Load
`scripts/emacs-code-navigator.el` from this skill directory. If the server is
unavailable, report the error and fall back to disk-based tools.
Use the public `emacs-code-navigator-` functions and their docstrings as the
interface; inspect source only to debug or modify it.

## Workflow

1. Locate with the project-files, search, or imenu entry point.
2. Expand the best hit with the context-at-line entry point.
3. Resolve relationships with the line-based xref entry points; use read-region only
   after identifying the relevant block.
4. Request line or file diagnostics when useful. Run project-wide diagnostics only
   when project-wide diagnostics justify visiting many files.

## When Not To Use

Do not use for simple non-code reads, exact path inspection, generated files, logs, JSON/YAML config, or cases where shell tools return a smaller answer. Do not run project-wide diagnostics by default on large projects.

Open Emacs buffers may include unsaved edits. Use shell reads when disk state is required.
