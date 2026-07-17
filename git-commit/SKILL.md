---
name: git-commit
description: >-
  Generate and validate evidence-backed Git commit messages for any repository. Use whenever the
  user asks to write, create, revise, amend, or perform a commit, or when another workflow needs a
  commit message. Collect actual changes, preserve 100-column formatting, and make the result easy
  for an AI or human to understand without reading the diff.
---

# Git Commit

Load `scripts/ai-git-commit.el` from this skill directory. Use
`ai-git-commit-run`: request compact `context`, derive fields from the evidence and
conversation, then request `format`. Use full context only when the bounded diff is
insufficient.

Supply the problem context, behavior-level changes, implementation reason, actual
validation, and unchanged boundary as structured inputs. Phrase them naturally; the
formatter orders them without section labels. Add `Log`, `PMS`, or `Influence`
trailers only when supported and useful.

Do not invent issues, tests, products, or impact. Ask when unrelated changes do not
fit one truthful commit. Commit or amend only when authorized. Return generated text
without a Markdown fence unless requested.
