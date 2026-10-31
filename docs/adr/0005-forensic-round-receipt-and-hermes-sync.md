# ADR-0005 — Forensic round receipt, script-owned rounds, and Hermes sync

- **Status:** Accepted (2026-10-27).
- **Kind:** `decision`
- **Deciders:** repo author.
- **Relates to:** ADR-0003 (off-repo state; `$SPRINT/dod.json` carries `rounds[]`).

## Context

`metate-build` stops at "0 blockers on a fan-out round over the patched tree", but that rule
lived only in prose. `rounds[]` was hand-written by the orchestrator, so nothing tied a recorded
round to the code that was actually reviewed, and nothing stopped a push of code no reviewer saw.
A triple audit found four gaps:

1. Rounds were hand-authored JSON: ids, dispositions and failed lenses were whatever the
   orchestrator typed.
2. Nothing bound a round to a tree — a fix applied after the last fan-out shipped unreviewed.
3. Headless makers received `reviewFocus` only when the orchestrator remembered to paste it,
   through shell strings that evaluate backticks.
4. Hermes loads skills from `~/.hermes/skills/autonomous-ai-agents`, which `install.sh` never
   synced, so Hermes ran stale hand-copied playbooks.

## Decision

**Prose advises; files block.** Each gap gets a deterministic script, tested in
`tests/contracts/validate.sh`.

- **`skills/metate/lib/round.sh`** owns `rounds[]`:
  - `tree [BASE]` → `{"codeTreeSha","patchId","baseSha"}`. `codeTreeSha` is `git write-tree`
    of a temporary index holding the whole working tree (tracked + untracked, not ignored),
    minus `docs/`, `README.md` and `CHANGELOG.md`. **Untracked** files with secret *names*
    (`.env`, `.env.*`, `*.env`, `*.envrc`, `.netrc`, `.npmrc`, `.git-credentials`, `*.pem`,
    `*.key`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`, `id_rsa*`, `id_dsa*`, `id_ecdsa*`,
    `id_ed25519*`, `credentials.json`, `secrets.{json,yml,yaml}`) are never staged, so their
    content is never written to the object store. Tracked files are always hashed whatever
    their name — substring patterns like `*token*` would silently drop real code such as
    `src/token_service.ts` from the receipt. The real index is never touched.
    `baseSha` is the merge base with `BASE` (a plain branch prefers `origin/BASE`); an
    unresolvable merge base fails closed rather than falling back to `HEAD`; `BASE`
    defaults to the profile's `start.baseBranch`, else `main`, for `tree`, `record` and
    `receipt` alike (`round.sh base` prints it). `patchId` is the sha256 of the
    `baseSha..codeTreeSha` code diff taken with `--binary -U3`, with `index` lines deleted
    and the numeric coordinates of `@@` headers blanked (the only things a clean rebase
    moves), or `empty`. Three lines of context anchor every hunk to the code around it — an
    added line moved elsewhere in its file is a different patch — and `--binary` keeps
    binary edits in the digest. An upstream change more than three lines away from a hunk
    still leaves the digest unchanged. It is deliberately not
    `git patch-id`, which ignores whitespace: `rm -rf "$P"/tmp` → `rm -rf "$P" /tmp` or a
    dedented Python line would otherwise survive a rebase as "the reviewed patch".
  - `prompt maker|reviewer OUT [TASK]` assembles `reviewFocus` + the Code Discovery clause +
    the task with `cat`/`printf` only — nothing in them is ever evaluated.
  - `record DOD --round N --gate pass|red|pending --lens NAME:JSON … [--failed-lens NAME]`
    reads raw reviewer reports (`finding.schema.json`), marks a missing/invalid report as a
    failed lens, dedups by `[file, line, summary]`, mints `R<N>-<i>` ids, records
    `codeTreeSha`, `patchId`, `lenses`, `failedLenses` and `artifactHashes` (sha256 per
    report) plus `baseSha`, and writes only after `dod.sh dod` validates the candidate.
    Re-recording a `pending` round keeps its dispositions but is refused once the tree has
    changed — a patched tree is round N+1. A closed round is never rewritten. Closing a
    round with no lenses (`--gate pass|red` only) keeps the `codeTreeSha`/`patchId` it
    *reviewed*. `artifactHashes` are an audit trail, not a replay guard: a byte-identical
    report proves nothing about which tree produced it, so `record` does not pretend to.
  - `adjudicate DOD --round N --id ID --disposition … [--rationale …]` (a decline needs one).
- **`dod.sh receipt FILE [BASE]`** fails closed unless the final round has `gate: pass`, no
  failed lenses, at least one lens, a `codeTreeSha` (an unsealed or hand-written round cannot
  certify anything), and every blocker `declined` — a blocker marked `fixed` in the final round
  was patched after its fan-out, so it needs another round. Blockers in earlier rounds must be
  `fixed` or `declined`. The current tree must match the final `codeTreeSha`; the `patchId`
  fallback applies **only when `baseSha` moved forward** — the recorded `baseSha` must be an
  ancestor of the current one (a real rebase onto newer upstream, never a rewind) — so on an
  unchanged base no tree other than the reviewed one passes. It must run inside the git
  worktree. It prints a Markdown receipt for the PR body, including each round's
  `artifactHashes` (first 12 hex characters per lens). `validate_dod` type-checks the new optional round fields
  (`codeTreeSha`, `patchId`, `baseSha`, `lenses`, `failedLenses`, `artifactHashes`), so older
  ledgers stay schema-valid — they just cannot pass the receipt.
- **`bootstrap.sh`** installs a marker-tagged `pre-push` hook in the git common dir. For every
  ref line git feeds it (deletions and tags aside) it checks both the source branch and the
  destination branch (`git push origin main:feat/x` lands on `feat/x`), resolving each one's
  sprint via `state.sh sprint-dir-of BRANCH`; a branch with a `dod.json` (other than the base) pushes
  only when the pushed sha is the checked-out `HEAD` of that same branch, no code is
  uncommitted, and the receipt passes — the receipt certifies the working tree, so a detached
  HEAD, another branch's checkout, or an uncommitted revert hiding an unreviewed commit is
  blocked. Run with no ref lines, it certifies the current branch. A foreign `pre-push` hook
  is never overwritten. `git push --no-verify` remains the deliberate escape hatch.
- **`install.sh --user`** also syncs `~/.hermes/skills/autonomous-ai-agents` when
  `~/.hermes/skills` exists, removing the legacy `metate-orchestrator` / `loop-engineering`
  copies; `make drift` checks that root too.

- **`ship.sh`** (2026-10-28) carries the receipt through to the merge:
  - `wait-and-merge PR [BASE] [--poll-interval S] [--timeout S]` runs only on a clean tree whose
    `HEAD` is the PR's `headRefOid` and whose receipt passes. It then polls the PR's
    `statusCheckRollup`: a CheckRun counts as green on `SUCCESS|NEUTRAL|SKIPPED`, a StatusContext
    on `SUCCESS`, and anything else that has finished is a failure (exit 1, with check names and
    URLs). When the repo has `.github/workflows/*`, it waits up to 60 s for CheckRuns to
    register. That way a fast external StatusContext cannot merge the PR before Actions has
    reported anything. After the 60 s it asks `gh run list --commit`, and with no runs at all it
    fails closed (`METATE_ALLOW_NO_CHECKS=1` overrides). A head that moves during polling, or a
    `DIRTY|BEHIND|DRAFT` merge state, aborts; a timeout exits 2. The merge is always
    `gh pr merge --merge --match-head-commit <oid>`, never squash and never `--delete-branch`.
    The remote branch is deleted only after GitHub reports `MERGED`, never for a cross-repository
    (fork) PR, and only with `--force-with-lease` at the merged head, so a branch that moved stays. Session files are then
    retired and the checkout returns to base. A linked worktree whose base branch is checked
    out elsewhere detaches at `origin/<base>` instead of switching. Re-running on a merged PR
    only redoes the cleanup.
  - `next-in-pillar [FILE]` reads `docs/pillars.yml`, where indentation defines the structure:
    `  - id:` pillars with `title`/`horizon`/`status`/`description` and `      - id:`
    `exit_invariants` with `description`/`status`. Quotes are stripped before comments, so
    `'M2 (#867)'` keeps its `(#867)`, and `>`/`|` blocks are folded. Values travel as TSV into
    `jq -R`, so quoting cannot break the JSON. It reports the active pillar (falling back to the
    first planned one) with its pending invariants and progress, the completed pillars and the
    next planned one, and `milestoneReadyToClose` — true only when the active pillar has
    invariants and all are `verified`. A pillar status outside `active|planned|completed`, an
    invariant status outside `pending|verified`, or a non-empty file that parses to no pillars (or
    to a pillar with no invariants — usually mis-indentation) fails closed.
  - Profile `ship.autoMerge` routes metate-ship's merge step through `wait-and-merge` without
    asking first. `ship.chainSprints` lets ship continue into scope → start for the next pending
    invariant, lets scope select it without the human's pick, and lets start file issues
    without confirming. Both default to `false`.
- **pre-push deletions**: the hook now marks a ref line as seen before skipping a deletion, so
  `git push origin --delete <branch>` no longer falls through to the no-ref-lines fallback (which
  certified, and could block on, an unrelated current branch).
- **Sprint Scope & Retire Contract (`retires` and `requiredTouches` in `dod.json`):**
  - `dod.json` accepts optional top-level `"retires"` (array of non-empty strings naming deprecated
    symbols/props) and `"requiredTouches"` (array of non-empty strings naming consumer file paths
    that must be migrated).
  - `round.sh prompt` automatically injects `.retires` and `.requiredTouches` from `$SPRINT/dod.json`
    into both `maker` and `reviewer` prompts so neither role can overlook off-diff consumers or keep
    parallel legacy fields.
  - `dod.sh receipt` enforces both arrays mechanically against the certified code tree (`$now_tree`
    vs `$now_base`): any occurrence of a `retires` symbol in the code tree (`git grep -F`, excluding
    `docs/`, `README.md`, `CHANGELOG.md`) or any file in `requiredTouches` absent from
    `git diff --name-only "$now_base" "$now_tree"` aborts the receipt with exit code 1.
- **Full Reviewer Lens Rendering (`sources/render.sh`):**
  - `generated/lens-prompts/<lens>.txt` renders the full per-lens specification
    (`sources/reviewers/<lens>.md`) alongside `materiality.md`, and reviewer rules explicitly treat
    lazy dual-path backwards-compatibility and orphaned sibling consumers as blockers.

## Consequences

- Close-out docs written after the final round do not void the receipt; any code change does.
- Reviewer `rationale` and a decline's `rationale` share one key; `adjudicate` overwrites it on
  decline, so the decline reason is always the stored one.
- The hook depends on the installed skill path; if it disappears the hook warns and allows the
  push (re-run `metate-init`).
- `ship.autoMerge` and `ship.chainSprints` trade the human's merge and pick gates for the receipt
  plus CI. Leave them `false` unless the receipt, the shipGate and CI together are trusted to
  stand in for that review.
