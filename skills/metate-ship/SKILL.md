---
name: metate-ship
version: 2.0.0
description: |
  Stage 4 (Ship) of the `metate` pipeline. Updates close-out deliverables,
  optionally proposes a semver release, restructures the branch into bisectable
  commits, runs the ship gate, opens the PR — only after the gate is green —
  then, on approval, merges, tags, and returns the repo to the base branch.
  Reads `.metate/profile.yml`. Commits/pushes/PRs/merges/tags only on explicit
  user confirmation.
license: MIT
compatibility:
  - claude-code
  - codex
  - cursor
allowed-tools:
  - Read
  - Bash
  - Agent
  - Write
---

# metate-ship — land it

Last ceremony. Only runs after verify is green. **Push/PR/merge/tag only when the
user explicitly says so.** Ship owns the full close-out: docs → optional release
proposal → gate → PR → merge → tag → back to the base branch, so the next cycle's
`metate-scope` starts from a clean, current base. There is no `release.json` —
the proposal is a step in this ceremony, not a file. A deferred merge re-runs
steps 5–9; step 9 recomputes the proposal from tags + the shipped diff.

## Step 0 — load the profile
Read `.metate/profile.yml` → `shipGate`, `ship.deliverables`, `ship.postCommand`,
`ship.prTarget`, `ship.commitStyle`, `ship.issueCloseKeyword`, optional
`verify.humanGates` (`required`), and optional `ship.release`. Fixed-path state:
`.metate/issues.json`, `.metate/session.json` (retired after the PR is open),
`.metate/human-gates.json` — ship honors open required gates but does **not** write
dispositions (`metate-verify` owns those). Identify the current sprint id the same
way verify does.

**`{N}` in a deliverable path** — resolve once (first integer in the sprint topic;
else highest matching file + 1; else ask) and state the value. Never write a literal `{N}`.

## Before the gate — docs and release proposal
1. **Diff** — `git diff <baseBranch>...HEAD`.
2. **Update `ship.deliverables`** — handoff, coverage, roadmap, tech-debt *with a trigger*,
   next-sprint pointers. Surface open `scope: engine` signals (do not change their status).
   Name `deferred` human gates so the next `metate-scope` resurfaces them.
3. **Release proposal** (when `ship.release.enabled`) — fetch tags, take the latest exact
   semver, propose patch|minor|major from THIS diff, **stop for the human**. Name the
   planned tag in the handoff / roadmap. Do not write a plan file. Skip on unversioned
   repos. Version-file bumps belong to Build, not here.
4. **`ship.postCommand`** if set, then commit the deliverables (`ship.commitStyle`).

Then the steps below. After merge, step 9 recomputes the proposal and asks a second yes.

## Steps
1. **Sync** — merge/rebase the latest `ship.prTarget` into the branch; resolve conflicts.
2. **Ship gate** — run `shipGate`. Must be **fully green** before anything is pushed. This
   mirrors CI; do not skip steps. If `verify.humanGates.required` is true, also read the
   human-gates ledger and apply **the same strict entry validation + fail-closed rules as
   verify** (missing/malformed/invalid entry/no current-sprint batch → 🛑 STOP). Block only on
   **current-sprint** items still `status: open`, and on any **prior-sprint** item still
   `open` (those should have been deferred or folded in verify). Explain each blocking gate
   the same way verify does (why / what to do / what approved means) — do not paste a bare
   H1…Hn list — then **route back to `metate-verify`** for disposition.
3. **Bisectable commits** — restructure the branch into commits per `ship.commitStyle`
   (typically one per layer, each compiling alone, dependencies first; conventional +
   scoped). Don't bury a refactor inside a feature commit.
4. **Open the PR** → `ship.prTarget`, with a commit table, verification evidence,
   out-of-scope notes, and one `<issueCloseKeyword> #N` line **per issue** in the body
   (not ranges/lists). Read the numbers from **`.metate/issues.json` → `issues[]` only** — one line per
   entry in that array, so the merge auto-closes every issue start filed; on merge to the
   default branch GitHub closes them automatically. **Never emit a close line for a
   `deferred[]` entry** — that work was cut and its issue must stay open; name the deferred
   ids in the out-of-scope notes instead, so the PR records the cut. If the ledger is absent
   (start skipped filing), fall back to the issues referenced on the branch/PR.
   - **Staleness guard — run before emitting any `<issueCloseKeyword>` line.** The ledger
     at `.metate/issues.json` is per-sprint local state; one left from a *previous* sprint
     would auto-close unrelated issues. **Both** must hold for every entry: (1) the issue is
     still **OPEN** (`gh issue view <N> --json state,title`); (2) the ledger's `sprint`
     matches the work on the branch/diff. If either fails for any entry, treat the ledger as
     **stale** — STOP and ask the user, never wire auto-close from it. (This is what catches
     a skipped start: a ledger that doesn't match the branch is never trusted into a blind
     close.) For **`deferred[]`** the check inverts: a deferred issue that is **CLOSED** is
     the anomaly — someone closed work that was cut. Report it and ask; never emit a close
     line for it either way.
   - Confirm auto-close wiring after creation.
   - If a tag class was approved before the gate, name it in the PR body (informational).
5. **Merge — on explicit human approval only.** Ask. If approved, merge the PR with
   `gh pr merge <N> --merge` (or `--rebase`; **never `--squash`** — it flattens the
   bisectable commits step 3 just built), then verify the ledger issues actually closed.
   Capture the merge commit OID: `gh pr view <N> --json mergeCommit -q .mergeCommit.oid`.
   If the user defers, stop after step 7 and tell them to re-run ship's close-out
   (steps 5–9) once the PR merges — step 9 recomputes the proposal; no file to keep.
6. **Close the milestone** — if the sprint uses one, close it now (it never auto-closes):
   `gh api -X PATCH repos/{owner}/{repo}/milestones/<num> -f state=closed`. If the merge
   was deferred, remind the user instead.
7. **Retire sprint-local state** — once the PR is open and auto-close is confirmed, reset
   the sprint's working files (all gitignored, so nothing to commit), for the same
   staleness reason as step 4:
   - the ledger file at `.metate/issues.json` → `{ "sprint": null, "issues": [] }`;
   - delete `.metate/session.json` and the transient `.metate/.session-start.json` if present.
   Do this even if the merge was deferred — the `<issueCloseKeyword>` lines live in the PR body,
   not the ledger. If a post-PR amendment then needs another review round, re-run Build to mint a
   fresh `.metate/session.json` (the prior session is intentionally retired).
8. **Return to base** — after the merge lands:
   ```bash
   git switch <ship.prTarget> && git pull --ff-only && git branch -d <sprint-branch>
   ```
   This leaves the repo clean and current, ready for the next cycle's `metate-scope`.
   `-d` (not `-D`) is deliberate: it refuses if the branch didn't merge.
9. **Release — on explicit human approval only** (when `ship.release.enabled`). After the
   pull in step 8, **recompute** the proposal the same way "Before the gate" did (fetch
   tags, latest exact semver, patch|minor|major from the shipped diff). Take the merge OID
   from `gh pr view <N> --json mergeCommit -q .mergeCommit.oid` (`git cat-file -t` → `commit`).
   Show current vs proposed (and the OID) and ask. If they skip, do not tag.

   **Resumable publish** (never treat a correct existing tag as stale):
   1. Let `tag=<proposed>` (the just-approved string only; quoted argv, never unquoted
      interpolation into a larger shell string). `proposed` must match
      `^v?[0-9]+\.[0-9]+\.[0-9]+$` with the configured `tagPrefix`.
   2. Resolve the tag's **target commit** with peel syntax:
      `git rev-parse "refs/tags/$tag^{commit}"` when the local ref exists.
      - if that commit equals the merge OID → local tag step is done;
      - if it equals something else → 🛑 STOP (stale / collision).
   3. Check the remote the same way: `git ls-remote --tags origin "refs/tags/$tag"`.
      If remote has the tag, fetch/peel and confirm it matches the merge OID; mismatch → 🛑.
      If local is correct but remote is missing → `git push origin "refs/tags/$tag"`
      (never `--force`).
   4. If neither local nor remote has the tag → create the annotated tag **on that OID**,
      not on whatever HEAD is now:
      `git tag -a "$tag" "<mergeOID>" -m "$tag"` then
      `git push origin "refs/tags/$tag"` (never `--force`).
   5. If `githubRelease` is true:
      - if `gh release view "$tag"` exists → release step done;
      - else `gh release create "$tag" --verify-tag --generate-notes` (or a short body from
        the PR). `--verify-tag` requires the tag to exist on the remote first.
      Tag-push success + release failure → say to re-run step 9 (resume at the release-only
      branch; do not re-create a correct tag).

   If the user declines or defers, say how to re-run step 9 later (it recomputes; no file).

## Guardrails
- Confirm before commit / push / PR / merge / tag. Approval for one is not approval for the next.
- Never squash-merge — it destroys the bisectable history step 3 built.
- If the gate is red, STOP and report — never push past a failing ship gate.
- Never wire auto-close from a stale ledger — run the step 4 staleness guard first.
- Open required human gates block ship — explain them, then hand off to `metate-verify` for
  disposition. Do not write gate dispositions from ship. Write is for deliverables and the
  `.metate/issues.json` reset only.
- Never cut a tag or GitHub Release without a fresh ship-time confirmation. Never force-push
  tags. Never tag `HEAD` after pull — tag the merge OID from `gh pr view` only. Never pass
  unvalidated tag strings to the shell.
