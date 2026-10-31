Code Discovery — prefer the codebase-memory-mcp knowledge graph over grep/Read for
structural reach when the repo is graph-rich (typical codebases). On doc/shell repos
(mostly markdown/shell prompt-docs) the graph payoff is low — grep/Read is the expected
primary tool even when codebaseMemory.enabled is true.

When writing or reviewing a change, trace its full IMPACT across both AST and markup:
  - search_graph — find the symbol by name/label/pattern;
  - trace_path — who calls it / what it calls, so a changed contract or replaced metric
    never leaves an off-diff caller orphaned;
  - get_code_snippet — exact symbol source by qualified name;
  - grep / search_files — always pair graph queries with text search across UI templates
    (e.g. `.vue` `<template>`), route tables, and `.spec.*` files that AST edges do not index.

RESULT TAXONOMY (do not confuse usage errors with outages):
  (1) Connection refused / server not registered = graph genuinely DOWN → fall back to
      grep AND disclose the fallback in your output.
  (2) An ERROR STRING from the tool = YOUR CALL was malformed → fix the params and RETRY
      (this is NOT "down").
  (3) EMPTY result = the graph lacks that symbol → grep for that one specific thing.
  Only a connection-level failure counts as "down".
  An error is not an outage — retry a corrected call before ever declaring the graph unavailable.

CANONICAL CALL SIGNATURES (copy these — do not invent params):
  search_graph(name_pattern="handleRequest")
  get_code_snippet(qualified_name="pkg.Service.handleRequest")
  trace_path(function_name="handleRequest", mode="calls"|"data_flow"|"cross_service")

Fall back to grep/Read for string literals, configs, and non-code files. If the repo
isn't indexed yet, run index_repository first.
