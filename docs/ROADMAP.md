# Roadmap

The loop-closing doc: `metate-aftercare` writes the next-sprint pointers here;
`metate-discover` reads it (an `aftercare` signal) to open the next cycle. Write entries as
decisions, not vague notes. Triggered detail lives in [TECH-DEBT.md](./TECH-DEBT.md).

## Done

- **Engine consolidation — parser correctness + drift gates + hygiene (sprint `engine-consolidation`,
  2026-07-03).** HOLD sprint that made the load-bearing config read correctly-or-loudly and closed two
  structural gaps the prior sprints left. **T1 (yq):** `lib/yaml.sh` now parses via `yq` v4 (a required
  dependency, peer to `jq`, gated in `install.sh`/`bootstrap.sh`) instead of hand-rolled indent-walking
  awk — the public function surface is unchanged, malformed YAML fails loudly (no more silent
  truncated `reviewFocus`), and leading-tab indentation is expanded while in-content tabs are preserved.
  **T2:** `bin/metate` `read_backend` and `bootstrap.sh` now read through `lib/profile.sh` (retiring the
  last hand-rolled awk + divergent quote-stripping — closes the "Later" parser residual); `render.sh` no
  longer shadows the shared `yaml_nested_scalar` (renamed `manifest_scalar`/`manifest_field`);
  `reviewer_lenses()` fallback asserts the shipped lens `.txt` set matches `YAML_REVIEWER_LENS_ORDER`
  instead of silently dropping a lens; the unknown-backend error now lists `gemini`. **T3 (drift gate):**
  the review-loop exit criteria are single-sourced under `sources/review-loop/` and rendered into both
  consumers, with a `make verify` `review-loop-drift` gate that fails on divergence between
  `codex-review.sh`'s verdict literals, `SKILL.md`'s spliced block, and the generated artifacts. **T4/T5
  (docs):** README gained an untrusted-branch security caveat next to the review ceremony and a
  minimal-path Quickstart. **T6 (cleanups):** `lc_f` localized, the two `codebaseMemory.enabled` guards
  folded, `RENDERED` derived from `render.sh --list-outputs`, `withheld.txt` as a jq set-difference, and
  `_review_engine_rel` now distinguishes a real typo (absent on disk → loud die) from a new-in-sprint
  untracked engine file (present → repo-relative fallback). **Verified:** 3-round `metate-review` (claude
  orchestrator, cursor implementer, session resumed each round) converged 0 blockers — R1 caught a real
  blocker (tab-in-block-scalar-content corruption that the first tab test missed, now covered by a
  regression test) + 3 warnings + 4 suggestions; the R1 fix to `_review_engine_rel` *introduced* a new
  blocker (dying on the sprint's own untracked T3 files) that R2 caught and R3 fixed and
  deterministically verified (untracked → resolves; absent → still dies); `make verify` green. Issues
  #68–#74. **Scope honesty:** the working-tree `backends.yml` roster-trust boundary stays deferred (the
  yq swap makes its parse cost heavier — noted in TECH-DEBT); two R2 elegance suggestions (exit-criteria
  prose as a third verdict-id representation; the withheld set-difference over-engineering + silent
  error-swallow) were captured, not fixed in-branch.

- **Backend source unification + discover source-naming cleanup (sprint `backend-source-unification`,
  2026-07-03).** Closes **M3**, the last staged follow-on from `engine-hardening`, and pays down the
  named "Backend duplication" REDUCE debt. **Source of truth (T1/T2):** reviewer lens bodies, the Code
  Discovery rule body, and backend/reviewer metadata now live once under `sources/` (`reviewers/*.md`,
  `code-discovery/*.md`, `backends.yml`) and render into every per-harness artifact — the three Cursor
  `readonly: true` reviewer agents, `cursor-rule.mdc`, `codex-rule.md`, and the Claude/Codex
  `generated/` prompt-clause + lens prompts — via a small `sources/render.sh` (files + a tiny renderer,
  not a template engine). **Drift gate (T4):** `make render` regenerates; `make render-check` (in
  `make verify`) fails the build if any committed artifact drifts from `sources/`, so the copy-paste
  drift the M2 clause enrichment made concrete can no longer happen silently. **Wiring (T3):**
  `codex-review.sh`/`bootstrap.sh` consume the generated/source-backed content; **backend switching
  preserved (T5)** — the orchestrator × implementer matrix is untouched, this removed maintenance
  copies, not flexibility. **Naming (T6/T7):** the `discover.signals` parent map → `discover.sources`
  (so capture signals aren't both the map and one source inside it), with a legacy `discover.signals`
  alias in `lib/profile.sh` so existing profiles don't break; dogfood profile + template + README
  updated. **Absent captures stay boring (T8):** absent/empty `signalsFile` → 0 open captures, gate-
  tested. Shared readers `lib/profile.sh` + generic `lib/yaml.sh` now back `codex-review.sh` and
  `render.sh` (retiring their duplicate parsers). **Verified:** `metate-review` (cursor implementer,
  resumed session) — R1 caught 2 blockers (`render.sh` `sed` `&`/`|` silent corruption that the drift
  gate would have certified as correct; the self-fix withhold set not covering the newly-extracted
  `lib/*.sh` engine files) + 1 warning (block-scalar blank-line truncation), all fixed; R2 verify
  clean; `make verify` green. Then all 4 review-captured elegance wants were paid down in the same
  session (unify parsers → `lib/yaml.sh`; derive the lens roster from `backends.yml`; document/derive
  the `PROFILE_ROOT` contract; collapse `yaml_cd_*`), whose verify round caught 2 more warnings (glob
  vs declaration lens order; `backends.yml`/`render.sh` missing from the withhold set) — fixed — and
  **downgraded a false blocker** (roster is frozen at startup, not re-read per round, so a mid-loop
  autofix can't shrink it). Issues #59–#66. **Scope honesty:** `bin/metate`/`bootstrap.sh` still
  hand-roll their profile reads (narrowed residual in TECH-DEBT); the untrusted-branch roster-trust
  boundary and the render-output-list duplication remain triggered debt, not this sprint's scope.

- **Review write-side: complete the capture lane + trim the schema (sprint `review-write-side`,
  2026-07-02).** Closes roadmap item 5's residual and the M4 follow-on. A review no longer loses
  its survivors to the terminal — `metate-review` now persists them, and the two kinds route to two
  sinks by semantics. **Bug half (T1):** an out-of-diff / exposed-latent, don't-fix-now defect is
  appended to `signalsFile` per `metate-smoke/signal.schema.json` with `foundIn: review:<lens>`
  (T2) — the read side (`metate-discover`) already folds it in. **Want half (T6, added in prep):**
  a deferred DESIGN/elegance survivor (or a declined warning) is appended to `prep.techDebtFile`
  as a trigger-gated bullet in the file's existing convention (stable-title dedup so aftercare
  doesn't double-file) — because a want is not a bug and doesn't fit the signal schema. In BOTH
  paths the reviewer fan-out stays **read-only**; **only the orchestrator writes** (new `Write` in
  review's allowed-tools, scoped by prose+invariant to `signalsFile`/`techDebtFile`), and the
  `reviewFocus` invariant was refined to match (fan-out read-only; orchestrator may write only the
  two capture sinks). **Schema trim (T3):** `severityGuess`/`blocksDoD` dropped from the signal
  schema's `required` (kept optional — capture is a lean record, triage enriches later). **Rename
  (T4):** the self-referential `discover.signals.signals` toggle → `captures`. **Verified:** 2-round
  `metate-review` (correctness · security · elegance) converged 0 blockers — R1 caught 3 real doc
  defects (Output overclaimed persistence for the in-diff-warning case; §2b's `###`-per-want format
  fragmented the ledger vs its real bullet-under-section convention; no blank-`techDebtFile` guard),
  all fixed; R2 verify came back clean; `make verify` green. Built through the resumed implementer
  session (`session.json`) — invariant honored, unlike the prior increment. Issues #52–#57.
  **Scope honesty:** M3 (backend unification) is the remaining staged follow-on; the capture
  round-trip is still unproven end-to-end here (metate has no e2e suite — see TECH-DEBT).

- **Signal-capture lane + discover explore mode (increment `signal-capture-lane`, 2026-07-02).**
  A bug found mid-flow no longer forces a choice between derailing the sprint and losing the find.
  **Write side:** `metate-smoke` now classifies each failure against `git diff <base>` — in-diff =
  a regression you own (back to build); out-of-diff / exposed-latent = a pre-existing find that is
  **captured, not fixed in-branch**, appended to `signalsFile` (new profile key) per the new
  `metate-smoke/signal.schema.json` (tier-1 capture: title/repro/evidence/attribution/severityGuess/
  blocksDoD/status — NOT a tracker issue). The smoke exit split means smoke can go green with
  out-of-diff finds parked as signals, removing the pressure that used to push the inline fix.
  **Read side:** `metate-discover` gained a `signals` source that folds open captures into the slate
  and **closes the loop** in Step 4 — a chosen signal is stamped `promoted`, an explicitly-dropped one
  `invalid`/`wontfix`, so nothing lives in the log forever. **Discover `mode`:** `steady` (default,
  today's behavior) vs `explore` (product not well-defined — lean on product intent + architecture,
  frame candidates as bets with assumption→validation, rank by learning value). Issue-filing stays
  gated behind `prep` (captures are not auto-issues). **Verified:** 3-round `metate-review` (correctness
  · security · elegance) converged 0 blockers — the review caught 6 real defects in the first cuts
  (missing `Write` grant, no `promoted` path, uncaptured `blocksDoD`, hardcoded path, missing injection
  guard, no `invalid`/`wontfix` trigger), all fixed; `make verify` green. Bent invariant (dogfood):
  written by hand on-branch, not through the implementer session (no `session.json`).
  Residual: the cold-intake `triage`/`hotfix` lane is still deferred (see below); the
  `metate-review` write-side is now **done** — see the `review-write-side` entry above.

- **Engine hardening — MCP-misuse fix + review read-only enforcement (sprint `engine-hardening`,
  2026-07-02).** Two milestones. **M1:** the three Cursor reviewer agents now carry
  `readonly: true` (read-only was enforced only by prose before — a real hole in the review
  engine's core contract); three stale Cursor claims in `ORCHESTRATORS.md` corrected and
  version-probed (headless Task fan-out exists on recent builds but `bin/metate` still `exit 2`s
  it pending verification; SKILL.md native since Cursor 2.4; `--approve-mcps` unconfirmed →
  `permissions.allow`+`--force`). **M2 (closes the "highest failure-surface" MCP item):** the
  Code Discovery clause now distinguishes *down vs bad-query vs empty* with a retry-on-usage-error
  rule + canonical call signatures, so agents stop misreading a malformed call as "MCP down"; the
  `fanOut` contract now has the orchestrator query the graph ONCE and pass the distilled slice to
  subagents as DATA (no N× rediscovery); Codex two-gate MCP note added (shell vs MCP approval),
  with the dangerous escape hatches scoped writer-only. **Verified:** 3-round `metate-review`
  (claude orchestrator, cursor implementer, session resumed each round) converged 0 blockers — R1
  caught a doc↔`bin/metate` contradiction, R2 caught the build's own `is_background` overreach
  (would have silently broken the synchronous fan-out merge), both fixed; `make verify` green.
  **Scope honesty:** M1+M2 only — M3 (backend unification) and M4 (review write-side) are staged
  as follow-on sprints (see below). Doc-only, no runtime behavior changed.

- **Cursor orchestrator adapter (increment `cursor-orchestrator`, 2026-07-01).** Native IDE path:
  Task fanOut for `review`/`discover` (mirrors Claude Agent tool — no `cursor-review.sh`);
  reviewer system prompts in `skills/metate-review/cursor-agents/`; bootstrap installs to
  `.cursor/agents/`; `bin/metate` headless `runStage` via `cursor-agent -p` (`review`/`discover`
  exit 2). Dogfood profile: `orchestrator.backend: cursor` + `implementer.backend: cursor`.
  **Verified:** 3-round IDE review (Task fanOut), implementer session handoff, `make verify` green.
  Residual: headless `fanOut` when `cursor-agent` CLI exposes Task (TECH-DEBT).

- **Codex as a native skill host (increment `codex-native-skills`, 2026-07-01).** Corrects an
  earlier wrong assumption that codex could only run metate via the shell dispatcher. Codex loads
  metate's `SKILL.md` playbooks **natively** through its interactive `$<skill>` picker (verified:
  `$metate` lists all stage skills), reading from the `.agents/skills` surface. Shipped: `install.sh`
  installs into BOTH `~/.claude/skills` (Claude) and `~/.agents/skills` (Codex), user + project scope;
  `metate-init` and `bin/metate` search both roots; `bootstrap.sh` gitignores `.agents/skills/metate-*`
  as vendored tooling. `metate run <stage>` is now explicitly the **headless/noninteractive** path,
  not the primary UX — interactive users invoke the skills natively in either runtime.

- **PR #29 made merge-safe (sprint `merge-safe-29`, 2026-07-01).** Closed the trust + DoD gaps
  gating the merge. Shipped: **M1/#43** review diff now includes untracked files (was a false
  "clean" — new implementer files were invisible), hardened with a RETURN-trap index restore, a
  case-insensitive secret skip-list (`.env`/`*.pem`/`id_*`/`*credentials*`/…), and NUL-safe I/O;
  **M2/#45** self-review guard (running review engine excluded from the fixable set + runStage-writes
  context to reviewers) — retires the metate-on-metate dogfood limitation; **M3/#46** Code Discovery
  clause + MCP override gated on `codebaseMemory.enabled`; **M5/#44** install.sh piped path clones the
  requested ref; **M6/#48** bootstrap autonomy whitelist is backend-agnostic (claude/cursor/codex).
  DoD ledger verified: **T1·T2·T4·T5·T7·T8 closed with evidence** (#35,#36,#38,#39,#41,#42; parent
  #28 too); **T3/#37 and T6/#40 re-triaged as tracked residuals** (kept open — not merge-blocking).
  README manual updated: `metate run <stage>` dispatcher, cursor-orchestrator marked not-yet-wired,
  `codebaseMemory.enabled` toggle. Ship gate `make verify` green. **Scope honesty:** the branch
  ships **claude + codex** orchestrators; **cursor-as-orchestrator stays deferred** (`bin/metate`
  `die`s on it) — see below.

- **Codex MCP reachability + review-loop convergence (sprint `stabilize-codex-orchestrator`,
  2026-06-30).** Closed the T10 limitation: headless `codex exec` auto-cancelled MCP tool calls
  (`approvals_reviewer="user"`, no TTY; `approval_policy="never"` covers shell only), so codex
  reviewers silently grepped. Fix (`39df709`): `-c …default_tools_approval_mode="approve"` on the
  reviewer fan-out + implement resume — graph reachable, sandbox intact, verified live. **T5**
  convergence validated on a neutral sandbox (find → resume-fix → gate → done, 2 rounds; resume by
  explicit session id). Issues #35–#38. **Learned:** metate reviewing its *own* engine is degenerate
  (self-edit crash + oscillation) — dogfood-only, see TECH-DEBT. Follow-ups filed: #43 (untracked-file
  review gap), #44 (install.sh piped path). Residual: T6 dedicated branch-behind scenario unexercised.

- **Pluggable orchestrator (sprint `pluggable-orchestrator`, 2026-06-30).** `orchestrator.backend`
  (claude · codex · cursor) independent of the implementer; `ORCHESTRATORS.md` adapter contract;
  `bin/metate` dispatcher; codex-only review pilot validated live (T3·T4·T5). Shipped as a
  **draft stabilization branch** (PR #29) — issues #19–#28 stay open until merge.

## In progress / next

**No staged follow-ons remain from the `engine-hardening` sprint** — all shipped (see Done), and the
`engine-consolidation` sprint (2026-07-03) closed the parser-correctness + drift-gate + hygiene batch.
**The prioritized next step is the external-repo proof run (validation):** one full
discover→ship pass on a real Python/TS repo with a real fast gate and e2e suite. It is the
reprioritization pivot and opportunistically closes the two long-deferred validation items
(#37 graph-unavailable fallback, #40 branch-behind anchoring) plus the unproven capture round-trip on
real data. After it, the **pluggable-roles epic (#30–#34, independent `reviewer.backend`)**; the
untrusted-branch hardening (roster-trust boundary — now with a heavier `yq` parse cost, see TECH-DEBT —
plus fix-apply egress) stays trigger-gated until a review actually runs on an untrusted branch.

## Legacy hardening backlog (post-merge-#29)

Ranked by failure-surface, not effort. Each has a trigger in TECH-DEBT.md.
(T10 codex MCP reachability, the metate-on-metate self-review guard, and the #43 untracked-file
review gap — all **done**, see the two Done entries above.)

1. **T3 live graph-unavailable fallback proof (#37).** Mechanism is in (in-rationale disclosure +
   `codebaseMemory.enabled:false` opt-out); missing is a live run with the MCP genuinely down that
   captures the logged fallback. Trigger in TECH-DEBT.md.
2. **T6 branch-behind dedicated validation (#40).** Merge-base→working-tree anchoring ran and clean
   multi-round convergence is proven (T5); the one unexercised path is a base strictly ahead of
   the feature branch.
3. **Deeper injection mitigation on the codex fix-apply step.** The DATA-boundary + cap +
   newline-strip are in (and this sprint added `.file`/`.line` sanitization); add network-egress
   denial during `workspace-write` resume and an imperative-verb/URL allow-pattern check on
   findings before handoff.
4. **Native typed-subagent fan-out — CLI upgrade (EXPAND).** Cursor IDE Task fanOut is shipped.
   Remaining: codex `.codex/agents/*.toml` batch fan-out and headless `cursor-agent` Task API
   once those CLIs stabilize — higher fidelity than shell-process `codex exec` baseline.
5. **Cold-intake `triage` + compressed `hotfix` lane.** The mid-testing capture path is in; the
   *externally-reported* bug path (triage → route → hotfix/backlog/interrupt) is designed but unbuilt.
   Only build if cold bug reports become a real, recurring need. Trigger in TECH-DEBT.md.
   *(`metate-review` signal write-side is now **done** — see the `review-write-side` Done entry.)*

## Later

- ~~Finish the parser consolidation~~ **DONE (sprint `engine-consolidation`, 2026-07-03).** All
  profile reads (incl. `bin/metate` `read_backend` and `bootstrap.sh`) now flow through
  `lib/profile.sh` over a `yq`-backed `lib/yaml.sh`; the hand-rolled awk is retired.
- Gemini as a verified backend (implementer and/or orchestrator) — currently unverified.
