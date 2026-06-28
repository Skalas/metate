# metate

A portable, codebase-agnostic **development pipeline** for Claude Code — the
*ceremonias de metate*. Six ceremonies, each a skill; the three-round review engine is one
of them.

```
metate-prep → (build) → metate-review → metate-smoke → metate-aftercare → metate-ship
   0            1            2              3              4               5
```

Across the whole pipeline the **implementer** (an external CLI — `cursor-agent` ·
`codex` · `claude` · `gemini`) is the **only writer**. Claude Code orchestrates and its
sub-agents are read-only. The implementer's **build session is resumed across review
rounds**, so it keeps the rationale behind its own code instead of re-deriving it.

## The ceremonies

Start with **`metate`** — the entry-point skill that orients you, fills
`.metate/profile.yml` with autodetected defaults on first run, and routes you to the
right stage. The six stage skills do the actual work:

| # | Skill | What it does |
|---|---|---|
| 0 | `metate-prep` | read handoff docs in order, triage tech debt, fix sprint mode, file the issue ledger from the plan, cut the branch |
| 1 | `metate-build` | start a **resumable** implementer session, write `.metate/session.json`, build in layers, fast gate |
| 2 | `metate-review` | ≤3 rounds of parallel read-only review; patch **only blockers** via the implementer (same session); re-gate |
| 3 | `metate-smoke` | run e2e/smoke bound to the DoD matrix (T1…Tn) on seeded data; human approves UX only |
| 4 | `metate-aftercare` | from the diff, update the project's close-out deliverables (handoff, coverage, roadmap, debt-with-triggers) |
| 5 | `metate-ship` | bisectable commits, full ship gate, PR with issue auto-close — only when green and confirmed |

## Architecture: engine vs profile

```
skills (generic, install once)        .metate/profile.yml (per-repo, versioned)
├─ metate-prep/                         ├─ fastGate / shipGate     (your commands)
├─ metate-build/                        ├─ implementer.backend     (cursor/codex/…)
├─ metate-review/   ← review engine     ├─ reviewFocus             (your invariants)
│   ├─ IMPLEMENTERS.md  (CLI adapters) ├─ prep / smoke / aftercare / ship blocks
│   ├─ profile.template.yml            └─ sessionFile / isolation
│   └─ bootstrap.sh
├─ metate-smoke/ · metate-aftercare/ · metate-ship/
```

Nothing project-specific lives in the skills. Porting to a new codebase = one
`bootstrap.sh` run + editing the profile (above all, `reviewFocus`).

## Install

The model is **install once globally, then init per project** — the same shape as a
user-level skill.

**From GitHub, one line** (no clone; the installer fetches itself):

```bash
curl -fsSL https://raw.githubusercontent.com/Skalas/metate/main/install.sh | bash -s -- --user
```

Or hand the line to an agent like Claude Code — "install metate user-level from GitHub"
and it runs exactly that. Pin a ref with `METATE_REF=v1.0.0` if you want a fixed version.

**From a local checkout — user level** (skills global, available in every project; leaves a `metate-init` you run per project):

```bash
./install.sh --user
# then, inside any repo:
metate-init
```

**Project level** (skills vendored into the repo; bootstraps that project immediately):

```bash
./install.sh --project /path/to/repo
```

**As a Claude Code plugin** (for teams): this repo is also a valid plugin
(`.claude-plugin/plugin.json` + `skills/`). Add it as a marketplace and
`claude plugin install metate`, then run `metate-init` per project.

## Updating

Refresh an existing install to a newer metate without losing your tuned profile:

```bash
./install.sh --update --user              # refresh the global skills
metate-init --update                      # in each project: reconcile its profile
# or, project-vendored skills + profile in one step:
./install.sh --update --project /path/to/repo
```

`--update` re-copies the skills and **reconciles `.metate/profile.yml` against the
template**: keys added in the new version are appended with their defaults, while your
existing values and comments are left untouched. It's idempotent — an up-to-date profile
comes out byte-identical — and it prints exactly which keys it added so you can tune them.

## First run in a project — the decisions you make

`metate-init` (or `bootstrap.sh`) autodetects your toolchain (pnpm / npm / yarn / python /
cargo / go), writes `.metate/profile.yml`, and gitignores the session handoff. It never
clobbers an existing profile. Everything else is decisions **you** make by editing that
file — the bootstrap only guesses the gates. In order of importance:

1. **`reviewFocus`** *(the one that matters)* — your real invariants, e.g. "tenant scope on
   every transactional query", "money math at the cent", "state changes go through the
   domain guard". This is the difference between a generic review and one that catches your
   domain's actual failure modes. The template ships with placeholders you must replace.
2. **`implementer.backend` + `model`** — who writes the code: `cursor` (verified end-to-end),
   `codex`, `claude`, or `gemini` (probe first). Blank model = adapter default. See
   `metate-review/IMPLEMENTERS.md` for the per-backend commands and verification status.
3. **Gates** — confirm the autodetected `fastGate` (run each review round) and `shipGate`
   (full pre-PR, mirrors CI). A `make verify` target is picked up automatically if present.
4. **`prep`** — `baseBranch` (set to `dev` if you gitflow), `readingOrder` (handoff docs to
   read before building), `techDebtFile`, and `issues` (file one issue per test-matrix item
   from the text plan → the ledger that `ship` auto-closes; set `issues.create: false` to opt out).
5. **`smoke`** — `command` (your e2e/smoke suite) and an idempotent `seedCommand`.
6. **`aftercare.deliverables`** — close-out docs to update from the diff (handoff, coverage,
   roadmap, debt ledger). `{N}` interpolates the sprint number.
7. **`ship`** — `prTarget` (match `baseBranch`), `commitStyle`, `issueCloseKeyword`.
8. **`isolation`** — `none`, or `worktree` to run the auto-approving implementer in an
   isolated git worktree and review the diff before merging back.

Then run the ceremonies in order in Claude Code:
`metate-prep → (build) → metate-review → metate-smoke → metate-aftercare → metate-ship`.

## Adding an implementer

Add a row + start/resume commands to `metate-review/IMPLEMENTERS.md`. The contract:
`start → sessionId`, `resume(sessionId, prompt)` headless with write access, a fast model.

## License

MIT
