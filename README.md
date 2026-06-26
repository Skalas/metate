# corte

A portable, codebase-agnostic **development pipeline** for Claude Code — the
*ceremonias de corte*. Six ceremonies, each a skill; the three-round review engine is one
of them.

```
corte-prep → (build) → corte-review → corte-smoke → corte-aftercare → corte-ship
   0            1            2              3              4               5
```

Across the whole pipeline the **implementer** (an external CLI — `cursor-agent` ·
`codex` · `claude` · `gemini`) is the **only writer**. Claude Code orchestrates and its
sub-agents are read-only. The implementer's **build session is resumed across review
rounds**, so it keeps the rationale behind its own code instead of re-deriving it.

## The ceremonies

| # | Skill | What it does |
|---|---|---|
| 0 | `corte-prep` | read handoff docs in order, triage tech debt, fix sprint mode, cut the branch |
| 1 | `corte-build` | start a **resumable** implementer session, write `.corte/session.json`, build in layers, fast gate |
| 2 | `corte-review` | ≤3 rounds of parallel read-only review; patch **only blockers** via the implementer (same session); re-gate |
| 3 | `corte-smoke` | run e2e/smoke bound to the DoD matrix (T1…Tn) on seeded data; human approves UX only |
| 4 | `corte-aftercare` | from the diff, update the project's close-out deliverables (handoff, coverage, roadmap, debt-with-triggers) |
| 5 | `corte-ship` | bisectable commits, full ship gate, PR with issue auto-close — only when green and confirmed |

## Architecture: engine vs profile

```
skills (generic, install once)        .corte/profile.yml (per-repo, versioned)
├─ corte-prep/                         ├─ fastGate / shipGate     (your commands)
├─ corte-build/                        ├─ implementer.backend     (cursor/codex/…)
├─ corte-review/   ← review engine     ├─ reviewFocus             (your invariants)
│   ├─ IMPLEMENTERS.md  (CLI adapters) ├─ prep / smoke / aftercare / ship blocks
│   ├─ profile.template.yml            └─ sessionFile / isolation
│   └─ bootstrap.sh
├─ corte-smoke/ · corte-aftercare/ · corte-ship/
```

Nothing project-specific lives in the skills. Porting to a new codebase = one
`bootstrap.sh` run + editing the profile (above all, `reviewFocus`).

## Install

**User level** (skills global, available in every project; leaves a `corte-init` you run per project):

```bash
./install.sh --user
# then, inside any repo:
corte-init
```

**Project level** (skills vendored into the repo; bootstraps that project immediately):

```bash
./install.sh --project /path/to/repo
```

**As a Claude Code plugin** (for teams): this repo is also a valid plugin
(`.claude-plugin/plugin.json` + `skills/`). Add it as a marketplace and
`claude plugin install corte`, then run `corte-init` per project.

## Per-project setup

`bootstrap.sh` autodetects your gate (pnpm / npm / yarn / python / cargo / go) and writes
`.corte/profile.yml`. Then:

1. Set `reviewFocus` to your real invariants — what makes the review catch your domain's
   failure modes instead of generic ones.
2. Fill the `prep` / `smoke` / `aftercare` / `ship` blocks (reading order, e2e command,
   deliverables, PR target).
3. Pick `implementer.backend` + `model`.
4. Run the ceremonies in order in Claude Code.

## Adding an implementer

Add a row + start/resume commands to `corte-review/IMPLEMENTERS.md`. The contract:
`start → sessionId`, `resume(sessionId, prompt)` headless with write access, a fast model.

## License

MIT
