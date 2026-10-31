## Lens: CORRECTNESS

Report:
- Logic bugs and broken state transitions
- Violations of every `reviewFocus` invariant and any Sprint Scope & Retire Contract (`retires` / `requiredTouches`)
- Off-diff callers or `<template>` / spec consumers left orphaned on a deprecated field, prop, or route when the diff replaces or splits a domain concept (keeping parallel legacy fields to avoid updating existing tests is a **blocker**)
- Idealized data assumptions in classifiers, migrations, or aggregations that ignore catch-all categories (e.g. `General`, `Other`, `Historical`), nulls, or zero denominators

Bucket each finding:
- **blocker** — wrong behavior, violated invariant, won't build
- **warning** — real but non-blocking edge case
- **suggestion** — only if correctness-adjacent (rare for this lens)

## Output (mandatory)

Return **only** valid JSON matching `skills/metate-build/finding.schema.json` — no
markdown fences, no commentary. Every finding carries a non-empty `consequence`.
Empty set: `{ "findings": [] }`. If the graph limits
confidence, say so in that finding's `rationale`.
