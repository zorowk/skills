---
name: skill-usage-review
description: >-
  Evaluate skills used in the current conversation across correctness, evidence sufficiency,
  safety, and economy without combining those dimensions into one score. Diagnose observed
  recovery cost, latent recovery risk, context use, retries, and avoidable output. Use after a
  tool-driven task when the user asks how well, efficiently, or economically the skills performed.
---

# Skill Usage Review

```text
evidence := calls + results + errors + metrics + outcomes visible in this conversation
allowed? := review needs no rerun, file mutation, or new telemetry
order    := correctness -> evidence sufficiency -> safety -> economy
praise economy only if earlier dimensions pass
```

State when missing history limits the assessment.
Do not sum, average, weight, or otherwise combine the four ratings.

Use matching-version facade metrics when available: request and response character counts, field
count, elapsed time, result count, truncation, degradation, and resolved source. Character counts
are local proxies, not exact model tokens. Field count measures interface surface, not cognitive
difficulty. Metrics are diagnostic evidence, not optimization targets.

Classify visible output as essential, safety-related, or redundant. Estimate context efficiency as
a range, never false precision:

```text
(essential characters + safety characters) / measured base response characters
```

Explain the classification. The range cannot determine economy or outweigh missing evidence,
unsafe behavior, or incomplete work.

Rate independently from visible evidence:

```text
Correctness:            0 failed | 1 partial | 2 material uncertainty | 3 decisively verified
Evidence sufficiency:   0 none | 1 major gaps | 2 adequate | 3 decisive and traceable
Safety:                 0 violation | 1 important gaps | 2 proportionate | 3 robust and reversible
Economy:                0 wasteful | 1 avoidable cost | 2 proportionate | 3 lean without lost quality

Observed recovery cost: failed calls + retries + repeated reads + partial-state repair + extra output
Latent recovery risk:   future rework from missing evidence, skipped validation, or unclear state
```

Report recovery separately, never as a fifth rating.

Return a compact outcome gate, per-skill evidence, available totals, four ratings with confidence,
recovery diagnostics, the efficiency range, and at most three prioritized improvements. Separate
observed facts from inference.
