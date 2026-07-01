# Roadmap

The loop-closing doc: `metate-aftercare` writes the next-sprint pointers here;
`metate-discover` reads it (an `aftercare` signal) to open the next cycle. Write entries as
decisions, not vague notes. Triggered detail lives in [TECH-DEBT.md](./TECH-DEBT.md).

## Done

- **Codex MCP reachability + review-loop convergence (sprint `stabilize-codex-orchestrator`,
  2026-06-30).** Closed the T10 limitation: headless `codex exec` auto-cancelled MCP tool calls
  (`approvals_reviewer="user"`, no TTY; `approval_policy="never"` covers shell only), so codex
  reviewers silently grepped. Fix (`39df709`): `-c …default_tools_approval_mode="approve"` on the
  reviewer fan-out + implement resume — graph reachable, sandbox intact, verified live. **T5**
  convergence validated on a neutral sandbox (find → resume-fix → gate → done, 2 rounds; resume by
  explicit session id). Issues #35–#38. **Learned:** metate reviewing its *own* engine is degenerate
  (self-edit crash + oscillation) — dogfood-only, see TECH-DEBT. Follow-ups filed: #43 (untracked-file
  review gap), #44 (install.sh piped path). Residual: T6 dedicated branch-behind scenario unexercised.

- **Pluggable orchestrator (sprint `pluggable-orchestrator`, 2026-06-30).** `orchestrator.backend`
  (claude · codex · cursor) independent of the implementer; `ORCHESTRATORS.md` adapter contract;
  `bin/metate` dispatcher; codex-only review pilot validated live (T3·T4·T5). Shipped as a
  **draft stabilization branch** (PR #29) — issues #19–#28 stay open until merge.

## In progress / next (stabilize the codex orchestrator before merging #29)

Ranked by failure-surface, not effort. Each has a trigger in TECH-DEBT.md.
(T10 codex MCP reachability — **done**, see Done above.)

1. **Self-review guard for metate-on-metate.** When codex reviews a diff that includes
   `codex-review.sh` itself, the running engine self-edits → crash, and reviewers oscillate for
   lack of the runStage-writes design context. Exclude the running engine from the fixable set (or
   snapshot-run) + feed that context. (New this sprint; dogfood-only.)
2. **cursor-as-orchestrator end-to-end.** `bin/metate` `die`s on `cursor` (probe-before-use).
   Wire the `runStage`/`fanOut` blocks and verify a resume round-trips (beta: 30s shell
   timeout, `--approve-mcps`, no `--model auto`).
3. **Deeper injection mitigation on the codex fix-apply step.** The DATA-boundary + cap +
   newline-strip are in; add network-egress denial during `workspace-write` resume and an
   imperative-verb/URL allow-pattern check on findings before handoff.
4. **T6 branch-behind dedicated validation.** Merge-base→working-tree anchoring ran and clean
   multi-round convergence is proven (T5); the one unexercised path is a base strictly ahead of
   the feature branch. Plus review-diff must include untracked files (#43).
5. **Native typed-subagent fan-out (EXPAND).** Map reviewers to `.codex/agents/*.toml` /
   `.cursor/agents/*.md` once those CLIs' fan-out leaves beta — higher fidelity than the
   shell-process baseline.

## Later

- Shared `lib/profile.sh` to collapse the three ad-hoc YAML parsers (DRY; see TECH-DEBT.md).
- Gemini as a verified backend (implementer and/or orchestrator) — currently unverified.
