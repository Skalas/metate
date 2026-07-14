# metate

> *Metate* — the Mesoamerican grinding stone, worked with a *mano*. The same
> stone grinds whatever you put on it: *maíz* into *masa*, seeds and chiles into
> *mole*, cacao into chocolate — raw material into something finished through
> patient, repeated passes. Here, the one stone that grinds *any* codebase into
> shipped work, one ceremony at a time — and is set up again for the next batch.

A portable, codebase-agnostic **development pipeline** for agent harnesses (Claude Code,
Codex, Cursor) — the *ceremonias de metate*. Seven ceremonies, each a skill; the
three-round review engine is one of them.

```
metate-discover → metate-prep → (build) → metate-review → metate-smoke → metate-aftercare → metate-ship
   0                 1             2            3              4               5                6
```

It's a loop: `metate-aftercare` writes the next-sprint pointers that `metate-discover` reads
to open the next cycle — with **you** as the stop-condition between iterations.

## Harness-first model

**The orchestrator is whichever agent harness you open.** There is no standalone bash driver —
you invoke each stage as a skill (`metate-review`, `metate-prep`, …) and the harness executes
the playbook.

Two **swappable roles** (independent config in `.metate/profile.yml`):

| Role | Config | Adapter table |
|------|--------|---------------|
| **Reviewers** (3 lenses) | `reviewer.backend` (+ optional per-lens overrides) | `metate-review/REVIEWERS.md` |
| **Implementer** (only writer) | `implementer.backend` | `metate-review/IMPLEMENTERS.md` |

Cross-harness spawn is the point: a Claude Code session can orchestrate three `codex exec`
reviewers and a `cursor-agent` implementer. The implementer's **build session is resumed across
review rounds** so it keeps the rationale behind its own code.

**Soft enforcement:** reviewers report findings; the orchestrator verifies or routes fixable
ones to the implementer. There is no sandbox/read-only hard boundary — use on **trusted**
branches only. A diff that modifies the review engine's own instruction files (lens prompts,
`prompt-clause`, `SKILL.md`) can subvert its own review; never run review on an untrusted branch.

## Quickstart

One backend end-to-end (Cursor orchestrator + Cursor implementer — the simplest path):

```bash
# 1. Install skills (user-level) and init the project
curl -fsSL https://raw.githubusercontent.com/Skalas/metate/main/install.sh | bash -s -- --user
cd your-repo && metate-init

# 2. In your harness, run the `metate` wizard skill — it detects fastGate/shipGate from the
#    repo's real tooling and fills reviewFocus + backends with you (gates ship as fail-loudly
#    placeholders until then). Defaults: reviewer.backend: claude, implementer.backend: cursor

# 3. Run ceremonies in order inside Cursor (invoke each as a skill):
#    metate-discover → metate-prep → metate-build → metate-review → metate-smoke → metate-aftercare → metate-ship
```

For **cross-harness** review (e.g. codex reviewers + cursor writer), set in the profile:

```yaml
reviewer:
  backend: codex
implementer:
  backend: cursor
```

Then `metate-review` fans out per `REVIEWERS.md` and resumes the implementer per `IMPLEMENTERS.md`.

## The ceremonies

Start with **`metate`** — the entry-point skill that orients you, fills
`.metate/profile.yml` with autodetected defaults on first run, and routes you to the
right stage. The seven stage skills do the actual work:

| # | Skill | What it does |
|---|---|---|
| 0 | `metate-discover` | the pre-plan: survey signals, rank candidate sprints, **you pick**, write the plan doc prep consumes |
| 1 | `metate-prep` | read handoff docs, triage tech debt, fix sprint mode, file the issue ledger, cut the branch |
| 2 | `metate-build` | start a **resumable** implementer session, write `.metate/session.json`, build in layers, fast gate |
| 3 | `metate-review` | ≤3 rounds: parallel reviewers → route fixable findings → resume implementer → re-gate |
| 4 | `metate-smoke` | e2e/smoke bound to the DoD matrix; walk open human gates (when configured); capture pre-existing failures as signals |
| 5 | `metate-aftercare` | update close-out deliverables from the diff |
| 6 | `metate-ship` | bisectable commits, full ship gate, PR with issue auto-close |

## Architecture: skills vs profile

```
skills (generic, install once)        .metate/profile.yml (per-repo, versioned)
├─ metate-discover/                     ├─ fastGate / shipGate
├─ metate-prep/                         ├─ reviewer.backend / implementer.backend
├─ metate-build/                        ├─ reviewFocus
├─ metate-review/                       ├─ discover / prep / smoke / aftercare / ship
│   ├─ SKILL.md      (review loop)      └─ sessionFile / signalsFile / techDebtFile
│   ├─ REVIEWERS.md  (reviewer CLIs)
│   ├─ IMPLEMENTERS.md (writer CLIs)
│   └─ bootstrap.sh
├─ metate-smoke/ · metate-aftercare/ · metate-ship/
```

Nothing project-specific lives in the skills. Porting = `bootstrap.sh` + editing the profile.

## Prerequisites

- **git** — required.
- An **implementer CLI** — `cursor-agent` · `codex` · `claude` · `gemini`.
- **[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)** — **required**.
  Install once:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/7824e505c192023a21b3e90bcb98ca6210629b64/install.sh | bash
  ```

## Install

**From GitHub:**

```bash
curl -fsSL https://raw.githubusercontent.com/Skalas/metate/main/install.sh | bash -s -- --user
cd your-repo && metate-init
```

**From a local checkout:**

```bash
./install.sh --user    # or --project /path/to/repo
```

Skills install to `.claude/skills` and `.agents/skills` (Claude + Codex surfaces).

## Updating

```bash
./install.sh --update --user
metate-init --update    # refresh harness artifacts in each project
```

Profile reconciliation is handled by the `metate` wizard skill (Step 2b).

## First run — profile decisions

`metate-init` scaffolds the profile; the `metate` wizard skill fills it with you:

1. **`reviewFocus`** — your real invariants (the highest-value field).
2. **`reviewer.backend`** + **`implementer.backend`** — see `REVIEWERS.md` / `IMPLEMENTERS.md`.
3. **Gates** — `fastGate` / `shipGate`, detected by the wizard from the repo's real tooling.
4. **`prep`**, **`smoke`**, **`aftercare`**, **`ship`** — project-specific paths and commands.

Then run ceremonies in order inside your harness.

### Graph-augmented review

When `codebaseMemory.enabled: true` (default), reviewers prefer the knowledge graph and the loop
re-indexes between rounds. Set `enabled: false` to opt out.

## Adding a backend

- **Reviewer:** add a row to `metate-review/REVIEWERS.md` (typed JSON fan-out).
- **Implementer:** add start/resume commands to `metate-review/IMPLEMENTERS.md`.

## License

MIT
