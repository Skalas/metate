<!-- metate:codebase-memory start -->
## Code Discovery — prefer the knowledge graph

This repo is indexed by **codebase-memory-mcp**. For **structural** code discovery,
prefer its MCP tools over plain grep / file-by-file reading.

Priority for code questions (functions, classes, routes, callers, call chains, impact, dead code):
1. `search_graph` — find symbols by name/label/pattern
2. `trace_path` — who calls X / what X calls (call chains, data flow, cross-service)
3. `get_code_snippet` — exact symbol source by qualified name
4. `query_graph` — Cypher for complex patterns
5. `get_architecture` — high-level project map

Fall back to grep freely for: string literals, error messages, config and non-code
files, or when the graph returns too little. If the repo isn't indexed yet, run
`index_repository` first. Always read a file before editing it.
<!-- metate:codebase-memory end -->

## Dogfooding caveat — do not edit the running review engine

metate reviews itself. When `orchestrator.backend: codex`, the review loop runs
`skills/metate-review/codex-review.sh` — and that same file is part of this repo's diff.
If a review-round blocker targets `codex-review.sh`, **do not edit it while the review loop
is running**: bash reads a script by byte offset, so rewriting the in-flight engine corrupts
the current run (observed: `line NNN: FIX_PROMPT=…: No such file or directory`, exit 127).
Defer any fix to `codex-review.sh` itself to a separate build/fix session, never mid-loop.
This is a metate-on-metate artifact only — in a real target repo the engine lives in the
installed skills dir, outside the reviewed diff, so it never arises.
