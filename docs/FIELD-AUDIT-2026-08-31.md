# Field audit → work order (2026-08-31)

**What this is.** An implementation order derived from auditing metate as *actually deployed*
across 15 repos, not from reading this repo alone. Every task below carries the evidence that
produced it and a command that re-verifies it before you touch anything.

**Who it's for.** An implementing agent with write access to this repo. Read the ground rules,
then work the tasks in order. Do not skip the verify step — several findings are live-state
dependent and may already be resolved by the time you run.

**How it was produced.** Two parallel audits: (a) six readers over this repo's playbooks, history
and gates; (b) forensics over the 14 other repos with a `.metate/` directory, plus a profile/schema
drift pass across all 15. Findings were then attacked by three adversarial critics, which
overturned several conclusions — the survivors are what's here.

---

## Ground rules

1. **Line numbers will drift.** This repo has an uncommitted sprint in the working tree. Every
   task gives a `grep` for the exact target string. Anchor on the string, never the number.
2. **Verify before editing.** Each task has a `Verify` block. If it doesn't reproduce, stop and
   report rather than editing.
3. **Prose is the product here.** These playbooks are executed by an LLM, and grep is the only
   enforcement (`docs/TECH-DEBT.md` → "Prose has no type system"). A wording change *is* a
   behavior change. Keep edits minimal and surgical.
4. **Honor the line budget.** `docs/TECH-DEBT.md` carries the rule: *a change that adds prose to a
   `skills/*/SKILL.md` must remove prose.* Several tasks below are net-negative by design; use
   that headroom for the ones that must add.
5. **Do not run a metate sprint to do this work.** These are `edit → /commit` changes. The repo's
   own rule (`docs/ROADMAP.md` → Next) is to touch this repo only when triggered debt fires. Most
   of these are fired triggers; none justifies a seven-stage ceremony.
6. **Scope discipline.** The "Do NOT do" section at the bottom is not advisory. Those items were
   argued for by the audit and rejected on evidence or on the author's stated decisions.

### Current repo state (read this first)

```bash
git rev-parse --short HEAD main    # both 3ca0d0e at audit time — branch has ZERO commits
git status --short                 # 14 modified files, uncommitted
```

`feat/review-aperture` holds a finished five-round sprint as **uncommitted working-tree changes**,
while `docs/ROADMAP.md` already carries its close-out entry calling it Done. One `git checkout` or
one `prep` run (`git pull --ff-only`) destroys it. **Commit or explicitly discard this branch
before starting.**

Note for context: this is a dogfood-only defect. Downstream repos commit correctly —
`cie11-validator` shipped nine layered commits on a clean tree, `escriba` commits every review
round. Do not "fix" a missing commit step in the playbooks on the strength of this repo alone.

---

# P0 — live risk, do these first

## P0-1 · The issue ledger will auto-close four deliberately-cut issues

**Severity:** data loss on the next `metate-ship` run. Verified live.

**Problem.** `.metate/issues.json` carries an undocumented top-level `deferred[]` array holding
four issues that were deliberately cut mid-sprint. `metate-ship` Step 4 says to emit *"one
`<issueCloseKeyword> #N` line **per issue** in the body … Read the numbers from `issueLedger` —
emit one line per ledger entry."* An agent enumerating ledger entries will include `deferred[]`.

Ship's staleness guard does **not** save you. It requires (1) the issue is still OPEN and (2) the
ledger's `sprint` matches the branch. Both hold for all four deferred entries.

**Evidence (verified 2026-08-31).**

```
.metate/issues.json  →  sprint: "review-aperture"
  issues[]  : T2/#99, T3/#100, T5/#102, T7/#104, T9/#106
  deferred[]: T1/#98, T4/#101, T6/#103, T8/#105   ← undocumented key
gh issue view: #98 #101 #103 #105 all OPEN
skills/metate-prep/SKILL.md   ledger schema documents { sprint, issues[] } only — no deferred[]
```

**Verify.**

```bash
jq 'keys, (.deferred // [] | length)' .metate/issues.json
for n in 98 101 103 105; do gh issue view $n --json number,state -q '"\(.number) \(.state)"'; done
grep -n 'per issue\|per ledger entry' skills/metate-ship/SKILL.md
grep -n '"sprint": "<topic>", "issues"' skills/metate-prep/SKILL.md
```

**Change.**

1. `skills/metate-prep/SKILL.md` Step 4 — document `deferred[]` in the ledger shape, with its
   purpose (issues filed but cut from scope, retained so aftercare/discover can re-plan them) and
   required fields `{ id, number, title, reason }`.
2. `skills/metate-ship/SKILL.md` Step 4 — state explicitly that close-keyword lines come from
   **`issueLedger.issues[]` only**, and that `deferred[]` entries are **never** emitted as
   auto-close lines. Add a line to the PR body instead: name deferred ids as explicitly
   out-of-scope, so the PR records the cut.
3. Add `deferred[]` to the Step 4 staleness guard's scope note: a deferred entry that is *closed*
   is the anomaly worth stopping on (someone closed work that was cut).

**Acceptance.** A ship run against the current `.metate/issues.json` emits exactly five `Closes`
lines (#99, #100, #102, #104, #106) and names #98/#101/#103/#105 as deferred in prose.

---

## P0-2 · `review`'s exit criteria contradict themselves, so `done` is unreachable under `autoFix: all`

**Severity:** this is the mechanical cause of every recorded round-cap overrun in the fleet.

**Problem.** Two statements in `skills/metate-review/SKILL.md` disagree:

```
"Convergence is anchored on **blockers**. ≤3 rounds maximum."          ← the promise
"When **no fixable findings** remain this round, evaluate top to bottom" ← gates the whole ✅ table
```

Under `review.autoFix: all`, *fixable* = blocker · warning · **DESIGN** (the routing table in the
same file). The elegance lens is defined **suggestion-only**, and from round 2 it runs
**unanchored** — a cold read of the entire diff with no prior-findings memo. So reaching ✅ `done`
requires a round in which the lens whose entire job is producing suggestions produces none.

**The fleet is a clean natural experiment.** Exactly three of fifteen profiles set `all`:

| repo | `autoFix` | recorded rounds |
|---|---|---|
| metate | `all` | 5 (cap is 3) |
| escriba | `all` | **9** — commits `267dd23`→`e92c0c4`, 2026-08-21 13:48→17:05 |
| Orbis | `all` | overruns recorded in close-outs |
| the other 11 | `blockers` / `blockers+warnings` | no overrun recorded |

Rounds 4 and 5 in escriba each declared "all blockers closed" and five more rounds followed.
Rounds 8 and 9 carry byte-identical subject lines eleven minutes apart. The loop ended because the
operator ran out, not because findings did.

**Verify.**

```bash
grep -n 'Convergence is anchored on' skills/metate-review/SKILL.md
grep -n 'When \*\*no fixable findings\*\*' skills/metate-review/SKILL.md
grep -n -A6 'review.autoFix\` | routed to implementer' skills/metate-review/SKILL.md
grep -n 'suggestion only' skills/metate-review/SKILL.md
grep -rn 'autoFix' /Users/skalas/github/*/*/.metate/profile.yml 2>/dev/null
```

**Change.** In `skills/metate-review/SKILL.md`, change the verdict-table gate from *"When **no
fixable findings** remain this round"* to gate on **zero blockers** — which is what the
"Convergence is anchored on **blockers**" line already promises. Suggestions and warnings continue
to be *routed* under `all`; they stop *blocking convergence*.

Keep both anti-self-certification rules exactly as they are — they were empirically vindicated
(escriba's rounds 4 and 5 made precisely the error those rules forbid):

- a round that applied fixes can never self-declare done;
- a failed or empty lens is disqualifying.

**Acceptance.** With `autoFix: all` and a round returning 0 blockers + N suggestions on a patched
tree with a green gate, the verdict is ✅ `done`, not another round.

---

## P0-3 · Flip the three `all` profiles to `blockers`

**Problem.** metate's own profile is one of only three on `all`, which is why its cost and
round-count evidence is unrepresentative of the eleven repos that converge normally.

**Change.**

```yaml
# .metate/profile.yml
review:
  autoFix: blockers    # was: all
```

Same edit in `/Users/skalas/github/skalas/escriba/.metate/profile.yml` and
`/Users/skalas/github/skalas/Orbis/.metate/profile.yml`. **Ask the owner before editing repos
other than this one** — those are separate projects with their own history.

**Acceptance.** `grep -rn autoFix` across the fleet shows zero profiles on `all`.

---

## P0-4 · The `claude` implementer adapter is missing the stdin guard, and it silently corrupts session capture

**Severity:** breaks the one mechanism the audit rated as metate's genuine IP.

**Problem.** `IMPLEMENTERS.md` documents the `< /dev/null` headless-stdin guard **four times** —
all inside the **codex** section. The `claude` section's four `claude -p` invocations carry none.
`claude` is the implementer in **6 of 8** field session files.

The failure mode is observed, not theoretical. In `prediagnostico-api`,
`.metate/.fix-precheck.json` is **not valid JSON** — its first line is the CLI warning
`"Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command,
redirect stdin explicitly: < /dev/null…"`. The documented extraction is
`jq -r .session_id .metate/.session-start.json`, and it fails on that file. Mechanism B's entire
promise rests on that one extraction succeeding.

**Verify.**

```bash
grep -n 'dev/null' skills/metate-review/IMPLEMENTERS.md          # all hits in the codex section
sed -n '/^## claude/,/^## gemini/p' skills/metate-review/IMPLEMENTERS.md | grep -n 'claude -p'
head -c 200 /Users/skalas/github/goes/prediagnostico-api/.metate/.fix-precheck.json
```

**Change.**

1. Add `< /dev/null` to every `claude -p` invocation in the `## claude` section of
   `IMPLEMENTERS.md` (both the plain and the `--dangerously-skip-permissions` variants, start and
   resume).
2. Lift the stdin note out of the codex section into the shared **"Long-running invocations"**
   section so it covers all backends, and remove the now-redundant per-backend repeats (net prose
   reduction — spend it on P1-1).
3. In `skills/metate-build/SKILL.md` Step 1, make the id extraction defensive: the session id must
   be read from the JSON envelope and **validated as a UUID before being written to
   `sessionFile`**; a non-parsing envelope is a 🛑 STOP, not a blank id.

**Acceptance.** `sed -n '/^## claude/,/^## gemini/p' … | grep -c 'dev/null'` ≥ 4, and build stops
loudly rather than writing an empty or garbage `sessionId`.

---

# P1 — structural, high value

## P1-1 · `review` will resume a two-month-dead implementer session

**Problem.** `sessionFile` is `{ implementer, sessionId, model }` — no branch or sprint context.
`metate-review`'s Inputs STOP condition only checks that the file **exists**. Ship Step 7
("retire sprint-local state") is *atomic* in the field: the same three repos that reset the ledger
also deleted the session file, and all three are back on `main`. It never runs unless the sprint
fully lands.

Consequence — stale explicit session ids sitting in repos right now: `cerbero` 62 days,
`music-sync` 64, `mictlan` 50. Nothing distinguishes them from live.

Two repos independently hand-added the missing key: `prediagnostico-api`
(`sprint: fix/test-suite-safety`) and `internal_lucho_tool` (`sprint: s1-rieles`).

**Change.**

1. Add `sprint` to the `sessionFile` shape in `skills/metate-build/SKILL.md` Step 2 and in
   `IMPLEMENTERS.md` → Build handshake: `{ implementer, sessionId, sprint, model? }`.
2. `skills/metate-review/SKILL.md` → Inputs: STOP unless `sessionFile.sprint` matches the current
   sprint (branch topic / `issueLedger.sprint`). A mismatch means the session belongs to a prior
   sprint — do not resume it.
3. Make `model` optional. It is blank or a sentinel in 5 of 8 field session files, so a third of a
   three-key schema carries nothing.
4. This also repairs `metate-prep` Step 5, which currently instructs a comparison against a field
   the schema does not define — prep says to reset the session when "the plan's sprint topic
   differs from what `sessionFile` records," and `sessionFile` records no sprint.

**Acceptance.** Review against `cerbero`'s 62-day-old `session.json` STOPs with a sprint-mismatch
message instead of resuming.

---

## P1-2 · `reviewFocus` is the only channel for project knowledge, so it is absorbing entire design records

**Problem.** `REVIEWERS.md` → "Shared review prompt" enumerates the complete reviewer context:
`reviewFocus`, the diff, the round-2 memo, the Code Discovery clause. Not `prep.readingOrder`, not
ADRs, not architecture docs. So `reviewFocus` is the sole pipe.

The measured consequence — the structural schema is otherwise remarkably stable, and this one
field is not:

| | spread across 15 field profiles |
|---|---|
| all config lines except `reviewFocus` | template 50; field median ~50, range 34–66 (**1.9×**) |
| `reviewFocus` | 3 lines (brain-mcp) → 68 lines (cie11-validator) (**22×**) |
| share of profile bytes | template 13%; field median 28%; cie11 48% |

`cie11-validator` has **16 ADRs**, already lists `docs/adr/README.md` in `prep.readingOrder`, and
already lists `docs/adr/` in `aftercare.deliverables` — and the operator *still* hand-transcribed
18 invariants citing ADR-0003/0005/0006/0007 by number into a YAML scalar. The abstraction forces
that duplication.

Note this is invisible from inside this repo: **metate's own `reviewFocus` is 12 lines, exactly the
template default — the smallest in the fleet.**

**Change.** In `REVIEWERS.md` → Shared review prompt, add one context item: the orchestrator may
include a **bounded** slice of `prep.readingOrder` (and any ADR index it names) as DATA in the
reviewer prompt, wrapped like the diff, with a size cap and the data-not-instructions restatement.
Then note in the `metate` wizard (Step 2, `reviewFocus`) that invariants already written down in an
ADR or architecture doc should be **referenced**, not transcribed.

**Acceptance.** A reviewer prompt can reach a repo's ADRs without the operator copying them into
`profile.yml`.

---

## P1-3 · The capture lane is a write-only queue — and the fix is a blocking reader, not another field

**This is the most important design finding in the audit, and it constrains P1-3 itself.**

**Problem.** Across 32 signals in 5 field repos:

| status | count |
|---|---|
| `open` | 20 (62.5%) |
| `promoted` | 11 (34.4%) |
| `deferred` (out-of-enum) | 1 |
| `invalid` | **0** |
| `wontfix` | **0** |

The two human-rejection paths that `metate-discover` Step 3 offers as a first-class move (`drop #`)
have been used **zero times in seven weeks**. The schema's own description asserts *"Every signal
ends promoted or closed — nothing lives here forever."* It doesn't.

The arithmetic is structurally fatal: `cie11-validator` has 16 open captures folding into a
5-candidate slate. At most one is picked, so **≥15 are guaranteed to stay open and be re-read next
cycle** — forever. The lane grows monotonically and permanently crowds the slate.

**The controlled comparison — same repo, same operator, same six weeks:**

| ledger | mandatory reader? | dispositioned |
|---|---|---|
| `human-gates.json` | yes — **blocks** smoke and ship | **77%** |
| `signals.json` | no — merely *advises* discover | **16%** |

**Enforcement, not design, is what drains a queue.**

**Change — engine intake, with teeth.** metate has no channel from field use back to engine work
(`git log --all` in this repo, grepped for all 15 deployment names: **zero hits**), and there is
already a downstream signal waiting that is explicitly an engine complaint —
`gov-skills/.metate/signals.json`, `foundIn: smoke:T2`: *"El comando de smoke del perfil no ejecuta
tests/contracts, que es donde vive la mayor parte del DoD de un sprint."*

1. Add `scope: engine|product` to `skills/metate-smoke/signal.schema.json` (default `product`).
2. `skills/metate-aftercare/SKILL.md` — when closing out, surface any `scope: engine` signals in
   the handoff and next-sprint pointers so they are visible at the sprint boundary.
3. **The blocking half — do not ship 1 and 2 without this.** `skills/metate-discover/SKILL.md`
   Step 3: discover may not present a slate while more than N open captures are undispositioned;
   it must first walk the human through them for `promoted` / `invalid` / `wontfix`, the way
   `metate-smoke` Step 4 walks human gates (why / what / what done looks like — never a bare
   list). Reuse that walkthrough shape; it is the mechanism with the 77% completion rate.
4. Fix the routing inversion while you are here: `attribution: in-diff` is used as a signal in
   **13 of 32** entries (41%) although the schema calls in-diff *"a blocker, not a signal — fix
   in-branch."* Either the schema's rule or smoke's Exit routing is wrong; pick one and state it
   once. Related: `brain-mcp` flipped 6 signals `open`→`promoted` inside the same PR that fixed
   them, so `promoted` means "I fixed it" there and "discover chose it into a plan" elsewhere.
   Disambiguate — a `fixed` status, or make `promoted` mean only "entered a plan."

**Acceptance.** Discover cannot emit a slate against `cie11`'s 16 open captures without
dispositioning them first, and an engine-scoped signal filed downstream is visible to this repo's
next discover.

---

## P1-4 · `signal.schema.json` is the wrong shape — too small where the field extends it, too tight where the field breaks it

**Problem.** The item schema is `additionalProperties: false` with required
`title, repro, attribution, status`. The field added keys anyway, so those files are **formally
invalid**:

| invented key | repo | why it was needed |
|---|---|---|
| `githubIssue` | Orbis | no pointer from signal → filed issue; the promotion is untraceable by design |
| `disposition` | Orbis | `promoted` alone is unfalsifiable — no room for *why* or *where* |
| `notes` | gov-skills (4/4 entries) | schema has only backward-looking observation, no field for the fix the capturer already has in mind |
| `items` (top level) | Orbis | a **byte-identical duplicate** of `signals[]` — two writers disagreed on the container key; ~50% of the file is a redundant copy |

And the enums are too tight exactly where use pushes — **6 of 32 entries (19%) carry out-of-enum
values**: `status: deferred`, `severityGuess: S4` (×4), `severityGuess: P3`. Only **4 of 32**
`foundIn` values (12.5%) match the documented `smoke:Tn` form; real forms include
`smoke:H1 walkthrough`, `review:round3 unverified-patch`, `review:ronda-2:seguridad`,
`live-test:orbis-bos`, `user:2026-08-26 architecture question`.

The sharpest instance: Orbis's `status: deferred` entry is in neither discover's read set (`open`)
nor its skip set (`promoted|invalid|wontfix`), so it can **never resurface and never close**. It
has been invisible for 44+ days.

Also: `blocksDoD: true` appears **zero times in all 32 entries**, so `metate-smoke`'s entire
hotfix-first / scope-expand escalation branch has never once executed. It would run for the first
time in anger.

**Change.**

1. Add `id` (required — discover currently matches by `title`, and `metate-discover` says so
   outright: *"the log has no id"*) and `capturedAt`.
2. Add `tracker` (issue link) and `disposition` (free-text closure reason) — harvest Orbis's two
   inventions rather than letting each repo reinvent them.
3. Add `notes` — harvest gov-skills'.
4. Add `scope` (P1-3).
5. Open `severityGuess` (accept S0–S4, or drop the enum and document the scale) and `foundIn`
   (make it a free string with documented conventional prefixes).
6. Add `fixed` to the `status` enum, or resolve the `promoted` ambiguity another way (P1-3.4).
7. Keep `additionalProperties: false` only if you also point a validator at the real files —
   otherwise it is a false guarantee. See P2-1.
8. Fix Orbis's duplicated `signals`/`items` arrays, and settle on **one** container key (the jq in
   `tests/contracts/validate.sh` currently tolerates three layouts for the *gates* ledger; do not
   repeat that here).

**Acceptance.** All 32 existing field signals validate against the revised schema without losing
information, and the Orbis `deferred` entry becomes reachable.

---

## P1-5 · Half the fleet silently discards review's most valuable output

**Problem.** **8 of 14** field profiles lack `signalsFile`, and the *same* 8 lack the `reviewer`
block. `metate-review` routes out-of-diff bug captures to `signalsFile` **"(if configured)"** — so
in 57% of the fleet that output is discarded silently and discover's `captures` source is
permanently empty. Worse: **Orbis and brain-mcp have a `signals.json` on disk with no key pointing
at it** — state exists that the engine cannot address.

Separately: `brain-mcp`'s `reviewFocus` is still the verbatim template placeholder
(`- <invariant 1, e.g. tenant/scope isolation on every transactional query>`) and review ran
anyway — its reviewers were instructed to enforce tenant isolation and payment-cent math on an MCP
server. The `metate` wizard knows how to detect `<invariant …>`; **`metate-review` never checks.**

**Change.**

1. `skills/metate-review/SKILL.md` Step 0 — when `signalsFile` is unset but `.metate/signals.json`
   exists on disk, say so loudly and use it; when neither exists, report captured survivors in the
   round output and tell the user to set the key. Never drop them silently.
2. `skills/metate-review/SKILL.md` Step 0 — if `reviewFocus` still matches the template
   placeholder pattern (`<invariant`) or is empty, **STOP** and tell the user to run the wizard.
   The engine's own docs call this "the highest-value field"; it should not be possible to run
   green without it.
3. Same placeholder check for `fastGate` / `shipGate` — `cerbero` and `Palladium-deliverables`
   (2 of 14) still run the fail-loudly placeholder, and `cerbero`'s carries a frozen copy-paste
   bug: `shipGate: "echo 'set fastGate in .metate/profile.yml' && false"` names *fastGate*.

**Acceptance.** A review run on `brain-mcp` stops on the placeholder `reviewFocus` instead of
shipping it to three reviewers.

---

## P1-6 · The Cursor-side artifacts harnesses actually load are eight weeks stale

**Problem.** Seven of eight installed skills under `~/.claude/skills` match the repo byte-for-byte
(the one exception is `metate-review`, which is the unlanded sprint — expected). The genuine
staleness is Cursor-side: `.cursor/agents/metate-*.md` are dated Jul 2 and still carry the retired
`readonly: true` frontmatter and pre-sprint wording, and `.cursor/rules/codebase-memory.mdc` is
never refreshed at all.

Cause: `bootstrap.sh` refreshes `.cursor/agents` only under `--update`, and
`aftercare.postCommand` is `bash install.sh --user`, which copies skills to the user roots but
**never invokes the project bootstrap**. This repo sets `reviewer.backend: cursor`, so those are
the files its own reviewers load.

**Verify.**

```bash
ls -l .cursor/agents/
diff -u skills/metate-review/cursor-agents/metate-elegance-reviewer.md .cursor/agents/metate-elegance-reviewer.md
grep -n 'postCommand' .metate/profile.yml
grep -n 'UPDATE -eq 1' skills/metate-review/bootstrap.sh
```

**Change.**

1. `.metate/profile.yml` → `aftercare.postCommand: "bash install.sh --update --user && metate-init --update"`.
2. `Makefile` — extend the drift gate. `render-check` today guards `sources/` → `skills/`, i.e.
   files nobody loads. Add a check on `skills/` → the copies harnesses actually read
   (`~/.claude/skills`, `~/.agents/skills`, `.cursor/agents/*.md`,
   `.cursor/rules/codebase-memory.mdc`), reporting version/mtime skew as a warning (not a hard
   fail — a legitimately unlanded branch will always differ).
3. Note in `skills/metate/SKILL.md` Step 2b that a metate update requires
   `metate-init --update` per project, not just the user-level install.

**Acceptance.** `make render-check` (or a new `make drift`) reports the Cursor agents as stale
today, and reports clean after `metate-init --update`.

---

# P2 — hygiene and harvest

## P2-1 · Delete the five prose-contract greps; they manufacture false confidence

**Problem.** An audit probe gutted four playbooks (`ship`, `prep`, `smoke`, `aftercare`) down to
**22–26 lines** of frontmatter plus five magic tokens. **All 13 `make verify` checks passed
green**, including `✓ skill prose contracts present`. The gate is worse than absent, because it
reads as coverage.

This repo already reached the same verdict once: `.metate/issues.json` shows T8 ("Prose contracts
for the new review invariants") cut with the reason *"prose contracts anchored on phrases guarded
nothing twice, and phrase anchors inside sections scheduled for rewrite would force preserving
wording verbatim to keep the gate green."* The construct was left in place anyway.

**Change.**

1. Delete the phrase-grep block in `tests/contracts/validate.sh` (from the
   `# --- prose drift: critical MUST phrases` comment through its `ok "skill prose contracts
   present …"` line). **Keep** the ordering check (branch-before-seed) — that one anchors on
   structure, not wording, which is the repo's own stated rule.
2. Keep and extend the jq fixture validators — those check real shapes.
3. `Makefile` — add `tests/contracts/validate.sh` to `SCRIPTS` so the validator is linted by the
   gate it implements. Its own `set -euo pipefail` silent-death bug (the one promoted as this
   repo's single signal) is exactly the class that self-linting catches.

**Acceptance.** The gut-four-playbooks probe now fails `make verify`, or the gate no longer claims
to cover prose.

---

## P2-2 · Profile reconciliation is a one-way ratchet, so dead config is permanent

**Problem.** `skills/metate/SKILL.md` Step 2b rule 5: *"**Additions only** — never remove,
reorder, or rewrite existing keys, values, or comments."* Consequences measured in the field:

- **`orchestrator:`** lived **3 days** in the engine (added `c3e2a0d` 2026-06-30, orphaned by
  `b713bea` 2026-07-03 when the headless engine was deleted) and still sits in **4** field
  profiles. Zero playbooks read it. `brain-mcp`'s `.bak` diff shows the operator hand-added it one
  day before the engine that read it was deleted; `escriba`'s profile was last edited seven weeks
  later and still carries it. Nothing breaks — which is worse: the operator believes they
  configured a backend no stage consults.
- **`discover.signals`** (renamed to `discover.sources` by `82e0019`) is honored by exactly **one
  line in one playbook**, with no contract test. 5 of 14 repos still carry the old name.
- **`discover.mode`** (shipped `a417188`, 2026-08-25) is **absent from 11 of 14** profiles —
  including `cie11-validator`, whose profile was edited **six days after** the key shipped. So
  `explore` mode, the whole point of that sprint, is unreachable everywhere it might matter. The
  only fully template-current profile in the fleet belongs to `Palladium-deliverables` — a repo
  that never ran a stage.
- **`{N}` interpolation** is promised in `skills/metate-aftercare/SKILL.md` ("paths, may use `{N}`
  for the sprint number") and that is the **only** `{N}` mention in the entire skills tree.
  Nothing supplies N. Orbis carries both `{N}` in `aftercare.deliverables` *and* a hand-maintained
  literal `docs/handoff/post-sprint-70.md` in `prep.readingOrder`; roughly a third of its 25
  profile edits exist to bump one integer the config language claims to interpolate.

**Change.**

1. Rewrite Step 2b rule 5: additions **plus** an explicit *retire* pass — list keys present in the
   profile that no current playbook reads, show them as a diff, and remove on confirmation. Keep
   the "never silently rewrite a value" half.
2. Have the retire pass name `orchestrator` and `discover.signals` specifically as known-dead, and
   migrate `discover.signals` → `discover.sources` rather than relying on the one-line alias.
3. Either implement `{N}` (resolve from `issueLedger.sprint` / the plan, and apply it to
   `prep.readingOrder` too) or delete the promise from aftercare and document the literal-path
   convention. Do not leave it half-true.

**Acceptance.** Running the wizard's reconcile against `escriba`'s profile proposes removing
`orchestrator:` and renaming `discover.signals`.

---

## P2-3 · Harvest the four artifacts the field already invented

The fleet extended metate in exactly four places, independently, with no engine support. Each is a
gap the engine left as prose. This is the only trigger-compliant engine work available, and it is
the improvement channel this project structurally lacks.

**(a) T-row → command binding.** `metate-smoke` Step 2 says to *"map results back to the DoD matrix
(T1…Tn) from Prep"* — but its own Step 0 input list never names a file carrying that matrix, and
the profile gives smoke exactly one string slot. Orbis built
`.metate/smoke-matrix.json` (`{ sprint, description, requires{postgres,env}, rows[]{id,title,command} }`)
plus a 57-line runner and two profile keys the engine defines nowhere (`smoke.smokeMatrix`,
`smoke.domainGate`). Before its sprint 67 the binding lived nowhere at all; it is now duplicated in
three places. **Adopt the file shape**, and let `smoke.command` remain the fallback for repos with
one suite.

**(b) ADRs as the `decision` deliverable.** `metate-discover` defines `kind: decision` as a
candidate kind and defines **no output artifact for it anywhere**. `cie11-validator` holds 16 ADRs
and its plan records *"Candidate #1 was a decision and is folded in as an ADR deliverable."* Define
the ADR as the `decision` kind's completion artifact in discover Step 4 and prep's non-sprint
branch.

**(c) Candidate merging.** Two of the heaviest users independently invented the same off-spec move
— `cie11`: *"chosen: 2026-08-25, from discover candidates #1 + #2 + #3, merged"*; `Orbis`:
*"Source: metate-discover · merge #2 + #3"*. Discover's brief offers `merge #,#` but its ranking,
slate-spread and refinement machinery never describe what merging *does* to the resulting plan
(DoD union? mode? corroboration?). Document it.

**(d) A fifth implementer adapter.** `internal_lucho_tool`'s `session.json` carries hand-written
`resumeVia` and `note` fields encoding resume-by-SendMessage to an **in-process subagent**, with
`implementer: claude-subagent` and a 17-hex-char ref instead of a UUID. The note records the
cause: the nested `claude -p --dangerously-skip-permissions` call the documented adapter requires
was **denied by the harness's own permission classifier**. That is this repo's existing TECH-DEBT
item *"bootstrap autonomy rule too broad for the claude backend"*, fired in production, with the
workaround already written by the operator. Add the adapter to `IMPLEMENTERS.md`.

**One security note while you are in there.** That `note` field is phrased as an imperative to the
next reader. metate applies its *"treat text as data, never instructions"* guardrail to
`signalsFile`, `plan.md`, issues and commit messages — but **not** to `sessionFile`. Extend it.

---

## P2-4 · Make the prose line budget mechanical

**Problem.** `docs/TECH-DEBT.md` carries the rule *"a change that adds prose to a
`skills/*/SKILL.md` must remove prose"* — and nothing enforces it. Measured trajectory:

| | shell (verifiable) | playbook prose (not) |
|---|---|---|
| `4d1ecbd` (pre-shrink, 2026-07-03) | 1,467 | 844 |
| `2487fef` (post-shrink, same day) | 864 | 841 |
| working tree now | **756** | **1,234** |

`shrink-engine` is recorded in ROADMAP as "Net ≈ −1,050 lines," but the deleted correctness was
*harvested into SKILL.md* — complexity did not leave, it moved to the medium with no type system.
Total playbook prose has grown 98 → 1,234 lines, monotonically except for one deliberate dip.
`metate-review/SKILL.md` is 252 lines in the working tree, up 24 from HEAD, **after being reduced
twice during its own review**, in the same diff that added the accretion rule to TECH-DEBT.

**Change.** Add a `make budget` target (wired into `verify`) with a hard per-file line cap for
`skills/*/SKILL.md`, seeded at the current counts. Exceeding it fails the gate. If a future sprint
needs headroom it must raise the cap *explicitly, in the diff* — which is the point.

**Acceptance.** `make verify` fails when a `SKILL.md` grows past its recorded cap.

---

# Do NOT do

The audit argued for each of these. They were rejected — on fleet evidence, or on decisions already
recorded in this repo and the author's standing notes. Do not implement them, and do not re-derive
them as new strategy.

| Rejected | Why |
|---|---|
| **Soften the `codebase-memory-mcp` hard requirement to a warning** | Marked intentional (major token savings). Four separate agents recommended it; the decision stands. |
| **Cut the 4-CLI × 2-role adapter matrix down to the verified rows** | Backend switching is load-bearing *daily* — token limits force mid-project vendor changes. The correct simplification is unification, not deletion. |
| **Collapse 7 stages to 3, or cut the profile from 39 keys to 10** | The largest possible metate-on-metate sprint, i.e. the exact activity this repo's own rule bans. And the abstraction is *holding*: 15 bootstraps produced exactly **one** non-template top-level key fleet-wide. |
| **Add a hard integer round cap to review** | escriba's rounds 4–7 each closed real blockers (60–299 lines apiece). The waste is entirely in the tail — rounds 8 and 9 carry identical subjects 11 minutes apart. The problem is a missing **terminator** (P0-2), not a missing cap. |
| **Add a "commit the implementation" step to a stage** | The uncommitted-sprint hole is a **dogfood-only artifact**. `cie11-validator` ships nine layered commits on a clean tree; `escriba` commits every review round. Fix this repo's branch (see Current repo state), not the playbooks. |
| **Retire `prep` / `build` / `smoke`** | `build`'s sole product — the persisted session binding — is the mechanism the audit rated most valuable: prediagnostico's session `91dad1bc` held across **117 turns, ~$17.33, 31h35m** and five resumptions with zero failures. |

---

# Contract violations to be aware of (not tasks — context)

Two of metate's own written 🛑 STOP rules are being bypassed at scale in the field, silently. Do not
"fix" these by tightening the rule; the rule is already strict and reality routes around it. They
are here so you understand what soft enforcement actually costs.

- `cie11-validator`'s live 13-gate ledger **fails metate's own strict entry validation** —
  duplicate `id` on 12 of 13 rows. Under the documented rules, smoke should have halted and ship
  should have refused the PR. **Two sprints shipped through anyway.**
- `Orbis`: **0 of 57** human-gate rows pass id-uniqueness (5 distinct ids across 57 rows), because
  `metate-prep` is required to emit `H1` every sprint and append. The 🛑 STOP was bypassed **21
  times** without anyone noticing.

If you change the gate ledger's `id` semantics, make them **sprint-scoped** (`s70:H1`) — that is
what the field's usage actually means, and it makes 57 rows valid instead of 0.

---

# Open question — measure before investing further

The one number that would actually decide metate's strategic direction is unresolved:

| Orbis | commits/month |
|---|---|
| 2026-06 | 680 |
| 2026-07 | 158 |
| 2026-08 | 36 |

Sprint cadence from handoff-doc dates: S0→S39 in **22 days** (pre-metate) against S65→S70 in
**35 days**. Heavily confounded by project maturity and by attention now splitting across 15 repos
— but that second confound is itself a metate effect, since metate is what makes 15 repos feel
individually tractable.

```bash
# reproduce
git -C /Users/skalas/github/skalas/Orbis log --date=format:'%Y-%m' --pretty='%ad' | sort | uniq -c
ls -l --time-style=long-iso /Users/skalas/github/skalas/Orbis/docs/handoff/ | head -60
```

Resolve this into *maturity*, *portfolio fragmentation*, or *ceremony drag* before any further
investment in stage features. Everything in P0–P2 above is worth doing regardless of how it lands.

---

# Appendix — the fleet

15 installs. This is what the engine is actually running against; it is not a self-referential
project.

| repo | scale | metate use |
|---|---|---|
| Orbis | 874 commits | 29 sprints (S45→S70), 131 issues filed in 17 batches — all closed, 20/20 milestones closed, 26 close-outs, 57 human-gate dispositions over 22 consecutive sprints, **0 left open** |
| prediagnostico-api | 1,002 commits | 9 bisectable layered commits; 117 implementer turns on one session across 32h; **$13.11** of recorded cost receipts |
| escriba | 291 commits | 10 sprint PRs (never squashed), 222/291 conventional, 15 tags, **review round 9** |
| grouphead | 173 commits | ~5 cycles, 24 issues (100% closed), PR #122 carries 15 `Closes #N`, tag v0.3.0 |
| cie11-validator | 52 commits | 3 sprints, ~44K LOC in 9 days, 17 ADRs, 927-line debt ledger, 19 signals, 13 gates |
| gov-skills | 23 commits | sprint merged 2026-08-28; 4 signals incl. one **engine complaint** |
| internal_lucho_tool | 13 commits | S0 shipped; invented the in-process-subagent adapter |
| mictlan · elegua · brain-mcp · music-sync · centinela · cerbero · Palladium | 1–40 commits | bootstrapped during metate's own two heaviest build weeks; effectively its test harness |

**Important context:** Orbis carried **88 handoff docs before metate's repo existed** (2026-06-25),
with the integration commit `53e9878` landing the next day. metate is an **extraction of a working
practice**, not an invention — which is why the profile abstraction ports so cleanly, and why the
"delete most of it" framings scored worst under adversarial review.

**The actual diagnosis.** metate is not over-optimized on its own repo. What is locally
over-optimized is metate's *development*: the only thing permitted to change the engine is prose
authored from the one installation that exercises it least — this repo's own profile has
`smoke.command` == `shipGate` == `make verify`, `seedCommand` empty, zero human gates, and **one**
signal, against cie11's 19 and Orbis's 57 gate dispositions. Meanwhile `git log` here has never
once cited any of the 15 deployments, and the last two sprints bypassed `discover` entirely
(`.metate/plan.md`: *"Chosen from a design conversation"*).

**P1-3 is the task that fixes that channel.** Everything else is repair.
