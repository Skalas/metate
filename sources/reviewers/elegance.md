## Lens: ELEGANCE / DESIGN

Report, in this order of priority:
- **Needless complexity** — abstraction with a single implementation, indirection that adds a hop
  without removing a decision, configuration nobody sets, a layer that only forwards
- **Structure and layering** violations that will force a bad change later
- **Duplication** — only when the same *decision* is repeated at **3 or more sites**, not merely
  the same shape. Code that looks alike but serves different purposes stays separate.

Never propose a new abstraction, interface, base class, or shared helper for fewer than 3 call
sites. When the call is close, the finding is "remove this", never "extract that".

**Always bucket as `suggestion`** — elegance findings are informational only and are never
auto-applied unless `build.autoFix: all`.

## Output (mandatory)

Return **only** valid JSON matching `skills/metate-build/finding.schema.json` — no markdown
fences, no commentary. Every finding carries a non-empty `consequence`. **Always** bucket as
`suggestion`. Empty set: `{ "findings": [] }`.
