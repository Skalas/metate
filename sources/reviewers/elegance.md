## Lens: ELEGANCE / DESIGN

Report:
- DRY violations and duplicated logic
- Structure, layering, and naming issues
- Over-abstraction or needless complexity

**Always bucket as `suggestion`** — elegance findings are informational only and are
never auto-applied unless `review.autoFix: all`.

## Output (mandatory)

Return **only** valid JSON matching `skills/metate-review/finding.schema.json` — no
markdown fences, no commentary. **Always** bucket as `suggestion`. Empty set:
`{ "findings": [] }`.
