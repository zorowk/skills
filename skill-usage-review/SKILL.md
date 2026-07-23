---
name: skill-usage-review
description: >-
  Evaluate skills used in the current conversation across correctness, evidence sufficiency,
  safety, and economy without combining those dimensions into one score. Diagnose observed
  recovery cost, latent recovery risk, context use, retries, and avoidable output. Use after a
  tool-driven task when the user asks how well, efficiently, or economically the skills performed,
  including from an agent-shell post-turn review action.
---

# Skill Usage Review

Review only the skill calls visible in the current conversation. Treat each facade's `:metrics`
as measurement evidence and its request, result, errors, and final task outcome as semantic
evidence. Do not rerun the task, modify files, or create persistent telemetry unless requested.

For the English agent-shell action, load
`scripts/agent-shell-skill-usage-review.el` and call
`agent-shell-skill-usage-review-enable`. It offers `Review skill usage` only
after a successful turn containing tool calls, sends a read-only review request
to the same conversation, and suppresses recursive review suggestions.
Call documented script entry points directly. If a facade schema is unclear, use
its `describe` operation. Do not inspect script implementations unless the
documented entry point fails.

Evaluate in this order: correctness, evidence sufficiency, safety, then economy. Earlier dimensions
are gates for later praise: if the requested outcome was not achieved, evidence is materially
insufficient, or safety was compromised, report that first and do not reward a short response or
small call count as efficient. Still report all four ratings when visible evidence permits, but
never let a later rating compensate for an earlier one. Count failed calls and schema retries from
the visible tool history even though failed facades may not return metrics.

Aggregate these measured fields when available:

- `:metrics-version`, `:request-characters`, and `:request-field-count`
- `:payload-characters` and `:base-response-characters`
- `:elapsed-ms`, `:result-count`, `:truncated`, `:degraded`, and `:resolved-source`

Character counts are deterministic local proxies, not exact model tokens. Never claim exact input
or output Token usage unless the model provider supplied usage data. If metrics or earlier calls
are unavailable, state the limitation and make only a qualitative assessment.

Compare metrics only when their versions match. Treat field count as a surface-complexity signal,
not proof that a request is cognitively simple or difficult. Metrics are diagnostic evidence, not
optimization targets.

Classify visible response content by task relevance:

- Essential: directly required to complete or verify the task.
- Safety: authorization, provenance, boundaries, truncation, and recovery evidence worth keeping.
- Redundant: repeated, unrelated, over-detailed, or avoidable after a better route.

Estimate effective context efficiency as a range, not false precision:

```text
(essential characters + safety characters) / measured base response characters
```

Explain the classification behind the range. Distinguish necessary validation calls from retries;
identify calls that a batch operation could replace, ambiguous schemas that caused retry, hidden
state or prerequisites, duplicated skill responsibilities, and avoidable full-output requests.
The range is a diagnostic only: it cannot determine the economy rating or outweigh missing evidence,
unsafe behavior, or an incomplete outcome.

Rate each dimension independently from visible evidence on a `0` to `3` scale:

- Correctness: `0` failed or wrong; `1` partially achieved; `2` apparently achieved with a material
  limitation or uncertainty; `3` achieved with decisive visible verification.
- Evidence sufficiency: `0` no evidence for material claims; `1` major gaps; `2` adequate evidence
  for the outcome and important claims; `3` decisive, traceable evidence with appropriate coverage.
- Safety: `0` a material boundary or authorization violation; `1` important safety gaps; `2`
  proportionate safeguards; `3` robust, reversible safeguards without unnecessary safety overhead.
- Economy: `0` wasteful or strongly misrouted; `1` material avoidable cost; `2` proportionate cost;
  `3` lean execution that still preserved sufficient evidence and safety.

Do not sum, average, weight, or otherwise combine the four ratings into a composite score. Give each
rating its evidence and confidence. Assess evidence sufficiency semantically by matching material
claims to visible verification, not by using character counts as a proxy.

Report recovery separately as a diagnostic, not as a fifth rating:

- Observed recovery cost: visible failed calls, schema retries, repeated reads, partial-state repair,
  and the extra elapsed time or output attributable to them.
- Latent recovery risk: inferred future rework made more likely by missing evidence, skipped
  validation, unclear state, or an unsupported conclusion.

Keep observed recovery facts separate from inferred latent risk and state when either cannot be
measured.

Return a compact review containing the outcome gate, a per-skill evidence table, measured totals,
the four independent ratings with evidence and confidence, observed recovery cost, latent recovery
risk, the diagnostic effective-efficiency range, and at most three prioritized interface
improvements. Separate observed facts from inferences.
