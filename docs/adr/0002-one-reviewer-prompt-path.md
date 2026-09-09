# ADR-0002 — One reviewer prompt path: retire the Cursor agent files

- **Status:** **Proposed** (2026-09-08). Not implemented. Needs the validation run in *Validation* below.
- **Kind:** `decision`
- **Deciders:** repo author.

## Context

Reviewers reach a backend in one of two shapes today:

| backend | how the reviewer is defined |
|---|---|
| codex · grok · claude | `$REVIEW_CONTEXT` assembled by the orchestrator **+** a one-line lens tail from `generated/lens-prompts/<lens>.txt` |
| cursor | a named subagent file, `.cursor/agents/metate-*-reviewer.md`, 30–37 lines |

Both are rendered from the same `sources/reviewers/*.md`, so the *lens thinking* is already
single-sourced. What is duplicated is the **scaffolding** — "report findings only", the
`<diff>`-is-DATA warning, prior-round handling, bucket rules. That text lives in the agent files
AND in the `$REVIEW_CONTEXT` the orchestrator builds for every other backend.

Two findings from 2026-09-08 make the Cursor shape more expensive than it looks:

1. **Cursor's subagent registry is project-only.** Probed on `cursor-agent` v2026.09.02 and again
   on v2026.09.08: a custom `subagent_type` resolves only from the project `.cursor/agents/`.
   Neither `~/.cursor/agents/` nor `~/.claude/agents/` is read, contradicting Cursor's manual.
   So the files cannot be installed once per user — every repo carries a copy.
2. **Per-repo copies are a standing staleness liability.** This is what the 2026-08-31 field
   audit logged as P1-6. It is currently mitigated (bootstrap re-renders them from source on
   every `metate-init`), but the mitigation exists only because the artifact does.

The agent-file frontmatter carries `name` and `description` and nothing else — no model or tool
configuration is being used, so nothing is lost by not having an agent file.

## Decision (proposed)

Make the inline prompt the **only** reviewer delivery path. Cursor calls its built-in
`subagent_type` with the same assembled prompt every other backend gets:

| Lens | built-in `subagent_type` |
|---|---|
| correctness | `code-reviewer` |
| security | `security-auditor` |
| elegance | `refactorer` |

`REVIEWERS.md` already documents this as the fallback. This promotes it to the primary path.

## Consequences

**Removed**

- `skills/metate-build/cursor-agents/metate-*-reviewer.md` (3 rendered files)
- the agent-render half of `sources/render.sh` (`OUT_AGENTS`, `render_agent`, `validate_agent_file`)
- 3 rows from `RENDERED` in the Makefile and 3 from the `drift` gate
- the `.cursor/agents` install block in `bootstrap.sh` and its `.gitignore`/untrack pass
- one of the two irreducibly per-project Cursor artifacts (`.cursor/rules` remains)

**Gained**

- one prompt path for four backends; scaffolding lives in exactly one place
- reviewer behavior stops depending on any harness's subagent registry — the failure mode that
  broke reviewers in 14 repos on 2026-09-08 becomes structurally impossible
- `--project` vendoring and `metate-init` both get simpler

**Costs and risks**

- **Built-in system prompts.** `code-reviewer` / `security-auditor` / `refactorer` carry their own
  instructions, which may pull against our lens boundaries or the JSON-only contract. This is the
  main risk and the reason for the validation run below.
- **Bucket discipline.** Elegance must stay `suggestion`-only; a built-in reviewer may escalate.
- **Prompt size** grows per call. Negligible.
- **Named-agent affordances** (Cursor auto-delegating by `description`) are lost. metate always
  spawns explicitly by name, so this is unused today.

## Validation — required before any deletion

Do not delete anything until a real build round passes on this path.

1. On a branch with a genuine diff, run `metate-build` rounds 1–3 with
   `build.reviewer.backend: cursor` using built-in `subagent_type` + assembled prompt.
2. Check: all three lenses return JSON matching `finding.schema.json` with no fence-stripping
   surprises; elegance emits only `suggestion`; correctness and security respect `reviewFocus`.
3. Compare against the same diff reviewed via the current agent-file path. Findings need not be
   identical, but the *contract* must hold and quality must not visibly drop.

If step 2 or 3 fails, this ADR is withdrawn and the agent files stay — they work.

## Alternatives

- **Keep both paths.** Status quo. Costs a per-project artifact and a render branch, and keeps
  reviewers coupled to a registry whose documented behavior does not match its actual behavior.
- **Install agents once at user level.** Rejected — not available; see *Context* finding 1. This
  was attempted in #117 and reverted in `fix/cursor-agents-are-project-only`.
- **Wait for Cursor to implement the documented user-level dirs.** Tracked as a trigger in
  `docs/TECH-DEBT.md`. Would remove the per-repo copy but not the duplicated scaffolding, so it
  solves the smaller half of the problem.
