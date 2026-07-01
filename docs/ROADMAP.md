# Roadmap

The loop-closing doc: `metate-aftercare` writes the next-sprint pointers here;
`metate-discover` reads it (an `aftercare` signal) to open the next cycle. Write entries as
decisions, not vague notes. Triggered detail lives in [TECH-DEBT.md](./TECH-DEBT.md).

## Done

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

## In progress / next (post-merge-#29 hardening)

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

## Later

- Shared `lib/profile.sh` to collapse the three ad-hoc YAML parsers (DRY; see TECH-DEBT.md).
- Gemini as a verified backend (implementer and/or orchestrator) — currently unverified.
