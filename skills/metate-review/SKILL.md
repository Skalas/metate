---
name: metate-review
version: 1.0.0
description: |
  Stage 2 (Review) of the `metate` pipeline — the three-round review engine.
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

## Inputs

- **Diff under review:** `git diff <baseBranch>...HEAD` (`prep.baseBranch` from the
  profile; or staged changes if mid-build).
- **Implement session:** read `sessionFile`
  `{ "implementer": "...", "sessionId": "<id|--last>" }`.
  Build writes it (see `IMPLEMENTERS.md` §Build handshake). If missing, STOP — do **not**
  silently open a fresh session (loses the implementer's rationale).

## The loop — at most 3 rounds

### 1. Fan-out review (parallel, read-only)
Spawn these sub-agents **in one message** so they run concurrently; each gets the diff +
`reviewFocus` and returns structured findings:

- `code-reviewer` — correctness bugs, broken state transitions, and every invariant
  listed in `reviewFocus`.
- `security-auditor` — authz/tenant isolation, secrets, PII in payloads/logs, injection.
- `refactorer` — DESIGN/elegance/DRY. **Informational only** — never auto-applied.

### 2. Aggregate + categorize
Merge, dedupe by `file:line`, bucket each finding:

- **blocker** — wrong behavior, security/isolation failure, violated `reviewFocus`
  invariant, or won't build.
- **warning** — real but non-blocking (low-blast-radius edge case).
- **suggestion / DESIGN** — elegance, naming, structure.

Only **blockers** are auto-fixed. `warning` + `DESIGN` are listed for the user to decide —
Claude does not silently rewrite working code.

### 3. Patch via the implementer (resume same session)
If blockers exist, hand them to the implementer through its resume command (see
`IMPLEMENTERS.md`, using `implementer.backend`/`model` from the profile). The prompt must:
- address **only** the listed blockers, by `file:line` + one-line fix intent;
- forbid touching anything else ("do not refactor, do not change unrelated code");
- remind it this is its own code and to respect prior deliberate decisions.

Zero blockers → skip patching; the loop is done.

### 4. Fast gate
After patching, run `fastGate` from the profile. Failures become blockers for the next round.

### Exit criteria
- **0 blockers and gate green** → ✅ done.
- **Blockers remain after round 3** → 🛑 STOP. Summarize survivors; hand back to the user.

## Output
Per round → findings by bucket, what was patched, gate result. End with the verdict
(done / stopped) and the surviving `warning`+`DESIGN` list.

## Guardrails
- Implementer write mode is auto-approving. If `isolation: worktree`, run the implementer
  in an isolated git worktree and show the diff before merging back (see `IMPLEMENTERS.md`).
- Never let a sub-agent write. Route every fix through the implementer as a blocker.
- Adversarially verify a finding before calling it a blocker — a plausible-but-wrong "bug"
  wastes a round and risks the implementer breaking working code.
