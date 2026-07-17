---
name: git-commit
description: >-
  Generate evidence-backed Git messages for any write, commit, revision, or amend request; collect
  actual changes, adapt detail to risk, and preserve natural 100-column output for AI and humans.
---

# Git Commit

Load `scripts/ai-git-commit.el` and call `ai-git-commit-run`. Collect `context`
before deriving the structured evidence used by `format`, `commit`, or `amend`.
Context includes bounded diffs for untracked files, with truncation metadata;
do not infer their contents from `git status` alone.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Derive claims only from actual changes and validation. Do not invent issues, tests,
products, or impact. Ask when unrelated changes do not fit one truthful commit.
Treat commit and amend as authorized only when the user explicitly requested them.

For `commit` or `amend`, pass `:paths` with the exact repository files authorized
for the operation. The facade validates and stages those paths, commits only that
path set, and verifies the resulting HEAD message. Omit `:paths` only when the user
intentionally wants to commit the existing index as-is.

Prefer `:detail compact` for routine personal-repository work. Automatic detail
also stays compact for up to four low-risk or three medium-risk changes; use
`:detail full` when risk, boundaries, or independent change groups need visibility.
