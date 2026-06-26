---
name: corte-build
version: 1.0.0
description: |
  Stage 1 (Build) of the `corte` pipeline. Starts a RESUMABLE implementer
  session (cursor/codex/claude) and writes the session handoff to
  `.corte/session.json` so later review rounds resume the same thread and keep
  the implementer's rationale. The implementer is the only writer; this skill
  drives it and records the session id. Reads `.corte/profile.yml`.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Bash
---

# corte-build — start the build session (and capture it)

The implementer writes the code. This skill's job is to start it as a **resumable
session** and persist the handle, closing the gap that would otherwise force the review
stage to open a fresh (amnesiac) session.

## Step 0 — load the profile
Read `.corte/profile.yml`: `implementer.backend`, `implementer.model`, `sessionFile`,
`isolation`. Adapter commands: read the `corte-review` skill's `IMPLEMENTERS.md`.

## Steps
1. **Start a resumable session** per the backend's `start` command (see IMPLEMENTERS.md).
   Capture the session id:
   - cursor → `CID=$(cursor-agent create-chat)`, then drive build with `--resume "$CID"`.
   - codex → run `codex exec …`; resume later with `--last` (or capture the id from `--json`).
   - claude → `claude -p --output-format json …` → `.session_id`.
2. **Write the handoff** to `sessionFile`:
   ```json
   { "implementer": "<backend>", "sessionId": "<id|--last>", "model": "<model>" }
   ```
3. **Build in layers** — domain → application → infrastructure → presentation. Pass the
   plan + DoD from Prep to the implementer. Honor project invariants (`reviewFocus`).
4. **Fast gate** — when the layer set is done, run `fastGate` from the profile. Fix before
   handing off to review.

## Output
Confirm `sessionFile` written (so review can resume), the layers built, and the fast-gate
result. Hand off to `corte-review`.

## Note
If you build interactively in a GUI instead of the CLI, you must still write
`sessionFile` yourself (or the review stage will stop). Prefer the CLI so the session id
is captured deterministically.
