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

## Consequences

- Close-out docs written after the final round do not void the receipt; any code change does.
- Reviewer `rationale` and a decline's `rationale` share one key; `adjudicate` overwrites it on
  decline, so the decline reason is always the stored one.
- The hook depends on the installed skill path; if it disappears the hook warns and allows the
  push (re-run `metate-init`).
