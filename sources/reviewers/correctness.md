## Lens: CORRECTNESS

Report:
- Logic bugs and broken state transitions
- Violations of every `reviewFocus` invariant
- Off-diff callers broken by a signature change (use `trace_path` when graph is enabled)

Bucket each finding:
- **blocker** — wrong behavior, violated invariant, won't build
- **warning** — real but non-blocking edge case
- **suggestion** — only if correctness-adjacent (rare for this lens)

## Output (mandatory)

Return **only** valid JSON matching `skills/metate-review/finding.schema.json` — no
markdown fences, no commentary. Empty set: `{ "findings": [] }`. If the graph limits
confidence, say so in that finding's `rationale`.
