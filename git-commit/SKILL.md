---
name: git-commit
description: >-
  Inspect or review Git changes, generate evidence-backed commit messages, and perform explicitly
  requested commit or amend operations. Use when the user asks to review changes, prepare a commit
  message, commit, or amend.
---

# Git Commit

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

The facade owns schema validation, authorization, path-scoped staging, message
formatting, mutation effects, and post-commit verification.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` on the
first attempt and request `prefix_rule: ["emacsclient", "--eval"]`. Treat socket
permission denial as a permission failure; report the server unavailable only if
the escalated call fails.

Before commit/amend, inspect `context` for the exact intended paths. Use full detail
only when boundaries, risk, or independent change groups matter. Split changes when
one truthful rationale does not cover all of them.

Never invent issues, tests, products, or impact. Keep routine validation out of the
commit narrative unless the user explicitly asks to preserve it in history.
