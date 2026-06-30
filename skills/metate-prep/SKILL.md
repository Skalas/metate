---
name: metate-prep
version: 1.0.0
description: |
  Stage 1 (Prep) of the `metate` pipeline. Reads the project's handoff docs in
  order, triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), files the
  sprint issue ledger from the text plan, and cuts the working branch from the
  base branch — before any code is written. Reads config from
  `.metate/profile.yml`. Codebase-agnostic; produces no code edits — its only side
  effects are the filed issues, the issue ledger, and the working branch.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Bash
---

# metate-prep — prepare the terrain

Runs after `metate-discover` (or as the entry point when the plan already exists). No
implementation here — just orient, decide scope, branch.

## Step 0 — load the profile
Read `.metate/profile.yml`. Use the `prep:` block:
- `prep.readingOrder` — docs to read first, in order.
- `prep.techDebtFile` — the debt ledger to triage.
- `prep.baseBranch` — branch new work from here.
- `prep.issues` — whether/how to file the sprint issues (`create`, `tracker`,
  `granularity`, `labels`, `milestone`).
- `issueLedger` (top-level) — where to record the filed issue numbers for ship.

## Steps
1. **Read the handoff** — read every doc in `prep.readingOrder`, in order. If the **file at**
   `discover.planFile` exists on disk (written by a prior `metate-discover` run), read it
   first as the entry doc; otherwise, if `readingOrder` is empty, ask the user for the entry
   doc (e.g. a sprint README / plan). Summarize the active goal, the DoD, and any test matrix
   (T1…Tn) you find.
2. **Triage debt** — open `prep.techDebtFile`; surface items whose **trigger** the
   upcoming work would hit. Recommend which to fold in vs defer. Don't fix anything.
3. **Fix the sprint mode** — declare **REDUCE** / **HOLD** / **EXPAND**, justified by
   *failure surface and value*, never by dev time. State the trade-off in one line.
4. **File the ledger** — when `prep.issues.create` is true, turn the **text plan into
   issues**: one issue per test-matrix item (T1…Tn) under `granularity: test-matrix`,
   plus any debt items folded in at step 2. The plan is prose; **the issues are the
   ledger** the rest of the sprint tracks against and ship later auto-closes.
   - **Confirm the list with the user before filing** — issue creation is outward-facing.
     Show the proposed title (lead with the `Tn` id) and body (DoD + acceptance) for each.
   - File via the tracker (`prep.issues.tracker: github` → `gh issue create`), applying
     `labels` and `milestone`. Record each result to `issueLedger`, e.g.:
     ```json
     { "sprint": "<topic>",
       "issues": [ { "id": "T1", "number": 42, "title": "…", "url": "…" } ] }
     ```
   - If `create` is false, skip filing and note that the ledger is externally managed.
5. **Cut the branch** — from `prep.baseBranch`:
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   ```
   Name the branch from the sprint/topic. Confirm with the user before pushing anything.

## Output
A short prep brief: goal + DoD, mode (with justification), debt-fold decisions, the filed
issues (id → #number), and the branch name. Hand off to Build.
