---
name: metate-ship
version: 1.0.0
description: |
  Stage 6 (Ship) of the `metate` pipeline. Restructures the branch into
  bisectable commits, runs the full ship gate, and opens the PR with issue
  auto-close wiring — only after the gate is green. Reads `.metate/profile.yml`.
  Codebase-agnostic. Commits/pushes/PRs only on explicit user confirmation.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
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
`ship.issueCloseKeyword`, the top-level `issueLedger` (the issues prep filed), and
`sessionFile` (retired in step 6).

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
   back to the issues referenced on the branch/PR.
   - **Staleness guard — run before emitting any `<issueCloseKeyword>` line.** The ledger
     (the file at `issueLedger`, e.g. `.metate/issues.json`) is per-sprint local state; one
     left from a *previous* sprint would auto-close unrelated issues. **Both** must hold for
     every entry: (1) the issue is still **OPEN** (`gh issue view <N> --json state,title`);
     (2) the ledger's `sprint` matches the work on the branch/diff. If either fails for any
     entry, treat the ledger as **stale** — STOP and ask the user, never wire auto-close from
     it. (This is what catches a skipped prep: a ledger that doesn't match the branch is never
     trusted into a blind close.)
   - Confirm auto-close wiring after creation.
5. **Milestone** — if the project uses one, remind the user to close it manually at merge
   (it does not auto-close).
6. **Retire sprint-local state** — once the PR is open and auto-close is confirmed, reset the
   sprint's working files (all gitignored, so nothing to commit), for the same staleness reason
   as step 4:
   - the ledger file at `issueLedger` → `{ "sprint": null, "issues": [] }`;
   - delete `sessionFile` and the transient `.metate/.session-start.json` if present.
   Do this even before the PR merges — the `<issueCloseKeyword>` lines live in the PR body, not
   the ledger. If a post-PR amendment then needs another review round, re-run Build to mint a
   fresh `sessionFile` (the prior session is intentionally retired).

## Guardrails
- Confirm before commit / push / PR. Approval for one is not approval for the next.
- If the gate is red, STOP and report — never push past a failing ship gate.
- Never wire auto-close from a stale ledger — run the step 4 staleness guard first.
