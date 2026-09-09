# ADR-0004 — One code-discovery path: retire the file-based rules

- **Status:** **Proposed** (2026-09-08). Not implemented.
- **Kind:** `decision`
- **Deciders:** repo author.
- **Relates to:** same argument as ADR-0002, one layer down; completes the zero-footprint end
  state of ADR-0003.

## Context

Every role metate spawns is told to prefer the `codebase-memory-mcp` knowledge graph over
grep/Read. That guidance is delivered twice:

| backend | how it learns the tool-priority |
|---|---|
| cursor | `.cursor/rules/codebase-memory.mdc` **+** prompt clause |
| codex | `AGENTS.md` block (rendered `codex-rule.md`) **+** prompt clause |
| grok | same `AGENTS.md` block **+** prompt clause |
| claude | **prompt clause only** — `-p` headless does not act on ambient `CLAUDE.md` |
| gemini | prompt clause only |

Read the column: every backend already receives `generated/prompt-clause.md`, and claude proves
the clause is sufficient on its own. The files are a **second delivery of the same content**,
rendered from the same `sources/`.

They are not cheap. **96 of `bootstrap.sh`'s 512 lines — 19%** — exist to install, refresh,
gitignore, untrack and drift-check them, plus two rendered artifacts (`cursor-rule.mdc` 21 lines,
`codex-rule.md` 15) and their render functions.

They are also the reason a repo still needs a bootstrap at all. ADR-0002 removes the Cursor agent
files; ADR-0003 moves state off the repo. These two files are what remains.

## Decision (proposed)

The **prompt clause is the only delivery path.** Reviewers and the implementer receive
`generated/prompt-clause.md` in their prompt, as claude already does. metate stops writing
`.cursor/rules/codebase-memory.mdc` and stops injecting the `AGENTS.md` block.

Ambient guidance for **humans** — a plain Cursor or Codex session with nothing to do with metate —
moves to user level, where it belongs and is written once:

- Codex and Grok: `~/.codex/AGENTS.md`, which already carries it (`bootstrap.sh` defers to it as
  of 2026-09-08) and which `codebase-memory-mcp`'s own installer writes.
- Cursor: a one-time **User Rule** in Cursor's settings. Cursor has no user-level rules *file*
  (verified 2026-09-08), so this step is manual and documented, not installed.

## Consequences

**Removed**

- `skills/metate-build/cursor-rule.mdc` and `codex-rule.md` (2 rendered artifacts) and their
  render functions in `sources/render.sh`
- the rule-install and `AGENTS.md`-inject blocks in `bootstrap.sh` (~96 lines) with their
  `.gitignore`/untrack passes
- 2 rows from `RENDERED` and 2 from the `drift` gate
- the last per-project metate artifact — with ADR-0002 and ADR-0003, a repo holds **nothing**

**Gained**

- one place where the graph guidance lives, so a fix lands once. This matters: the clause already
  carries the RESULT TAXONOMY that stops sub-agents misreading MCP usage errors as outages, and
  that fix currently has to be mirrored into two rendered files.
- `bootstrap.sh` drops below the threshold where it needs to exist as a program

**Costs and risks**

- **Ambient guidance for humans is weaker in Cursor**, since its user-level equivalent is a manual
  settings step rather than an installed file. This is a real regression for non-metate sessions
  in Cursor specifically.
- **Graph usage could fall.** If a file-based rule was doing more work than the clause, the
  implementer may drift back to grep, costing tokens. This is measurable and is the main thing to
  watch in validation.
- **Prompt size** grows slightly on every spawn.

## Validation

1. Run a build round with `implementer.backend: cursor` and the rule file **absent**, and confirm
   from the transcript that the implementer still reaches for `search_graph` / `trace_path` before
   grep.
2. Same for a codex reviewer with no `AGENTS.md` block present.
3. Compare token cost against a run with the files present. A visible increase means the clause is
   weaker than the file, and this ADR is withdrawn or the clause is strengthened first.

## Alternatives

- **Keep both paths.** Status quo: two deliveries of one truth, 19% of bootstrap, and a fix that
  must be mirrored.
- **Drop the prompt clause, keep the files.** Rejected — claude and gemini have no file path, and
  headless claude demonstrably ignores ambient rules.
- **Keep only the `AGENTS.md` block** (drop the Cursor rule). Cheaper half-step: `AGENTS.md` is
  already deferred to the global file, so the per-project inject rarely fires. Worth considering
  if validation shows Cursor specifically needs its rule file.
