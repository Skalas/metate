---
name: metate-build
version: 1.0.0
description: |
  Stage 2 (Build) of the `metate` pipeline. Starts a RESUMABLE implementer
  session (cursor/codex/claude) and writes the session handoff to
  `.metate/session.json` so later review rounds resume the same thread and keep
  the implementer's rationale. The implementer is the only writer; this skill
  drives it and records the session id. Reads `.metate/profile.yml`.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
allowed-tools:
  - Read
  - Write
  - Bash
---

# metate-build — start the build session (and capture it)

The implementer writes the code. This skill's job is to start it as a **resumable
session** and persist the handle, closing the gap that would otherwise force the review
stage to open a fresh (amnesiac) session.

## Step 0 — load the profile
Read `.metate/profile.yml`: `implementer.backend`, `implementer.model`, `implementer.autonomous`,
`isolation`. The session handoff is written to `.metate/session.json`. Adapter commands (incl. the autonomous flag for the `claude` backend):
read the `metate-review` skill's `IMPLEMENTERS.md`.

## Steps
1. **Start a resumable session** per the backend's `start` command (see IMPLEMENTERS.md).
   Run the build as a **long-running invocation** so it isn't bound to a short foreground
   timeout that would SIGTERM it mid-write (on the claude orchestrator that means the Bash
   tool's background mode — exit 143 otherwise); see IMPLEMENTERS.md → "Long-running
   invocations" for which call to background vs. capture in the foreground. Capture the
   session id:
   - cursor → `CID=$(cursor-agent create-chat)`, then drive build with `--resume "$CID"`.
   - codex → run `codex exec --json …` and **capture the real session id** into `.metate/session.json`
     (`< /dev/null` so headless doesn't block on stdin). `--last` is **not** safe when the
     orchestrator is also codex: the review fan-out spawns intervening codex sessions, so the
     codex review pilot requires the explicit id (see IMPLEMENTERS.md → codex §).
   - claude → `claude -p --output-format json …` → `.session_id`, read from
     `.metate/.session-start.json` *after* the backgrounded call completes (see IMPLEMENTERS.md
     → claude section for the redirect), then proceed to step 2.
   - claude-subagent → spawn the in-process implementer agent and record the ref it returns;
     there is no CLI and no JSON envelope, so the UUID check below does not apply — the ref must
     simply be non-empty. Resume is `SendMessage`, never a fresh agent (IMPLEMENTERS.md).

   **Validate the id before writing it.** Read it out of the JSON envelope with `jq` — never a
   substring of raw stdout — and check it against the backend's id form (a UUID for
   cursor/codex/claude). An envelope that does not parse, an empty id, or a leading CLI warning
   line is a 🛑 **STOP**: report the first line verbatim and fix the invocation (nearly always a
   missing `< /dev/null`). Never write a blank or garbage `sessionId` — review would resume an
   amnesiac session and the sprint's rationale is gone.
2. **Write the handoff** to `.metate/session.json`:
   ```json
   { "implementer": "<backend>", "sessionId": "<id|--last>", "sprint": "<topic>", "model": "<model>" }
   ```
   `sprint` is **required** — the branch topic, matching `.metate/issues.json` → `sprint`. It is what lets
   review tell a live session from a dead one (metate-review → Inputs); without it a two-month-old
   session file is indistinguishable from today's. `model` is **optional** — omit it rather than
   writing a placeholder.
3. **Build in layers** — domain → application → infrastructure → presentation. Pass the
   plan + DoD from Prep to the implementer. Honor project invariants (`reviewFocus`).
   **When `codebaseMemory.enabled`**, prepend the tool-priority clause (see
   `metate-review/IMPLEMENTERS.md` → "Code Discovery clause") to the build prompt: a
   `claude`-backed implementer does NOT pick this up from ambient CLAUDE.md the way the
   interactive loop does, and `cursor`/`codex` get it from their file-based rules — so the
   prompt is the only path that reaches the claude backend. Skip when `enabled: false`.
4. **Fast gate** — when the layer set is done, run `fastGate` from the profile. Fix before
   handing off to review.

## Output
Confirm `.metate/session.json` written (so review can resume), the layers built, and the fast-gate
result. Hand off to `metate-review`.

## Note
If you build interactively in a GUI instead of the CLI, you must still write
`.metate/session.json` yourself (or the review stage will stop). Prefer the CLI so the session id
is captured deterministically.
