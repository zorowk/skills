---
name: emacs-code-navigator
description: >-
  Use for code questions that depend on live Emacs buffers, cursor context, unsaved edits,
  diagnostics, definitions, references, or explicit single- and multi-project navigation. Prefer
  live evidence when editor state matters. Do not use for general explanations or saved-file
  questions that do not depend on editor or project state.
---

# Emacs Code Navigator

## Decision summary

```text
run?  := the answer depends on live Emacs or project-navigation evidence
live? := unsaved state OR cursor context OR session-backed capability
done? := requested evidence is returned with its source and limitations
```

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-code-navigator.el")
  (emacs-code-navigator-query REQUEST))
```

Replace `<skill-dir>` and uppercase placeholders with real Elisp values.
`REQUEST` is a plist beginning with `:operation`. Describe an unknown operation:

```elisp
(emacs-code-navigator-query
 (list :operation (quote describe) :target (quote locate)))
```

Typical project lookup:

```elisp
(emacs-code-navigator-query
 (list :operation (quote locate) :query QUERY :file FILE
       :source (quote live)))
```

## Execution and recovery

Call documented operations directly. Use `describe` only when the schema is
unknown or after the first `invalid-request`; revise and retry once. A second
invalid request stops the goal. On `partial`, preserve returned evidence, then
retry only the safe missing query.

`stop` means no further facade calls for the blocked goal in this turn. If safe
recovery is unclear, report returned evidence and the remaining query, then stop.

When `describe` is used, send only fields declared by the returned schema. Inspect
the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Operation selection

Choose operations directly:

```text
unsaved buffer                  -> source=live
saved content                   -> source=disk
one exact name                  -> symbol
several exact names             -> symbols
uncertain name or pattern search -> capability
uncertain project backend       -> locate
multiple explicit roots         -> locate-many(roots in user order)
```

Let `auto` retain the live-session default. Read `:provenance` before combining
results with disk or batch evidence; call `file-state` when live and disk may
differ. `symbols` preserves input order and returns `:found nil` for misses. Pass
`:full t` only for complete Help facets. Treat each project independently; never
assume an xref or clangd index crosses project boundaries.

## Live-session boundaries

Do not run this facade in batch Emacs as a substitute for the user's session.
When the server is unavailable, use direct filesystem reads for `search`,
`files`, and saved `region` work. Report live Help, xref, workspace symbols,
Eldoc/Eglot, and Flymake as unavailable; never silently replace them with batch
results. Request diagnostics only when relevant because they are evidence, not
a code-search backend.

## Agent-shell integration

For bounded automatic context in agent-shell, load
`scripts/agent-shell-code-context.el` and call
`emacs-code-navigator-agent-shell-enable`. It returns nil on failure so normal
agent-shell fallbacks can continue.

Open-on-demand semantic queries may retain navigator-owned hidden project
buffers. Use `emacs-code-navigator-close-semantic-buffers` for cleanup; it closes
only unmodified, undisplayed buffers. Text fallback remains available when no
live semantic backend is ready.
