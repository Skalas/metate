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

## Long-running invocations — background the work call, not the id-capture call

Two kinds of call show up in the adapters below, and they want opposite treatment:

- **Fast id-capture calls** (e.g. cursor's `cursor-agent create-chat`) return an id on stdout
  in well under a second. Run these in the **foreground** and capture with command
  substitution (`CID=$(…)`) — backgrounding them would discard the very stdout you need.
- **The long-running work call** — the build, or a review round's resume + gate re-run — can
  run for many minutes. Run it with the Bash tool's **`run_in_background: true`**.

Why background the work call: a foreground Bash call is bound to the tool's timeout ceiling —
default 120000 ms (2 min), max 600000 ms (10 min). When the work outlives it, Bash sends
SIGTERM and the call dies with **exit 143**, killing the implementer mid-write. Raising
`timeout` to the 10-min max only postpones this; a real build/review round can legitimately
exceed 10 minutes, so the ceiling is not a reliable bound. A backgrounded call has no such
ceiling: it runs across turns and re-invokes the orchestrator when it exits, at which point
its output is retrievable.

So capture the id **on completion**, not mid-run — nothing needs it earlier (build only writes
`sessionFile` for the *later* review stage). When the work call is also the id source (claude's
`claude -p --output-format json` → `.session_id`), read it from the completed call's output;
redirecting stdout to a file (see the `claude` section below) is the robust form — it isolates
clean JSON for `jq` instead of fishing it out of the completion buffer's mixed stdout/stderr.
That file is a **transient** capture buffer — distinct from the durable `sessionFile`; overwrite
or delete it freely. Backends that resume by most-recent (`codex … resume --last`) need no id
capture at all.

## Code Discovery clause

When `codebaseMemory.enabled` in the profile, `metate-build` and `metate-review` prepend
this block to the implementer prompt (build prompt and resume/fix prompt alike). Backends
differ in how they otherwise learn the preference — see the per-backend table below — so the
prompt is the **only** path that reaches the `claude` backend in `-p` mode.

```
Code Discovery — prefer the codebase-memory-mcp knowledge graph over grep/Read for
structural reach. Before editing, trace the IMPACT of each change:
  - search_graph — find the symbol you're about to touch by name/label/pattern;
  - trace_path — who calls it / what it calls, so a changed signature doesn't break an
    off-diff caller;
  - get_code_snippet — exact symbol source by qualified name.
Fall back to grep/Read for string literals, configs, and non-code files. If the repo
isn't indexed yet, run index_repository first.
```

| backend | how it learns the tool-priority |
|---|---|
| cursor  | `.cursor/rules/codebase-memory.mdc` (file-based) **+** prompt clause |
| codex   | `AGENTS.md` block (file-based) **+** prompt clause |
| claude  | **prompt clause ONLY** — `-p` headless does not act on ambient CLAUDE.md the way the interactive loop does |
| gemini  | prompt clause only (no file-based rule wired) |

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
# start: pass to the Bash tool with run_in_background: true (foreground hits SIGTERM/exit 143)
# — see "Long-running invocations". Stdout → file for clean JSON; on completion: jq -r .session_id …
claude -p --output-format json "<build prompt>" > .metate/.session-start.json   # background this call
claude -p --resume "<SESSION_ID>" "<blocker fixes>"      # resume round — also a work call, background it
```

Single-vendor loop, or fallback implementer.

**Autonomy (`implementer.autonomous: true`).** Two independent gates must both be cleared, or
the loop stalls waiting on a prompt with no TTY:

1. **Outer** — the orchestrator spawning `claude -p` needs the `Bash(claude -p:*)` allow-rule.
   `bootstrap.sh` writes it to `.claude/settings.local.json` when `autonomous: true`. A Claude
   session can't self-grant it (self-modification guard); the user-invoked installer can.
2. **Inner** — the nested `claude -p` writing files + running the gate needs
   `--dangerously-skip-permissions`, or it cannot act headless:

   ```bash
   # both backgrounded work calls; start redirects stdout to recover the id (see above)
   claude -p --dangerously-skip-permissions --output-format json "<build prompt>" > .metate/.session-start.json
   claude -p --dangerously-skip-permissions --resume "<SESSION_ID>" "<blocker fixes>"
   ```

   Omit this flag when `autonomous: false` — the implementer then surfaces a normal permission
   prompt per write (human-in-loop; metate's design is otherwise identical, see metate-build Note).

> ⚠️ Unlike `cursor`/`codex`, the `claude` backend has **no file-based rule** wiring the
> knowledge graph. In `-p` headless mode it will grep/Read by default (burning tokens on
> structural reach) unless the prompt carries the **Code Discovery clause** above. When
> `codebaseMemory.enabled`, build and review MUST prepend it — for claude it's the only path.

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
