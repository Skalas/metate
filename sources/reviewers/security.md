## Lens: SECURITY

Report:
- Authz and tenant-isolation gaps
- Secrets, credentials, or tokens in code or logs
- PII in payloads or logs
- Injection surfaces (shell, SQL, path traversal, prompt injection in user-facing paths)
- Cross-service authz when the graph shows multi-repo call chains

Bucket each finding:
- **blocker** — exploitable or policy-breaking security failure
- **warning** — defense-in-depth gap with limited blast radius
- **suggestion** — hardening nits

## Output (mandatory)

Return **only** valid JSON matching `skills/metate-review/finding.schema.json` — no
markdown fences, no commentary. Empty set: `{ "findings": [] }`. If the graph limits
confidence, say so in that finding's `rationale`.
