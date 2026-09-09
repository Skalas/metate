# ADR-0003 — State off the repo, one sprint ledger, sprints any agent can take over

- **Status:** **Phase 1 accepted and implemented** (2026-09-08) — `rounds[]` in `.metate/dod.json`,
  plus the cold-takeover branch in build's Round 0. **Phase 2 remains Proposed** (relocation,
  consolidation, parallel worktree sprints).
- **Kind:** `decision`
- **Deciders:** repo author.
- **Relates to:** extends ADR-0001 (fixed state paths, ledger consolidation); sequenced with
  ADR-0002 (one reviewer prompt path).

## Context

Four goals, stated by the author on 2026-09-08:

1. A sprint must be **takeable by a fresh agent** — not necessarily the one that started it.
2. metate must **not depend on per-repository agent configuration**.
3. metate's state should live **off the repo**, and be **simple and non-repeated**.
4. Two sprints must be workable **at the same time, in separate worktrees**.

What is true today:

- **Takeover is broken, in one specific way.** `.metate/session.json` holds
  `{implementer, sessionId, model}` — a vendor handle. The knowledge that accumulates across
  review rounds — which findings were **declined and why** — lives only in the orchestrator's
  context. `metate-build/SKILL.md` depends on it three times (do not re-raise a declined finding;
  fold near-duplicates; report a near-match of a declined item as new). A fresh agent joining at
  round 2 therefore re-raises findings that were already argued down. Warm context is an
  optimization; **the declined ledger is correctness.**
- **`dod.json` is already the consolidation target.** ADR-0001 folded `issues.json` and
  `smoke-matrix.json` into `{sprint, rows[]}`, and `validate_dod` rejects stray top-level keys.
  It records what must be true to be **done**. It has never recorded what **happened**.
- **Seven state files, three lifetimes, no shared shape** — the accretion ADR-0001 diagnosed but
  only partly resolved.
- **Parallel sprints have no story.** Every state path is `.metate/<file>` relative to the repo
  root, so two worktrees of the same project either share one working tree's state or collide.

## Decision (proposed)

### 1. All metate files move off the repo

```
~/.metate/repos/<repo-key>/          # repo-scoped, shared by every worktree
  profile.yml                        # config: gates, reviewFocus, backends, baseBranch
  ledger.json                        # cross-sprint: gates + signals
  archive/<sprint>/                  # closed sprints
  sprints/<sprint-key>/              # ONE PER ACTIVE SPRINT — worktree-safe
    sprint.json
    plan.md
```

A repo's metate footprint becomes **zero files** — including `profile.yml`, which an earlier draft
kept in-repo-but-ignored. Paths remain **fixed, not config** (ADR-0001's rule), just re-rooted.

**Two keys, because they answer different questions.**

- `<repo-key>` — from `git remote get-url origin`, normalized (drop scheme, credentials, trailing
  `.git`); falls back to a hash of the **main** worktree's path when there is no remote. Every
  worktree of a project resolves to the same repo-key, which is correct: gates, invariants and
  signals are properties of the project, not of a branch.
- `<sprint-key>` — the **current branch**, slugified. Git guarantees a branch is checked out in at
  most one worktree, so branch is collision-free by construction. Detached HEAD falls back to a
  hash of the worktree path.

### 2. Parallel sprints in separate worktrees are a first-class requirement

- **Per-sprint state is isolated** by `<sprint-key>` — separate `sprint.json`, `plan.md`, and
  `rounds[]`. There is no shared mutable per-sprint state.
- **Repo-scoped state is shared and concurrently written.** `ledger.json` can be appended by two
  sprints at once. Rules: write via **temp file + atomic rename**; **merge by item id** on append
  instead of rewriting the array; every item carries `sprint`, so entries coexist.
- **`profile.yml` is read-mostly** and shared deliberately — one set of gates per project. Only
  the wizard writes it, never during a sprint.
- `isolation: worktree` already exists for the implementer; this makes the *state* layer agree.

### 3. Consolidate by lifetime, and give every ledger one shape

| file | lifetime | absorbs |
|---|---|---|
| `sprint.json` | one sprint | `dod.json` (rows) · `session.json` (handle) · `release.json` |
| `ledger.json` | across sprints | `human-gates.json` · `signals.json` |
| `plan.md` | one sprint | unchanged |

```json
{
  "sprint": "off-repo-state",
  "branch": "feat/off-repo-state",
  "base": "main",
  "mode": "REDUCE",
  "session": { "implementer": "cursor", "sessionId": "…" },
  "release": { },
  "rows":   [ { "id": "T1", "title": "…", "command": "…" } ],
  "rounds": [ { "n": 1, "gate": "pass", "failedLenses": [],
                "findings": [ { "id": "R1-3", "file": "…", "line": 42, "bucket": "blocker",
                                "summary": "…",
                                "disposition": "fixed | declined | deferred",
                                "rationale": "required when declined",
                                "destination": "techDebtFile | signals (when deferred)" } ] } ]
}
```

`rounds[]` is the new part and the reason this ADR exists. Human gates keep their `sprint` field
and grandfathering, so they cannot live in a per-sprint file — hence the split by lifetime rather
than by topic.

Every ledger uses the **same container shape** — `{ items: [ { id, sprint, … } ] }`, ids unique
within a file — replacing today's three container layouts and three id conventions.

### 4. Resume becomes an optimization; takeover becomes an entry point

- `session` in `sprint.json` is **optional**. Absent or stale → cold start: read `sprint.json` +
  `plan.md` + the branch diff and continue. No vendor resume required.
- `IMPLEMENTERS.md`'s resume column becomes informational ("supports resume: yes/no") rather than
  a prerequisite. A backend with no resume story is usable.
- The `metate` wizard gains a **takeover** route: read state, print where the sprint stands, name
  the next stage. A fresh agent and a returning agent use the same path.

## Consequences

**A repo's metate footprint becomes nothing at all.** With ADR-0002 (retire the Cursor agent
files) and the matching change for the code-discovery rule files, no metate artifact remains in
any repo — the question that started this line of work, answered by subtraction rather than
relocation.

**Simpler:** 7 state files → 3. One container shape. One per-sprint file. `bootstrap.sh` loses
every `.gitignore`/untrack pass for state, and most of its reason to exist.

**Riskier / lost:**

- **Machine-local.** No cross-machine or CI takeover. Accepted deliberately.
- **`reviewFocus` stops being shared.** A teammate cloning the repo gets no gates and no
  invariants; the wizard re-derives them per machine. The real cost of moving `profile.yml`.
- **Concurrency is now real.** Two agents appending to `ledger.json` is a genuine race; atomic
  rename plus id-merge is the mitigation, and it needs a test, not just a rule.
- **Key edge cases:** no remote, renamed remote or branch mid-sprint, forks sharing an upstream
  URL, a repo cloned twice on purpose. Needs a stated rule and a `metate-init --relink` escape.
- **Archive growth** — nothing prunes `archive/<sprint>/`.
- **State is invisible to `git status`.** Losing it is silent. Needs `metate --where`.

## Migration

15 repos in the field. `metate-init --update`, per repo:

1. Compute `<repo-key>`; create `~/.metate/repos/<repo-key>/`.
2. Move `profile.yml`; `git rm --cached` it where tracked.
3. Fold `dod.json` + `session.json` + `release.json` → `sprints/<branch>/sprint.json`
   (`rounds: []`); `human-gates.json` + `signals.json` → `ledger.json`; move `plan.md`.
4. Leave the originals until a round-trip validation passes, then remove — the pattern ADR-0001
   used for `issues.json`.

An in-repo `.metate/` continues to win while it exists, so migration is per-repo and reversible.

## Validation

- A sprint started in one harness and finished by a **different, cold** harness with no vendor
  resume: no declined finding is re-raised, and the DoD closes.
- **Two worktrees, two branches, two sprints, concurrently**: no cross-talk in `sprint.json`, and
  interleaved `ledger.json` appends from both lose nothing.
- `metate-scope` still reads the previous sprint from `archive/`.
- Migration round-trips on a copy of a real repo before anything is deleted.

## Alternatives

- **Keep state in-repo, add `rounds[]` only.** Much smaller; fixes takeover, leaves the footprint
  and has no parallel-sprint story. Viable as phase 1 — see *Sequencing*.
- **Commit the ledger.** Enables cross-machine and CI takeover; costs merge conflicts every sprint
  and puts review findings in project history. Reconsider only if takeover must cross machines.
- **Key per-sprint state by worktree path instead of branch.** Survives branch renames, breaks on
  moved worktrees, and makes the state unfindable from a second clone. Branch is the better key.

## Sequencing

This is a sprint, not an edit — it touches every stage playbook, since all of them read state
paths. Splitting it makes the valuable half land early and independently:

- **Phase 1 — `rounds[]`, in place.** Add the adjudication ledger to `dod.json` where it already
  lives. Fixes takeover, the highest-value defect, with no relocation risk.
- **Phase 2 — relocate and consolidate.** Two keys, off-repo layout, migration, parallel sprints.

Phase 1 is worth doing even if phase 2 is never accepted.
