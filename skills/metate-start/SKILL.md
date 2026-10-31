---
name: metate-start
version: 2.0.0
description: |
  Stage 1 (Start) of the `metate` pipeline. Reads the project's handoff docs,
  triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), writes
  `$SPRINT/dod.json` from the plan's T-rows (exactly one of `command` or `gate`
  per row), files tracker issues, seeds human-validation gates, and cuts the
  working branch — before any code is written. Reads `$STATE/profile.yml`.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
  - grok
allowed-tools:
  - Read
  - Bash
  - Write
---

# metate-start — prepare the terrain

Runs after `metate-scope`, or as the entry point when a plan already exists. No code here.

## Step 0 — load the profile
Run `eval "$(bash <metate-skill>/lib/state.sh env)"` for `$STATE`/`$SPRINT`, then read
`$STATE/profile.yml` → the `start:` block: `readingOrder` (paths may carry `{N}` — resolve as
metate-ship Step 0), `techDebtFile`, `baseBranch`, `issues` (`create`, `tracker`, `granularity`,
`labels`, `milestone`), `ship.chainSprints`, optional `verify.humanGates`.

## Steps
1. **Read the handoff** — every doc in `start.readingOrder`, in order. If a plan exists
   (`$STATE/plan.md`, or `$SPRINT/plan.md` on a re-run), read it first; if `readingOrder` is empty, ask. Summarize the goal, **`kind`**
   (`sprint` default), DoD / completion condition, T-matrix, and any H-matrix.
   When a sprint replaces, splits, or migrates a domain concept, metric, route, or data
   calculation, spawn an **Unbiased Pre-Flight Subagent Council** (parallel read-only discovery
   subagents **without anchoring them to a pre-selected file list**):
   - **Blind Blast-Radius Hunter:** given only the domain concept/symbols, queries the graph +
     `<template>`/spec grep to enumerate 100% of consumers (`requiredTouches`) and deprecated symbols (`retires`).
   - **Tenant Data Reality Probe:** inspects real tenant data shapes/snapshots (catch-all categories,
     nulls, edge distributions) before drafting the task spec.
   - **Adversarial Spec Critic:** verifies no legacy dual-path is kept merely to avoid updating existing tests.
   Fold findings autonomously into the spec and `$SPRINT/dod.json` (`retires`, `requiredTouches`);
   pause for human input only at milestone start or when a business rule is genuinely ambiguous.
2. **Triage debt** — open `start.techDebtFile`; surface items whose **trigger** the upcoming
   work would hit. Recommend fold vs defer. Don't fix anything.
3. **Fix the sprint mode** — REDUCE / HOLD / EXPAND, justified by *failure surface and value*,
   never by dev time. One-line trade-off.
4. **Confirm and file** — when `start.issues.create` is true, show the proposed titles/bodies
   and file via the tracker (`github` → `gh issue create`). **`kind: sprint`:** one issue per
   T-row (plus folded debt). **non-`sprint`:** one tracking issue **`C1`** (for `decision`, name
   the ADR path; add the ADR dir to `ship.deliverables` if missing). Pass `--milestone` when
   `start.issues.milestone` is set. When `create: false`, file nothing. Confirm before filing —
   it is outward-facing — unless `ship.chainSprints: true` (pre-authorized; file without pausing).
5. **Reset session file** — a new branch gets a fresh `$SPRINT`, so nothing carries over. Only
   when a new sprint reuses the current branch: clear `$SPRINT/session.json`.
6. **Cut the branch** — from `start.baseBranch`, then re-resolve state and claim the plan.
   `$SPRINT` is branch-derived: nothing sprint-scoped may be written before this. `claim-plan`
   exits non-zero when no plan is pending — fine when the plan came via `readingOrder`, not scope.
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   # <baseBranch> held by another worktree: git fetch origin <baseBranch> && git checkout --no-track -b <branch> "origin/<baseBranch>"
   eval "$(bash <metate-skill>/lib/state.sh env)"; bash <metate-skill>/lib/state.sh claim-plan || true
   ```
7. **Write DoD and seed gates** — after the branch exists, with the **`Write` tool**:

   **`$SPRINT/dod.json`** from the T-rows (or `C1`). Every live row has **exactly one** of
   `command` or `gate`. A proposed gate phrased *walk A → B → C, expect D* is a `command`
   row, not a gate. A gate that recurs sprint after sprint is a `command` row. `cut` rows
   need `reason` and neither field. `id` may span (`T1-T3`). Fill `tracker` (`#N`) from
   step 4. Optional top-level `"retires"` (deprecated symbols `dod.sh receipt` verifies are 100%
   purged from the code tree) and `"requiredTouches"` (consumer file paths `dod.sh receipt`
   verifies were modified in the sprint diff) lock blast-radius scope. Run
   `bash <metate-skill>/lib/dod.sh dod "$SPRINT/dod.json"` (🛑 **dod.json
   validates** — blocking set). Overwrite; never append a prior sprint.

   **Gates** (when `verify.humanGates` is set) — always write this sprint's batch, even if
   the plan has no H-matrix (explicit zero-gate). Layout is `{ "gates": [ … ] }` only.
   Current-sprint entries: `{ id, title, type, status, reason, sprint, date, steps, expected }`
   with `type` ∈ `judgment`|`device`|`external`|`acceptance`, `steps` a non-empty array,
   `expected` non-empty, `status: "open"`. A 🛑 **gate admission** (blocking set) if the
   validator refuses. Prior-sprint history stays; if any prior item is still `open`, 🛑
   **open prior-sprint gate** — fold or `deferred`+reason. Run
   `bash <metate-skill>/lib/dod.sh gates "$STATE/human-gates.json" <sprint>`.
   No `verify.humanGates` block → skip; H-matrix stays plan prose.

## Output
Goal + DoD, mode, debt-fold decisions, dod.json rows (id → tracker, command|gate|cut),
seeded H items (or explicit zero-gate), branch name. Hand off to Build.
