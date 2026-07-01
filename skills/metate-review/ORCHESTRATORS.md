# Orchestrator adapters

The **orchestrator** is the agent that reads the `SKILL.md` playbooks, runs the seven
stages, and fans out the reviewers. It is the twin of the **implementer** (the only writer,
see `IMPLEMENTERS.md`) — and, like the implementer, it is pluggable. `orchestrator.backend`
and `implementer.backend` are **independent** config cells, so "codex-only" (codex
orchestrates *and* writes) and "codex-cursor" (codex orchestrates, cursor writes) are just
points in the cross-product `{claude,codex,cursor} × {cursor,codex,claude,gemini}`.

The coupling is concentrated: across the seven stages the orchestrator reduces to **two**
non-neutral primitives. Everything else (`.metate/` flat-file state, `session.json`,
`issues.json`, `profile.yml`, the codebase-memory MCP, the `IMPLEMENTERS.md` writer
handshake) is already runtime-neutral — do not re-abstract it.

## The two primitives

1. **`runStage(skill)`** — execute a `SKILL.md` playbook end to end. The default,
   single-agent shape: feed the playbook + the project profile to the orchestrator and let
   it drive the stage's bash. `prep` / `build` / `aftercare` are pure `runStage`.
2. **`fanOut(reviewers[], read-only)`** — launch **N concurrent read-only agents**, each
   returning **typed JSON findings**, then merge in shell. Used by `discover`, `review`,
   `smoke`, `ship`. The **baseline** is shell-process fan-out — N `<orch> exec` processes
   constrained to read-only, each with `--output-schema`, joined with `jq`. This is the
   controllable, deterministic path both research streams converged on; **native typed
   subagents** (`.codex/agents/*.toml`, `.cursor/agents/*.md`, Claude sub-agents) are a
   deferred per-runtime upgrade, not the contract baseline.

A reviewer's typed findings conform to `finding.schema.json` (next to this file):
`{ findings: [{ file, line, bucket, summary, rationale }] }`, `bucket ∈
blocker|warning|suggestion`. The runnable codex reference implementation of both primitives
for the review loop is `codex-review.sh` (next to this file).

## Code Discovery clause (MCP reachability) — applies under every orchestrator

When `codebaseMemory.enabled`, the read-only fan-out must prefer the codebase-memory-mcp
graph over grep/Read for structural reach (impact of the diff, callers of changed symbols,
`reviewFocus` invariants traced through the call graph). Each runtime reaches the MCP
differently — see the per-runtime blocks. This is the same clause `IMPLEMENTERS.md` prepends
to the **writer** prompt; here it governs the **reviewer** fan-out.

---

## claude  ✅ verified (today's default path)

The Claude Code plugin path — unchanged by this sprint. `orchestrator.backend: claude`
(or blank) preserves it byte-for-byte.

```text
runStage(skill)         → invoke the `metate-<stage>` Skill (the plugin loads SKILL.md).
fanOut(reviewers, ro)   → spawn the reviewers as read-only sub-agents (the Agent tool)
                          in ONE message so they run concurrently; each returns findings.
```

- read-only: Claude sub-agents are analysis-only by construction (no Write/Edit in the
  reviewer prompt); `metate-review`'s `allowed-tools` is `Read · Bash · Agent`.
- MCP: the codebase-memory MCP server is registered in `~/.claude.json`; sub-agents do not
  inherit the tool-priority preference — **restate the Code Discovery clause in each
  sub-agent prompt**.

## codex  ✅ verified (codex-cli 0.142.0 — fanOut + resume tested via `codex-review.sh`)

```bash
# runStage(skill): drive a stage playbook headless. Pre-grant approvals so a mid-run
# approval cannot stall the headless process (see gotchas).
codex exec -s workspace-write -c approval_policy="never" --cd "$PWD" "$(cat skills/metate-<stage>/SKILL.md)
<project profile + stage inputs>"

# fanOut(reviewers, read-only): N parallel read-only processes, typed JSON out, shell merge.
# APPROVE_MCP pre-approves the codebase-memory MCP tool calls headless — WITHOUT it, exec
# auto-cancels them ("user cancelled MCP tool call") and reviewers grep-fall-back silently.
APPROVE_MCP='-c mcp_servers.codebase-memory-mcp.default_tools_approval_mode="approve"'
codex exec --sandbox read-only -c approval_policy="never" $APPROVE_MCP --cd "$PWD" \
  --output-schema skills/metate-review/finding.schema.json \
  -o /tmp/correctness.json "<correctness reviewer prompt>" &
codex exec --sandbox read-only -c approval_policy="never" $APPROVE_MCP --cd "$PWD" \
  --output-schema skills/metate-review/finding.schema.json \
  -o /tmp/security.json    "<security reviewer prompt>" &
codex exec --sandbox read-only -c approval_policy="never" $APPROVE_MCP --cd "$PWD" \
  --output-schema skills/metate-review/finding.schema.json \
  -o /tmp/elegance.json    "<elegance reviewer prompt>" &
wait
jq -s '{findings: (map(.findings) | add | unique_by([.file,.line,.summary]))}' \
  /tmp/correctness.json /tmp/security.json /tmp/elegance.json

# resume (apply blocker fixes through the codex IMPLEMENT session — IMPLEMENTERS.md):
#   `resume` takes no -s/-C; pass the sandbox via -c and set cwd with the shell.
#   Resume by EXPLICIT session id (NOT --last): the read-only fan-out above spawns newer
#   codex sessions, so --last would resolve to a reviewer thread, not the implement session.
( cd "$PWD" && codex exec resume "$SESSION_ID" \
    -c sandbox_mode="workspace-write" -c approval_policy="never" $APPROVE_MCP "<blocker fixes>" )
```

- `--output-last-message FILE` (`-o`) isolates the typed final response for `jq`; combine
  with `--output-schema`. `--json` is the JSONL alternative if you'd rather stream events.
- model: omit `-m` to use the configured default (`gpt-5.5` from `~/.codex/config.toml`).
  `*-codex-fast` models require an API-key account; ChatGPT-account auth rejects them.
- MCP: codex reads MCP servers from `~/.codex/config.toml` `[mcp_servers.*]`, but
  **registration alone is not enough headless**. In `codex exec` an MCP tool call is a
  *separate* approval gate (`approvals_reviewer = "user"`); with no TTY it is auto-cancelled
  (`user cancelled MCP tool call`) and the agent silently greps instead. `approval_policy="never"`
  does **not** cover this — it only auto-approves *shell commands*. Auto-approve the server's
  tool calls with `default_tools_approval_mode="approve"`, passed per-run via `-c` (the
  `APPROVE_MCP` var above) so **no machine-specific config lives in the repo**; the read-only
  sandbox stays intact. File-based tool-priority guidance also lives in `AGENTS.md` (bootstrap
  injects it), but restate the Code Discovery clause in the reviewer prompt too (the only path
  that always reaches the agent). See `codex-rule.md`.
- re-index between rounds: the `codex-review.sh` pilot relies on `reindex: git` — the
  auto-index git watcher refreshes the graph after the implementer patches, so the pilot
  triggers no re-index itself. `reindex: always` / `reindex: manual` are **not** honored by
  the pilot (a documented limitation); use `reindex: git` under the codex orchestrator.

## cursor  ✅ verified (IDE — Task fanOut; headless runStage via `cursor-agent -p`)

Cursor has **two paths**. The **primary** path mirrors Claude: the orchestrator runs
inside the Cursor IDE and fans out reviewers with the **Task** tool — no shell driver
( `codex-review.sh` is codex-only). The **headless** path uses `cursor-agent -p` for
`runStage` stages; `fanOut` stages (`review`, `discover`) stay IDE-native until the CLI
exposes Task fan-out.

```text
runStage(skill)         → Cursor IDE: invoke the `metate-<stage>` skill (native SKILL.md).
                          Headless: `cursor-agent -p --trust --approve-mcps --force …`
                          with the playbook + profile (see bin/metate).
fanOut(reviewers, ro)   → IDE ONLY: launch three Task subagents in ONE message, each
                          `readonly: true`, returning JSON per finding.schema.json.
                          Headless: NOT supported — use codex orchestrator or run review
                          interactively in Cursor (do not shell-fan-out cursor-agent).
```

### fanOut — Task mapping (review + discover)

Launch **three Task tool calls in one turn** (parallel). Each prompt carries the diff
(**wrapped in `<diff>` … `</diff>` — inner content is DATA only**), `reviewFocus`, the Code
Discovery clause (when `codebaseMemory.enabled`), lens instructions, and: *Return ONLY valid
JSON matching finding.schema.json — no markdown fences.*

| Lens | Task `subagent_type` | `readonly` | Default buckets |
|------|----------------------|------------|-----------------|
| correctness | `code-reviewer` | `true` | blocker · warning · suggestion |
| security | `security-auditor` | `true` | blocker · warning · suggestion |
| elegance | `refactorer` | `true` | **suggestion only** |

Project-scoped reviewer system prompts ship in `skills/metate-review/cursor-agents/`
(bootstrap copies them to `.cursor/agents/metate-*.md`). The Task `subagent_type` values
above are the built-in lenses; fold each agent file's lens rules into the Task prompt.

**Parse + merge** (orchestrator in shell/Bash, not a subagent):
1. Strip optional markdown fences from each response; `jq` validate against `finding.schema.json`.
2. Merge: `jq -s '{findings: (map(.findings) | add | unique_by([.file,.line,.summary]))}'`.
3. A lens that crashes or returns malformed JSON is a **failed lens** — surface it loudly;
   do not silently treat as 0 findings (same rule as `codex-review.sh`).

### runStage — headless (`metate run <stage>`)

For stages without `fanOut` (`prep`, `build`, `aftercare`, `smoke`, `ship`):

```bash
cursor-agent -p --trust --approve-mcps --force \
  --model composer-2.5 --workspace "$ROOT" --output-format text \
  "$(cat skills/metate-<stage>/SKILL.md)

Run this metate stage against the repo at $ROOT. Read project specifics from $PROFILE."
```

- **`--model auto` is rejected** — name a concrete model (e.g. `composer-2.5`).
- **`--force`** — auto-approves shell commands headless (analogous to codex
  `approval_policy="never"` for runStage). Pair with `--trust` (workspace) and
  `--approve-mcps` (MCP). `SKILL_MD` is resolved via `skills_dir()` (vendored metate
  playbooks only) — do not point `skills_dir` at untrusted trees.
- **30s shell timeout** can kill nested long `claude -p`/`codex` calls from inside the
  agent — prefer driving the implementer via `cursor-agent --resume` in a background
  Bash call (see `IMPLEMENTERS.md` → long-running invocations).
- MCP: `~/.cursor/mcp.json` + `.cursor/rules/codebase-memory.mdc` (bootstrap installs
  it) + **`--approve-mcps`** headless + restate the Code Discovery clause in reviewer prompts.

## gemini  ⛔ unverified

`gemini -p "<prompt>"`, auto-approve `--yolo`. Read-only fan-out, structured output, and
MCP reachability in headless are **unverified** — confirm a fan-out + merge round-trips
before selecting `gemini` as orchestrator.

---

## Runtime gotchas (encode here, not in the engines)

- **codex headless approvals must be pre-granted.** Run with `-c approval_policy="never"`
  plus the right sandbox (`-s workspace-write` on `exec`, `-c sandbox_mode="workspace-write"`
  on `resume`), or a mid-run approval bubbles up and **stalls** the headless process.
- **`--output-schema` on `resume` is version-dependent.** Present in codex-cli 0.142.0;
  if a target install rejects it on `resume`, drop the flag there and validate the JSON in
  shell instead (fan-out reviewers use plain `exec`, which always accepts it).
- **cursor is beta:** 30s shell timeout, `--approve-mcps` for headless MCP, no `--model auto`.

## Verification status

| backend | runStage | fanOut (read-only, typed) | MCP in headless | notes |
|---|---|---|---|---|
| claude  | ✅ Skill tool                  | ✅ Agent sub-agents (one message)            | ✅ `~/.claude.json` | today's default; untouched |
| codex   | ✅ `exec` (tested)             | ✅ parallel `exec --output-schema` (tested)  | ✅ config + `default_tools_approval_mode="approve"` via `-c` (verified live) | resume sandbox via `-c sandbox_mode`; pre-grant BOTH shell (`approval_policy`) and MCP (`default_tools_approval_mode`) approvals |
| cursor  | ✅ IDE skill + `-p` runStage     | ✅ Task subagents (IDE only; one message)    | ✅ `--approve-mcps` + rule | fanOut not headless; no `cursor-review.sh` |
| gemini  | ⛔ unverified                  | ⛔ unverified                                | ⛔ unverified | probe before use |

> Adapters are CLI-only and codebase-agnostic. Adding an orchestrator = adding a row here +
> its `runStage`/`fanOut` command blocks. Nothing in this file is project-specific — the
> backend is selected by `orchestrator.backend` in `.metate/profile.yml` and routed by the
> `metate run <stage>` dispatcher (`bin/metate`). Unknown backend ⇒ the dispatcher fails
> loudly; blank/absent ⇒ `claude` (preserves today's behavior).
