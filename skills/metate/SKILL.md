---
name: metate
version: 1.0.0
description: |
  Entry point, first-run setup wizard, and router for the `metate` development
  pipeline (discover → prep → build → review → smoke → aftercare → ship). Use this to get
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

The pipeline is seven ceremonies, one skill each. **There is no single `metate` worker** —
this skill orients you, sets up the profile on first run, and routes you to the right
stage.

```
metate-discover → metate-prep → (build) → metate-review → metate-smoke → metate-aftercare → metate-ship
   0                  1             2            3              4                5                6
```

The macro-loop closes back on itself: `metate-aftercare` writes next-sprint pointers that
`metate-discover` reads to open the next cycle. **You** are the stop-condition between
iterations — discover proposes, you decide.

Two roles, both pluggable and **independent** (see `metate-review/ORCHESTRATORS.md` and
`IMPLEMENTERS.md`): the **orchestrator** (`orchestrator.backend` — claude / codex / cursor)
runs the playbooks and fans out the read-only reviewers; the **implementer**
(`implementer.backend` — cursor / codex / claude / gemini) is the only writer. Everything
project-specific lives in `.metate/profile.yml`.

## Step 1 — detect state

```bash
test -f .metate/profile.yml && echo "profile: present" || echo "profile: MISSING"
test -f .metate/session.json && echo "build session: present" || echo "build session: none"
git branch --show-current
```

- **No profile** → run first-run setup (Step 2). If `.metate/` doesn't exist at all,
  run the bootstrap first: `bash .claude/skills/metate-review/bootstrap.sh` (or
  `metate-init` if installed user-level).
- **Profile has placeholders** (`<invariant …>`, empty `[]`/`""`) → finish setup (Step 2).
- **Profile filled** → route (Step 3).

## Step 2 — first-run setup (fill the profile with detected defaults)

Bootstrap already set `fastGate`/`shipGate` from the package manager. Fill the rest by
**autodetecting, proposing a default, and confirming with the user** before writing.
Edit `.metate/profile.yml` in place.

**implementer** — pick from what's installed; default to the first found:
```bash
for c in cursor-agent codex claude; do command -v "$c" >/dev/null && echo "found: $c"; done
```
- cursor → `backend: cursor`, `model: auto`
- codex  → `backend: codex`,  `model: ""` (omit; `*-codex-fast` need an API-key account)
- claude → `backend: claude`, `model: ""`

**orchestrator** — who runs the playbooks + fans out reviewers, independent of the writer.
Default `backend: claude` (today's behavior; the Claude Code plugin path). Switch to `codex`
to run the pipeline with no Claude Code in the loop, or `cursor` (probe-before-use). The
`metate run <stage>` dispatcher routes per `metate-review/ORCHESTRATORS.md`.

**reviewFocus** (highest-value field) — draft from the repo's own rules, don't invent:
```bash
ls CLAUDE.md AGENTS.md .cursor/rules/* docs/adr/* docs/ADR* 2>/dev/null
```
Read those, extract the real invariants (auth/tenant isolation, money/precision, state
guards, "don't duplicate X", design-system rules), draft 3–6 bullets, and **ask the user
to confirm or correct**. This is what makes the review catch real failure modes.

**discover** — keep the template defaults unless the user objects: all four `signals` on,
`planFile: .metate/plan.md`, `candidates: 5`. Turn `codebaseMemory` off here only if
`codebaseMemory.enabled` is false. The `planFile` is what `prep` reads as its entry doc.

**prep** — detect docs + base branch:
```bash
ls README* docs/handoff/README* docs/*roadmap* 2>/dev/null            # readingOrder candidates
ls docs/TECH-DEBT* docs/tech-debt* TODO* 2>/dev/null                   # techDebtFile
git symbolic-ref --quiet refs/remotes/origin/HEAD | sed 's@.*/@@'      # base branch (fallback: main)
```

**smoke** — detect the e2e suite + seed:
```bash
ls playwright.config.* cypress.config.* 2>/dev/null                    # → command
grep -oE '"(e2e|test:e2e|db:seed|seed)"\s*:' package.json 2>/dev/null  # → command / seedCommand
```
Map: Playwright/Cypress present → `command: "<pm> e2e"`; a `db:seed` script → that.

**aftercare** — propose `deliverables` from the docs layout (handoff notes, CHANGELOG,
coverage docs, roadmap, this profile's sibling rules). Confirm with the user.

**ship** — `prTarget` = the detected base branch; keep `commitStyle`/`issueCloseKeyword`
defaults unless the user uses a different convention.

After writing, show the user the filled profile and confirm before they run the pipeline.

## Step 3 — route to the ceremony

| You are… | Run |
|---|---|
| don't know what to work on / a sprint just closed | `metate-discover` |
| have a plan, no branch for the work yet | `metate-prep` |
| branch cut, ready to write code | `metate-build` (starts the resumable implementer session) |
| code written, want it reviewed | `metate-review` |
| review green, need behavior proof | `metate-smoke` |
| smoke green, closing the sprint | `metate-aftercare` |
| docs done, ready to land | `metate-ship` |

## First-round checklist
1. `.metate/profile.yml` filled (esp. `reviewFocus`) ✅
2. an implementer CLI installed and chosen ✅
3. Build started through that CLI so `.metate/session.json` exists (else `metate-review`
   stops) ✅
4. run `metate-review`.
