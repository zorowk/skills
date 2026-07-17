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

Use `locate` as the default code-discovery entry point. Give it `:file` context
when available so it can prefer xref workspace symbols (Eglot/clangd for managed
C/C++ buffers), then fall back to bounded text search. Use `xref` with `:line` for
precise definitions or references. Use `search` directly for literals, messages,
macros, or regexps; narrow large searches with `:glob` and a small `:limit`.

Use `context` for a bounded live-buffer region. Its default is deliberately cheap.
Request `:defun t`, `:eldoc t`, or `:diagnostics t` only when that data is needed.
Flymake is a diagnostics transport (including Eglot language-server diagnostics),
not a normal code-search backend; never trigger it during ordinary navigation.

Read `:data` from the standard result. Use `describe` only when an operation schema
is unclear; inspect explicit truncation metadata before requesting full output.

Use exact disk reads for generated files, logs, configuration, or when saved state
matters. Do not request project-wide diagnostics by default on large projects.
