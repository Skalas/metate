---
name: metate-ship
version: 1.0.0
description: |
  Stage 5 (Ship) of the `metate` pipeline. Restructures the branch into
  bisectable commits, runs the full ship gate, and opens the PR with issue
  auto-close wiring — only after the gate is green. Reads `.metate/profile.yml`.
  Codebase-agnostic. Commits/pushes/PRs only on explicit user confirmation.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Bash
  - Agent
---

# metate-ship — land it

Last ceremony. Only runs after Review + Smoke are green. **Push/PR only when the user
explicitly says so.**

## Step 0 — load the profile
Read `.metate/profile.yml` → `shipGate`, `ship.prTarget`, `ship.commitStyle`,
`ship.issueCloseKeyword`, and the top-level `issueLedger` (the issues prep filed).

## Steps
1. **Sync** — merge/rebase the latest `ship.prTarget` into the branch; resolve conflicts.
2. **Ship gate** — run `shipGate`. Must be **fully green** before anything is pushed. This
   mirrors CI; do not skip steps.
3. **Bisectable commits** — restructure the branch into commits per `ship.commitStyle`
   (typically one per layer, each compiling alone, dependencies first; conventional +
   scoped). Don't bury a refactor inside a feature commit.
4. **Open the PR** → `ship.prTarget`, with a commit table, verification evidence,
   out-of-scope notes, and one `<issueCloseKeyword> #N` line **per issue** in the body
   (not ranges/lists). Read the numbers from `issueLedger` — emit one line per ledger
   entry so the merge auto-closes every issue prep filed; on merge to the default branch
   GitHub closes them automatically. If the ledger is absent (prep skipped filing), fall
   back to the issues referenced on the branch/PR. Confirm auto-close wiring after creation.
5. **Milestone** — if the project uses one, remind the user to close it manually at merge
   (it does not auto-close).

## Guardrails
- Confirm before commit / push / PR. Approval for one is not approval for the next.
- If the gate is red, STOP and report — never push past a failing ship gate.
