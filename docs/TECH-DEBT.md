# Tech debt — triggered ledger

Each item carries a **trigger**: the condition that should force the fix. `metate-discover`
surfaces an item only once its trigger has fired (don't pull debt whose trigger is still cold).

> Wire this file into `.metate/profile.yml` as `prep.techDebtFile: docs/TECH-DEBT.md` (and
> optionally `techDebtFile:` top-level) so discover/prep pick it up automatically.

## From the `pluggable-orchestrator` sprint (2026-06-30)

### Functional — validation status

- **Live codex-only review pilot (T3·T4·T5) — VALIDATED 2026-06-30.** Exercised end-to-end
  against a real `codex 0.142.0` build+review loop in an isolated sandbox repo: read-only
  fan-out returns schema-valid findings (T3), `codex exec resume <explicit-id>` reaches the
  build session and applies the fix (T4), and round 2 sees the patched working tree and reports
  0 blockers (T5 convergence). Live testing surfaced **7 defects that static review missed**,
  all fixed this sprint: (1) headless `codex exec` deadlocks without `< /dev/null`; (2)
  `resume --last` resumes a reviewer session (the fan-out spawns intervening sessions) — now
  resumes by explicit id; (3) clean round declared done without running the gate; (4) a crashed
  reviewer lens wasn't disqualifying; (5) `FIXABLE` array vs `.findings[]` jq crash blocked all
  fix application; (6) review read the committed `...HEAD` diff so applied fixes were invisible
  and the loop never converged — now merge-base → working tree; (7) base-tip vs merge-base
  anchoring. **Residual:** convergence proven; codex's MCP reachability (T10) remains the
  documented limitation below.

- **cursor-as-orchestrator end-to-end.** `bin/metate`'s `cursor)` arm `die`s ("not yet wired");
  ORCHESTRATORS.md marks it probe-before-use (beta: 30s shell timeout, `--approve-mcps`, no
  `--model auto`).
  **Trigger:** someone needs cursor to *drive* (not just implement), OR the Cursor CLI Task
  tool leaves beta. Wire the arm + verify a resume round-trips.

- **Residual prompt-injection hardening on the codex fix-apply step.** The DATA/instruction
  boundary + 500-char cap + newline-strip are in place; egress-deny and allow-pattern gating
  on the `workspace-write` resume were scoped out.
  **Trigger:** before running `metate run review` under the codex orchestrator against an
  **untrusted** branch (e.g. external PRs in CI). Add network-egress denial during fix-apply
  and an imperative-verb/URL allow-pattern check on findings before handoff.

### Design / DRY (review DESIGN findings, report-only)

- **Three ad-hoc YAML-scalar parsers** — `bin/metate` `read_backend`, `codex-review.sh`
  `prof_*`, and `bootstrap.sh`'s inline awk reimplement the same "scalar nested one level under
  a key" lookup, and they already diverge (quote-stripping differs between `bin/metate` and
  `bootstrap.sh`).
  **Trigger:** a fourth consumer needs profile parsing, OR a parsing bug is found in any copy.
  Extract `skills/metate-review/lib/profile.sh` (`prof_scalar`/`prof_nested`/`prof_block`) and
  source it from all three.

- **`bin/metate` unknown-backend error omits `gemini`** — the `*)` arm says "expected claude |
  codex | cursor" though `gemini)` has its own arm. **Trigger:** next edit to `bin/metate`.

- **ORCHESTRATORS.md ↔ codex-review.sh command duplication** — the codex invocation shape
  appears in both; nothing keeps them in lockstep. **Trigger:** a codex CLI flag change.

### Native fan-out (deferred from the plan, EXPAND)

- **Native typed-subagent fan-out** — map reviewers to `.codex/agents/*.toml` /
  `.cursor/agents/*.md` for higher fidelity than the shell-process baseline.
  **Trigger:** cursor's CLI Task tool is GA **and** codex's typed batch fan-out
  (`spawn_agents_on_csv`) is stable.

### Tooling / autonomy

- **bootstrap autonomy rule too broad** — for `autonomous: true` it writes `Bash(claude -p:*)`,
  but the auto-mode safety classifier blocks the nested `claude -p --dangerously-skip-permissions`
  loop without the *explicit* `Bash(claude -p --dangerously-skip-permissions:*)` rule (hit during
  this sprint's build).
  **Trigger:** next time the headless `claude` implementer is provisioned via bootstrap. Emit
  the explicit dangerous-flag rule (or document the manual step in IMPLEMENTERS.md).
