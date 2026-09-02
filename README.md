# metate

> *Metate* — the Mesoamerican grinding stone, worked with a *mano*. The same
> stone grinds whatever you put on it: *maíz* into *masa*, seeds and chiles into
> *mole*, cacao into chocolate — raw material into something finished through
> patient, repeated passes. Here, the one stone that grinds *any* codebase into
> shipped work, one ceremony at a time — and is set up again for the next batch.

A portable, codebase-agnostic **development pipeline** for agent harnesses (Claude Code,
Codex, Cursor) — the *ceremonias de metate*. Six ceremonies, each a skill; build owns
the implementer session (round 0 writes, rounds 1–3 review).

```
metate-discover → metate-prep → metate-build → metate-smoke → metate-aftercare → metate-ship
   0                 1              2               3               4                5
```

It's a loop: `metate-aftercare` writes the next-sprint pointers that `metate-discover` reads
to open the next cycle — with **you** as the stop-condition between iterations.

## Harness-first model

**The orchestrator is whichever agent harness you open.** There is no standalone bash driver —
you invoke each stage as a skill (`metate-build`, `metate-prep`, …) and the harness executes
the playbook.

Two **swappable roles** (independent config in `.metate/profile.yml`):

| Role | Config | Adapter table |
|------|--------|---------------|
| **Reviewers** (3 lenses) | `build.reviewer.backend` (+ optional per-lens overrides) | `metate-build/REVIEWERS.md` |
| **Implementer** (only writer) | `implementer.backend` | `metate-build/IMPLEMENTERS.md` |

Cross-harness spawn is the point: a Claude Code session can orchestrate three `codex exec`
reviewers and a `cursor-agent` implementer. The implementer's **build session is resumed across
review rounds** so it keeps the rationale behind its own code.

**Soft enforcement:** reviewers report findings; the orchestrator adjudicates findings and routes
fixable ones to the implementer. There is no sandbox/read-only hard boundary — use on **trusted**
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
#    placeholders until then). Defaults: build.reviewer.backend: claude, implementer.backend: cursor

# 3. Run ceremonies in order inside Cursor (invoke each as a skill):
#    metate-discover → metate-prep → metate-build → metate-smoke → metate-aftercare → metate-ship
```

For **cross-harness** review (e.g. codex reviewers + cursor writer), set in the profile:

```yaml
build:
  reviewer:
    backend: codex
implementer:
  backend: cursor
```

Then `metate-build` fans out per `REVIEWERS.md` and resumes the implementer per `IMPLEMENTERS.md`.

## The ceremonies

Start with **`metate`** — the entry-point skill that orients you, fills
`.metate/profile.yml` with autodetected defaults on first run, and routes you to the
right stage. The six stage skills do the actual work:

| # | Skill | What it does |
|---|---|---|
| 0 | `metate-discover` | the pre-plan: survey signals, **read the situation**, rank candidates within posture by kind (sprint · decision · spike · retire · process), **you pick**, write the plan doc prep consumes |
| 1 | `metate-prep` | read handoff docs, triage tech debt, fix sprint mode, file the issue ledger (T-rows, or a `C1` tracking issue for a non-sprint kind), cut the branch |
| 2 | `metate-build` | round 0: resumable implementer session, layers, fast gate; rounds 1–3: parallel reviewers → route fixes → resume the same session → re-gate |
| 3 | `metate-smoke` | e2e/smoke bound to the DoD matrix (or the completion condition for a non-sprint kind); walk open human gates (when configured); capture pre-existing failures as signals |
| 4 | `metate-aftercare` | update close-out deliverables; optional semver release proposal |
| 5 | `metate-ship` | bisectable commits, full ship gate, PR with issue auto-close; optional tag/release |

## Architecture: skills vs profile

```
skills (generic, install once)        .metate/profile.yml (per-repo, versioned)
├─ metate-discover/                     ├─ fastGate / shipGate
├─ metate-prep/                         ├─ build.reviewer.backend / implementer.backend
├─ metate-build/                        ├─ reviewFocus
│   ├─ SKILL.md      (round 0 + review) ├─ discover / prep / smoke / aftercare / ship
│   ├─ REVIEWERS.md  (reviewer CLIs)    └─ .metate/session.json · signals.json · techDebtFile
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
2. **`build.reviewer.backend`** + **`implementer.backend`** — see `REVIEWERS.md` / `IMPLEMENTERS.md`.
3. **Gates** — `fastGate` / `shipGate`, detected by the wizard from the repo's real tooling.
4. **`prep`**, **`smoke`**, **`aftercare`**, **`ship`** — project-specific paths and commands.

Then run ceremonies in order inside your harness.

### Graph-augmented review

When `codebaseMemory.enabled: true` (default), reviewers prefer the knowledge graph and the loop
re-indexes between rounds. Set `enabled: false` to opt out.

## Adding a backend

- **Reviewer:** add a row to `metate-build/REVIEWERS.md` (typed JSON fan-out).
- **Implementer:** add start/resume commands to `metate-build/IMPLEMENTERS.md`.

## License

MIT
