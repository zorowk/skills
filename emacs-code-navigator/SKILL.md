---
name: emacs-code-navigator
description: >-
  Use for code questions involving live Emacs buffers, cursor context, unsaved edits,
  diagnostics, definitions, references, or single- and multi-project navigation. Prefer live
  Emacs evidence over disk when editor state matters.
---

# Emacs Code Navigator

## Decision summary

```text
run?  := the answer depends on live Emacs or project-navigation evidence
live? := unsaved state OR cursor context OR session-backed capability
done? := requested evidence is returned with its source and limitations
```

Every request is one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-code-navigator.el")
  (emacs-code-navigator-query REQUEST))
```

Replace `<skill-dir>` with this skill's directory and uppercase names with real
Elisp values. `REQUEST` is a plist beginning with `:operation`. Query exact
parameters before an unfamiliar operation:

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

```text
known documented operation       -> call directly
schema unknown or version unsure -> describe, then call
first invalid-request            -> describe, revise, retry once
second invalid-request           -> report rejected fields; stop
status=partial                    -> preserve returned evidence;
                                     retry only the safe missing query
```

Treat `stop` as no further facade calls for the blocked goal in this turn. If
safe partial recovery is unclear, report returned evidence and the remaining
query, then stop.

Use only fields returned by `describe`. Do not inspect the script unless the entry
point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

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

Do not run this facade in batch Emacs as a substitute for the user's session.
When the server is unavailable, use direct filesystem reads for `search`,
`files`, and saved `region` work. Report live Help, xref, workspace symbols,
Eldoc/Eglot, and Flymake as unavailable; never silently replace them with batch
results. Request diagnostics only when relevant because they are evidence, not
a code-search backend.

For bounded automatic context in agent-shell, load
`scripts/agent-shell-code-context.el` and call
`emacs-code-navigator-agent-shell-enable`. It preserves explicit region and
error context priority, adds bounded definitions and synchronous Eldoc at the
actual cursor, reads existing Flymake diagnostics without starting Flymake,
and returns nil on failure so agent-shell fallbacks can continue.

Multi-project semantic queries reuse an existing project buffer or, under the
`open-on-demand` policy, visit one hidden anchor file per explicit project and
retain it for later queries. Use
`emacs-code-navigator-close-semantic-buffers` to close only navigator-owned,
unmodified, undisplayed anchors. Text fallback remains available when no live
semantic backend is ready.
