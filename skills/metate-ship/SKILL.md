---
name: metate-ship
version: 1.1.0
description: |
  Stage 6 (Ship) of the `metate` pipeline. Restructures the branch into
  bisectable commits, runs the full ship gate, opens the PR with issue
  auto-close wiring — only after the gate is green — then, on approval, merges,
  closes the milestone, and returns the repo to the base branch for the next
  cycle. Reads `.metate/profile.yml`. Codebase-agnostic. Commits/pushes/PRs/
  merges only on explicit user confirmation.
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

Last ceremony. Only runs after Review + Smoke are green. **Push/PR/merge only when the
user explicitly says so.** Ship owns the full close-out: once the human approves, it
merges, closes the milestone, and returns the repo to the base branch — the next cycle's
`metate-discover` starts from a clean, current base.

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
5. **Merge — on explicit human approval only.** Ask. If approved, merge the PR with
   `gh pr merge <N> --merge` (or `--rebase`; **never `--squash`** — it flattens the
   bisectable commits step 3 just built), then verify the ledger issues actually closed.
   If the user defers, stop after step 7 and tell them to re-run ship's close-out
   (steps 5–8) once the PR merges.
6. **Close the milestone** — if the sprint uses one, close it now (it never auto-closes):
   `gh api -X PATCH repos/{owner}/{repo}/milestones/<num> -f state=closed`. If the merge
   was deferred, remind the user instead.
7. **Retire sprint-local state** — once the PR is open and auto-close is confirmed, reset the
   sprint's working files (all gitignored, so nothing to commit), for the same staleness reason
   as step 4:
   - the ledger file at `issueLedger` → `{ "sprint": null, "issues": [] }`;
   - delete `sessionFile` and the transient `.metate/.session-start.json` if present.
   Do this even if the merge was deferred — the `<issueCloseKeyword>` lines live in the PR body,
   not the ledger. If a post-PR amendment then needs another review round, re-run Build to mint a
   fresh `sessionFile` (the prior session is intentionally retired).
8. **Return to base** — after the merge lands:
   ```bash
   git switch <ship.prTarget> && git pull --ff-only && git branch -d <sprint-branch>
   ```
   This leaves the repo clean and current, ready for the next cycle's `metate-discover`.
   `-d` (not `-D`) is deliberate: it refuses if the branch didn't merge.

## Guardrails
- Confirm before commit / push / PR / merge. Approval for one is not approval for the next.
- Never squash-merge — it destroys the bisectable history step 3 built.
- If the gate is red, STOP and report — never push past a failing ship gate.
- Never wire auto-close from a stale ledger — run the step 4 staleness guard first.
