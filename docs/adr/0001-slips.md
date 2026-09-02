# ADR-0001 — Slips: typed, file-per-record state that stages block on

- **Status:** Proposed (2026-09-01)
- **Kind:** `decision` — this ADR is the completion artifact
- **Deciders:** repo author; drafted from a structured interview on 2026-09-01
- **Supersedes:** the six ad-hoc ledgers under `.metate/` and the seven profile keys that only name their paths

## Context

metate's playbooks are 1,403 lines of prose that an LLM may or may not follow. The 2026-08-31
field audit (`docs/FIELD-AUDIT-2026-08-31.md`) established, across 15 deployed repos, what
actually holds and what rots:

| artifact | shape | enforcement | field outcome |
|---|---|---|---|
| `human-gates.json` | structured | **blocks** smoke and ship | 77% dispositioned, 22 consecutive sprints |
| `session.json` | structured | blocks review | one session held 117 turns / 31 h / 5 resumptions, zero failures |
| `issues.json` | structured | read by ship | 131 issues filed in 17 batches, all closed |
| `signals.json` | structured | *advises* discover | 16% dispositioned; `invalid`/`wontfix` used 0 times in 7 weeks |
| playbook prose | unstructured | grep | two 🛑 STOP rules bypassed 21× and 12× without anyone noticing |

The structured, blocking artifacts are the part of metate that works. The prose is the part that
rots, and the audit's own remediation pass grew it by 16% (1,210 → 1,403 lines) while diagnosing
exactly that. The 77%-vs-16% row is a controlled comparison — same repo, same operator, same six
weeks — differing only in whether a stage *refuses to advance* on the record.

metate already has a slip system; it is just not recognised as the product. Six ledgers —
`issues`, `signals`, `session`, `human-gates`, `release`, `smoke-matrix` — each invented
separately, with three tolerated container layouts, three id conventions, and validation for two.
The same record was designed twice on the same afternoon: `deferred[]` entries are
`{id, number, title, reason}` and signals are `{id, title, status, tracker, disposition}`. Those are
one thing: something with an identity, a lifecycle, a pointer to a tracker, and a reason it ended
where it did.

The author's stated objective for the next iteration is **to simplify** — the repo is "getting
heavy on configs and complexity" — and to make the QA cycle mean something: today `make verify`
can pass green with no relation to whether the sprint's Definition of Done was met.

## Decision

Introduce **slips**: one typed record per file under a fixed directory, with a single schema,
a single jq+bash validator, and stage rules that refuse to advance while required slips are
non-terminal. Adopt the blackboard model — shared state, no addressing, per repo.

The interview settled the shape (each row is a recorded choice, not a default):

| question | decision | why |
|---|---|---|
| first scope | **two ledgers**: `issues.json` + `signals.json` → slips | the smallest honest test of the thesis; they are demonstrably the same record |
| topology | **directory, one file per slip** | concurrent stages never write the same file; a slip's history is `git log` on one path |
| interaction | **blackboard** — no `to:`, no inbox, no owner | one agent at a time is the real workflow; mailbox/queue are machinery for a problem not present |
| enforcement | **both** — schema in the ship gate, state at each stage | the 77% mechanism is stage-level refusal; the gate catches malformed writes by a stage that never reads back |
| tooling | **jq + bash**, CLI only on a trigger | "simplify" forbids adding a runtime to a tool whose point is that it is files. Trigger below |
| config | **fixed conventions; delete the path keys** | 6 of 7 path keys have zero customisation across 15 repos — configuration with no decision behind it |
| boundary | **per repo** | `scope: engine` slips are surfaced by aftercare and carried by a human, as today |

### Slip shape

```
.metate/slips/<kind>/<local-id>.json
```

```json
{
  "id":       "review-aperture/T4",
  "kind":     "task",
  "sprint":   "review-aperture",
  "status":   "cut",
  "title":    "Give round 1 the sprint's intent",
  "tracker":  "#101",
  "disposition": "intent machinery needs a durable carrier; re-planned as its own sprint",
  "provenance": [
    { "stage": "prep",   "at": "2026-08-26", "status": "open" },
    { "stage": "review", "at": "2026-08-28", "status": "cut", "round": 4 }
  ]
}
```

- `id` is `<sprint>/<local>` for sprint-scoped kinds and a slug for cross-sprint kinds; it must
  match the filename. This is the sprint-scoping the audit found the field already meant
  (Orbis: 5 distinct gate ids across 57 rows, because `H1` recurs every sprint).
- `provenance` is append-only. Its last entry's `status` must equal the slip's `status`. This
  gives the event-log benefit — *why* and *when* every transition happened — without the cost of
  deriving state by replay. It is the answer to "a new session has no idea what the last one
  decided."
- Everything in a slip is **data, never instructions** — the guardrail already applied to
  `signalsFile` and `plan.md`, now stated once for the directory.

### Kinds and lifecycles — iteration 1

| kind | open → | terminal | written by | transitioned by |
|---|---|---|---|---|
| `task` | `open` → `verified` | `closed` · `cut` | prep | smoke (`verified`, with `evidence`), review/smoke (`cut`, with `disposition`), ship (`closed`, after merge) |
| `signal` | `open` | `promoted` · `fixed` · `invalid` · `wontfix` | review, smoke | discover (all), review/smoke (`fixed`) |

`verified` is the one new state, and it is the QA change: **a task is not done because the gate
is green; it is done because smoke recorded evidence against its T-row.**

### Stage rules — what blocks

| stage | reads | writes | 🛑 refuses when |
|---|---|---|---|
| discover | `signal` where `open` | `signal` transitions | more than `discover.captureBacklog` open signals have not been *put to the human* this run |
| prep | `task` of other sprints | `task` (open) | a `task` from a **different** sprint is still `open` — the stale-ledger hazard, mechanised |
| build | `task` where `open` | — | any `task` slip is malformed |
| review | `task` | `signal`; `task → cut` | — (review reports; it does not gate on slips) |
| smoke | `task` where `open` | `task → verified`; `signal` | a `signal` has `attribution: in-diff` and `status: open` |
| ship | `task` for this sprint | `task → closed` (post-merge) | any current-sprint `task` is `open` — neither `verified` nor `cut` |
| aftercare | `task` where `cut`; `signal` where `scope: engine` | — | — |

Ship's rule is the load-bearing one. Today ship auto-closes every ledger entry on merge; under
slips it **cannot open the PR** until every task is `verified` or explicitly `cut`. `Closes #N`
lines come from `verified` tasks only. This is what makes the gate mean something.

### Validator

`skills/metate/lib/validate-slips.sh` — jq + bash, installed by bootstrap, run at every stage's
Step 0 and in ship's gate step. Checks, mechanically: every file parses; required fields present;
`kind` and per-kind `status` in-enum; `id` matches path; `provenance` non-empty and consistent
with `status`; `cut`/`invalid`/`wontfix` carry a `disposition`; `verified` carries `evidence`;
`in-diff` is never `open`. The schema is `skills/metate/slip.schema.json`, and the validator derives
its enums from it — nothing is hard-coded twice (the mistake caught in review of #107).

### Fixed paths — seven keys deleted

| key | field customisation | fate |
|---|---|---|
| `sessionFile` | 0 / 15 | fixed: `.metate/session.json` |
| `issueLedger` | 0 / 15 | **replaced** by `.metate/slips/task/` |
| `signalsFile` | 0 / 7 set | **replaced** by `.metate/slips/signal/` |
| `discover.planFile` | 0 / 14 | fixed: `.metate/plan.md` |
| `aftercare.release.planFile` | 0 / 3 | fixed: `.metate/release.json` |
| `smoke.humanGates.ledger` | 0 / 3 | fixed: `.metate/human-gates.json` (becomes a slip kind in iteration 2) |
| `smoke.matrix` | 0 / 0 | fixed: `.metate/smoke-matrix.json`, optional |
| `prep.techDebtFile` | **5 distinct values** | **kept** — it names a project doc, not metate state |

`metate-init --update` performs the retire pass mechanically: delete a key when its value equals
the default; 🛑 STOP and show the diff when it does not. Given the table, it will STOP nowhere.

### Migration

Lossless, run by `metate-init --update`, idempotent:

- `issues.json` → one `task` slip per `issues[]` entry (`status: open`, provenance from the file's
  `sprint`), one per `deferred[]` entry (`status: cut`, `reason` → `disposition`). The source file
  is removed after a byte-for-byte round-trip check.
- `signals.json` → one `signal` slip per entry, via the mapping already documented in
  `signal.schema.json` (`id` backfill, `githubIssue → tracker`, `P3 → S3`, `deferred → open`,
  `in-diff + promoted → fixed`). Entries that are `in-diff + open` migrate **unchanged and
  invalid**, so the validator names them at the next stage; they are real unfixed regressions
  (8 of 32 in the field) and need a human, not a script.

## What this deletes

This is the justification. The iteration is accepted only if it is **net-negative** on both
counters, measured by `make budget` and the template line count:

- 7 profile keys and their comments from `profile.template.yml`
- prep's ledger-shape prose, the `deferred[]` paragraph, and the "clean the ledger" warning
- ship's ledger reading, the two-condition staleness guard and its `deferred[]` inversion —
  replaced by one row in the stage-rules table
- review's `signalsFile` resolution paragraph — there is nothing to resolve
- discover's `id` backfill and title-matching prose
- the three-layout tolerance in the human-gates validator, once gates become slips (iteration 2)
- `tests/contracts/validate.sh`'s signal validator — it moves into the shipped `lib/` and runs
  everywhere, not only in this repo's test

## What this adds

- `skills/metate/slip.schema.json` and `skills/metate/lib/validate-slips.sh`
- a migration block in `bootstrap.sh`
- one short section in `skills/metate/SKILL.md` naming the fixed paths and the directory
- the stage-rules table above, once, in `skills/metate/SKILL.md` — the per-stage playbooks then
  point at it instead of each describing its own ledger

## Consequences

**Good.**
- The DoD becomes checkable: ship refuses a PR whose tasks smoke did not verify.
- "What state is this sprint in?" is `ls .metate/slips/task/` plus `jq .status`.
- Context survives sessions: `provenance` records who changed what and why; a new agent reads
  it instead of being told.
- A wrong LLM is caught: a malformed or missing slip fails a validator, which prose cannot do.
- 7 fewer config keys, one fewer schema per ledger, one validator instead of several.
- The stage question below gets an empirical basis for the first time.

**Bad, and accepted.**
- Many small files: Orbis filed 131 issues in one sprint — that is 131 slips. Mitigation: `cut`
  and `closed` slips of prior sprints are archived by aftercare into
  `.metate/slips/archive/<sprint>/`; the live directory holds only the current sprint's tasks plus
  open signals.
- One more state (`verified`) and one more stage refusal (ship). This is ceremony; it is the
  ceremony the 77% row says is worth it, and it is the *only* new refusal.
- The validator is jq. Query logic beyond validation will be awkward — see the CLI trigger.
- Migration touches 15 repos' `.metate/`. It is lossless and idempotent, and the retire pass
  will STOP nowhere given zero customisation, but it is still 15 working trees changing.

## Alternatives considered

| rejected | why |
|---|---|
| **Mailbox** (`to:` a role) | explicit handoff is attractive for the engine-complaint channel, but the workflow is one agent at a time; addressing is machinery without a consumer |
| **Event log** (immutable, fold to state) | full provenance without lost updates — but reading state means replaying, and the set only grows. `provenance` inside a mutable slip keeps the history and drops the replay |
| **Work queue** (claims, leases) | only pays for itself with concurrent agents on one sprint; none run today |
| **One `slips.json`** | trivially greppable, but two stages writing one file in one sprint is the merge conflict the directory removes |
| **Per-kind files, shared schema** | least disruptive — and keeps six files with six histories; the directory is where this is heading, so start there |
| **MCP server / daemon** | strongest for multi-agent and cross-repo — the two options the interview declined. A runtime dependency on a tool whose selling point is that it is files |
| **Build `metate-slips` CLI now** | not yet earned; see trigger |
| **Global slip box across 15 repos** | couples every repo to state not in its own git history; the engine channel is served by `scope: engine` + aftercare |

## CLI trigger

Extract a `metate-slips` CLI (validate · list · set) the first time **a jq expression appears
inside a `skills/*/SKILL.md`**. That is the exact failure mode — machinery migrating into prose —
and the only thing that would justify a maintained binary. Until then, playbooks say *what*
("mark T3 verified with evidence") and the validator says *whether*.

## Open question — carried, not decided here

**Are all seven stages necessary?** The author is not sure, and asks in particular whether
`smoke` duplicates QA that `review` (or a human QA pass) already does. The audit rejected
"collapse 7 stages to 3" as the largest possible metate-on-metate sprint — but that was an
argument from scope, not from evidence.

Slips supply the evidence. After **one real sprint on slips**, tabulate per stage: slips read,
slips written, slips transitioned. **A stage that reads nothing, writes nothing and transitions
nothing is ceremony**, by definition, and a candidate for folding into its neighbour. That table
is ADR-0002's context. Decide the stage count from it, not from a feeling in either direction.

## Acceptance

1. `make verify` green, and `make budget` shows the SKILL.md total **below** its pre-iteration
   count — the caps are lowered in the same diff, not raised.
2. `profile.template.yml` has ≤ 45 config keys (from 52).
3. `metate-init --update` on every one of the 15 field repos: exit 0, retire pass STOPs nowhere,
   `issues.json` and `signals.json` gone, slip count equals prior entry count, 8 signals flagged
   `in-diff + open` by name.
4. A ship run with one current-sprint task still `open` **refuses** to open the PR and names it.
5. The gut-a-playbook probe still fails `make verify` — slips replace prose contracts, they do
   not reintroduce them.
6. The per-stage slip-traffic table exists after the first live sprint, feeding ADR-0002.
