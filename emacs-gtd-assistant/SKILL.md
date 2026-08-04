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
run?        := explicit persistent-task request
propose?    := actionable follow-up inferred but not confirmed
mutate?     := explicit confirmation AND unambiguous task target
done?       := requested task state is observable through the facade
```

Actionability permits a proposal, never mutation. Invoke the facade with one
self-loading expression; `REQUEST` is a plist beginning with `:operation`:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-execute REQUEST))
```

## Execution and recovery

```text
known schema       -> call operation directly
unknown schema     -> describe(target), then call
invalid-request #1 -> describe(target), revise once
invalid-request #2 -> stop
partial            -> preserve evidence/effects; retry only the safe remainder
stop               -> report effects and remaining goal; no more facade calls
```

Send only schema-declared fields. Inspect the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

```text
ambiguous match         -> present choices; stop
delete or archive       -> require explicit request
task merely mentioned   -> propose 1..3 candidates; stop
candidate confirmed     -> add-many with authorization=explicit
```

Prefer `DONE` for completed work. Keep IDs internal and never edit the Org file
directly. Use priority B for valuable research, A only for blocking or
time-sensitive work, and C for optional exploration.

Store short research background in `:context-notes`, queryable metadata in
`:properties`, and HTTP, documentation, or file references in structured
`:links`; never save the full transcript or raw Org drawer text.
