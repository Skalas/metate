# Implementation brief — wire the playbooks to off-repo state

**For the agent picking this up.** ADR-0003 phase 2 is half-landed: the resolver exists and is
tested, but nothing reads it. This is the remaining half. Read
[`docs/adr/0003-off-repo-state-and-sprint-handoff.md`](adr/0003-off-repo-state-and-sprint-handoff.md)
first — this brief assumes it.

## State of play

Merged and green (26 contract checks):

| commit | what |
|---|---|
| `cea7b66` | `skills/metate/lib/state.sh` — keys, layout, `migrate`, `where` |
| `a8d5908` | bootstrap backs up `.metate/` before untracking (a real data-loss fix) |
| `010efb8` | `state.sh env` + `claim-plan` |

`state.sh` is **inert**: no playbook, no script reads it yet. The pipeline still uses `.metate/`.

## The one hard rule

**Land the wiring in a single commit.** A half-wired pipeline reads `.metate/` while `state.sh`
points elsewhere. That split-brain — tooling moved, prose didn't — is exactly the shape of the two
worst bugs in this line of work (reviewer agents relocated to a directory nothing reads; `git rm
--cached` deleting a live profile). Do not stage it across commits.

## Path mapping

Resolve once per playbook, in its existing Step 0 line:

```bash
eval "$(bash <metate-skill>/lib/state.sh env)"    # exports $STATE and $SPRINT
```

| file | scope | new path |
|---|---|---|
| `profile.yml` | repo | `$STATE/profile.yml` |
| `signals.json` | repo | `$STATE/signals.json` |
| `human-gates.json` | repo | `$STATE/human-gates.json` |
| `plan.md` (pending, written by scope) | repo | `$STATE/plan.md` |
| `plan.md` (claimed, after branch cut) | sprint | `$SPRINT/plan.md` |
| `dod.json` | sprint | `$SPRINT/dod.json` |
| `session.json` · `.session-start.json` | sprint | `$SPRINT/session.json` |
| `release.json` | sprint | `$SPRINT/release.json` |

Repo-scoped files are shared by every worktree — gates and invariants are properties of the
project. Sprint-scoped files are isolated per branch, which is what makes two sprints at once safe.

## Files to change

```
skills/metate/SKILL.md            profile, plan, session, human-gates, .metate/
skills/metate-scope/SKILL.md      profile, plan, dod, signals
skills/metate-start/SKILL.md      profile, plan, dod, session, human-gates, .metate/
skills/metate-build/SKILL.md      profile, dod, session, signals
skills/metate-verify/SKILL.md     profile, dod, signals, human-gates
skills/metate-ship/SKILL.md       profile, dod, session, .session-start, human-gates
skills/metate-build/IMPLEMENTERS.md   session, .session-start
skills/metate-build/REVIEWERS.md      profile
skills/metate-build/bootstrap.sh      writes the profile; add `state.sh migrate`
```

## Budget — read before editing prose

**All six SKILL.md files sit at exactly their cap** (`tests/contracts/prose-budget.txt`); `make
budget` fails on +1 line. This is deliberate and it is why `$STATE`/`$SPRINT` are short:
`$SPRINT/dod.json` is the same length as `.metate/dod.json`, and `$STATE/profile.yml` is shorter
than `.metate/profile.yml`. Substitutions are line-neutral if you keep wrapping tight.

The `eval` line is the one real addition. Fold it into each playbook's existing
``Read `.metate/profile.yml`…`` sentence rather than adding a line. If a file still overruns,
**look for duplication before raising the cap** — the last three commits each found real
repetition when the gate complained (the write-scope restated in Guardrails, the "round that
applied a fix" rule restated in Exit criteria, the exit-message list restating the verdict
column). Raising a cap is permitted, but it must be an explicit line in the diff and argued in the
commit message.

## Ordering gotchas, all discovered the hard way

1. **`metate-scope` runs on the base branch.** Its plan cannot be sprint-scoped — it writes
   `$STATE/plan.md`. `metate-start` calls `state.sh claim-plan` **immediately after cutting the
   branch** (step 6) to move it into `$SPRINT`. Without this, scope's plan lands in `sprints/main`
   and start looks in `sprints/<branch>`.
2. **`metate-start` step 6 cuts the branch before writing sprint state.** That ordering is now
   load-bearing for a second reason: `$SPRINT` is branch-derived, so anything written before the
   cut lands in the wrong sprint dir.
3. **`bootstrap.sh` must call `state.sh migrate`** so a legacy in-repo `.metate/` moves before
   anything reads the new paths. Keep the `pre-untrack-backup` step — it is the fix for the
   deletion bug in `a8d5908`.
4. **A legacy `plan.md` migrates sprint-scoped** (it is the current branch's), while a newly
   scoped plan is repo-scoped and pending. Both paths are pinned by tests; do not "fix" the
   apparent inconsistency.

## Validation

`make verify` must stay green (26 checks). Then, beyond the suite:

- `bash skills/metate/lib/state.sh where` in a repo with a legacy `.metate/` — run bootstrap,
  confirm the files land per the mapping table and the legacy dir is gone.
- **Two worktrees, two branches**: confirm one shared `$STATE` and two distinct `$SPRINT`s, and
  that a sprint in one does not touch the other's `dod.json`.
- Grep for stragglers: `grep -rn '\.metate/' skills/` should return only `state.sh` itself,
  migration code, and prose that is genuinely *about* the legacy layout.
- Run one real stage end to end (`metate-scope` is cheapest) and confirm it reads and writes the
  new locations.

## After this lands

1. **Migrate the 14 other repos lazily** — do not batch. `metate-init` fixes each on contact; the
   author's standing instruction is not to touch them until they break or are worked on.
2. **ADR-0002** — retire the Cursor agent files; validate on one real build round.
3. **ADR-0004** — retire the file-based code-discovery rules; validate the same way, watching
   whether graph usage drops.
4. **Prove the cold takeover** — delete `session.json` mid-sprint on a real build round and
   confirm the agent resumes from `rounds[]` instead of restarting round 0. Still unproven.

**Closed, do not reopen:** the opt-in-to-commit mechanism. `docs/ROADMAP.md` is already the
tracked loop-closing handoff (ship writes next-sprint pointers, scope reads them), so a clone has
what it needs. The only gap is `profile.yml`, and re-running the wizard beats inheriting stale
gates. If it ever bites one repo, it is a single `!.metate/<file>` negation added there and then.

## Standing constraints

- **The implementer is the only writer.** Reviewers report; the orchestrator adjudicates.
- **No metate sprint on metate** without a trigger from real use on another repo. This wiring is
  triggered work, not a self-improvement sprint.
- **Prose has no type system.** `make verify`'s greps are the only enforcement — anchor contracts
  on structure, never on a sentence fragment.
