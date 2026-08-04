---
name: emacs-gtd-assistant
description: >
  Manage persistent Org GTD tasks through Emacs. For conversation capture,
  propose candidates and wait for explicit confirmation; do not capture
  merely mentioned next steps.
---

# Emacs GTD Assistant

```text
actionable? := begins with a concrete action
               AND has an identifiable completion state
propose?    := actionable follow-up inferred but not confirmed
```

Actionability permits a proposal, never mutation. Invoke the facade with one
self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-execute REQUEST))
```

The facade owns request validation, authorization, target disambiguation, and effects.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

```text
task merely mentioned   -> propose 1..3 candidates; stop
candidate confirmed     -> add-many with authorization=explicit
```

Prefer `DONE` for completed work. Never bypass the facade to edit Org. Use priority
B for valuable research, A only for blocking or time-sensitive work, and C for
optional exploration.

Store short research background in `:context-notes`, queryable metadata in
`:properties`, and HTTP, documentation, or file references in structured
`:links`; never save the full transcript or raw Org drawer text.
