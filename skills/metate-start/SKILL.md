---
name: metate-start
version: 1.3.0
description: |
  Stage 1 (Start) of the `metate` pipeline. Reads the project's handoff docs in
  order, triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), files the
  issue ledger from the text plan (`T1…Tn` for `kind: sprint`, or a single `C1`
  tracking issue for non-`sprint` kinds with a completion condition), optionally
  seeds human-validation gates (H1…Hn) when `verify.humanGates` is configured, and
  cuts the working branch from the base branch — before any code is written. Reads
  config from `.metate/profile.yml`. Codebase-agnostic; produces no code edits — its
  only side effects are the filed issues, the issue ledger, an optional human-gates
  ledger update, and the working branch.
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
Read `.metate/profile.yml`. Use the `start:` block:
- `start.readingOrder` — docs to read first, in order. A path may carry `{N}` for the sprint
  number; resolve it as metate-ship Step 0 defines, so a numbered handoff path is
  configured once rather than hand-bumped each sprint.
- `start.techDebtFile` — the debt ledger to triage.
- `start.baseBranch` — branch new work from here.
- `start.issues` — whether/how to file the sprint issues (`create`, `tracker`,
  `granularity`, `labels`, `milestone`).
- `verify.humanGates` (optional) — when set, step 5 seeds `.metate/human-gates.json` from the
  plan's H-matrix.
- Filed issue numbers go to `.metate/issues.json` for ship.

## Steps
1. **Read the handoff** — read every doc in `start.readingOrder`, in order. If the **file at**
   `.metate/plan.md` exists on disk (written by a prior `metate-scope` run), read it
   first as the entry doc; otherwise, if `readingOrder` is empty, ask the user for the entry
   doc (e.g. a sprint README / plan). Summarize the active goal, the plan's **`kind`**
   (`sprint` default), the DoD (or **completion condition** when `kind` is not `sprint`), any
   test matrix (T1…Tn — expect none for non-`sprint`), and any **human-validation matrix
   (H1…Hn)** you find.
2. **Triage debt** — open `start.techDebtFile`; surface items whose **trigger** the
   upcoming work would hit. Recommend which to fold in vs defer. Don't fix anything.
3. **Fix the sprint mode** — declare **REDUCE** / **HOLD** / **EXPAND**, justified by
   *failure surface and value*, never by dev time. State the trade-off in one line.
4. **File the ledger** — when `start.issues.create` is true, turn the text plan into issues:
   - **`kind: sprint`** — one issue per test-matrix item (T1…Tn) under `granularity: test-matrix`,
     plus any debt items folded in at step 2.
   - **non-`sprint`** — skip test-matrix filing; file **one** tracking issue summarizing the
     completion condition (ledger id **`C1`**), plus any folded debt. For **`kind: decision`**
     the completion condition is an **ADR** (metate-scope → Candidate kinds): name the target
     path in the `C1` body, and add the ADR directory to `ship.deliverables` if it is not
     already there, so close-out writes it.
   When `create: false`, file no issues and leave `.metate/issues.json` untouched at start time (note:
   ship still clears it at close-out). **When `create` is true**, overwrite `.metate/issues.json` with
   this sprint's topic for both kinds — never leave a stale ledger from a prior sprint.
   - **Confirm the list with the user before filing** — issue creation is outward-facing.
     Show the proposed title (lead with the `Tn` id for sprint rows, or **`C1`** for the
     non-sprint tracking issue) and body (DoD + acceptance) for each.
   - File via the tracker (`start.issues.tracker: github` → `gh issue create`), applying
     `labels` and `milestone`. Record each result to `.metate/issues.json`, e.g. sprint:
     `{ "sprint": "<topic>", "issues": [ { "id": "T1", … }, { "id": "T2", … } ] }`; non-`sprint`:
     `{ "sprint": "<topic>", "issues": [ { "id": "C1", … } ] }`.
   - **`deferred[]`** — an optional sibling of `issues[]` holding rows **filed but cut from
     scope** mid-sprint, retained so ship and scope can re-plan them:
     `{ id, number, title, reason }`. Start seeds it empty or omits it; whoever cuts a row moves
     it there. Its issues stay **open** in the tracker — ship never auto-closes them
     (metate-ship step 4).
   - **Clean the ledger.** Writing the ledger **overwrites** any prior one — never append to a
     ledger whose `sprint` differs, or last sprint's issues leak into this sprint's auto-close
     at ship. Stamp the current `sprint` topic.
5. **Reset session file** — only when starting a *new* sprint: if the plan's sprint topic differs
   from `.metate/session.json` → `sprint` (or, on a legacy file that predates that key, the prior ledger's
   `sprint`), clear `.metate/session.json` so the next Build opens a fresh implementer session. Re-running start **within the same sprint**
   (e.g. to refile an issue) — leave `.metate/session.json` untouched; deleting an in-flight Build session
   would make the next Build open a fresh session (see metate-build round 0). No prior ledger → treat as a new sprint.
6. **Cut the branch** — from `start.baseBranch` **before** writing any tracked sprint
   files (human-gates ledger is tracked and must land on the working branch, not the base):
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   ```
   Name the branch from the sprint/topic. Confirm with the user before pushing anything.
7. **Seed human gates (when configured)** — if `.metate/human-gates.json` is set, always
   materialize **this sprint's batch** into that ledger with the **`Write` tool** — even when
   the plan has **no H-matrix** (write an explicit zero-gate batch for this `sprint` so
   required verify does not fail closed on a missing sprint scope). Verify walks open items
   later; start only seeds.

   **Entry shape (required fields — match verify's schema):** for each H row write
   `{ id, title, type, status, reason, sprint, date }` — `id` from the plan (`H1`…),
   `title` an actionable description a person can follow (not a cryptic label),
   `type` one of `ux`|`live`|`graduation`|`other` (infer from the plan; default `other`),
   `status: "open"`, `reason: ""`, `sprint` = this sprint's id, `date: ""`.
   Zero-gate batch: keep prior history; ensure this sprint has **no** residual rows (delete
   any same-sprint leftovers from a re-run) and do not invent placeholder H ids.

   **Overwrite semantics (mirror the issue ledger):**
   - **Same-sprint re-run** — replace only this sprint's entries with the plan's H-matrix
     (or empty); leave other sprints' history untouched.
   - **New sprint** — append this sprint's items (or record the empty batch); keep historical
     `approved`/`deferred` entries. If any **prior-sprint** item is still `open`, 🛑 stop and
     ask before writing — only two dispositions are allowed: **fold** it into this sprint
     (rewrite `sprint`), or mark it **`deferred`** with a written reason (scope resurfaces
     deferred). Never leave it `open` (verify/ship would block forever) and never silently drop it.
   - The human-gates ledger is **tracked project state** (commit with the sprint) — not
     gitignored like `issues.json`.
   - If the profile has no `verify.humanGates` block, skip — H-matrix stays prose in the plan.

## Output
A short start brief: goal + DoD, mode (with justification), debt-fold decisions, the filed
issues (id → #number), any seeded H items (or explicit zero-gate), and the branch name.
Hand off to Build.
