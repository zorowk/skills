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
needed and full context only when the bounded diff is insufficient.

Supply the problem context, behavior-level changes, implementation reason, actual
validation, and unchanged boundary as structured inputs. Phrase them naturally; the
formatter orders them without section labels. Add `Log`, `PMS`, or `Influence`
trailers only when supported and useful. Let `:detail auto` compact low-risk changes;
use `full` when the history needs every boundary explicitly.

Do not invent issues, tests, products, or impact. Ask when unrelated changes do not
fit one truthful commit. Commit or amend only when authorized. Return generated text
without a Markdown fence unless requested.
