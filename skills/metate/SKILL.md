---
name: metate
version: 1.0.0
description: |
  Entry point, first-run setup wizard, and router for the `metate` development
  pipeline (scope → start → build → verify → ship). Use this to get
  oriented, to configure `.metate/profile.yml` with autodetected defaults on a
  fresh repo, or to find out which ceremony to run next. The actual work lives in
  the `metate-<stage>` skills; this one explains the flow and sets it up.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
allowed-tools:
  - Read
  - Write
  - Edit
  - Bash
---

# metate — pipeline entry point & setup

The pipeline is five ceremonies, one skill each. **There is no single `metate` worker** —
this skill orients you, sets up the profile on first run, and routes you to the right
stage.

```
metate-scope → metate-start → metate-build → metate-verify → metate-ship
   0               1              2               3              4
```

The macro-loop closes back on itself: `metate-ship` writes next-sprint pointers that
`metate-scope` reads to open the next cycle. **You** are the stop-condition between
iterations — scope proposes, you decide.

Two roles, both pluggable and **independent** (see `metate-build/REVIEWERS.md` and
`IMPLEMENTERS.md`): **reviewers** (`build.reviewer.backend` — spawn as other-harness CLIs) report
findings; the **implementer** (`implementer.backend` — cursor / codex / claude / gemini) is the
only writer. The harness session you opened is the orchestrator. Everything project-specific
lives in `.metate/profile.yml`.

## Step 1 — detect state

```bash
test -f .metate/profile.yml && echo "profile: present" || echo "profile: MISSING"
test -f .metate/session.json && echo "build session: present" || echo "build session: none"
git branch --show-current
```

- **No profile** → run first-run setup (Step 2). If `.metate/` doesn't exist at all,
  run the bootstrap first: `metate-init` if installed user-level, or
  `bash .agents/skills/metate-build/bootstrap.sh` / `bash .claude/skills/metate-build/bootstrap.sh`
  for a project-vendored install.
- **Profile has placeholders** (`<invariant …>`, empty `[]`/`""`) → finish setup (Step 2).
- **Profile filled** → route (Step 3).

## Step 2 — first-run setup (fill the profile with detected defaults)

Bootstrap writes the template with failing placeholder gates. Fill everything by
**autodetecting, proposing a default, and confirming with the user** before writing.
Edit `.metate/profile.yml` in place.

**gates** (`fastGate` / `shipGate`) — read the repo's real tooling, don't guess from the
lockfile alone:
```bash
grep -E '^(verify|check|test|lint):' Makefile 2>/dev/null          # make verify = canonical CI mirror
jq -r '.scripts | keys[]' package.json 2>/dev/null                 # lint / test / build / verify scripts
ls pnpm-lock.yaml yarn.lock package-lock.json pyproject.toml Cargo.toml go.mod 2>/dev/null
ls .github/workflows/*.yml 2>/dev/null                             # what CI actually runs
```
`fastGate` = the quick loop (lint + unit tests + build), run after each review round.
`shipGate` = the full pre-PR gate — mirror CI; prefer `make verify` when the target exists.

**implementer** — pick from what's installed; default to the first found:
```bash
for c in cursor-agent codex claude; do command -v "$c" >/dev/null && echo "found: $c"; done
```
- cursor → `backend: cursor`, `model: auto`
- codex  → `backend: codex`,  `model: ""` (omit; `*-codex-fast` need an API-key account)
- claude → `backend: claude`, `model: ""`

**reviewer** — who runs the three review lenses (can differ per lens). Default `backend: claude`
(matches the Claude Code plugin path). Set `codex` or `cursor` for cross-harness fan-out — see
`metate-build/REVIEWERS.md`. Lives at `build.reviewer` in the profile.

Invoke stage skills natively in your harness (`metate-build`, `metate-start`, etc.).

**reviewFocus** (highest-value field) — draft from the repo's own rules, don't invent:
```bash
ls CLAUDE.md AGENTS.md .cursor/rules/* docs/adr/* docs/ADR* 2>/dev/null
```
Read those, extract the real invariants (auth/tenant isolation, money/precision, state
guards, "don't duplicate X", design-system rules), draft 3–6 bullets, and **ask the user
to confirm or correct**. This is what makes the review catch real failure modes.
**Reference, don't transcribe.** If an invariant is already written down in an ADR or an
architecture doc, cite it (`ADR-0003 — <one-line gist>`) and make sure that doc is in
`start.readingOrder`; reviewers can be handed a bounded slice of it (REVIEWERS.md → Shared
review prompt). Copying whole design records into this scalar is how it grows to 60+ lines
and drifts out of sync with the source.

**scope** — keep the template defaults unless the user objects: all six `sources` on
(`aftercare`, `codebaseMemory`, `issues`, `gitHistory`, `captures`, `productIntent`),
`mode: steady`, `candidates: 5`. Turn `codebaseMemory` off
here only if `codebaseMemory.enabled` is false. `productIntent` reads README plus
`start.readingOrder` for stated goals — no separate path config. `.metate/plan.md` is what
`start` reads as its entry doc.

**start** — detect docs + base branch:
```bash
ls README* docs/handoff/README* docs/*roadmap* 2>/dev/null            # readingOrder candidates
ls docs/TECH-DEBT* docs/tech-debt* TODO* 2>/dev/null                   # techDebtFile
git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@.*/@@'      # base branch (fallback: main)
```

**verify** — detect the e2e suite + seed:
```bash
ls playwright.config.* cypress.config.* 2>/dev/null                    # → command
grep -oE '"(e2e|test:e2e|db:seed|seed)"\s*:' package.json 2>/dev/null  # → command / seedCommand
```
Map: Playwright/Cypress present → `command: "<pm> e2e"`; a `db:seed` script → that.
If the product needs PO/UX or live graduations a suite cannot sign off on, propose optional
`verify.humanGates` (`ledger: .metate/human-gates.json`, `required: true`) and confirm —
verify will then walk the human through open H items instead of a bare checklist. The ledger
is **tracked** project state (commit with the sprint).

**ship** — propose `deliverables` from the docs layout (handoff notes, CHANGELOG,
coverage docs, roadmap, this profile's sibling rules). Confirm with the user.
If the repo already has semver tags (or GitHub Releases), propose optional
`ship.release` (`enabled: true`, `scheme: semver`, `tagPrefix: "v"`,
`currentFrom: git-tag`, `githubRelease: true`) —
ship proposes patch/minor/major from the sprint diff and tags only after merge + a
second yes. Do **not** enable this on unversioned repos.
```bash
git tag -l 'v*.*.*' --sort=-v:refname | head -5
gh release list --limit 3 2>/dev/null
```

`prTarget` = the detected base branch; keep `commitStyle`/`issueCloseKeyword`
defaults unless the user uses a different convention.

After writing, show the user the filled profile and confirm before they run the pipeline.

## Fixed paths — state is not config

metate's state lives at fixed paths under `.metate/` — `plan.md`, `issues.json`, `session.json`,
`signals.json`, `human-gates.json` (tracked), optional `smoke-matrix.json` — and is
**not** configurable. Only `techDebtFile` and `start.readingOrder` are config: they name *your*
documents. `metate-init --update` strips the retired path keys from old profiles (ADR-0001).

## Step 2b — reconcile an existing profile (after a metate update)

Profile reconciliation is prose, not code — no script merges YAML. When metate has been
updated and the project already has a profile:

1. Read `.metate/profile.yml` and the shipped template (`profile.template.yml`, beside
   `metate-build/bootstrap.sh` in the installed skill).
2. List keys present in the template but missing from the profile.
3. For each missing key, propose a value fitted to THIS repo (detect it as in Step 2 —
   never paste the template placeholder verbatim when a real value is detectable).
4. Show the additions as a diff and confirm with the user before editing.
5. **Then a retire pass.** Additions alone make the profile a one-way ratchet: keys outlive the
   playbooks that read them, and the operator goes on believing they configured something. List
   every key in the profile that **no current playbook reads**, show them as a removal diff, and
   delete on the user's confirmation. Known dead as of now:
   - **`orchestrator:`** — read by nothing since the headless engine was deleted (`b713bea`).
   - **`scope.signals`** — renamed to `scope.sources`; **migrate** it (rename the key,
     keep the values) rather than leaning on the one-line alias.

   The half of the old rule that stays: **never silently rewrite a value.** Removals and renames
   are proposed as a diff and applied only on confirmation — the retire pass may not touch a key
   a playbook still reads, and may never change a value the user chose.
6. **Harness artifacts are separate from skills.** Updating metate at user level (`install.sh
   --update --user`) refreshes the skill files but **not** the per-project copies harnesses
   actually load — `.cursor/agents/metate-*.md`, `.cursor/rules/codebase-memory.mdc`. Those only
   refresh under `metate-init --update`, per project. Tell the user to run it, and put it in
   `ship.postCommand` so it is not a thing to remember.

## Step 3 — route to the ceremony

| You are… | Run |
|---|---|
| don't know what to work on / a sprint just closed | `metate-scope` |
| have a plan, no branch for the work yet | `metate-start` |
| branch cut, ready to write and review | `metate-build` (round 0 writes; rounds 1–3 review) |
| review green, need behavior proof | `metate-verify` |
| verify green, ready to land | `metate-ship` (docs, gate, PR, merge, tag) |

## First-round checklist
1. `.metate/profile.yml` filled (esp. `reviewFocus`) ✅
2. an implementer CLI installed and chosen ✅
3. run `metate-build` — round 0 writes `.metate/session.json`; rounds 1–3 resume it.
