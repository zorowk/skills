---
name: git-commit
description: >-
  Generate evidence-backed Git messages for any write, commit, revision, or amend request; collect
  actual changes, adapt detail to risk, and preserve natural 100-column output for AI and humans.
---

# Git Commit

Load `scripts/ai-git-commit.el` and call `ai-git-commit-run`. Collect `context`
before deriving the structured evidence used by `format`, `commit`, or `amend`.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Derive claims only from actual changes and validation. Do not invent issues, tests,
products, or impact. Ask when unrelated changes do not fit one truthful commit.
Treat commit and amend as authorized only when the user explicitly requested them.
