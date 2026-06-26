# three-round-review

A portable, codebase-agnostic **cut ceremony** for Claude Code.

Claude Code orchestrates up to **3 rounds** of parallel read-only sub-agent review
(correctness · security · elegance), categorizes findings (blocker / warning / DESIGN),
and applies **only blockers** by driving an **external implementer CLI** — resuming the
*same build session* so the implementer keeps the rationale behind its own code. The
project's fast gate runs after each round; it stops at 0 blockers or after round 3.

The implementer is **pluggable**: `cursor-agent` · `codex` · `claude` · `gemini`.
The single writer is always the implementer — Claude's sub-agents are read-only.

## Architecture

```
engine (generic, install once)            profile (per-repo, versioned with code)
└─ skills/three-round-review/             └─ .review/profile.yml
   ├─ SKILL.md          orchestration        ├─ fastGate / shipGate  (your commands)
   ├─ IMPLEMENTERS.md   CLI adapters          ├─ implementer.backend  (cursor/codex/…)
   ├─ profile.template  scaffold              ├─ reviewFocus          (your invariants)
   └─ bootstrap.sh      per-project init      └─ sessionFile / isolation
```

Nothing project-specific lives in the engine. Porting to a new codebase = one
`bootstrap.sh` run + editing `reviewFocus`.

## Install

**User level** (engine global, available in every project; leaves a `trr-init` you run per project):

```bash
./install.sh --user
# then, inside any repo:
trr-init
```

**Project level** (engine vendored into the repo; bootstraps that project immediately):

```bash
./install.sh --project /path/to/repo
```

**As a Claude Code plugin** (for teams): this repo is also a valid plugin
(`.claude-plugin/plugin.json` + `skills/`). Add it as a marketplace and
`claude plugin install three-round-review`, then run `trr-init`/`bootstrap.sh` per project.

## Per-project setup

`bootstrap.sh` autodetects your gate (pnpm / npm / yarn / python / cargo / go) and writes
`.review/profile.yml`. Then:

1. Set `reviewFocus` to your real invariants — this is what makes the review catch your
   domain's failure modes instead of generic ones.
2. Pick `implementer.backend` + `model`.
3. Build through that implementer CLI so it writes `.review/session.json` (see
   `IMPLEMENTERS.md` §Build handshake).
4. Invoke the `three-round-review` skill in Claude Code after Build.

## Adding an implementer

Add a row + start/resume commands to `IMPLEMENTERS.md`. The contract: `start → sessionId`,
`resume(sessionId, prompt)` headless with write access, a fast model. See the verification
table for what's tested.

## License

MIT
