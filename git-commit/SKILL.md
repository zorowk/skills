---
name: git-commit
description: >-
  Inspect or review Git changes, generate evidence-backed commit messages, and perform explicitly
  requested commit or amend operations. Use when the user asks to review changes, prepare a commit
  message, commit, or amend.
---

# Git Commit

Resolve `scripts/ai-git-commit.el` from this skill directory, not the working
directory; load it and call `ai-git-commit-run`. Collect `context` before deriving
the structured evidence used by `format`, `commit`, or `amend`.
Call documented script entry points directly. If a facade schema is unclear, use
its `describe` operation. Do not inspect script implementations unless the
documented entry point fails.
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

Derive claims only from actual changes and validation. Do not invent issues, tests,
products, or impact. Ask when unrelated changes do not fit one truthful commit.
Treat commit and amend as authorized only when the user explicitly requested them.
Always supply `:validation` as internal evidence, but do not repeat test commands,
pass counts, or routine validation results in the commit body. Report them to the
user after the operation. Include validation in Git history only when the user
explicitly enables that formatter option.

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
