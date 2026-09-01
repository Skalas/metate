---
name: metate-aftercare
version: 1.2.0
description: |
  Stage 5 (Aftercare) of the `metate` pipeline. From the branch diff, creates or
  updates the project's required close-out deliverables (handoff notes, coverage
  docs, roadmap, tech-debt with triggers, next-sprint pointers), optionally
  proposes a semver release (tag/GitHub) for user confirmation, then runs the
  optional `aftercare.postCommand`. Reads the deliverable list from
  `.metate/profile.yml`. Codebase-agnostic; docs (+ optional release plan) only.
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

# metate-aftercare — sync the documentation

Runs after Smoke is green, on the same branch, so the docs ship in the sprint PR.

## Step 0 — load the profile
Read `.metate/profile.yml` → `aftercare.deliverables` (paths, may use `{N}` — see below),
`aftercare.postCommand` (optional), and optional `aftercare.release`
(`enabled`, `scheme`, `tagPrefix`, `currentFrom`, `versionFile`, `githubRelease`,
`planFile`). If deliverables is empty, ask the user for the close-out doc set.

**`{N}` — the sprint number.** Any `{N}` in a deliverable path is substituted before the path is
used. Resolve it once, in this order, and **state the resolved value** in the output:
1. the first integer in the sprint topic (`issueLedger.sprint`, the plan, or the branch name) —
   `s70-billing` → `70`;
2. otherwise the highest integer already present in files matching the same pattern, **+1** —
   `docs/handoff/post-sprint-{N}.md` with `…-69.md` on disk → `70`;
3. otherwise ask the user. Never guess, and never write a literal `{N}` to disk.

The same substitution applies to `prep.readingOrder` (metate-prep Step 1), so a numbered handoff
path is written once in config instead of hand-bumped every sprint.

## Steps
1. **Read the diff** — `git diff <baseBranch>...HEAD` to know what actually changed.
2. **Update each deliverable** in `aftercare.deliverables`:
   - handoff / post-sprint note → what shipped, POC limits, deferred debt;
   - coverage docs → only the items this branch touched;
   - roadmap / status → mark this sprint done, next in progress;
   - tech-debt ledger → new debt **with a trigger** (the condition that forces the fix);
   - next-sprint pointers / agent-context → advance to N+1.
3. **Surface engine-scoped signals** — read `signalsFile` and pull every entry with
   `scope: engine` that is still `open`. These are defects in **metate itself**, filed from this
   repo's use of it; nothing else carries them out of this repo. Name them in the handoff and in
   the next-sprint pointers, with `id`, `title` and `foundIn`, under a heading that says plainly
   they are engine complaints, not product work. Do not attempt to fix them here and do not
   change their status — this stage's job is to make them visible at the sprint boundary.
4. **Stay factual** — derive everything from the diff and the prep brief; don't invent
   scope. Intentional omissions are documented `—` placeholders, not silent gaps. If
   `smoke.humanGates.ledger` has `deferred` items, name them in the handoff / next-sprint
   pointers so the next `metate-discover` resurfaces them (with the written reason).
5. **Release proposal (when configured)** — only if `aftercare.release.enabled` is true
   (typical when the repo already has semver tags / GitHub Releases). Do **not** invent
   a versioning scheme for a repo that has none.

   Detect current version:
   - `currentFrom: git-tag` (default) → **fetch first** (`git fetch --tags origin` or
     equivalent) so local tags are not stale. Then list only **exact** release tags matching
     `^${tagPrefix}[0-9]+\.[0-9]+\.[0-9]+$` (no prerelease / no junk suffixes), sort by
     version, take the latest. If none exist after filtering, 🛑 STOP and ask — do not guess.
   - `currentFrom: file` → read `aftercare.release.versionFile` (a path whose contents are
     the current version string). **Do not edit that file here** — version-file bumps belong
     to the implementer during Build (so Review + Smoke still see them). Aftercare only
     *reads* current and proposes the next tag. If the file is missing/blank/non-semver,
     🛑 STOP.

   From the sprint diff, **propose** one SemVer bump and justify it in plain language:
   - **patch** — fixes, docs-only, no new capability;
   - **minor** — new backward-compatible capability / opt-in behavior;
   - **major** — breaking change for consumers of the published artifact.

   Show a short proposal and **stop for the human** — never auto-bump or tag:

   ```
   ▸ RELEASE PROPOSAL
     current:  <tagPrefix><X.Y.Z>
     proposed: <tagPrefix><X'.Y'.Z'>  (<patch|minor|major>)
     why:      <1–2 sentences from THIS sprint's diff — capability added, fix only, or break>
     publish:  git tag[+ GitHub Release if profile.githubRelease]
   > approve as proposed · change to patch/minor/major · skip release this sprint
   ```

   After the human answers, write `aftercare.release.planFile` (default
   `.metate/release.json`) with the **`Write` tool**:

   ```json
   { "sprint": "<topic>",
     "current": "<tagPrefix><X.Y.Z>",
     "proposed": "<tagPrefix><X'.Y'.Z'>",
     "bump": "patch|minor|major",
     "rationale": "…",
     "githubRelease": true,
     "status": "approved",
     "mergeCommit": null }
   ```

   `status` is `approved` | `skipped`. If they pick a different bump class, **recompute**
   `proposed` from `current` + the new `bump` (SemVer rules + `tagPrefix`) and confirm once
   more before writing. `proposed` must always equal that recomputation — ship will reject
   mismatches. Leave `mergeCommit` null; ship fills it after merge.

   The published artifact for tag-only repos is the **git tag**. Do **not** modify
   package manifests or other version files from aftercare.

   Name the planned tag in the handoff / roadmap entry so discover sees it next cycle.
   Ship is the only stage that creates the tag / GitHub Release — and only after merge,
   with a second confirmation.
6. **Post-sync command** — if `aftercare.postCommand` is set, run it from the repo root
   after the deliverables are updated and report its result (e.g. metate itself uses
   `bash install.sh --user` so the installed skills never drift from the repo).
7. **Commit the deliverables** — commit them on the branch (e.g.
   `docs(aftercare): sprint N close-out`, following `ship.commitStyle` if set). Ship
   expects a clean working tree; it restructures commits anyway, so this commit is
   cheap and never final. Do **not** commit `planFile` (gitignored sprint-local state).

## Output
List the deliverables updated and the one-line change to each, plus the release decision
(`approved` → planned tag, `skipped`, or `n/a` when release is disabled). They are
committed on the branch (step 6) and ship in the sprint PR (never direct to the base
branch). The roadmap, next-sprint pointers, and triggered debt written here are the
**primary input to the next cycle's `metate-discover`** — write them as decisions, not
vague notes. Hand off to `metate-ship`.
