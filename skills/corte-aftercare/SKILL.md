---
name: corte-aftercare
version: 1.0.0
description: |
  Stage 4 (Aftercare) of the `corte` pipeline. From the branch diff, creates or
  updates the project's required close-out deliverables (handoff notes, coverage
  docs, roadmap, tech-debt with triggers, next-sprint pointers). Reads the
  deliverable list from `.corte/profile.yml`. Codebase-agnostic; docs only.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---

# corte-aftercare — sync the documentation

Runs after Smoke is green, on the same branch, so the docs ship in the sprint PR.

## Step 0 — load the profile
Read `.corte/profile.yml` → `aftercare.deliverables` (paths, may use `{N}` for the sprint
number). If empty, ask the user for the close-out doc set.

## Steps
1. **Read the diff** — `git diff <baseBranch>...HEAD` to know what actually changed.
2. **Update each deliverable** in `aftercare.deliverables`:
   - handoff / post-sprint note → what shipped, POC limits, deferred debt;
   - coverage docs → only the items this branch touched;
   - roadmap / status → mark this sprint done, next in progress;
   - tech-debt ledger → new debt **with a trigger** (the condition that forces the fix);
   - next-sprint pointers / agent-context → advance to N+1.
3. **Stay factual** — derive everything from the diff and the prep brief; don't invent
   scope. Intentional omissions are documented `—` placeholders, not silent gaps.

## Output
List the deliverables updated and the one-line change to each. These commit on the branch
and ship in the PR (never direct to the base branch). Hand off to `corte-ship`.
