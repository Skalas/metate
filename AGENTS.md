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
