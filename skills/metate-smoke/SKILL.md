---
name: metate-smoke
version: 1.0.0
description: |
  Stage 3 (Smoke) of the `metate` pipeline. Runs the project's e2e/smoke suite
  bound to the DoD test matrix (T1…Tn) on seeded data, checks seed idempotency,
  and leaves only aesthetic/UX approval to the human. Reads `.metate/profile.yml`.
  Codebase-agnostic.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Bash
  - Agent
---

# metate-smoke — prove behavior on real data

Tests do the cent-level checking; the human only approves look-and-feel.

## Step 0 — load the profile
Read `.metate/profile.yml` → `smoke.command`, `smoke.seedCommand`. If `smoke.command` is
empty, ask the user how the e2e/smoke suite runs.

## Steps
1. **Seed idempotency** — run `smoke.seedCommand` twice; the second run must not error or
   duplicate data. Report any drift.
2. **Run the suite** — `smoke.command`. Map results back to the **DoD matrix (T1…Tn)** from
   Prep: each row either has a passing assertion or a documented gap. Flag rows that the
   fresh-tenant specs skip but a seeded-tenant smoke should cover (role/KPI/money claims).
3. **Cent-level money** — confirm on-screen/asserted amounts reconcile to the cent for any
   payment/settlement flows in scope.
4. **Hand the human the UX check** — summarize what passed; ask the user only for the
   aesthetic / flow approval the suite can't make.

## Exit
- All T1…Tn covered (pass or documented gap) + seed idempotent → ✅ advance to Aftercare.
- Failing assertions → 🛑 back to review/build with the failures as blockers.
