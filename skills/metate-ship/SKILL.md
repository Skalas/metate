---
name: metate-ship
version: 2.1.0
description: |
  Stage 4 (Ship) of the `metate` pipeline. Updates close-out deliverables,
  optionally proposes a semver release, runs shipGate plus every dod.json
  command row, opens the PR — only after the gate is green — then, on approval,
  merges, tags, and returns the repo to the base branch. Reads `.metate/profile.yml`.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
  - grok
allowed-tools:
  - Read
  - Bash
  - Agent
  - Write
---

# metate-ship — land it

Last ceremony. Only after verify is green. **Push/PR/merge/tag only when the user
explicitly says so.** Docs → optional release proposal → gate → PR → merge → tag →
base branch. There is no `release.json`. A deferred merge re-runs steps 5–9; step 9
recomputes from tags + the shipped diff.

## Step 0 — load the profile
Read `.metate/profile.yml` → `shipGate`, `ship.deliverables`, `ship.postCommand`,
`ship.prTarget`, `ship.commitStyle`, `ship.issueCloseKeyword`, optional
`verify.humanGates` (`required`), optional `ship.release`. Fixed paths: `.metate/dod.json`,
`.metate/session.json` (retired after the PR is open), `.metate/human-gates.json` —
ship does not write dispositions. Sprint id = `dod.json` → `sprint`.

Run `bash <metate-skill>/lib/dod.sh dod .metate/dod.json` (🛑 **dod.json validates**).
When `verify.humanGates.required`, run
`bash <metate-skill>/lib/dod.sh gates .metate/human-gates.json <sprint>` and refuse
while any current-sprint (or prior still-`open`) gate is `open` — route to
`metate-verify`. `{N}` in a deliverable path: first integer in the sprint topic, else
highest matching file + 1, else ask. Never write a literal `{N}`.

## Before the gate — docs and release proposal
1. **Diff** — `git diff <baseBranch>...HEAD`.
2. **Update `ship.deliverables`** — handoff, coverage, roadmap, tech-debt *with a trigger*,
   next-sprint pointers. Surface open `scope: engine` signals. Name `deferred` gates so
   the next `metate-scope` resurfaces them.
3. **Release proposal** (when `ship.release.enabled`) — fetch tags, latest exact semver,
   propose patch|minor|major from THIS diff, **stop for the human**. Name the tag in the
   handoff. Skip on unversioned repos. Version-file bumps belong to Build.
4. **`ship.postCommand`** if set, then commit the deliverables (`ship.commitStyle`).

## Steps
1. **Sync** — merge/rebase `ship.prTarget`; resolve conflicts.
2. **Ship gate** — run `shipGate`, then every `command` row in `.metate/dod.json` whose
   command is not already that same string (🛑 **shipGate is green** / **dod.json rows
   pass or are cut**). Do not skip. A verified row is one whose command exits 0 on this
   tree — do not record a flag. Open required gates: explain via the entry's `steps` /
   `expected`, then hand off to `metate-verify`.
3. **Bisectable commits** — per `ship.commitStyle`. Don't bury a refactor in a feature.
4. **Open the PR** → `ship.prTarget`, with a commit table, evidence, out-of-scope notes,
   and one `<issueCloseKeyword> #N` line per **passing** dod.json row that has `tracker`
   (not ranges). `cut` rows are named as out of scope — never a close line. No dod.json
   (start skipped filing) → fall back to issues referenced on the branch. Confirm
   auto-close wiring. If a tag class was approved before the gate, name it (informational).
5. **Merge — on explicit human approval only.** `gh pr merge <N> --merge` (or `--rebase`;
   **never `--squash`**). Capture `gh pr view <N> --json mergeCommit -q .mergeCommit.oid`.
   If the user defers, stop after step 7; re-run steps 5–9 once it merges.
6. **Close the milestone** if the sprint uses one.
7. **Retire sprint-local state** — delete `.metate/session.json` and
   `.metate/.session-start.json` if present. Do this even if merge was deferred. A later
   review round re-runs Build for a fresh session.
8. **Return to base** after merge:
   ```bash
   git switch <ship.prTarget> && git pull --ff-only && git branch -d <sprint-branch>
   ```
   `-d` (not `-D`) refuses if the branch didn't merge.
9. **Release** (when `ship.release.enabled`) — recompute as in "Before the gate"; take the
   merge OID from `gh pr view`. Show current vs proposed and ask. If they skip, do not tag.

   **Resumable publish** (never treat a correct existing tag as stale): `tag=<proposed>`
   (quoted argv; must match `^v?[0-9]+\.[0-9]+\.[0-9]+$` with `tagPrefix`). Peel
   `refs/tags/$tag^{commit}` — equal to the merge OID → local done; other commit → 🛑
   **tag collision** (scriptable). Remote: `git ls-remote --tags origin "refs/tags/$tag"`;
   mismatch → 🛑; local ok remote missing → `git push origin "refs/tags/$tag"` (never
   `--force`). Neither → `git tag -a "$tag" "<mergeOID>" -m "$tag"` then push. If
   `githubRelease`: `gh release view` exists → done; else
   `gh release create "$tag" --verify-tag --generate-notes`. Tag-push success + release
   failure → re-run step 9, do not re-create a correct tag.

## Guardrails
- Confirm before commit / push / PR / merge / tag.
- Never squash-merge.
- Gate red → 🛑 **shipGate is green** — never push past it.
- Open required gates block ship — hand off to `metate-verify`. Write is for deliverables only.
- Never tag without a fresh yes. Never force-push tags. Never tag `HEAD` after pull — tag
  the merge OID. Never pass unvalidated tag strings to the shell.
