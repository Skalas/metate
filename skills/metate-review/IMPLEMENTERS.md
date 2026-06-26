# Implementer adapters

The implementer is the **only writer**. The contract any backend must satisfy:

1. **start(prompt) → sessionId** — begin an implement session and expose a resumable id.
2. **resume(sessionId, prompt)** — continue that *same* thread, headless, with write access.
3. **fast model** — selectable, low-latency.

Continuity matters: review rounds resume the **build** session so the implementer keeps
the rationale behind its own code instead of re-deriving it.

## Build handshake

Build writes the session handoff (path = `sessionFile` in `.metate/profile.yml`, default
`.metate/session.json`) so the review skill knows how to resume:

```json
{ "implementer": "cursor", "sessionId": "44ca13f5-...", "model": "composer-2.5" }
```

For backends that support "resume most-recent", `sessionId` may be the literal `"--last"`.

---

## cursor  ✅ verified (continuity tested end-to-end)

```bash
CID=$(cursor-agent create-chat)                      # capture id ONCE
cursor-agent --print --resume "$CID" --model composer-2.5 --force \
  --workspace "$PWD" "<build prompt>"
# patch round — same session:
cursor-agent --print --resume "$CID" --force "<blocker fixes, by file:line>"
# read-only review mode: add --mode ask  or  --plan
```

- session capture: `create-chat` prints a clean UUID.
- write: `--force` (alias `--yolo`); constrain with `--sandbox enabled`.
- fast model: `composer-2.5` (or any `-fast`). `--list-models` enumerates.
- parseable output: `--output-format json|stream-json`.

## codex  ✅ verified (start + `resume --last` continuity tested)

```bash
# start (cd into the repo first; -C also works on `exec`)
codex exec -s workspace-write "<build prompt>"
# resume — NOTE: the `resume` subcommand does NOT accept -s or -C.
# Pass the sandbox via -c, and set cwd with the shell (cd) beforehand.
codex exec resume --last -c sandbox_mode="workspace-write" "<blocker fixes>"
# or by explicit id: codex exec resume "<SESSION_ID>" -c sandbox_mode="workspace-write" "<fixes>"
```

- session: `resume --last` (verified — no id parsing needed); or capture the id from `--json`.
- write: `-s workspace-write` on `exec`; on `resume` use `-c sandbox_mode="workspace-write"`.
  `-s read-only` for review-only passes.
- model: with an **API-key** account, `-m <model>` (e.g. a `codex` variant). With a
  **ChatGPT** account the `*-codex-fast` models are rejected — omit `-m` to use the
  configured default (e.g. `gpt-5.5` from `~/.codex/config.toml`). `--output-schema` for
  structured final response.

## claude  ✅ available

```bash
claude -p --output-format json "<build prompt>"          # → .session_id
claude -p --resume "<SESSION_ID>" "<blocker fixes>"
```

Single-vendor loop, or fallback implementer.

## gemini  ⛔ probe before use

When installed: non-interactive `gemini -p "<prompt>"`, auto-approve `--yolo`. Session
continuity (likely `--checkpointing` / saved sessions) is **unverified** — confirm a
resume round-trips before selecting `gemini`.

---

## Isolation (`isolation: worktree` in profile)

Auto-approving writes act on the working tree. For an unfamiliar diff, isolate:

- cursor: `-w, --worktree [name]` → `~/.cursor/worktrees/<repo>/<name>`.
- codex: run `exec` under a manual `git worktree` with `-C <path>` (start only; for
  `resume`, `cd` into the worktree since `resume` has no `-C`).

Show the diff before merging back.

## Verification status

| backend | headless write | session resume | fast model | notes |
|---|---|---|---|---|
| cursor  | ✅ `--force`            | ✅ `create-chat`+`--resume` (tested)       | ✅ `composer-2.5`         | fully verified |
| codex   | ✅ `-s workspace-write` | ✅ `resume --last` (tested)                | ✅ default (`gpt-5.5`)¹   | resume sandbox via `-c sandbox_mode` |
| claude  | ✅ default perms        | ✅ `--resume <session_id>`                 | ✅ sonnet                 | single-vendor option |
| gemini  | ⛔ unverified            | ⛔ unverified                         | —                        | probe before use |

¹ `*-codex-fast` models require an API-key account; ChatGPT-account auth rejects them —
omit `-m` to use the configured default.

> Adapters are CLI-only and codebase-agnostic. Adding a backend = adding a row here +
> its start/resume commands. Nothing in this file is project-specific.
