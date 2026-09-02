# ADR-0001 — Subtraction: fewer stages, fewer keys, checkable evidence

- **Status:** Proposed (2026-09-01)
- **Kind:** `decision`
- **Deciders:** repo author. Drafted from a design conversation on 2026-09-01; an earlier draft of
  this ADR proposed a "slip system" and was withdrawn by the author as over-stated — see
  *Alternatives*.

## Context

metate is 68 days old: 118 commits, 13 sprints, 15 deployments, ~3,600 lines. Its core is sound
and field-proven — the resumable implementer session (117 turns / 31 h / 5 resumptions, zero
failures), backend switching as a first-class axis, and the human-gates ledger (77% dispositioned
over 22 consecutive sprints). Its practice is an extraction of something that already worked,
which is why the profile ports so cleanly across 15 repos.

The apparatus around that core has accreted. Measured on 2026-09-01:

| | count | note |
|---|---|---|
| stages | 7 | each with its own playbook, `Step 0`, `Output`, `Guardrails` |
| playbook prose | 1,403 lines | 39% of the repo; grew 16% in the pass that diagnosed prose growth |
| profile keys | 52 | 7 are paths nobody has ever changed |
| state ledgers | 6 | three container layouts, three id conventions, validation for two |
| `session.json` in the field | 7 / 15 | build's only product, absent in half the fleet |
| `release.json` in the field | 2 / 15 | exists only to pass state from aftercare to ship |
| 🛑 STOP rules bypassed silently | 21× and 12× | in two repos, over two sprints each |

The author's objective is **to simplify**: the repo is heavy on config and complexity, and a green
gate does not mean the sprint's Definition of Done was met. Two enforcement stories coexist — human
gates block and work; everything else is prose, and prose is bypassed at scale. The design has not
chosen between them.

## Decision

Four moves, in order of certainty. Each is a separate PR; each must leave `make verify` green and
the playbook total **lower** than it found it.

### 1 · Delete the seven path keys

Six have zero customisation across all 15 field profiles; the seventh (`smoke.matrix`) shipped
this week and has none. They become fixed conventions under `.metate/`:

| key | customised | becomes |
|---|---|---|
| `sessionFile` | 0 / 15 | `.metate/session.json` |
| `issueLedger` | 0 / 15 | folded into `.metate/dod.json` (move 3) |
| `signalsFile` | 0 / 7 | `.metate/signals.json` |
| `discover.planFile` | 0 / 14 | `.metate/plan.md` |
| `aftercare.release.planFile` | 0 / 3 | gone with the merge (move 2) |
| `smoke.humanGates.ledger` | 0 / 3 | `.metate/human-gates.json` |
| `smoke.matrix` | 0 / 0 | folded into `.metate/dod.json` (move 3) |

`prep.techDebtFile` is **kept** — five distinct values in the field; it names a project document,
not metate state. `metate-init --update` removes a key when its value equals the default and 🛑
STOPs otherwise; given the table it stops nowhere.

### 2 · Collapse seven stages to five

A stage earns its existence by having a **distinct product** and a **distinct human moment**.
Two pairs fail that test:

| merge | evidence | result |
|---|---|---|
| `build` → into `review` as **round 0** | build's sole product is `session.json`, created here and consumed only by review. Review already resumes that session every round. In the field the file exists in 7/15 repos — the stage is skipped or hand-rolled half the time. | review owns the session's whole life: round 0 builds in layers and runs the fast gate; rounds 1–3 review. `session.json` becomes review-internal (still on disk — it must survive across sessions). |
| `aftercare` → into `ship` | `release.json` exists only to hand a release proposal from aftercare to ship, and is present in 2/15 repos. aftercare's `postCommand` is a ship-time concern. Both stages run after smoke is green and before the PR. | ship = update deliverables → propose release → gate → bisectable commits → PR → merge → tag → cleanup. `release.json` is deleted: the proposal is a step, not a handoff. |

`discover`, `prep`, `smoke` stay distinct: a plan, a branch-with-issues-and-no-code, and evidence
are three different products with three different confirmation moments.

Result: **discover → prep → review → smoke → ship.** Two playbooks deleted, along with their
frontmatter, `Step 0`, `Output`, and `Guardrails` boilerplate; `metate-init --update` removes the
two installed skill directories from each repo. The `metate` router's table shrinks by two rows.

### 3 · Make evidence re-runnable — one DoD file replaces two ledgers

`issues.json` (tracker numbers for auto-close) and `smoke-matrix.json` (T-row → command, invented
by Orbis because the engine gave it nowhere to live) are two views of the same thing: the sprint's
Definition of Done. They become one file:

```json
// .metate/dod.json
{ "sprint": "review-aperture",
  "rows": [
    { "id": "T2", "title": "One unanchored lens per round",
      "tracker": "#99", "command": "make verify" },
    { "id": "T4", "title": "Give round 1 the sprint's intent",
      "tracker": "#101", "status": "cut",
      "reason": "needs a durable carrier; re-planned" },
    { "id": "T7", "title": "Wallet flow renders on iOS",
      "tracker": "#104", "gate": "H1" }
  ] }
```

- **prep** writes it from the plan's T-rows, then fills `tracker` as issues are filed.
- **Every row has exactly one of `command` or `gate`.** A `command` is evidence a script can
  produce; a `gate` points at a human-gates entry. A row with neither cannot be written — the
  validator refuses it. This is the whole of the "does the gate mean anything" fix.
- **smoke** runs every `command` row and reports; **ship re-runs them** at gate time. Nothing is
  *recorded* as verified — a verified row is one whose command exits 0 **on the commit being
  shipped**. Re-running is cheaper than trusting a stored claim, and cannot be faked by a wrong LLM.
- **ship** refuses the PR while any row is neither passing nor `cut`-with-reason, and emits
  `Closes #N` from passing rows only. `cut` rows are named in the PR as out of scope. This replaces
  the `deferred[]` construct and the two-condition staleness guard added in #107.

Rows may span (`T1-T3`) when one command proves several, as Orbis already does.

### 4 · One enforcement rule

> **A stage may refuse to advance only on a check a script can run. Prose advises; files block.**

The blocking set, in full: the profile parses and carries no template placeholder; `dod.json`
validates and every row passes or is cut; every current-sprint human gate is dispositioned;
`session.json` exists for review rounds ≥ 1; `shipGate` is green. Everything else in a playbook is
advice, and advice is what gets cut when the line budget bites. Every 🛑 in a `SKILL.md` must name
which item of the blocking set it is; a 🛑 that names none is rewritten as advice or deleted.

## What this deletes

- 2 playbooks, 2 installed skill directories, 2 router rows
- 7 profile keys and their comments; `aftercare:` block reduced to `deliverables` + `release`
  under `ship:`
- 2 ledgers (`issues.json`, `release.json`) and one never-adopted one (`smoke-matrix.json`)
- prep's ledger-shape prose and `deferred[]` paragraph; ship's staleness guard and its inversion;
  the aftercare→ship release handoff prose on both sides; build's entire session-capture text
  (moves into review's round 0, shorter, because review already documents the resume)
- every 🛑 STOP that cannot name a scriptable check

**Acceptance for the whole sequence:** playbook total **≤ 1,100 lines** (from 1,403), caps in
`tests/contracts/prose-budget.txt` lowered in the same diffs; template **≤ 42 keys** (from 52);
5 stage directories under `skills/`.

## What this adds

- `dod.json` and a validator for it (jq + bash, shipped in `lib/`, run by prep on write, smoke and
  ship on read)
- the enforcement rule, stated once in `skills/metate/SKILL.md`
- a migration in `metate-init --update`: `issues.json` → `dod.json` rows (`deferred[]` → `cut`),
  `smoke-matrix.json` rows merged by id, both source files removed after a round-trip check

## Consequences

**Good.** A green ship gate means every DoD row's command passed on the shipped commit — the first
time the gate has meant that. Two fewer stages to invoke, explain, and keep in sync. Ten fewer
keys. The enforcement story is decided, and it is the one that scored 77%.

**Bad, accepted.** Every T-row must now be bound to a command or a gate at prep time; that is work
prep did not previously force, and it will surface rows that were never really testable. Ship
re-runs the DoD commands, so ship takes longer. Merging stages loses the option of running build
without review, or aftercare without ship — nobody in the field is recorded doing either.

## Alternatives considered

| rejected | why |
|---|---|
| **Slips** — a typed file-per-record store all ledgers migrate into, with a schema, validator, provenance arrays, and per-stage refusal rules | Proposed by the author, drafted in detail, then withdrawn as over-stated by the drafter. It generalises what human-gates already does at the cost of a new subsystem, a directory of hundreds of files per heavy sprint, and a migration across 15 repos — while the enforcement it promised is delivered by move 4 with one file and one rule. Its genuine insight survives: *checkable files block, prose advises*. |
| **Collapse to 3 stages** (plan · build · ship) | Loses the smoke confirmation moment, which is where human gates — the one mechanism that measurably works — live. Five keeps every distinct product. |
| **Keep 7, delete only keys** | Certain, and insufficient: the ledger sprawl and the two thin stages are the complexity the author named. |
| **Record `verified` state instead of re-running** | A stored claim is prose in JSON; an LLM can write it without doing it. A re-run cannot be faked. |
| **Make `dod.json` optional** | Then it is the 16%-dispositioned signals lane again. Rows without evidence are the problem, not a use case. |

## Open questions — carried, not decided

- **Review yield.** 3 lenses × ≤3 rounds is the most expensive stage and its return is unmeasured.
  The elegance lens is suggestion-only and runs unanchored every round; nobody knows what it
  catches per dollar. After move 2, record per-round findings-by-lens for five sprints, then decide.
- **Orbis cadence** — 680 → 158 → 36 commits/month after adoption. Maturity, portfolio split, or
  ceremony drag. Two commands to reproduce; an afternoon to judge. Do it before adding *anything*.
- **Eight `in-diff` + `open` signals** in cie11-validator and gov-skills are unfixed regressions in
  real products. Nothing in this ADR touches them; someone should.

## Sequencing

1. **Keys** — one PR, ~zero risk, this week.
2. **Collapse** — one PR per merge (`build`→`review` first; it's the smaller one). Each must land
   net-negative on the budget.
3. **DoD file + enforcement rule** — one PR, after the collapse so it is written into five stages,
   not seven.
4. **Measure** — one real sprint on the result before touching anything else. Then the review-yield
   question.
