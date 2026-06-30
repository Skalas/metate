# Roadmap

The loop-closing doc: `metate-aftercare` writes the next-sprint pointers here;
`metate-discover` reads it (an `aftercare` signal) to open the next cycle. Write entries as
decisions, not vague notes. Triggered detail lives in [TECH-DEBT.md](./TECH-DEBT.md).

## Done

- **Pluggable orchestrator (sprint `pluggable-orchestrator`, 2026-06-30).** `orchestrator.backend`
  (claude · codex · cursor) independent of the implementer; `ORCHESTRATORS.md` adapter contract;
  `bin/metate` dispatcher; codex-only review pilot validated live (T3·T4·T5). Shipped as a
  **draft stabilization branch** (PR #29) — issues #19–#28 stay open until merge.

## In progress / next (stabilize the codex orchestrator before merging #29)

Ranked by failure-surface, not effort. Each has a trigger in TECH-DEBT.md.

1. **codex MCP (codebase-memory) reachability in headless `-p`.** Today T10 is a documented
   limitation — codex reviewers fall back to grep/Read. Wire `~/.codex/config.toml`
   `[mcp_servers.*]` + the approve path so the Code Discovery clause actually reaches codex.
2. **cursor-as-orchestrator end-to-end.** `bin/metate` `die`s on `cursor` (probe-before-use).
   Wire the `runStage`/`fanOut` blocks and verify a resume round-trips (beta: 30s shell
   timeout, `--approve-mcps`, no `--model auto`).
3. **Deeper injection mitigation on the codex fix-apply step.** The DATA-boundary + cap +
   newline-strip are in; add network-egress denial during `workspace-write` resume and an
   imperative-verb/URL allow-pattern check on findings before handoff.
4. **Broader live validation.** Exercise more diffs and branch-behind scenarios (the merge-base
   anchoring fix), and a clean multi-round convergence on a real feature (not just the sandbox).
5. **Native typed-subagent fan-out (EXPAND).** Map reviewers to `.codex/agents/*.toml` /
   `.cursor/agents/*.md` once those CLIs' fan-out leaves beta — higher fidelity than the
   shell-process baseline.

## Later

- Shared `lib/profile.sh` to collapse the three ad-hoc YAML parsers (DRY; see TECH-DEBT.md).
- Gemini as a verified backend (implementer and/or orchestrator) — currently unverified.
