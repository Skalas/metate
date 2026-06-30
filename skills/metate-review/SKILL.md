---
name: metate-review
version: 1.0.0
description: |
  Stage 3 (Review) of the `metate` pipeline — the three-round review engine.
  Orchestrates up to 3 rounds of parallel read-only sub-agent review
  (correctness · security · elegance) and applies ONLY blocker fixes through a
  pluggable implementer CLI (cursor-agent · codex · claude · gemini), resuming
  the SAME implement session so the implementer keeps the rationale behind its
  own code. Re-runs the project's fast gate each round; stops when 0 blockers
  remain or after round 3. Project-specific settings live in `.metate/profile.yml`
  — this engine is codebase-agnostic.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Bash
  - Agent
---

# Three-Round Review — pluggable cut ceremony

Claude Code orchestrates. The **implementer** (an external CLI) is the only writer —
Claude's sub-agents are **read-only** analysis. This avoids two agents editing the same
tree, and keeps the implementer's session so it remembers *why* it built things.

This engine carries **no project specifics**. Read them from the repo's profile.
Adapter registry + verified commands per backend: **read `IMPLEMENTERS.md`** (next to this file).

## Step 0 — load the project profile

Read `.metate/profile.yml` from the repo root. If absent, STOP and tell the user to run
the bootstrap (`bootstrap.sh`, shipped beside this skill). Keys:

- `fastGate` — command run after each patch round (quick loop).
- `shipGate` — full pre-PR gate (mirrors CI); informational here, enforced at Ship.
- `implementer.backend` / `implementer.model` — which adapter + model to drive.
- `sessionFile` — path to the implement-session handoff (default `.metate/session.json`).
- `isolation` — `none` | `worktree`.
- `reviewFocus` — the invariants the sub-agents must scrutinize in THIS codebase.
- `review.autoFix` — which buckets get routed to the implementer. One of:
  `blockers` (default) · `blockers+warnings` · `all`. Absent ⇒ `blockers`.
  Reporting is unconditional regardless of this setting (see Output).
- `codebaseMemory` — structural context provider (codebase-memory-mcp, a **required
  prerequisite** — install/bootstrap abort without it). The `enabled` flag (default
  `true`) toggles whether review *uses* the graph: when `enabled: true`, sub-agents
  prefer the knowledge graph over grep/Read and the loop re-indexes between rounds.
  Set `enabled: false` to opt this repo out of graph-augmented review (no graph calls,
  no re-index step). Read `reindex` (`git`|`always`|`manual`) and `indexCommand` only
  when enabled.

## Inputs

- **Diff under review:** `git diff <baseBranch>...HEAD` (`prep.baseBranch` from the
  profile; or staged changes if mid-build).
- **Implement session:** read `sessionFile`
  `{ "implementer": "...", "sessionId": "<id|--last>" }`.
  Build writes it (see `IMPLEMENTERS.md` §Build handshake). If missing, STOP — do **not**
  silently open a fresh session (loses the implementer's rationale).

## The loop — at most 3 rounds

**Each round is adversarial and cumulative, not a re-run.** Round 1 reviews the build diff.
Every round after carries forward the prior rounds' findings *and* the patch the implementer
just applied — and the reviewers have two jobs beyond a fresh read:

- **Verify the last patch.** For each finding fixed last round, confirm the fix actually
  resolves it and introduced no new defect the fast gate can't catch — a broken `reviewFocus`
  invariant, a regressed state transition, a newly-affected caller (`trace_path` the patched
  symbols when `codebaseMemory.enabled`). A fix is a fresh change under review, not a closed
  ticket. The orchestrator that drove the fix is the maker; verification comes from the
  read-only fan-out (§1), never the orchestrator's own spot-check or grep.
- **Catch what earlier rounds missed.** The point of multiple rounds is *escalating*
  scrutiny: treat a quiet prior round as a signal to probe harder and from new angles, not to
  relax. Do **not** re-raise a finding the implementer explicitly declined with a rationale
  (that never converges) — carry it forward as settled.

### 1. Fan-out review (parallel, read-only)
Spawn these sub-agents **in one message** so they run concurrently; each gets the diff +
`reviewFocus` and returns structured findings. **From round 2 on, also hand each sub-agent
the prior rounds' findings (fixed · declined-with-rationale · still-open) and the patch diff
applied since**, so it can verify the fixes and avoid re-litigating settled points:

- `code-reviewer` — correctness bugs, broken state transitions, and every invariant
  listed in `reviewFocus`.
- `security-auditor` — authz/tenant isolation, secrets, PII in payloads/logs, injection.
- `refactorer` — DESIGN/elegance/DRY. **Informational only** — never auto-applied.

**When `codebaseMemory.enabled`**, each sub-agent prompt must instruct it to prefer the
codebase-memory-mcp graph over grep/Read for structural reach (sub-agents do not inherit
this preference — restate it). Concretely:
- compute the **impact of the diff** — `trace_path` the changed symbols to find callers the
  diff doesn't show (a changed signature breaking an off-diff caller is a classic blocker);
- trace each `reviewFocus` invariant through the call graph rather than grepping for it;
- `security-auditor` uses cross-service tracing for authz/tenant isolation across repos;
- `refactorer` uses dead-code/high-fan-out queries for DESIGN findings.
Fall back to grep/Read for string literals, configs, non-code files, or when the graph
returns too little. If `enabled: false`, skip this — review proceeds grep-only as before.

### 2. Aggregate + categorize
Merge, dedupe by `file:line`, bucket each finding:

- **blocker** — wrong behavior, security/isolation failure, violated `reviewFocus`
  invariant, or won't build.
- **warning** — real but non-blocking (low-blast-radius edge case).
- **suggestion / DESIGN** — elegance, naming, structure.

Which buckets get auto-fixed is governed by `review.autoFix` from the profile
(default `blockers`):

| `review.autoFix`    | auto-fixed (routed to implementer) | reported only       |
|---------------------|------------------------------------|---------------------|
| `blockers`          | blocker                            | warning · DESIGN    |
| `blockers+warnings` | blocker · warning                  | DESIGN              |
| `all`               | blocker · warning · DESIGN         | —                   |

Whatever is **not** auto-fixed is still **always reported** (see Output) — Claude never
silently rewrites working code beyond the configured scope, and never silently drops a
finding either.

### 3. Patch via the implementer (resume same session)
Let **fixable** = the buckets selected by `review.autoFix`. If any fixable findings exist,
hand them to the implementer through its resume command (see `IMPLEMENTERS.md`, using
`implementer.backend`/`model` from the profile). The prompt must:
- address **only** the listed fixable findings, by `file:line` + one-line fix intent;
- forbid touching anything else ("do not refactor, do not change unrelated code");
- remind it this is its own code and to respect prior deliberate decisions;
- **when `codebaseMemory.enabled`**, prepend the tool-priority clause (see
  `IMPLEMENTERS.md` → "Code Discovery clause") so the implementer uses `trace_path` to
  check the **impact** of each fix before editing, instead of grepping. The `claude`
  backend does NOT inherit this from ambient CLAUDE.md in `-p` mode; `cursor`/`codex` get
  it from their file-based rules — the prompt is the only path to the claude backend.

When `autoFix` includes warnings or DESIGN, label each handed-off finding with its bucket so
the implementer can weigh a low-blast-radius warning or an elegance nit against the deliberate
decision it may be overturning — these are softer than blockers, so it may decline with a
one-line rationale rather than churn working code.

Zero fixable findings → skip patching; the loop is done (remaining findings are reported).

### 4. Fast gate
After patching, run `fastGate` from the profile. Failures become **blockers** for the next round
— regardless of which bucket's fix introduced them.

**Re-index (only when `codebaseMemory.enabled`).** The implementer just changed the tree, so
the graph is stale — refresh it before the next round's fan-out, or impact analysis lies:
- `reindex: git` — let the auto_index git watcher pick up the change (no action; the cheapest path);
- `reindex: always` — run `indexCommand` (or `index_repository` on the repo root) explicitly;
- `reindex: manual` — skip; the operator refreshes out of band.
Skip this step entirely when disabled.

### Exit criteria
Convergence is anchored on **blockers** — the objective signal. Auto-fixed warnings/DESIGN are
attempted opportunistically each round but never by themselves force another round (subjective
findings would never converge).

**A round that applied fixes can never declare done.** "0 blockers" must come from a fan-out
round on the patched tree — any patch *requires* a following verify round. A green fast gate is
necessary, not sufficient: it proves the build, not the logic.

- **0 blockers and gate green** → ✅ done. Any unfixed (or implementer-declined)
  warning/DESIGN findings are reported, not looped on.
- **Blockers remain after round 3** → 🛑 STOP. Summarize survivors; hand back to the user.
- **Round 3 *applied* fixes that cleared the last blockers** → 🛑 STOP, not ✅: the cap leaves
  no round to verify that patch, and round 3 cannot self-certify. Hand back with the round-3
  diff flagged as unverified — the user runs a spot-check (or a manual round-4 fan-out) before
  declaring done.

## Output
Reporting is **unconditional** — every finding surfaces regardless of `review.autoFix`.
Per round → findings by bucket (blocker · warning · DESIGN), which were routed to the
implementer vs. report-only, any the implementer declined (with its rationale), and the gate
result. End with the verdict (done / stopped) and the full surviving `warning`+`DESIGN` list
so nothing the auto-fix scope skipped is lost.

## Guardrails
- Implementer write mode is auto-approving. If `isolation: worktree`, run the implementer
  in an isolated git worktree and show the diff before merging back (see `IMPLEMENTERS.md`).
- Never let a sub-agent write. Route every fix through the implementer, tagged with its bucket.
- Adversarially verify a finding before calling it a blocker — a plausible-but-wrong "bug"
  wastes a round and risks the implementer breaking working code.
