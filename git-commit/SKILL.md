---
name: git-commit
description: >-
  Inspect or review Git changes, generate evidence-backed commit messages, and perform explicitly
  requested commit or amend operations. Use when the user asks to review changes, prepare a commit
  message, commit, or amend.
---

# Git Commit

```text
review? := explicit review request
commit? := explicit commit or amend request
mutate? := commit? AND exact authorized paths are known AND one truthful commit fits
done?   := committed paths equal authorized paths AND HEAD message matches
truthful-commit? := one message accurately describes every included change
                    AND no change needs a materially different rationale
```

A feature and its focused tests can form one truthful commit. An unrelated
documentation cleanup bundled with that feature cannot.

Invoke the facade with one self-loading expression; `REQUEST` is a plist beginning
with `:operation`:

```elisp
(progn
  (load-file "<skill-dir>/scripts/ai-git-commit.el")
  (ai-git-commit-run REQUEST))
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

Before commit/amend, call `context` with the same exact authorized `:paths`. It returns
bounded tracked and untracked diffs plus `:excluded-change-count`; never infer untracked
content from status alone. Use `:detail full` only when boundaries, risk, or independent
change groups require it.

Pass conventional category and scope separately (`:type "fix"`, `:scope "theme"`),
truthful evidence-derived fields, required internal `:validation`, and explicit
authorization. Omit `:paths` only when the user intentionally authorizes the existing
index as-is.

Never invent issues, tests, products, or impact. Keep routine test commands, pass counts,
and validation results out of the commit body; report them afterward. Include validation
in history only when explicitly requested. Keep message lines within 100 columns.
