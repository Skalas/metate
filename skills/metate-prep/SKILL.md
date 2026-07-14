---
name: metate-prep
version: 1.1.0
description: |
  Stage 1 (Prep) of the `metate` pipeline. Reads the project's handoff docs in
  order, triages tech debt, fixes the sprint mode (REDUCE/HOLD/EXPAND), files the
  sprint issue ledger from the text plan, optionally seeds human-validation gates
  (H1…Hn) when `smoke.humanGates` is configured, and cuts the working branch from
  the base branch — before any code is written. Reads config from
  `.metate/profile.yml`. Codebase-agnostic; produces no code edits — its only side
  effects are the filed issues, the issue ledger, an optional human-gates ledger
  update, and the working branch.
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
- `smoke.humanGates` (optional) — when set, step 5 seeds its ledger from the plan's
  H-matrix.

## Steps
1. **Read the handoff** — read every doc in `prep.readingOrder`, in order. If the **file at**
   `discover.planFile` exists on disk (written by a prior `metate-discover` run), read it
   first as the entry doc; otherwise, if `readingOrder` is empty, ask the user for the entry
   doc (e.g. a sprint README / plan). Summarize the active goal, the DoD, any test matrix
   (T1…Tn), and any **human-validation matrix (H1…Hn)** you find.
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
   - **Clean the ledger.** Writing the ledger **overwrites** any prior one — never append to a
     ledger whose `sprint` differs, or last sprint's issues leak into this sprint's auto-close
     at ship. Stamp the current `sprint` topic.
   - **Reset the session file — only when starting a *new* sprint.** If the existing ledger's
     `sprint` differs from the one you're setting up, clear `sessionFile` (written by a prior
     sprint's Build run) so the next Build opens a fresh implementer session. If you're
     re-running prep **within the same sprint** (e.g. to refile an issue), leave `sessionFile`
     untouched — deleting an in-flight Build session would make the next review STOP (see
     metate-review). If no ledger file exists yet (first sprint), treat it as a new sprint and
     clear `sessionFile`.
   - If `create` is false, skip filing and note that the ledger is externally managed.
5. **Seed human gates (when configured)** — if `smoke.humanGates.ledger` is set and the plan
   carries an H-matrix (H1…Hn), materialize this sprint's items into that ledger with the
   **`Write` tool**. Smoke walks the human through them later; prep only seeds.

   **Entry shape (required fields — match smoke's schema):** for each H row write
   `{ id, title, type, status, reason, sprint, date }` — `id` from the plan (`H1`…),
   `title` an actionable description a person can follow (not a cryptic label),
   `type` one of `ux`|`live`|`graduation`|`other` (infer from the plan; default `other`),
   `status: "open"`, `reason: ""`, `sprint` = this sprint's id, `date: ""`.

   **Overwrite semantics (mirror the issue ledger):**
   - **Same-sprint re-run** — replace only this sprint's entries with the plan's H-matrix;
     leave other sprints' history untouched.
   - **New sprint** — append this sprint's open items; keep historical `approved`/`deferred`
     entries. If any **prior-sprint** item is still `open`, 🛑 stop and ask before writing:
     fold it into this sprint, mark it `deferred` with a written reason, or leave it for
     discover — never silently drop a still-open gate.
   - If the profile has no `smoke.humanGates` block, skip — H-matrix stays prose in the plan.
6. **Cut the branch** — from `prep.baseBranch`:
   ```bash
   git checkout <baseBranch> && git pull --ff-only && git checkout -b <branch>
   ```
   Name the branch from the sprint/topic. Confirm with the user before pushing anything.

## Output
A short prep brief: goal + DoD, mode (with justification), debt-fold decisions, the filed
issues (id → #number), any seeded H items, and the branch name. Hand off to Build.
