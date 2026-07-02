---
name: emacs-code-navigator
description: Use the user's running Emacs server to inspect code faster with Emacs project, xref, imenu, Eldoc, Flymake, and Eglot/LSP capabilities. Use when Codex needs targeted Emacs-native code context instead of repeatedly using cat, grep, rg, sed, or broad shell reads.
---

# Emacs Code Navigator

## Purpose

Read code through the user's running Emacs session. Prefer Emacs project, xref, imenu, Eldoc, Flymake, and Eglot-aware navigation for targeted context gathering. Use ordinary shell tools only when Emacs cannot provide the needed result or when checking non-code artifacts is simpler.

## Setup

Load the helper into Emacs before using its functions:

```elisp
(load-file "/path/to/emacs-code-navigator/scripts/emacs-code-navigator.el")
```

From Codex, call it through `emacsclient --eval`:

```bash
emacsclient --eval '(progn
  (load-file "/path/to/emacs-code-navigator/scripts/emacs-code-navigator.el")
  (emacs-code-navigator-project-files "/path/to/repo"))'
```

Assume `emacsclient` can connect to the user's running Emacs server. If it cannot, report the connection error directly.

## Workflow

1. Load `scripts/emacs-code-navigator.el` into the Emacs server.
2. Identify the project root with `emacs-code-navigator-project-root`.
3. List candidate files with `emacs-code-navigator-project-files`.
4. Use targeted helpers before broad reads:
   - `emacs-code-navigator-read-region` for line ranges.
   - `emacs-code-navigator-search` for project regexp matches through Emacs xref.
   - `emacs-code-navigator-imenu` for symbols in one file.
   - `emacs-code-navigator-context-at-line` for compact symbol/defun/Eldoc/diagnostic context around one hit.
   - `emacs-code-navigator-xref-definitions-at-line` for definition lookup at an exact line.
   - `emacs-code-navigator-xref-references-at-line` for reference lookup at an exact line.
   - `emacs-code-navigator-xref-definitions` for fallback definition lookup by identifier.
   - `emacs-code-navigator-xref-references` for fallback reference lookup by identifier.
   - `emacs-code-navigator-eglot-managed-p` to check whether a file has Eglot/LSP active.
   - `emacs-code-navigator-defun-at-line` to read the function/form around a line.
   - `emacs-code-navigator-flymake-diagnostics` to read Flymake/Eglot diagnostics for one file.
   - `emacs-code-navigator-diagnostics-at-line` to read diagnostics near one line.
   - `emacs-code-navigator-symbol-at-line` to identify the symbol and context at a line.
   - `emacs-code-navigator-eldoc-at-line` to read Eldoc/Eglot hover-style documentation.
   - `emacs-code-navigator-project-diagnostics` to collect project-level Flymake diagnostics with file and diagnostic limits.
5. Fall back to `rg`, `sed`, or `cat` only when Emacs navigation is unavailable or a shell view is more direct.

## AI Navigation Flow

Use this flow flexibly; skip steps that do not help the current task:

1. **Map the project**: call `project-root` and `project-files` with a small limit to understand layout.
2. **Find entry points**: use `search` for user-mentioned names, errors, strings, or config keys.
3. **Inspect structure before content**: call `imenu` on promising files to see functions/classes/sections.
4. **Expand one result**: call `context-at-line` on the most relevant search hit.
5. **Use line-based language intelligence**: call `xref-definitions-at-line` or `xref-references-at-line` when definition/reference context is needed. Use identifier-only xref helpers only as fallback.
6. **Read narrow regions**: use `read-region` for nearby lines only after locating the relevant symbol or function.
7. **Check errors**: call `flymake-diagnostics` for one file, `diagnostics-at-line` for one hit, or `project-diagnostics` only when project-wide Emacs/Flymake diagnostics are explicitly useful.
8. **Then edit**: only after the code path, references, and diagnostics are clear.

Prefer returning compact Emacs data to the model over dumping large source files. The typical bare Codex loop is `search -> context-at-line -> xref-definitions-at-line/read-region`.

## When Not To Use

Do not use this skill for simple non-code file reads, exact path inspection, generated files, logs, JSON/YAML config, or cases where shell tools provide a smaller answer. Do not run project-wide diagnostics by default on large projects; prefer file-level diagnostics or line-level diagnostics unless the user asks for a project-wide Emacs/Flymake view.

When a file is already open in Emacs, helpers may observe the current Emacs buffer contents, including unsaved edits. Use shell reads when disk state is required.

## Function Reference

All functions return printable Lisp data that Codex can read from `emacsclient --eval`.

`(emacs-code-navigator-project-root DIRECTORY)`

- Return the Emacs project root for `DIRECTORY`, or the directory itself when no project is found.

`(emacs-code-navigator-project-files DIRECTORY &optional LIMIT)`

- Return project files relative to the project root.
- Use `LIMIT` to avoid huge results. Default: 500.

`(emacs-code-navigator-read-region FILE START-LINE &optional END-LINE)`

- Return lines from `FILE`, including line numbers.
- Prefer this over reading entire large files.

`(emacs-code-navigator-search DIRECTORY REGEXP &optional LIMIT)`

- Search project files for `REGEXP` using Emacs' `xref-matches-in-files`.
- Return `(file line summary)` entries.
- The actual search backend follows Emacs' `xref-search-program`.
- Default limit: 100 matches.

`(emacs-code-navigator-imenu FILE)`

- Return top-level symbols known to Emacs for `FILE`.
- Useful before opening a large source file.

`(emacs-code-navigator-xref-definitions-at-line FILE LINE &optional IDENTIFIER)`

- Visit `FILE`, move to `LINE`, and ask xref/Eglot for definitions at that exact context.
- Use `IDENTIFIER` only to disambiguate which symbol on the line should be used.

`(emacs-code-navigator-xref-references-at-line FILE LINE &optional IDENTIFIER)`

- Visit `FILE`, move to `LINE`, and ask xref/Eglot for references at that exact context.
- Use `IDENTIFIER` only to disambiguate which symbol on the line should be used.

`(emacs-code-navigator-xref-definitions FILE IDENTIFIER)`

- Fallback: visit `FILE`, find the first occurrence of `IDENTIFIER`, and ask xref/Eglot for definitions.
- Prefer the line-based helper when the search result includes a line number.

`(emacs-code-navigator-xref-references FILE IDENTIFIER)`

- Fallback: visit `FILE`, find the first occurrence of `IDENTIFIER`, and ask xref/Eglot for references.
- Prefer the line-based helper when the search result includes a line number.

`(emacs-code-navigator-eglot-managed-p FILE)`

- Return non-nil when `FILE` is managed by Eglot in the current Emacs session.

`(emacs-code-navigator-symbol-at-line FILE LINE)`

- Return `(symbol bounds major-mode eglot-managed defun-line)`.
- Use this after a search hit to know what identifier and function context the line belongs to.

`(emacs-code-navigator-defun-at-line FILE LINE)`

- Return the top-level function/form around `LINE`.
- Use this after search/xref finds a relevant line, instead of reading a large file.

`(emacs-code-navigator-flymake-diagnostics FILE)`

- Return Flymake diagnostics as `(beg-line end-line type text)`.
- When Eglot manages the file, this exposes LSP diagnostics through Emacs' Flymake interface.

`(emacs-code-navigator-diagnostics-at-line FILE LINE &optional RADIUS)`

- Return Flymake diagnostics near `LINE` in `FILE`.
- `RADIUS` defaults to 0, meaning only diagnostics whose range contains `LINE`.

`(emacs-code-navigator-project-diagnostics DIRECTORY &optional LIMIT FILE-LIMIT)`

- Return project diagnostics as `(file beg-line end-line type text)`.
- `LIMIT` defaults to 200 diagnostics. `FILE-LIMIT` defaults to 50 visited files to avoid opening very large projects accidentally.
- Use this only when project-wide Emacs/Flymake diagnostics are explicitly useful.

`(emacs-code-navigator-context-at-line FILE LINE &optional DIAGNOSTIC-RADIUS)`

- Return a compact plist containing symbol data, surrounding defun, Eldoc strings, and diagnostics near `LINE`.
- This is the preferred expansion step after `search` finds a promising line.

## Usage Rules

- Prefer small, targeted calls and iterate.
- Do not dump entire files unless the file is short or the full context is needed.
- Use `imenu` to understand structure before reading implementation details.
- Use line-based xref helpers for definitions and references when a search result includes a line number.
- Use identifier-only xref helpers only as fallback because they use the first matching identifier in the file.
- Use `symbol-at-line`, `defun-at-line`, `eldoc-at-line`, and `context-at-line` to understand a specific hit before expanding context.
- Use Flymake diagnostics when debugging compile, type, or LSP-reported errors.
- Use `project-files` and `search` to locate relevant files before editing.
- Avoid project-wide diagnostics on large projects unless the user explicitly asks for them.
- If Emacs returns an error, report the error and use shell tools as fallback.

## Examples

List project files:

```elisp
(emacs-code-navigator-project-files "/home/uos/src/project" 100)
```

Read lines 20 to 80:

```elisp
(emacs-code-navigator-read-region "/home/uos/src/project/src/main.cpp" 20 80)
```

Find definitions:

```elisp
(emacs-code-navigator-xref-definitions
 "/home/uos/src/project/src/main.cpp"
 "createSurface")
```
