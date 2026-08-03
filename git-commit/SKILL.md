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

## Semantic predicates

```text
truthful-commit? := one message accurately describes every included change
                    AND no change needs a materially different rationale
```

A feature and its focused tests can form one truthful commit. An unrelated
documentation cleanup bundled with that feature cannot.

Invoke the facade with one self-loading expression:

```elisp
(progn
  (load-file "<skill-dir>/scripts/ai-git-commit.el")
  (ai-git-commit-run REQUEST))
```

Replace `<skill-dir>` and uppercase placeholders with real Elisp values.
`REQUEST` is a plist beginning with `:operation`. Describe an unknown operation:

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

Call documented operations directly. Use `describe` only when the schema is
unknown or after the first `invalid-request`; revise and retry once. A second
invalid request stops the goal. On `partial`, preserve returned evidence and
effects, then retry only the safe remainder.

`stop` means no further facade calls for the blocked goal in this turn. If safe
recovery is unclear, report observed effects and the remaining goal, then stop.

Derive `commit` or `amend` fields from that result. When `describe` is used, send
only fields declared by the returned schema. Inspect the script only if the entry
point fails.
Context includes bounded diffs for untracked files, with truncation metadata;
do not infer their contents from `git status` alone.
When the intended file set is known, pass the same exact `:paths` to `context`.
It keeps global status visibility while excluding unrelated diff contents and
untracked-file reads.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

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

Use `:detail full` only when risk, boundaries, or independent change groups need
visibility; otherwise let `auto` choose.
