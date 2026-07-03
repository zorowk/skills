---
name: emacs-code-navigator
description: "Use when Codex needs targeted code context from the user's running Emacs server: project files, imenu symbols, exact-line xref definitions/references, Eldoc/Eglot hints, Flymake diagnostics, or current Emacs buffer state instead of broad cat/grep/rg/sed reads."
---

# Emacs Code Navigator

## Purpose

Use the running Emacs session as a compact code-context provider. Prefer it when Emacs project, buffers, imenu, xref, Eglot/Eldoc, Flymake, or unsaved buffer state can narrow what Codex needs to read.

Load the helper before calling functions:

```elisp
(load-file "/path/to/emacs-code-navigator/scripts/emacs-code-navigator.el")
```

Call through `emacsclient --eval`. If Emacs cannot connect, report the exact error and fall back to shell tools.

## Bare Codex Workflow

1. Map: `project-root`, then `project-files` with a small limit.
2. Find: `search` for user-mentioned symbols, errors, strings, or keys.
3. Structure: `imenu` on the most relevant file.
4. Expand: `context-at-line` on the best hit.
5. Resolve: `xref-definitions-at-line` / `xref-references-at-line` when needed.
6. Read: `read-region` only after locating the relevant function/block.
7. Diagnose: `diagnostics-at-line` or `flymake-diagnostics`; use `project-diagnostics` only when project-wide Emacs/Flymake diagnostics are explicitly useful.

Typical loop: `search -> context-at-line -> xref-definitions-at-line/read-region`.

## When Not To Use

Do not use for simple non-code reads, exact path inspection, generated files, logs, JSON/YAML config, or cases where shell tools return a smaller answer. Do not run project-wide diagnostics by default on large projects.

Open Emacs buffers may include unsaved edits. Use shell reads when disk state is required.

## Key Helpers

| Need | Call |
|---|---|
| Project root/files | `project-root`, `project-files` |
| Project search | `search` |
| File symbols | `imenu` |
| Expand one hit | `context-at-line` |
| Exact-line xref | `xref-definitions-at-line`, `xref-references-at-line` |
| Fallback xref | `xref-definitions`, `xref-references` |
| Narrow read | `read-region` |
| Diagnostics | `diagnostics-at-line`, `flymake-diagnostics`, `project-diagnostics` |

Line-based xref is preferred. Identifier-only xref uses the first matching identifier in the file.

## Usage Rules

- Keep calls small and targeted.
- Prefer compact helper output over dumping source files.
- Use `context-at-line` before expanding to larger regions.
- Report Emacs errors directly; do not invent context.
