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

When operating from agent-shell with an Emacs server available, treat the
running Emacs as a capability registry. Before reimplementing an operation in
the shell or guessing an Emacs API, use `emacs-code-navigator-apropos` to search
names or documentation, then use `emacs-code-navigator-symbol-info` to inspect
the exact Help and source definition. Use `emacs-code-navigator-library-info`
when the relevant unit is a library rather than a symbol.

## Workflow

1. For Emacs capability discovery, search with apropos, inspect the selected
   function or variable, and follow its returned source location. Prefer these
   structured entry points over parsing interactive `*Help*` buffers.
2. For project code, locate with the project-files, search, or imenu entry point.
3. Expand the best hit with the context-at-line entry point.
4. Resolve relationships with the line-based xref entry points; use read-region only
   after identifying the relevant block.
5. Request line or file diagnostics when useful. Run project-wide diagnostics only
   when project-wide diagnostics justify visiting many files.

## When Not To Use

Do not use for simple non-code reads, exact path inspection, generated files, logs, JSON/YAML config, or cases where shell tools return a smaller answer. Do not run project-wide diagnostics by default on large projects.

Open Emacs buffers may include unsaved edits. Use shell reads when disk state is required.
