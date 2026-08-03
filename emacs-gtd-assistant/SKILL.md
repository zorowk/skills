---
name: emacs-gtd-assistant
description: >
  Manage persistent Org GTD tasks through Emacs. For conversation capture,
  propose candidates and wait for explicit confirmation; do not capture
  merely mentioned next steps.
---

# Emacs GTD Assistant

## Decision summary

```text
run?    := explicit persistent-task request
propose := actionable follow-up is inferred but not confirmed
mutate? := explicit confirmation AND unambiguous task target
done?   := requested task state is observable through the facade
```

## Semantic predicates

```text
actionable? := begins with a concrete action
               AND has an identifiable completion state
```

"Compare the two backends and record the result" is actionable. "Eglot may be
interesting" is not. Actionability permits a proposal, never an unconfirmed
mutation.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-execute REQUEST))
```

Replace `<skill-dir>` and uppercase placeholders with real Elisp values.
`REQUEST` is a plist beginning with `:operation`. Describe an unknown operation:

```elisp
(emacs-gtd-execute
 (list :operation (quote describe) :target (quote add-many)))
```

Confirmed conversation capture:

```elisp
(emacs-gtd-execute
 (list :operation (quote add-many) :tasks TASKS
       :authorization (quote explicit)))
```

## Execution and recovery

Call documented operations directly. Use `describe` only when the schema is
unknown or after the first `invalid-request`; revise and retry once. A second
invalid request stops the goal. On `partial`, preserve returned evidence and
effects, then retry only the safe remainder.

`stop` means no further facade calls for the blocked goal in this turn. If safe
recovery is unclear, report observed effects and the remaining goal, then stop.

When `describe` is used, send only fields declared by the returned schema. Inspect
the script only if the entry point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

Follow these gates:

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
