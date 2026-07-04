# Roadmap

The loop-closing doc: `metate-aftercare` writes the next-sprint pointers here;
`metate-discover` reads it (an `aftercare` signal) to open the next cycle. Write entries as
decisions, not vague notes. Triggered detail lives in [TECH-DEBT.md](./TECH-DEBT.md).
Done entries are compressed to their decisions — the full sprint archaeology lives in git
history and PR bodies (pruned 2026-07-03, `polish-bootstrap`).

## Done

- **`polish-bootstrap` (2026-07-03)** — REDUCE polish after the shrink: bootstrap reads the
  profile via shared `lib/yaml.sh`; `reconcile-profile.awk` retired — profile reconciliation is
  wizard prose (metate skill, Step 2b); gate detection moved to the wizard (template ships
  fail-loudly placeholder gates); bootstrap carries a scope contract (deterministic file
  provisioning only — judgment lives in the wizard); TECH-DEBT/ROADMAP ledgers pruned.
  2-round review converged 0 blockers (cursor implementer session, claude reviewer fan-out).
- **`shrink-engine` (2026-07-03, PR #84)** — the great shrink: deleted the headless engine
  (`codex-review.sh`, `bin/metate`, `ORCHESTRATORS.md`, trust/sandbox scaffolding, orphan libs);
  harvested the review loop's hard-won correctness (merge-base→working-tree diff, untracked
  intent-to-add, resume-by-explicit-id, fix-round-requires-verify-round, failed-lens-disqualifies,
  ≤3 rounds + verdicts) into `metate-review/SKILL.md`; reviewer adapters → `REVIEWERS.md`.
  Harness-first + soft-enforce locked in. Net ≈ −1,050 lines. Accepted trade-offs: no
  untrusted-branch safety, no CI/no-agent runner (see TECH-DEBT accepted limitations).
- **`backend-source-unification` (2026-07-03)** — reviewer lenses, the Code Discovery rule body,
  and backend metadata single-sourced under `sources/`, rendered into every per-harness artifact
  via `sources/render.sh`, drift-gated by `make render-check`.
- **`review-write-side` (2026-07-02)** — review persists its survivors: out-of-diff bugs →
  `signalsFile` (signal schema), deferred wants → the tech-debt ledger; reviewer fan-out stays
  read-only, only the orchestrator writes, scoped to the two sinks.
- **`signal-capture-lane` (2026-07-02)** — smoke classifies failures in-diff vs out-of-diff;
  out-of-diff finds are captured to `signalsFile`, not fixed in-branch; discover folds open
  captures into the slate and dispositions them (`promoted`/`invalid`/`wontfix`); discover
  gained `explore` mode (candidates as bets).
- **`engine-hardening` (2026-07-02)** — Cursor reviewer agents `readonly: true`; the Code
  Discovery clause gained the down/bad-query/empty taxonomy + retry-on-usage-error rule +
  canonical call signatures, and the fan-out queries the graph once and passes the slice as
  DATA (the MCP-misuse fix).
- **`cursor-orchestrator` + `codex-native-skills` (2026-07-01)** — cursor IDE Task fan-out with
  project reviewer agents; codex loads the SKILL.md playbooks natively (`$<skill>` picker);
  install targets both `.claude/skills` and `.agents/skills`.
- **`merge-safe-29` (2026-07-01)** — untracked files included in the review diff + the secret
  skip-list; self-review guard; install.sh piped-path fix; backend-agnostic autonomy whitelist.
- **`stabilize-codex-orchestrator` + `pluggable-orchestrator` (2026-06-30)** — codex headless
  MCP reachability (`default_tools_approval_mode`); live codex review pilot (fan-out →
  explicit-id resume → convergence) surfacing 7 defects static review missed; pluggable
  reviewer/implementer backends proven end-to-end.

## Next

The tool is at its target shape (7 stage playbooks + wizard, two adapter tables, per-repo
profile, finding/signal schemas + lens prompts, the sources renderer). Default next move:
**run the full ceremony on real projects** — touch this repo only when triggered debt fires
(see TECH-DEBT.md). Candidates when a metate sprint IS warranted:

1. **Validation residuals** — #37 (disclosed graph-down fallback proof), #40 (branch-behind
   anchoring scenario).
2. **Native typed-subagent fan-out (EXPAND)** — codex `.codex/agents/*.toml` batch fan-out and
   headless `cursor-agent` Task API, once those CLIs stabilize; higher fidelity than the
   shell-process baseline.
3. **Cold-intake triage + hotfix lane** — only if cold bug reports become a recurring need
   (trigger in TECH-DEBT.md).

## Later

- Gemini as a verified backend (reviewer and/or implementer) — currently ⛔ unverified rows in
  the adapter tables; probe before use.
