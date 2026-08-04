---
name: emacs-code-navigator
description: >-
  Use for code questions that depend on live Emacs buffers, cursor context, unsaved edits,
  diagnostics, definitions, references, or explicit single- and multi-project navigation. Prefer
  live evidence when editor state matters. Do not use for general explanations or saved-file
  questions that do not depend on editor or project state.
---

# Emacs Code Navigator

```text
run?  := the answer depends on live Emacs or project-navigation evidence
live? := unsaved state OR cursor context OR session-backed capability
done? := requested evidence is returned with its source and limitations
```

Invoke the facade with one self-loading expression; `REQUEST` is a plist beginning
with `:operation`:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-code-navigator.el")
  (emacs-code-navigator-query REQUEST))
```

## Execution and recovery

```text
known schema       -> call operation directly
unknown schema     -> describe(target), then call
invalid-request #1 -> describe(target), revise once
invalid-request #2 -> stop
partial            -> keep returned evidence; retry only the safe missing query
stop               -> report evidence and remaining query; no more facade calls
```

Send only schema-declared fields. Inspect the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

## Operation selection

```text
unsaved buffer                   -> source=live
saved content                    -> source=disk
one exact name                   -> symbol(:name)
several exact names              -> symbols(:names)
uncertain name or pattern        -> capability
uncertain project backend        -> locate
multiple explicit roots          -> locate-many(roots in user order)
```

Let `auto` retain the live-session default. Read `:provenance` before combining
results with disk evidence; call `file-state` when live and disk may differ.
`symbols` preserves input order and reports misses. Use `:full t` only for complete
Help facets. Treat projects independently; never assume xref or clangd crosses roots.

## Live-session boundaries

Do not run this facade in batch Emacs as a substitute for the user's session.
When the server is unavailable, use direct filesystem reads for `search`,
`files`, and saved `region` work. Report live Help, xref, workspace symbols,
Eldoc/Eglot, and Flymake as unavailable; never silently replace them with batch
results. Diagnostics are evidence, not a search backend; request them only when relevant.

## Agent-shell integration

For bounded automatic context in agent-shell, load
`scripts/agent-shell-code-context.el` and call
`emacs-code-navigator-agent-shell-enable`. It returns nil on failure so normal
fallbacks continue. Open-on-demand queries may retain navigator-owned hidden
buffers; `emacs-code-navigator-close-semantic-buffers` closes only unmodified,
undisplayed ones. Use text fallback when no live semantic backend is ready.
