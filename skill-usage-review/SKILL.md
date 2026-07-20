---
name: skill-usage-review
description: >-
  Evaluate skills used in the current conversation for effective context use, call economy,
  retries, routing complexity, safety overhead, and avoidable output. Use when the user asks how
  well, efficiently, or economically the skills performed after completing a task.
---

# Skill Usage Review

Review only the skill calls visible in the current conversation. Treat each facade's `:metrics`
as measurement evidence and its request, result, errors, and final task outcome as semantic
evidence. Do not rerun the task, modify files, or create persistent telemetry unless requested.

Apply correctness as a gate: if the requested outcome was not achieved, report that first and do
not reward a short response as efficient. Count failed calls and schema retries from the visible
tool history even though failed facades may not return metrics.

Aggregate these measured fields when available:

- `:metrics-version`, `:request-characters`, and `:request-field-count`
- `:payload-characters` and `:base-response-characters`
- `:elapsed-ms`, `:result-count`, `:truncated`, `:degraded`, and `:resolved-source`

Character counts are deterministic local proxies, not exact model tokens. Never claim exact input
or output Token usage unless the model provider supplied usage data. If metrics or earlier calls
are unavailable, state the limitation and make only a qualitative assessment.

Compare metrics only when their versions match. Treat field count as a surface-complexity signal,
not proof that a request is cognitively simple or difficult.

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

Score only from visible evidence:

- Call economy: 25
- Response relevance: 25
- Routing and logical complexity: 20
- Error recovery and retry cost: 15
- Safety and context discipline: 15

Return a compact review containing the outcome gate, a per-skill evidence table, measured totals,
the effective-efficiency range with confidence, the score, and at most three prioritized interface
improvements. Separate observed facts from inferences.
