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

Every request is one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/emacs-gtd-assistant.el")
  (emacs-gtd-execute REQUEST))
```

Replace `<skill-dir>` with this skill's directory and uppercase names with real
Elisp values. `REQUEST` is a plist beginning with `:operation`. Query exact
parameters before an unfamiliar operation:

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

```text
known documented operation       -> call directly
schema unknown or version unsure -> describe, then call
first invalid-request            -> describe, revise, retry once
second invalid-request           -> report rejected fields; stop
status=partial                    -> inspect effects and verification;
                                     preserve completed effects;
                                     retry only the safe remainder
```

Treat `stop` as no further facade calls for the blocked goal in this turn,
especially no effectful calls. If safe partial recovery is unclear, enumerate
observed effects and the remaining goal, then stop.

Use only fields returned by `describe`. Do not inspect the script unless the entry
point fails.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

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
