---
name: corte-prep
version: 1.0.0
description: |
  Stage 0 (Prep) of the `corte` pipeline. Reads the project's handoff docs in
  order, triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), and cuts
  the working branch from the base branch — before any code is written. Reads
  config from `.corte/profile.yml`. Codebase-agnostic; produces no edits beyond
  the branch.
license: MIT
compatibility: claude-code
allowed-tools:
  - Read
  - Bash
  - Agent
---

# corte-prep — prepare the terrain

First ceremony. No implementation here — just orient, decide scope, branch.

## Step 0 — load the profile
Read `.corte/profile.yml`. Use the `prep:` block:
- `prep.readingOrder` — docs to read first, in order.
- `prep.techDebtFile` — the debt ledger to triage.
- `prep.baseBranch` — branch new work from here.

## Steps
1. **Read the handoff** — read every doc in `prep.readingOrder`, in order. If empty,
   ask the user for the entry doc (e.g. a sprint README / plan). Summarize the active
   goal, the DoD, and any test matrix (T1…Tn) you find.
2. **Triage debt** — open `prep.techDebtFile`; surface items whose **trigger** the
   upcoming work would hit. Recommend which to fold in vs defer. Don't fix anything.
3. **Fix the sprint mode** — declare **REDUCE** / **HOLD** / **EXPAND**, justified by
   *failure surface and value*, never by dev time. State the trade-off in one line.
4. **Cut the branch** — from `prep.baseBranch`:
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   ```
   Name the branch from the sprint/topic. Confirm with the user before pushing anything.

## Output
A short prep brief: goal + DoD, mode (with justification), debt-fold decisions, branch
name. Hand off to Build.
