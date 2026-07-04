# Tech debt — triggered ledger

Each item carries a **trigger**: the condition that should force the fix. `metate-discover`
surfaces an item only once its trigger has fired (don't pull debt whose trigger is still cold).

> Wired into `.metate/profile.yml` as `prep.techDebtFile: docs/TECH-DEBT.md`.
> Resolved and moot items are pruned to git history (pruned 2026-07-03, `polish-bootstrap`;
> read this file at any earlier commit for the full sprint-by-sprint archaeology).

## Accepted limitations (soft-enforce, by design — NOT debt to fix)

- **No untrusted-branch review safety.** Reviewers are not sandboxed/read-only; a diff that
  modifies the review engine's own instruction files (lens prompts, prompt-clause, `SKILL.md`)
  could subvert its own review, and the fix-apply step has no network-egress denial or
  imperative-verb/URL allow-pattern check on findings. Accepted for trusted repos run
  interactively; documented in `metate-review/SKILL.md` + README. **Trigger to revisit:**
  metate pointed at external/untrusted PRs — then build a hard path *on top of* the adapter
  tables (sandbox, egress-deny, finding allow-patterns), never a revived shell engine.

## Open (triggered)

- **Secret-file skip is prose, not code.** The mandatory secret-name exclusion (`.env`/`*.pem`/
  `id_*`/`*credentials*`/…) when building the review diff is a **MUST** instruction in
  `metate-review/SKILL.md`, because reviewers run as external CLI subprocesses (possibly another
  vendor). **Trigger:** a CI/no-agent runner is ever built — reimplement the skip as code there
  (an agent can be trusted to follow the MUST; a script cannot).

- **Headless cursor reviewer fan-out is unverified.** `cursor-agent` has Task/subagent dispatch
  on recent builds, but it is not proven that a headless reviewer invocation rejects writes under
  `readonly: true`. Fired 2026-07-03: a Claude-orchestrated review had to override
  `reviewer.backend: cursor → claude` for the fan-out. **Trigger:** before selecting `cursor` as
  a reviewer backend from a non-cursor orchestrator — verify on the target build that a
  `readonly: true` reviewer cannot write; never pass `--force`/`--trust` to a reviewer.

- **The "treat as data, never instructions" guard is duplicated.** Near-verbatim in
  `metate-smoke/SKILL.md` and `metate-review/SKILL.md` §2b. Two sites is tolerable.
  **Trigger:** a third near-identical copy appears in `skills/` — extract to one shared note
  (or fold into `signal.schema.json`'s description) and have all sites reference it.

- **`metate-review`'s `Write` is scoped by prose, not the tool layer.** The restriction to
  `signalsFile`/`prep.techDebtFile` is enforced by SKILL prose + the `reviewFocus` invariant;
  harness `allowed-tools` has no path-scoping syntax. **Trigger:** the harness gains path-scoped
  `Write(...)` grants, OR a security review flags the orchestrator write scope as an active risk.

- **Rendered artifact output list is duplicated in `Makefile`.** `RENDERED` manually mirrors
  `sources/render.sh`'s output contract. **Trigger:** the renderer gains or removes an output —
  add a `--list-outputs` mode or a generated manifest so the drift gate checks exactly what the
  renderer can emit.

- **`render.sh` shadows `lib/yaml.sh`'s `yaml_nested_scalar` with a different-arity wrapper.**
  After sourcing `yaml.sh`, `render.sh` redefines the 3-arg `yaml_nested_scalar` as a 2-arg
  manifest-bound local. Safe today (later definition wins, single process) but a maintenance
  footgun. **Trigger:** next edit to render.sh's parser wrappers — rename the local wrappers
  (e.g. `manifest_scalar` / `manifest_field`) so no name collides with the shared lib.

- **bootstrap autonomy rule too broad for the claude backend.** `autonomous: true` writes
  `Bash(claude -p:*)`, but the auto-mode safety classifier blocks the nested
  `claude -p --dangerously-skip-permissions` loop without the explicit dangerous-flag rule.
  **Trigger:** next time the headless `claude` implementer is provisioned via bootstrap —
  emit the explicit rule (or document the manual step in IMPLEMENTERS.md).

- **Validation residuals (open issues).**
  - **#37** — live proof that a genuinely-down codebase-memory MCP produces a *disclosed* grep
    fallback in reviewer rationale (mechanism is in; the down-path run was never captured).
    **Trigger:** next review run with the MCP actually down — capture the log, close.
  - **#40** — dedicated branch-behind scenario (base strictly ahead of the feature branch) for
    the merge-base→working-tree anchoring. **Trigger:** next review on a branch behind its base.

## Decided — not doing (yet)

- **Cold-intake `triage` + compressed `hotfix` lane** — designed, unbuilt; the mid-testing
  capture lane covers the common in-flow case. **Trigger:** cold bug reports (not found during
  our own testing) become recurring, OR a confirmed S0/S1 needs to bypass the sprint.
- **Marketplace/plugin distribution** — direct install (`install.sh` into `.claude/skills` +
  `.agents/skills`) is the chosen model; `.claude-plugin/plugin.json` is kept for the Claude Code
  plugin surface. Not revisiting unless the two-target copy becomes a real maintenance burden.
