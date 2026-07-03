# Tech debt — triggered ledger

Each item carries a **trigger**: the condition that should force the fix. `metate-discover`
surfaces an item only once its trigger has fired (don't pull debt whose trigger is still cold).

> Wire this file into `.metate/profile.yml` as `prep.techDebtFile: docs/TECH-DEBT.md` (and
> optionally `techDebtFile:` top-level) so discover/prep pick it up automatically.

## Engine-wide (identified in discover, 2026-07-02)

### MCP misuse read as "MCP down" — RESOLVED (sprint `engine-hardening`, 2026-07-02)

- **RESOLVED (M2).** The Code Discovery clause (`IMPLEMENTERS.md`) now carries the
  down/bad-query/empty taxonomy + retry-on-usage-error rule + canonical call signatures, and the
  `ORCHESTRATORS.md` `fanOut` contract has the orchestrator query the graph once and pass it as
  DATA. Verified via 3-round review. Residual: the clause enrichment landed only in the prompt
  path, widening drift vs `cursor-rule.mdc`/`codex-rule.md` — folded into the backend-unification
  item below (single-sourcing resolves it). Original writeup kept for context:
- **codebase-memory MCP: subagents misread a usage error as an outage, and each fanned-out
  agent independently rediscovers structure (N× payload).** Two root causes, both in the engine
  (NOT fixable per-repo — `codebaseMemory.enabled` only turns the graph off, it can't make agents
  use it correctly): (1) the injected **Code Discovery clause** tells agents to prefer the graph
  but not *how* — a malformed call returns an error string, which agents collapse into "graph is
  down" and silently grep-fallback; (2) the **fanOut pattern** sends N read-only agents to each run
  their own `get_architecture`/broad `search_graph`, paying discovery cost N times and flooding
  context. **Fix (two engine files):**
  - **Code Discovery clause** (`skills/metate-review/IMPLEMENTERS.md` + the injected review/discover
    prompt): add a *down vs bad-query vs empty* taxonomy + a retry-on-usage-error rule + canonical
    call signatures (`search_graph(name_pattern=…)`, `get_code_snippet(qualified_name=…)`,
    `trace_path(function_name=…, mode=…)`) with one worked example. Only a connection-level failure
    counts as "down"; an error string means fix-params-and-retry; empty means grep that one symbol.
  - **`ORCHESTRATORS.md` fanOut**: codify "orchestrator queries the graph ONCE, distills the
    diff-impact/relevant subgraph, and passes it to subagents as DATA" so reviewers stop
    rediscovering. Scale intensity to graph value (dial down on doc/shell repos like this one).
  **Trigger: fires now** — hits every graph-backed repo on every review/discover fanOut. Fix before
  the next sprint that runs review on a graph-rich codebase. **Highest failure-surface open item.**

### Backend duplication — unify at installation, keep the switching flexibility

- **Multi-backend support is maintained by copy-paste, not abstraction.** The orchestrator ×
  implementer matrix is genuinely used (daily token-limit exhaustion forces switching interface or
  implementer mid-project — the flexibility is load-bearing, do NOT collapse it). But it's carried as
  *parallel per-backend guides/adapters/install flows* that drift (`ORCHESTRATORS.md` ↔
  `codex-review.sh` command duplication; three ad-hoc YAML parsers; per-runtime prose). Switching is
  a runtime capability; a separate guide per backend is a maintenance artifact — you can keep full
  switch-anytime flexibility with one path. **Fix:** one install path that provisions whatever
  backends are present; one adapter *contract* + a per-backend capability table (the differing CLI
  invocation is a table row, not a whole doc); collapse the three parsers into the deferred
  `lib/profile.sh`. **Trigger:** the next thorough code-review / simplification sprint — this is its
  primary scope (REDUCE mode). Prerequisite decision already made: metate is a *tool* that needs
  multiple backends, so pay for the abstraction rather than deleting backends.
  **Update (2026-07-02):** the `engine-hardening` M2 enriched the Code Discovery clause in the
  prompt path only, so `cursor-rule.mdc`/`codex-rule.md` now carry a leaner version — the drift this
  item warns about is now concrete, not hypothetical. Raises the priority.
  **RESOLVED — core (sprint `backend-source-unification`, 2026-07-03).** This was the named REDUCE
  trigger and it fired. Reviewer lenses, the Code Discovery rule body, and backend/reviewer metadata
  now live once under `sources/` and render into every per-harness artifact via `sources/render.sh`,
  gated by `make render-check` (drift = red build) — the copy-paste-drift class (incl. the M2 clause
  drift above) is closed for those surfaces. Shared readers `lib/profile.sh` + `lib/yaml.sh` exist and
  back `codex-review.sh`/`render.sh`. **Residual (still open, narrower):** `bin/metate` `read_backend`
  and `bootstrap.sh`'s inline awk are not yet on the shared reader (see the parser entry below); and
  the `ORCHESTRATORS.md` ↔ `codex-review.sh` command duplication is unchanged. **Trigger for the
  residual:** the next edit to `bin/metate`/`bootstrap.sh` profile reads, or a codex CLI flag change.

## From the `engine-hardening` sprint (2026-07-02)

### Resolved

- **Review fan-out read-only rested on prose — RESOLVED (M1).** The three Cursor reviewer agents now
  declare `readonly: true` in frontmatter (source + installed `.cursor/agents/` copies), enforcing
  the "reviewers never write" contract at the harness level instead of by prose alone.

### New debt (triggered)

- **`bin/metate` still passes `--approve-mcps` on the cursor writer/runStage path**, which
  `ORCHESTRATORS.md`/`IMPLEMENTERS.md` now flag as unconfirmed in current Cursor CLI docs (the
  documented headless MCP-approval path is `permissions.allow`/`permissions.deny` + `--force`). Docs
  and dispatcher were reconciled to *describe* this as a residual, not fixed. **Trigger:** verify
  `--approve-mcps` against the target `cursor-agent` build; if rejected/renamed, switch `bin/metate`
  to the `permissions`+`--force` path.
- **Headless cursor read-only fan-out enforcement is unverified.** The cursor-agent CLI has Task/
  subagent dispatch on recent builds, but it is NOT proven that a reviewer invocation rejects write
  tool calls under `readonly: true` headlessly — so `bin/metate` still `exit 2`s cursor
  `review`/`discover`, and the docs say do not enable headless cursor review until verified.
  **Trigger:** before wiring headless cursor fan-out into `bin/metate` — first confirm on a target
  build that a `readonly: true` reviewer cannot write, and never pass `--force`/`--trust` to it.

### Learned (process)

- **A build prompt can introduce a harness-level defect the fast gate can't catch.** M1's build
  added `is_background: true` to the reviewer agents (plausible from the Cursor spec), but it
  conflicts with metate's *synchronous* fan-out (launch in parallel → immediately `jq`-merge each
  result); a backgrounded reviewer would return nothing to merge → silent zero-findings. `make check`
  passed; the round-2 review caught it. Reinforces: verify frontmatter/flags against the *contract
  that consumes them*, not just validity.

## From the `signal-capture-lane` increment (2026-07-02)

### New debt (triggered)

- **`metate-review` is a documented-but-unwired signal source. — RESOLVED (sprint `review-write-side`,
  2026-07-02).** Review now has both write-paths: out-of-diff bugs → `signalsFile` (T1), deferred
  DESIGN wants → `prep.techDebtFile` (T6); `Write` added to review's allowed-tools (orchestrator-only,
  scoped to the two sinks), schema description + `foundIn: review:<lens>` updated, `reviewFocus`
  invariant refined. Verified via 2-round review, `make verify` green. Original writeup kept for
  context: *the capture design names smoke and review as write sides, but only smoke was wired the
  prior increment; review's frontmatter had no `Write` tool and no capture step.*

- **No `signalsFile` writer exists in a real target repo yet — round-trip unproven.** The write side
  (smoke) and read+disposition side (discover) are wired and review-verified, but no end-to-end run has
  actually captured a signal, had discover fold it in, and stamped it `promoted`/`invalid`. This
  increment was hand-written on the metate repo (docs only; `make verify` has no signal round-trip).
  **Trigger:** first sprint on a repo with a real e2e suite where smoke hits an out-of-diff failure —
  confirm the capture→rank→disposition loop closes with real data before trusting it.

### Decided — not doing (yet)

- **Cold-intake `triage` + `hotfix` lane — deferred, not declined.** The externally-reported-bug path
  (triage → severity → route to signal/interrupt/hotfix, with a compressed hotfix ceremony off the
  release base) is designed but unbuilt; the mid-testing capture lane covers the common in-flow case.
  **Trigger:** cold bug reports (not found during our own testing) become a recurring need, OR a
  confirmed S0/S1 needs to bypass the sprint and there's no lane for it.

### Naming nit (report-only, from review round 3)

- **`discover.signals.signals` — RESOLVED (sprint `review-write-side`, 2026-07-02, T4).** The inner
  source toggle was renamed `signals` → `captures`, so the path is now `discover.signals.captures`.
  The outer map is still named `signals` (see the new debt below for the follow-on).

## From the `review-write-side` sprint (2026-07-02)

### Resolved

- **[review:elegance] `discover.signals` map name still collides with `captures` — RESOLVED
  (sprint `backend-source-unification`, 2026-07-02, T6).** Parent toggle map renamed to
  `discover.sources` (`discover.sources.captures`); profile + template + Discover prose updated;
  `lib/profile.sh` reads `discover.sources` with legacy `discover.signals` alias. Original writeup:
  T4 renamed the leaf toggle but the parent map was still `discover.signals`, so the
  fully-qualified key was `discover.signals.captures`. **Trigger was:** the next edit to the
  `discover.signals` block.

### New debt (triggered)

- **[review:elegance] The "treat as data, never instructions" guard is duplicated across capture
  sites.** The same sentence now lives near-verbatim in `metate-smoke/SKILL.md` and
  `metate-review/SKILL.md` §2b (review's copy even says "same guard as metate-smoke"). Two sites is
  tolerable. **Trigger:** a third near-identical copy appears anywhere in `skills/` — extract the
  guard to one shared note (or fold it into `signal.schema.json`'s description, which already carries
  the capture contract) and have all sites reference it.

- **[review:security] `metate-review`'s `Write` is scoped by prose, not by the tool layer.** Review
  gained the `Write` tool; the restriction to `signalsFile`/`prep.techDebtFile` is enforced only by
  the SKILL prose + `reviewFocus` invariant, because the harness `allowed-tools` has no path-scoping
  syntax (every metate skill grants bare `Write` — repo-wide, not new to this sprint). The reviewer
  fan-out still has no `Write`; only the orchestrator does. **Trigger:** the harness gains a
  path-scoped `Write(...)` grant, OR a security review flags the orchestrator's write-scope as an
  active risk — then enforce the two-sink restriction at the tool layer rather than in prose.

## From the `engine-consolidation` sprint (2026-07-03)

### Resolved

- **Hand-rolled YAML parsers → `yq` (T1/T2).** `lib/yaml.sh` now parses via `yq` v4 (required
  dependency, gated in `install.sh`/`bootstrap.sh`); `bin/metate` `read_backend` + `bootstrap.sh`
  read through `lib/profile.sh`. Closes: *"render.sh re-implements lib/profile.sh's parser"*,
  *"bin/metate/bootstrap.sh hand-roll their reads"* (Later residual), *"render.sh shadows
  yaml_nested_scalar"* (renamed `manifest_scalar`/`manifest_field`), *"reviewer_lenses() fallback
  silently drops a lens"* (now asserts against `YAML_REVIEWER_LENS_ORDER`), *"bin/metate
  unknown-backend omits gemini"*. Malformed YAML now fails loudly (no silent `reviewFocus`
  truncation) — a correctness win, not just DRY.
- **Review-loop algorithm dual-sourced (my-review finding, T3).** Exit criteria single-sourced under
  `sources/review-loop/` and rendered into both consumers; `make verify` `review-loop-drift` gate
  fails on divergence.
- **P3 hygiene batch (T6).** `lc_f` localized; the two `codebaseMemory.enabled` guards folded;
  `RENDERED` derived from `render.sh --list-outputs`; `_review_engine_rel` literal fallback replaced
  with a disk-existence check (absent → loud die; untracked-but-present → repo-relative fallback).

### New debt (triggered)

- **[review:security] `yq` is a heavier parser than the old awk on a hostile working-tree
  `backends.yml`.** Folds into the existing roster-trust item below: `codex-review.sh` reads
  `sources/backends.yml` for the lens roster from the working tree of the reviewed branch (not the
  trusted merge-base copy). The awk scanner was bounded per-line; `yq` builds a full document tree
  (anchor/alias fan-out, large-doc cost), so a crafted `backends.yml` on an untrusted branch costs
  materially more CPU/memory per unattended review round. **Trigger:** before running
  `metate run review` under any orchestrator on an **untrusted** branch — load the roster through the
  same trusted boundary as lens-prompt text (`lib/trusted-review-text.sh`), OR cap `yq` input size.
  Same fix as the roster-trust item; this raises its priority once untrusted-branch review is wired.

- **[review:elegance] T3 single-sources the verdict-*id* axis only; `sources/review-loop/exit-criteria.md`
  prose is a third, ungated representation.** The drift gate checks verdicts.yml ↔ `codex-review.sh`
  literals and `SKILL.md` ↔ generated block, but nothing checks that the backtick-wrapped ids in the
  exit-criteria prose match `verdicts.yml`. Rename a verdict and the prose goes stale silently.
  **Trigger:** the next verdict rename, or the next edit to `review-loop-drift` — have the gate also
  diff the prose's backtick id set against `verdicts.yml`.

- **[review:elegance] `codex-review.sh` withheld-report set-difference is over-engineered and swallows
  errors.** T6 rewrote the withheld-fix report from a one-pass negated `.file` predicate into a
  two-step `slurpfile` set-difference plus a `2>/dev/null || :` fallback that silently emits an empty
  report on any jq formatting error — against the repo's fail-loudly ethos. The *enforcement* set
  (`FIXABLE_APPLY`) is unaffected (security-verified), so this is report-only. **Trigger:** the next
  edit to the withhold/fixable logic — revert to the direct negated predicate, or make the fallback
  loud.

## From the `backend-source-unification` sprint (2026-07-02)

### New debt (triggered)

- **[review:elegance] Rendered artifact output list is duplicated in `Makefile`.** `render-check`
  now detects drift for the artifacts listed today, but `RENDERED` manually duplicates
  `sources/render.sh`'s output contract. **Trigger:** the next time the renderer gains or removes
  an output — add a `sources/render.sh --list-outputs` mode or committed generated-output manifest
  so the drift gate checks exactly what the renderer can emit.

- **[review:elegance] `render.sh` re-implements `lib/profile.sh`'s nested-YAML parser.**
  `render.sh`'s `yaml_nested_scalar`/`yaml_cd_*` and `lib/profile.sh`'s `_prof_*` are two
  independent hand-rolled awk "walk-by-indent" parsers — the same drift pattern this sprint set
  out to kill, one layer down. **Trigger:** the next time either parser needs a third nesting
  level, a quoting fix, or a parsing bug is found in either — unify onto one shared reader.

- **[review:elegance] `yaml_cd_scalar` is a subset of `yaml_cd_block` in `render.sh`.** The two
  functions share the identical `in_cd`/`in_h` state machine; the block variant only adds a
  continuation branch. **Trigger:** the next edit to either — collapse into one
  `yaml_cd_field(harness, field)` that auto-detects the trailing `|`.

- **[review:elegance] Reviewer lens list is hardcoded, not derived from `backends.yml`.** The
  `correctness security elegance` loop literal lives in both `render.sh` and `codex-review.sh`
  even though `backends.yml` already enumerates the lenses under `reviewers:`. **Trigger:**
  adding or removing a lens — derive the loop set from the manifest so a new lens is one edit.

- **[review:elegance] `lib/captures.sh` has no runtime consumer; `PROFILE_ROOT` is a
  test-only contract.** Only the Makefile self-tests source `captures.sh`; no production path
  (codex-review.sh, discover) calls `count_open_captures`, and `signals_file_path` relies on
  `PROFILE_ROOT`, which `lib/profile.sh` neither sets nor documents (tests export it, masking
  the gap). **Trigger:** the first runtime consumer that needs the open-capture count — wire it
  in and derive/​document `PROFILE_ROOT` in `profile.sh`, or drop the shell copy and keep the
  rule as prose.

- **[review:security] Reviewer roster derived from working-tree `backends.yml` has no trusted-source boundary.**
  Deriving the lens list from `sources/backends.yml` (T9 cleanup) means that when metate reviews a
  branch which itself contains that file, the roster is read from the working tree rather than the
  trusted bundled install — unlike reviewer prompt *text*, which `lib/trusted-review-text.sh` gates
  via merge-base / bundled copy. A branch that drops a lens under `reviewers:` would be reviewed with
  that lens missing. Low risk today (dogfood branches are trusted; installed usage falls back to the
  trusted `generated/lens-prompts/`), and `backends.yml`/`render.sh` are now in the mid-loop
  self-fix withhold set. **Trigger:** before running `metate run review` under the codex orchestrator
  against an **untrusted** branch (ties to the existing untrusted-branch hardening residual) — load
  the `reviewers:` key list through the same trusted boundary as lens prompt text.

- **[review:elegance] `render.sh` shadows `lib/yaml.sh`'s `yaml_nested_scalar` with a different-arity local wrapper.**
  After sourcing `yaml.sh`, `render.sh` redefines `yaml_nested_scalar` (2-arg, binds `$MANIFEST`) over
  yaml.sh's 3-arg function of the same name. Safe now (later definition wins, single process) but a
  maintenance footgun. **Trigger:** the next edit to render.sh's parser wrappers — rename the local
  wrappers (e.g. `manifest_scalar` / `manifest_field`) so no name collides with the shared lib.

- **[review:correctness] `reviewer_lenses()` fallback silently drops any lens not in `YAML_REVIEWER_LENS_ORDER`.**
  The absent-manifest fallback (the normal installed path) walks the canonical `YAML_REVIEWER_LENS_ORDER`
  array in `lib/yaml.sh` and emits only those ids — so a lens shipped as `generated/lens-prompts/<id>.txt`
  but absent from the array would vanish from review coverage with no error. Harmless today (three lenses,
  all listed). **Trigger:** adding a 4th reviewer lens — update `YAML_REVIEWER_LENS_ORDER` in the same
  commit (or derive the fallback order from the shipped `.txt` set so the array can't go stale).

## From the `codex-native-skills` increment (2026-07-01)

### Opportunity — native codex mechanisms this pivot did not adopt

- **`codex review --base <branch>` / `--uncommitted` reimplemented by hand.** `codex-review.sh`
  hand-rolls merge-base anchoring + the untracked-file intent-to-add dance (all of M1). Codex has a
  native `codex review` subcommand with `--base`, `--uncommitted` (staged + unstaged + **untracked**),
  and `--commit` — i.e. M1's entire diff-scope machinery overlaps with `--uncommitted`.
  **Checked live against codex-cli 0.142.4:** `codex review --uncommitted` emits a single
  human-readable review pass, rejects custom prompts with `--uncommitted`, and rejects `--json`,
  `--output-schema`, and `-o`. It does **not** provide metate's structured multi-lens JSON contract
  or fanOut→resume-fix→gate loop. **Trigger:** before the next substantive edit to
  `codex-review.sh`'s diff logic — consider whether only diff collection can be delegated, but do not
  replace the loop with native `codex review` unless that command gains structured output + fix-loop
  controls.

### Decided — not doing

- **`codex plugin` marketplace distribution — declined.** Direct install (`install.sh` copying into
  `.claude/skills` + `.agents/skills`) is the chosen model; no marketplace snapshot. Not revisiting
  unless the two-target copy becomes a real maintenance burden.

### Process — resolved

- **Pivot committed + reviewed (2026-07-01).** The codex-native-skill wiring was committed
  (`feat(install)` + `docs(codex-native-skills)`) and run through a `metate-review` round
  (correctness · security · doc-accuracy): 0 blockers, security clean, docs verified against code.
  Fixes applied from that round: install.sh project bootstrap now tries both skill roots (parity
  with `metate-init`) instead of hardcoding `.claude/skills`.

## From the `merge-safe-29` sprint (2026-07-01)

### Resolved

- **Untracked files invisible to review (#43) — RESOLVED (M1).** The review diff anchored on
  `git diff <merge-base>` only, so brand-new implementer-created files were never reviewed (false
  "clean"). Fixed by intent-to-adding untracked, non-ignored files into the diff, hardened against
  index leakage with a `RETURN`-trap restore + a case-insensitive secret skip-list + NUL-safe I/O.
- **metate-on-metate self-review degeneracy — RESOLVED (M2).** The running review engine is now
  excluded from the fixable set (so a mid-loop self-edit can't corrupt the executing script), and
  reviewers are told runStage legitimately writes non-code artifacts (kills the oscillation). The
  prior sprint's dogfood-only limitation is retired.
- **Code Discovery / MCP override ignored `codebaseMemory.enabled` — RESOLVED (M3).** Both the clause
  injection and the `default_tools_approval_mode="approve"` override are now gated on the flag.
- **install.sh piped path (#44) — RESOLVED (M5).** Local-checkout detection requires a real
  `install.sh` next to `skills/`; the piped path always clones the requested ref.
- **bootstrap autonomy whitelist claude-only — RESOLVED (M6).** Backend→grant map
  (claude→`Bash(claude -p:*)`, cursor→`Bash(cursor-agent:*)`, codex→`Bash(codex:*)`), idempotent,
  claude path byte-identical.

### New debt (triggered) — review DESIGN findings, report-only

These surfaced in the merge-safe-29 review as report-only (elegance/DRY), not blockers. All in
`skills/metate-review/codex-review.sh` unless noted.

- **Duplicate `if [ "$CODEBASE_MEMORY" = "true" ]` guards** — the MCP-approve-flag setup and the
  Code Discovery clause live in two adjacent identical conditionals; fold into one.
  **Trigger:** next time a third `codebaseMemory.enabled`-gated behavior is added — merge the guards
  first so it doesn't become three.
- **`REVIEW_ENGINE_REL` hard-codes `skills/metate-review/codex-review.sh`** as a fallback when
  `git ls-files --full-name` is empty — silent coupling if the skill is relocated.
  **Trigger:** if the review engine's path/filename ever changes — make it `die` loudly or derive
  the path instead of a literal fallback.
- **`withheld.txt` recomputes the self-fix filter** (`file == $eng`) a second time rather than a
  set-difference of `FIXABLE − FIXABLE_APPLY`. Minor DRY.
  **Trigger:** next edit to the withhold/fixable logic — collapse to one jq pass.
- **`lc_f` not declared `local`** in `build_review_diff` (harmless global leak; assigned before use,
  no `set -u` failure). **Trigger:** any refactor of that function — add it to the `local` line.
- **Cross-file profile-key parsing duplicated** — `codebaseMemory.enabled` is hand-parsed
  independently in `codex-review.sh` (`prof_nested`) and `bootstrap.sh` (awk). Consistent with the
  repo's "each script hand-rolls its reader" convention; unifying is the deferred `lib/profile.sh`.
  **Trigger:** when a third script needs the same key, or the `lib/profile.sh` item is picked up.

- **cursor-as-orchestrator IDE path — RESOLVED (2026-07-01).** Task fanOut documented in
  `ORCHESTRATORS.md`; reviewer agents ship in `skills/metate-review/cursor-agents/` (bootstrap
  → `.cursor/agents/`); `bin/metate` wires headless `runStage` and points `review`/`discover`
  at the IDE ceremony (exit 2). No `cursor-review.sh` — shell fan-out is codex-only. Dogfood:
  3-round IDE review converged (0 blockers round 3); `read_implementer_field` helper in bootstrap.
  **Residual trigger:** headless `fanOut` when `cursor-agent` CLI exposes Task fan-out.

## From the `stabilize-codex-orchestrator` sprint (2026-06-30)

### Resolved

- **codex ↔ codebase-memory MCP reachability in headless `exec` (T10) — RESOLVED.** Root cause:
  headless `codex exec` gates MCP tool calls behind a **separate** approval
  (`approvals_reviewer = "user"`); with no TTY the call is auto-cancelled (`user cancelled MCP
  tool call`) and reviewers silently grep. `approval_policy="never"` covers only *shell* commands.
  Fix (commit `39df709`): pass `-c mcp_servers.codebase-memory-mcp.default_tools_approval_mode="approve"`
  on the reviewer fan-out **and** the implement resume — graph reachable, read-only sandbox intact.
  Verified live and on a neutral sandbox (T5 clean convergence, 2 rounds). Issues #35–#38.

### New debt (triggered)

- **metate reviewing its OWN engine is degenerate (dogfood-only).** With `orchestrator.backend:
  codex` on a diff that includes `skills/metate-review/codex-review.sh` itself: the implement
  resume edits the running script mid-loop → bash byte-offset corruption (exit 127); and reviewers
  flag pre-existing engine code without the design context that runStage stages *legitimately*
  write non-code artifacts → oscillation, no convergence. The `AGENTS.md` note asking the
  implementer to defer such edits is **not reliably honored**.
  **Trigger:** before running `metate run review` under the codex orchestrator on a diff that
  modifies the review engine itself. Then exclude the running engine from the fixable set (or
  snapshot-run it) and feed reviewers the runStage-writes design context. Does NOT arise on a
  normal target repo (the engine lives in the installed skills dir, off-diff).

- **codex-review.sh injects the Code Discovery clause + MCP override unconditionally**, ignoring
  `codebaseMemory.enabled: false`. A repo that opts out still has reviewers attempt graph discovery.
  **Trigger:** a project sets `codebaseMemory.enabled: false` expecting grep-only review. Gate both
  the clause and the `default_tools_approval_mode` override on `codebaseMemory.enabled`.

- **Follow-up findings from the MCP-backed review (filed as issues, NOT this sprint's ledger):**
  #43 — the review diff omits untracked files (implementer-created files invisible → false clean);
  #44 — install.sh piped path may treat cwd as a local checkout instead of cloning the ref.
  **Trigger (#43):** an implementer creates a NEW file during build (common) — fix before relying on
  review to catch defects in new files.

### Not yet exercised

- **T6 branch-behind dedicated scenario (issue #40, kept OPEN).** The merge-base→working-tree
  anchoring ran in every review this sprint and clean multi-round convergence is proven (T5), but a
  scenario where the base branch is strictly ahead of the feature branch was not constructed.
  Re-triaged as a residual in the `merge-safe-29` M4 verification pass — NOT merge-blocking (the
  anchoring code path is exercised on every run; only the strictly-behind edge is unbuilt).
  **Trigger:** next codex-orchestrated review on a branch that is behind its base.

- **T3 graph-unavailable fallback logging (issue #37, kept OPEN).** The Code Discovery clause
  instructs reviewers to disclose a grep fallback in the finding's rationale ("SAY SO … do not
  silently fall back"), and M3 added a clean `codebaseMemory.enabled: false` opt-out path — but a
  dedicated LIVE run with the MCP genuinely unreachable at runtime (confirming the fallback is both
  taken AND logged) was never constructed. Re-triaged as a residual in the `merge-safe-29` M4 pass —
  NOT merge-blocking (mechanism present; only the live down-path proof is missing).
  **Trigger:** next time the codebase-memory MCP is down/unregistered during a codex-orchestrated
  review — capture the reviewer log showing the disclosed fallback, then close #37.

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
  anchoring. **Residual:** convergence proven; codex's MCP reachability (T10) was **RESOLVED**
  in the `stabilize-codex-orchestrator` sprint — see that section above.

- **cursor-as-orchestrator headless fanOut.** IDE Task fanOut is shipped; `cursor-agent -p` has
  no Task/subagent API yet, so `metate run review` under `orchestrator.backend: cursor` prints
  the IDE ceremony instead of shell-fan-out.
  **Trigger:** `cursor-agent` CLI exposes Task fan-out (or stable `.cursor/agents/` invocation
  headless). Do **not** add `cursor-review.sh` — that path is codex-only.

- **Residual prompt-injection hardening on the codex fix-apply step.** The DATA/instruction
  boundary + 500-char cap + newline-strip are in place; egress-deny and allow-pattern gating
  on the `workspace-write` resume were scoped out.
  **Trigger:** before running `metate run review` under the codex orchestrator against an
  **untrusted** branch (e.g. external PRs in CI). Add network-egress denial during fix-apply
  and an imperative-verb/URL allow-pattern check on findings before handoff.

### Design / DRY (review DESIGN findings, report-only)

- **Three ad-hoc YAML-scalar parsers — PARTIALLY RESOLVED (sprint `backend-source-unification`,
  2026-07-03).** The shared readers now exist: `lib/profile.sh` (`prof_scalar`/`prof_nested`/
  `prof_block`/`prof_discover_toggle`) over a generic `lib/yaml.sh` walker, sourced by
  `codex-review.sh` and `sources/render.sh` (which retired its own `yaml_cd_scalar`/`yaml_cd_block`
  copies). **Still hand-rolled:** `bin/metate` `read_backend` and `bootstrap.sh`'s inline awk — not
  yet migrated to `lib/profile.sh` (and their quote-stripping still diverges).
  **Trigger:** the next edit to either script's profile reads, OR a parsing bug found in either copy —
  source `lib/profile.sh` instead of the inline awk.

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
