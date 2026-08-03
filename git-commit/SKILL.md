---
name: git-commit
description: >-
  Inspect or review Git changes, generate evidence-backed commit messages, and perform explicitly
  requested commit or amend operations. Use when the user asks to review changes, prepare a commit
  message, commit, or amend.
---

# Git Commit

## Decision summary

```text
review? := explicit review request
commit? := explicit commit or amend request
mutate? := commit? AND exact authorized paths are known AND one truthful commit fits
done?   := committed paths equal authorized paths AND HEAD message matches
```

Every request is one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/ai-git-commit.el")
  (ai-git-commit-run REQUEST))
```

Replace `<skill-dir>` with this skill's directory and uppercase names with real
Elisp values. `REQUEST` is a plist beginning with `:operation`. Query exact
parameters before an unfamiliar operation:

```elisp
(ai-git-commit-run
 (list :operation (quote describe) :target (quote commit)))
```

Collect bounded evidence first:

```elisp
(ai-git-commit-run
 (list :operation (quote context) :directory DIRECTORY :paths PATHS))
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

Then derive the fields required by `commit` or `amend` from that result. Use only
fields returned by `describe`. Do not inspect the script unless the entry point
fails.
Context includes bounded diffs for untracked files, with truncation metadata;
do not infer their contents from `git status` alone.
When the intended file set is known, pass the same exact `:paths` to `context`.
It keeps global status visibility while excluding unrelated diff contents and
untracked-file reads.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Use this contract:

```text
PRE:
  commit or amend was explicitly requested
  claims are supported by actual changes and validation
  unrelated changes fit one truthful commit, or user resolved the split
ACTION:
  run with exact authorized paths and internal :validation
POST:
  committed paths = authorized paths
  HEAD message = requested message
```

Never invent issues, tests, products, or impact. Keep routine test commands, pass
counts, and validation results out of the commit body; report them after the
operation. Include validation in history only when explicitly requested.
Keep every generated commit-message line within the facade's 100-column limit.

For `commit` or `amend`, pass `:paths` with the exact repository files authorized
for the operation. The facade validates and stages those paths, commits only that
path set, and verifies the resulting HEAD message. Omit `:paths` only when the user
intentionally wants to commit the existing index as-is.
Path-scoped context returns status and content only for that path set; use
`:excluded-change-count` to detect unrelated repository changes without exposing
their names.

Prefer `:detail compact` for routine personal-repository work. Automatic detail
also stays compact for up to four low-risk or three medium-risk changes; use
`:detail full` when risk, boundaries, or independent change groups need visibility.
