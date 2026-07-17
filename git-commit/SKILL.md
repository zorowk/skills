---
name: git-commit
description: >-
  Generate evidence-backed Git messages for any write, commit, revision, or amend request; collect
  actual changes, adapt detail to risk, and preserve natural 100-column output for AI and humans.
---

# Git Commit

Load `scripts/ai-git-commit.el` from this skill directory. Use
`ai-git-commit-run`: request compact `context`, derive evidence, then request
`format`. Read `:data` and explicit truncation metadata; use `describe` only when
needed and full context only when the bounded diff is insufficient. For an
authorized write, send the same structured evidence to the `commit` or `amend`
operation with `:authorization explicit`.

Run `emacsclient --eval` with `sandbox_permissions: "require_escalated"` from the
first attempt and request the narrow reusable `prefix_rule: ["emacsclient",
"--eval"]`, so the user can allow or reject server-socket access. Never interpret
a sandbox `Operation not permitted` or socket-access denial as evidence that the
Emacs server is down. Report it unavailable only when the escalated attempt also
fails.

Supply the problem context, behavior-level changes, implementation reason, actual
validation, and unchanged boundary as structured inputs. Phrase them naturally; the
formatter orders them without section labels. Add `Log`, `PMS`, or `Influence`
trailers only when supported and useful. Let `:detail auto` compact low-risk changes;
use `full` when the history needs every boundary explicitly.

Treat `:data` returned by `format` as the immutable final message. Use the
facade's `commit` or `amend` operation instead of invoking Git from a shell. The
facade passes that exact string to Magit as one message argument with verbatim
cleanup, without a temporary message file or editor window. Never retype,
reflow, summarize, or reconstruct it with multiple message arguments. The
facade reads the committed `%B`, normalizes only its terminal newline, verifies
that it equals the formatter output, and checks every line against the
100-column limit. If exact transport or verification is unavailable, it stops
with an error.

Do not invent issues, tests, products, or impact. Ask when unrelated changes do not
fit one truthful commit. Commit or amend only when authorized. Return generated text
without a Markdown fence unless requested.
