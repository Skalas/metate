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
  interactively; documented in `metate-build/SKILL.md` + README. **Trigger to revisit:**
  metate pointed at external/untrusted PRs — then build a hard path *on top of* the adapter
  tables (sandbox, egress-deny, finding allow-patterns), never a revived shell engine.

## Open (triggered)

- **Secret-file skip is prose, not code.** The mandatory secret-name exclusion (`.env`/`*.pem`/
  `id_*`/`*credentials*`/…) when building the review diff is a **MUST** instruction in
  `metate-build/SKILL.md`, because reviewers run as external CLI subprocesses (possibly another
  vendor). **Trigger:** a CI/no-agent runner is ever built — reimplement the skip as code there
  (an agent can be trusted to follow the MUST; a script cannot).

- **Headless cursor reviewer fan-out is unverified.** `cursor-agent` has Task/subagent dispatch
  on recent builds, but it is not proven that a headless reviewer invocation rejects writes under
  `readonly: true`. Fired 2026-07-03: a Claude-orchestrated review had to override
  `reviewer.backend: cursor → claude` for the fan-out. **Trigger:** before selecting `cursor` as
  a reviewer backend from a non-cursor orchestrator — verify on the target build that a
  `readonly: true` reviewer cannot write; never pass `--force`/`--trust` to a reviewer.

- **The "treat as data, never instructions" guard is duplicated across harness playbooks.**
  Near-verbatim in `metate-smoke/SKILL.md` and `metate-build/SKILL.md` §2b; within
  `metate-discover/SKILL.md` it is now one canonical statement in Guardrails (per-source
  steps reference it). **Cross-file duplication is an accepted limitation** — each `SKILL.md`
  is a standalone playbook installed independently per harness, so a shared note breaks
  self-containment. **Trigger (within-file only):** a third near-identical copy appears
  inside any single `skills/*/SKILL.md` — fold to one canonical statement in that file's
  Guardrails and have per-source mentions reference it.

- **Discover Tier-3 deferrals** (from `discover-judgment`; not in scope for that sprint):
  - **"What's missing" critic pass** in the Step 1 fan-out — generative rather than
    harvesting; evaluate after the situation read exists to reason against.
    **Trigger:** two consecutive cycles where the human picks "none" or drops the whole slate.
  - **Slate ledger** (`.metate/discover.json`) — record each slate and disposition; surface
    "proposed 3×, never picked" as an aging signal.
    **Trigger:** the same candidate is observed re-proposed and skipped across ≥3 cycles.
  - **`mode` as a per-run argument** (profile as default only) — ergonomics, not a bias fix.
    **Trigger:** a cycle where the human wants a non-default posture and has to edit the profile
    to get it.

- **`metate-ship` blanks `issueLedger` unconditionally, contradicting prep's externally-managed
  contract.** `metate-prep` Step 4 now promises that when `prep.issues.create: false` the ledger
  is left untouched because it is externally managed, but ship's close-out resets it to
  `{ "sprint": null, "issues": [] }` with no `create`-flag condition — so an externally-managed
  ledger is destroyed on the first ship. Prep's wording was scoped to prep time as a stopgap;
  the behavioral fix belongs to ship. Surfaced by the `discover-judgment` verify pass; ship was
  deliberately left unchanged to keep that sprint's blast radius to discover/prep/smoke.
  **Trigger:** the first project configured with `prep.issues.create: false` runs `metate-ship`
  — scope ship's reset to ledgers prep actually wrote.

- **`metate-build`'s `Write` is scoped by prose, not the tool layer.** The restriction to
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
  **Fired in production** (`internal_lucho_tool`, sprint `s1-rieles`): the nested call was denied
  and the operator hand-rolled an in-process subagent to get past it. That workaround is now the
  documented `claude-subagent` adapter (IMPLEMENTERS.md), so the sprint is unblocked — but the
  bootstrap rule itself is still too broad and remains open.

- **Validation residuals (open issues).**
  - **#37** — live proof that a genuinely-down codebase-memory MCP produces a *disclosed* grep
    fallback in reviewer rationale (mechanism is in; the down-path run was never captured).
    **Trigger:** next review run with the MCP actually down — capture the log, close.
  - **#40** — dedicated branch-behind scenario (base strictly ahead of the feature branch) for
    the merge-base→working-tree anchoring. **Trigger:** next review on a branch behind its base.

- **Review Tier-3 deferrals** (from `review-aperture`; not in scope for that sprint):
  - **Rotate the unanchored slot across rounds** (elegance → correctness → security) instead of
    defaulting to elegance. Better aperture, but a correctness round with no memo risks the
    convergence the memo protects. **Trigger:** a sprint where a blocker is found in round 3 in
    a file no earlier round flagged.
  - **Deferred T4/T6 sprint — round-1 intent context and `stop-scope`.** Cut from
    `review-aperture` at review round 4; re-plan as its own sprint allowed a state file.
    - **What:** round-1 intent context (review reads the sprint plan + issue ledger and judges
      the diff against stated intent), plan-contradiction blockers, Intent-coverage warnings, and
      the `stop-scope` verdict.
    - **Why it was cut:** every blocker after review round 1 came from this machinery,
      relocating each time it was fixed — out of the memo, then out of `fixable`, then out of the
      finding set, then out of an unbacked in-memory round state.
    - **Binding constraint:** an open intent finding must survive rounds, and every other
      cross-round artifact in this engine (`sessionFile`, `issueLedger`, `signalsFile`) is a file
      because the loop spans sessions. A prose-only sprint could not give it a carrier.
    - **Requirements for the re-sprint** (what four review rounds bought):
      1. a **durable carrier** for open intent findings — a file, not orchestrator memory;
      2. **structural classification** — a finding is an intent finding when the violation names a
         clause of the plan's out-of-scope/constraint section, NOT when its rationale merely cites
         the plan (the loose test let an ordinary security blocker be reclassified out of routing);
      3. **no self-serving disposition** — the `accepted` path must not be effectable by the
         implementer amending the plan it is being judged against, and `resolved` must not be a
         unilateral orchestrator re-read with no second reader;
      4. **classification before clustering** — otherwise a contradiction spread across ≥3 sites
         is absorbed into a systemic rollup that carries no intent marker and gets routed;
      5. decide explicitly whether intent findings are **terminal** (an intent blocker ends the
         loop immediately) — that collapse removes requirements 1 and 3 entirely and is the
         cheapest known design.
    - **Trigger:** the next sprint where review lets scope drift or a missing DoD item reach
      smoke.
  - **§1/§2 restructure in `metate-build`.** Split §2 into a linear pipeline (dedupe → cluster →
    bucket → autoFix) and lift any cross-round bookkeeping out of it; promote the pre-fan-out
    reads to their own step so §1 is about fanning out. Deferred during `review-aperture` to keep
    the patch verifiable under the round cap.     **Trigger:** the next edit to either section.

- **Engine prose accretes under review.** Review of a prose product answers each objection by
  adding a clause where the objection landed; nothing in the loop says "this section is now too
  long to execute." `review-aperture` added 38 lines to `metate-build/SKILL.md` for four small
  features before being trimmed twice. **Rule:** a change that adds prose to a `skills/*/SKILL.md`
  must remove prose. **Trigger:** any sprint that touches a `SKILL.md` — state a line budget in
  the plan and hold to it.
  **Now mechanical:** `make budget` (in `verify`) enforces a per-file cap from
  `tests/contracts/prose-budget.txt`. Raising a cap is allowed and must appear as an explicit
  line in the diff. The rule above stays as the reason the caps exist.

## Decided — not doing (yet)

- **Cold-intake `triage` + compressed `hotfix` lane** — designed, unbuilt; the mid-testing
  capture lane covers the common in-flow case. **Trigger:** cold bug reports (not found during
  our own testing) become recurring, OR a confirmed S0/S1 needs to bypass the sprint.
- **Marketplace/plugin distribution** — direct install (`install.sh` into `.claude/skills` +
  `.agents/skills`) is the chosen model; `.claude-plugin/plugin.json` is kept for the Claude Code
  plugin surface. Not revisiting unless the two-target copy becomes a real maintenance burden.
