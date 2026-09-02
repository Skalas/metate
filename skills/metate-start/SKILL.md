---
name: metate-start
version: 2.0.0
description: |
  Stage 1 (Start) of the `metate` pipeline. Reads the project's handoff docs,
  triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), writes
  `.metate/dod.json` from the plan's T-rows (exactly one of `command` or `gate`
  per row), files tracker issues, seeds human-validation gates, and cuts the
  working branch — before any code is written. Reads `.metate/profile.yml`.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
allowed-tools:
  - Read
  - Bash
  - Write
---

# metate-start — prepare the terrain

Runs after `metate-scope` (or as the entry point when the plan already exists). No
implementation here — just orient, decide scope, branch.

## Step 0 — load the profile
Read `.metate/profile.yml`. Use the `start:` block: `readingOrder` (paths may carry `{N}` —
resolve as metate-ship Step 0), `techDebtFile`, `baseBranch`, `issues` (`create`, `tracker`,
`granularity`, `labels`, `milestone`), optional `verify.humanGates`. DoD goes to
`.metate/dod.json` (tracked). Gates go to `.metate/human-gates.json` (tracked).

## Steps
1. **Read the handoff** — every doc in `start.readingOrder`, in order. If `.metate/plan.md`
   exists, read it first; if `readingOrder` is empty, ask. Summarize the goal, **`kind`**
   (`sprint` default), DoD / completion condition, T-matrix, and any H-matrix.
2. **Triage debt** — open `start.techDebtFile`; surface items whose **trigger** the upcoming
   work would hit. Recommend fold vs defer. Don't fix anything.
3. **Fix the sprint mode** — REDUCE / HOLD / EXPAND, justified by *failure surface and value*,
   never by dev time. One-line trade-off.
4. **Confirm and file** — when `start.issues.create` is true, show the proposed titles/bodies
   and file via the tracker (`github` → `gh issue create`). **`kind: sprint`:** one issue per
   T-row (plus folded debt). **non-`sprint`:** one tracking issue **`C1`** (for `decision`, name
   the ADR path; add the ADR dir to `ship.deliverables` if missing). When `create: false`, file
   nothing. Confirm before filing — it is outward-facing.
5. **Reset session file** — new sprint only: if the plan's topic differs from
   `.metate/session.json` → `sprint` (or the prior DoD's `sprint` on a legacy file), clear
   `.metate/session.json`. Same-sprint re-run: leave it. No prior DoD → new sprint.
6. **Cut the branch** — from `start.baseBranch` **before** writing tracked sprint files:
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   ```
7. **Write DoD and seed gates** — after the branch exists, with the **`Write` tool**:

   **`.metate/dod.json`** from the T-rows (or `C1`). Every live row has **exactly one** of
   `command` or `gate`. A proposed gate phrased *walk A → B → C, expect D* is a `command`
   row, not a gate. A gate that recurs sprint after sprint is a `command` row. `cut` rows
   need `reason` and neither field. `id` may span (`T1-T3`). Fill `tracker` (`#N`) from
   step 4. Run `bash <metate-skill>/lib/dod.sh dod .metate/dod.json` (🛑 **dod.json
   validates** — blocking set). Overwrite; never append a prior sprint.

   **Gates** (when `verify.humanGates` is set) — always write this sprint's batch, even if
   the plan has no H-matrix (explicit zero-gate). Layout is `{ "gates": [ … ] }` only.
   Current-sprint entries: `{ id, title, type, status, reason, sprint, date, steps, expected }`
   with `type` ∈ `judgment`|`device`|`external`|`acceptance`, `steps` a non-empty array,
   `expected` non-empty, `status: "open"`. A 🛑 **gate admission** (blocking set) if the
   validator refuses. Prior-sprint history stays; if any prior item is still `open`, 🛑
   **open prior-sprint gate** — fold or `deferred`+reason. Run
   `bash <metate-skill>/lib/dod.sh gates .metate/human-gates.json <sprint>`.
   No `verify.humanGates` block → skip; H-matrix stays plan prose.

## Output
Goal + DoD, mode, debt-fold decisions, dod.json rows (id → tracker, command|gate|cut),
seeded H items (or explicit zero-gate), branch name. Hand off to Build.
