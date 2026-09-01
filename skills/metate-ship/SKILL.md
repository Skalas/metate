---
name: metate-ship
version: 1.2.0
description: |
  Stage 6 (Ship) of the `metate` pipeline. Restructures the branch into
  bisectable commits, runs the full ship gate, opens the PR with issue
  auto-close wiring — only after the gate is green — then, on approval, merges,
  closes the milestone, optionally cuts an approved semver tag / GitHub Release,
  and returns the repo to the base branch for the next cycle. Reads
  `.metate/profile.yml`. Codebase-agnostic. Commits/pushes/PRs/merges/tags only
  on explicit user confirmation.
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

Last ceremony. Only runs after Review + Smoke are green. **Push/PR/merge/tag only when the
user explicitly says so.** Ship owns the full close-out: once the human approves, it
merges, closes the milestone, optionally publishes the release aftercare proposed, and
returns the repo to the base branch — the next cycle's `metate-discover` starts from a
clean, current base.

## Step 0 — load the profile
Read `.metate/profile.yml` → `shipGate`, `ship.prTarget`, `ship.commitStyle`,
`ship.issueCloseKeyword`, the top-level `issueLedger` (the issues prep filed),
`sessionFile` (retired in step 7), optional `smoke.humanGates` (`ledger`, `required`) —
ship honors open required human gates but does **not** write gate dispositions (smoke
owns those) — and optional `aftercare.release` (`enabled`, `planFile`, `tagPrefix`,
`githubRelease`). If release is enabled, also read the plan file (default
`.metate/release.json`). Identify the **current sprint id** the same way smoke does.

## Steps
1. **Sync** — merge/rebase the latest `ship.prTarget` into the branch; resolve conflicts.
2. **Ship gate** — run `shipGate`. Must be **fully green** before anything is pushed. This
   mirrors CI; do not skip steps. If `smoke.humanGates.required` is true, also read the
   human-gates ledger and apply **the same strict entry validation + fail-closed rules as
   smoke** (missing/malformed/invalid entry/no current-sprint batch → 🛑 STOP). Block only on
   **current-sprint** items still `status: open`, and on any **prior-sprint** item still
   `open` (those should have been deferred or folded in smoke). Explain each blocking gate
   the same way smoke does (why / what to do / what approved means) — do not paste a bare
   H1…Hn list — then **route back to `metate-smoke`** for disposition.
3. **Bisectable commits** — restructure the branch into commits per `ship.commitStyle`
   (typically one per layer, each compiling alone, dependencies first; conventional +
   scoped). Don't bury a refactor inside a feature commit.
4. **Open the PR** → `ship.prTarget`, with a commit table, verification evidence,
   out-of-scope notes, and one `<issueCloseKeyword> #N` line **per issue** in the body
   (not ranges/lists). Read the numbers from **`issueLedger.issues[]` only** — one line per
   entry in that array, so the merge auto-closes every issue prep filed; on merge to the
   default branch GitHub closes them automatically. **Never emit a close line for a
   `deferred[]` entry** — that work was cut and its issue must stay open; name the deferred
   ids in the out-of-scope notes instead, so the PR records the cut. If the ledger is absent
   (prep skipped filing), fall back to the issues referenced on the branch/PR.
   - **Staleness guard — run before emitting any `<issueCloseKeyword>` line.** The ledger
     (the file at `issueLedger`, e.g. `.metate/issues.json`) is per-sprint local state; one
     left from a *previous* sprint would auto-close unrelated issues. **Both** must hold for
     every entry: (1) the issue is still **OPEN** (`gh issue view <N> --json state,title`);
     (2) the ledger's `sprint` matches the work on the branch/diff. If either fails for any
     entry, treat the ledger as **stale** — STOP and ask the user, never wire auto-close from
     it. (This is what catches a skipped prep: a ledger that doesn't match the branch is never
     trusted into a blind close.) For **`deferred[]`** the check inverts: a deferred issue
     that is **CLOSED** is the anomaly — someone closed work that was cut. Report it and ask;
     never emit a close line for it either way.
   - Confirm auto-close wiring after creation.
   - If `aftercare.release.planFile` has `status: approved`, mention the planned tag in the
     PR body (informational — the tag is cut only after merge + a second confirmation).
5. **Merge — on explicit human approval only.** Ask. If approved, merge the PR with
   `gh pr merge <N> --merge` (or `--rebase`; **never `--squash`** — it flattens the
   bisectable commits step 3 just built), then verify the ledger issues actually closed.
   **Capture the merge commit OID** immediately:
   `gh pr view <N> --json mergeCommit -q .mergeCommit.oid` (or the merge commit from
   `gh pr merge`'s result). If release is in play, write that OID into the plan file's
   `mergeCommit` field with the **`Write` tool** (ship may Write **only** to
   `aftercare.release.planFile` for this field and for clearing the plan in step 9).
   If the user defers, stop after step 7 and tell them to re-run ship's close-out
   (steps 5–9) once the PR merges — keep `release.json` if present so the tag can still
   land later.
6. **Close the milestone** — if the sprint uses one, close it now (it never auto-closes):
   `gh api -X PATCH repos/{owner}/{repo}/milestones/<num> -f state=closed`. If the merge
   was deferred, remind the user instead.
7. **Retire sprint-local state** — once the PR is open and auto-close is confirmed, reset the
   sprint's working files (all gitignored, so nothing to commit), for the same staleness reason
   as step 4:
   - the ledger file at `issueLedger` → `{ "sprint": null, "issues": [] }`;
   - delete `sessionFile` and the transient `.metate/.session-start.json` if present;
   - **keep** `aftercare.release.planFile` when `status: approved` — step 9 consumes it;
     clear it only when `status: skipped` or release is disabled.
   Do this even if the merge was deferred — the `<issueCloseKeyword>` lines live in the PR body,
   not the ledger. If a post-PR amendment then needs another review round, re-run Build to mint a
   fresh `sessionFile` (the prior session is intentionally retired).
8. **Return to base** — after the merge lands:
   ```bash
   git switch <ship.prTarget> && git pull --ff-only && git branch -d <sprint-branch>
   ```
   This leaves the repo clean and current, ready for the next cycle's `metate-discover`.
   `-d` (not `-D`) is deliberate: it refuses if the branch didn't merge.
9. **Release — on explicit human approval only** (when `aftercare.release.enabled` and the
   plan file has `status: approved`). Re-read the plan after the pull in step 8.

   **Validate before any shell that interpolates plan fields:**
   - required keys: `sprint`, `current`, `proposed`, `bump`, `status`, `mergeCommit`;
   - `status` is `approved`; `bump` is exactly `patch`|`minor`|`major`;
   - `current` and `proposed` match `^v?[0-9]+\.[0-9]+\.[0-9]+$` (with the configured
     `tagPrefix` if set — typically `v`);
   - **recompute** expected `proposed` from `current` + `bump` (SemVer + prefix); if the
     file's `proposed` ≠ recomputed, 🛑 STOP — do not tag;
   - `mergeCommit` is a 40-char hex OID that exists locally after the pull
     (`git cat-file -t <oid>` → `commit`);
   - `sprint` matches this ship (same staleness idea as the issue ledger).

   Show current vs proposed (and the merge OID) once more and ask. If approved:

   **Resumable publish** (never treat a correct existing tag as stale):
   1. Let `tag=<proposed>` (use the validated string only; pass as a quoted argv, never
      unquoted interpolation into a larger shell string).
   2. Resolve the tag's **target commit** with peel syntax (annotated tags point at a tag
      object — bare `rev-parse refs/tags/$tag` is the wrong comparison):
      `git rev-parse "refs/tags/$tag^{commit}"` when the local ref exists.
      - if that commit equals `mergeCommit` → local tag step is done;
      - if it equals something else → 🛑 STOP (stale / collision).
   3. Check the remote the same way: `git ls-remote --tags origin "refs/tags/$tag"`.
      If remote has the tag, fetch/peel and confirm it matches `mergeCommit`; mismatch → 🛑.
      If local is correct but remote is missing → `git push origin "refs/tags/$tag"`
      (never `--force`).
   4. If neither local nor remote has the tag → create the annotated tag **on that OID**,
      not on whatever HEAD is now:
      `git tag -a "$tag" "$mergeCommit" -m "$tag"` then
      `git push origin "refs/tags/$tag"` (never `--force`).
   5. If `githubRelease` is true:
      - if `gh release view "$tag"` exists → release step done;
      - else `gh release create "$tag" --verify-tag --generate-notes` (or a short body from
        the PR). `--verify-tag` requires the tag to exist on the remote first.
      Tag-push success + release failure → leave the plan file intact and say to re-run
      step 9 (resume at the release-only branch; do not re-create a correct tag).
   6. On full success, clear the plan file to `{ "sprint": null, "status": null }` (or delete).

   If the user declines or defers, leave the plan file and say how to re-run step 9 later.
   If the plan is missing/`skipped`, do not tag — report and move on.

## Guardrails
- Confirm before commit / push / PR / merge / tag. Approval for one is not approval for the next.
- Never squash-merge — it destroys the bisectable history step 3 built.
- If the gate is red, STOP and report — never push past a failing ship gate.
- Never wire auto-close from a stale ledger — run the step 4 staleness guard first.
- Open required human gates block ship — explain them, then hand off to `metate-smoke` for
  disposition. Do not write gate dispositions from ship. Ship may Write only to
  `aftercare.release.planFile` (mergeCommit + clear).
- Never cut a tag or GitHub Release without an aftercare-approved plan **and** a fresh
  ship-time confirmation. Never force-push tags. Never tag `HEAD` after pull — tag the
  recorded `mergeCommit` only. Never pass unvalidated plan fields to the shell.
