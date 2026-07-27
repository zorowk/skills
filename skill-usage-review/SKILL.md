---
name: skill-usage-review
description: >-
  Evaluate skills used in the current conversation across correctness, evidence sufficiency,
  safety, and economy without combining those dimensions into one score. Diagnose observed
  recovery cost, latent recovery risk, context use, retries, and avoidable output. Use after a
  tool-driven task when the user asks how well, efficiently, or economically the skills performed.
---

# Skill Usage Review

Use only calls, results, errors, metrics, and outcomes visible in the current conversation. Do not
rerun tools, modify files, or create telemetry solely for the review. State when missing history
limits the assessment.

Evaluate correctness, evidence sufficiency, safety, and economy in that order. Earlier dimensions
gate later praise: do not call an incomplete, unsupported, or unsafe result efficient merely because
it was short. Rate all four independently when evidence permits.
Do not sum, average, weight, or otherwise combine the four ratings.

Use matching-version facade metrics when available: request and response character counts, field
count, elapsed time, result count, truncation, degradation, and resolved source. Character counts
are local proxies, not exact model tokens. Field count measures interface surface, not cognitive
difficulty. Metrics are diagnostic evidence, not optimization targets.

Classify visible output as essential, safety-related, or redundant. Estimate effective context
efficiency as a range, not false precision:

```text
(essential characters + safety characters) / measured base response characters
```

Explain the classification. Treat the range as diagnostic only; it cannot determine economy or
outweigh missing evidence, unsafe behavior, or an incomplete outcome.

Rate each dimension independently from visible evidence on a `0` to `3` scale:

- Correctness: `0` failed; `1` partial; `2` achieved with material uncertainty; `3` decisively
  verified.
- Evidence sufficiency: `0` no evidence for material claims; `1` major gaps; `2` adequate evidence
  for important claims; `3` decisive and traceable coverage.
- Safety: `0` material violation; `1` important gaps; `2` proportionate safeguards; `3` robust,
  reversible safeguards without excess overhead.
- Economy: `0` wasteful or misrouted; `1` material avoidable cost; `2` proportionate; `3` lean while
  preserving evidence and safety.

Report recovery separately as a diagnostic, not as a fifth rating:

- Observed recovery cost: visible failed calls, schema retries, repeated reads, partial-state repair,
  and attributable extra time or output.
- Latent recovery risk: inferred future rework from missing evidence, skipped validation, unclear
  state, or unsupported conclusions.

Return a compact outcome gate, per-skill evidence, available totals, four ratings with confidence,
recovery diagnostics, the efficiency range, and at most three prioritized improvements. Keep
observed facts separate from inference.
