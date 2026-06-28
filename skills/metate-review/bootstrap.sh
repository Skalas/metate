#!/usr/bin/env bash
# Per-project bootstrap for the `metate` pipeline.
# Scaffolds .metate/profile.yml (gates autodetected) and updates .gitignore.
# Self-contained: works whether the skills are installed user-level or per-project.
#
#   bootstrap.sh             create the profile if absent; never touch an existing one
#   bootstrap.sh --update    additionally reconcile an existing profile with the
#                            template — add new keys non-destructively (existing
#                            values and comments are preserved; idempotent)
set -euo pipefail

UPDATE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/profile.template.yml"
RECONCILE="$SCRIPT_DIR/reconcile-profile.awk"
CURSOR_RULE="$SCRIPT_DIR/cursor-rule.mdc"
CODEX_RULE="$SCRIPT_DIR/codex-rule.md"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
METATE_DIR="$PROJECT_ROOT/.metate"
PROFILE="$METATE_DIR/profile.yml"

echo "▸ bootstrapping metate in: $PROJECT_ROOT"

# --- detect the fast + ship gates from project tooling ---------------------
fast="echo 'set fastGate in .metate/profile.yml' && false"
ship="$fast"
has_make_verify() { [ -f "$PROJECT_ROOT/Makefile" ] && grep -qE '^verify:' "$PROJECT_ROOT/Makefile"; }

if   [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ]; then
  fast="pnpm lint && pnpm test && pnpm build"; ship="pnpm verify"
elif [ -f "$PROJECT_ROOT/yarn.lock" ]; then
  fast="yarn lint && yarn test && yarn build"; ship="yarn verify"
elif [ -f "$PROJECT_ROOT/package-lock.json" ]; then
  fast="npm run lint && npm test && npm run build"; ship="npm run verify"
elif [ -f "$PROJECT_ROOT/pyproject.toml" ] || [ -f "$PROJECT_ROOT/requirements.txt" ]; then
  fast="ruff check . && pytest"; ship="ruff check . && mypy . && pytest"
elif [ -f "$PROJECT_ROOT/Cargo.toml" ]; then
  fast="cargo clippy && cargo test && cargo build"; ship="cargo clippy -- -D warnings && cargo test"
elif [ -f "$PROJECT_ROOT/go.mod" ]; then
  fast="go vet ./... && go test ./... && go build ./..."; ship="$fast"
fi
# A `make verify` target is the canonical CI mirror — prefer it for any toolchain.
has_make_verify && ship="make verify"
echo "  detected fastGate: $fast"

# --- write or reconcile the profile ----------------------------------------
# Escape chars that are special in a sed replacement (\, &) and our | delimiter.
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
mkdir -p "$METATE_DIR"

# A template with the detected gates filled in — the source of truth for both a
# fresh write and an --update reconcile (so any added key carries real defaults).
FILLED="$(mktemp)"; MERGED="$(mktemp)"; AWKERR="$(mktemp)"
trap 'rm -f "$FILLED" "$MERGED" "$AWKERR"' EXIT
sed -e "s|__FASTGATE__|$(sed_escape "$fast")|" \
    -e "s|__SHIPGATE__|$(sed_escape "$ship")|" "$TEMPLATE" > "$FILLED"

FRESH=0
if [ ! -s "$PROFILE" ]; then   # missing or empty → fresh write
  cp "$FILLED" "$PROFILE"
  FRESH=1
  echo "  ✓ wrote $PROFILE"
elif [ "$UPDATE" = 1 ]; then
  # Reconcile: added keys go to stdout→$MERGED, the key list to stderr→$AWKERR.
  # Gate the overwrite on awk SUCCEEDING and producing non-empty output, so a
  # reconcile error can never replace a tuned profile with a truncated one.
  if awk -f "$RECONCILE" "$PROFILE" "$FILLED" >"$MERGED" 2>"$AWKERR" && [ -s "$MERGED" ]; then
    if [ -s "$AWKERR" ]; then
      cp "$PROFILE" "$PROFILE.bak"
      cp "$MERGED" "$PROFILE"
      echo "  ✓ reconciled $PROFILE (backup: $PROFILE.bak) — added keys:"
      sed 's/^/      /' "$AWKERR"
      echo "    review the new keys and tune their values."
    else
      echo "  ✓ $PROFILE already up to date — no keys added"
    fi
  else
    echo "  ✗ reconcile failed — $PROFILE left untouched" >&2
    [ -s "$AWKERR" ] && sed 's/^/      /' "$AWKERR" >&2
    exit 1
  fi
else
  echo "  ✓ $PROFILE already exists — leaving it untouched (use --update to reconcile)"
fi

# --- gitignore: per-sprint local state + vendored tooling -------------------
GI="$PROJECT_ROOT/.gitignore"

# Append a gitignore rule once (idempotent), then stop tracking anything it now
# covers that a previous install committed. The pattern doubles as a git pathspec.
gi_ignore_untrack() {  # $1 = pattern, $2 = comment
  local pat="$1" comment="$2"
  if ! { [ -f "$GI" ] && grep -qxF "$pat" "$GI"; }; then
    { echo "# $comment"; echo "$pat"; } >> "$GI"
    echo "  ✓ added $pat to .gitignore"
  fi
  if [ -n "$(git -C "$PROJECT_ROOT" ls-files "$pat" 2>/dev/null)" ]; then
    # Pipe -z straight to xargs — capturing it in $() strips the null separators.
    git -C "$PROJECT_ROOT" ls-files -z "$pat" \
      | xargs -0 git -C "$PROJECT_ROOT" rm -r --cached --quiet -- \
      && echo "  ✓ untracked previously-committed $pat (commit to finish)"
  fi
}

if ! { [ -f "$GI" ] && grep -qE '^\.metate/session\.json' "$GI"; }; then
  { echo ""; echo "# metate session handoff"; echo ".metate/session.json"; } >> "$GI"
  echo "  ✓ added .metate/session.json to .gitignore"
fi
if ! { [ -f "$GI" ] && grep -qE '^\.metate/issues\.json' "$GI"; }; then
  { echo "# metate issue ledger"; echo ".metate/issues.json"; } >> "$GI"
  echo "  ✓ added .metate/issues.json to .gitignore"
fi
if ! { [ -f "$GI" ] && grep -qE '^\.metate/.*\.bak' "$GI"; }; then
  { echo "# metate profile reconcile backups"; echo ".metate/*.bak"; } >> "$GI"
  echo "  ✓ added .metate/*.bak to .gitignore"
fi

# Project-level skill installs are vendored tooling whose source of truth is the
# metate repo — don't track them, or every skill update is noise in this project.
# (.metate/profile.yml stays tracked: it's this project's config.) Skipped for
# user-level installs, where the skills live in ~/.claude/skills, not the project.
compgen -G "$PROJECT_ROOT/.claude/skills/metate-*" >/dev/null 2>&1 \
  && gi_ignore_untrack '.claude/skills/metate-*' 'metate skills are installed tooling (source of truth: metate repo)'

# --- codebase-memory-mcp: detect, configure if present, suggest if not ------
# cbm gives review sub-agents a structural knowledge graph (prefer it over grep).
# Present  → enable it in a freshly-written profile + drop the Cursor rule.
# Absent   → leave codebaseMemory.enabled:false and suggest the install one-liner.
CBM_BIN="$(command -v codebase-memory-mcp 2>/dev/null || true)"
[ -z "$CBM_BIN" ] && [ -x "$HOME/.local/bin/codebase-memory-mcp" ] && CBM_BIN="$HOME/.local/bin/codebase-memory-mcp"

if [ -n "$CBM_BIN" ]; then
  echo "  ✓ codebase-memory-mcp detected: $CBM_BIN"

  # Enable in the profile only on a fresh write — never clobber a tuned value.
  if [ "$FRESH" = 1 ]; then
    # Single `enabled:` key in the template lives under codebaseMemory.
    sed -i.bak 's/^\(  enabled:\)[[:space:]]*false/\1 true/' "$PROFILE" && rm -f "$PROFILE.bak"
    echo "  ✓ set codebaseMemory.enabled: true"
  else
    grep -qE '^\s*enabled:\s*true' "$PROFILE" \
      || echo "  • existing profile left untouched — set codebaseMemory.enabled: true to use the graph"
  fi

  # Drop the Cursor rule (idempotent; only if Cursor is installed, never clobber).
  if [ -d "$HOME/.cursor" ]; then
    RULE_DIR="$PROJECT_ROOT/.cursor/rules"
    RULE_DEST="$RULE_DIR/codebase-memory.mdc"
    if [ -f "$RULE_DEST" ]; then
      echo "  ✓ Cursor rule already present — left untouched"
    elif [ -f "$CURSOR_RULE" ]; then
      mkdir -p "$RULE_DIR"
      cp "$CURSOR_RULE" "$RULE_DEST"
      echo "  ✓ installed Cursor rule: .cursor/rules/codebase-memory.mdc"
    fi
  fi
  # The Cursor rule is a vendored copy of cursor-rule.mdc — ignore (and untrack)
  # it like the skills, so its source of truth stays the metate repo.
  [ -f "$PROJECT_ROOT/.cursor/rules/codebase-memory.mdc" ] \
    && gi_ignore_untrack '.cursor/rules/codebase-memory.mdc' 'codebase-memory Cursor rule is installed tooling (source: metate repo)'

  # Codex has no per-rule dir — it reads AGENTS.md. Inject the same guidance as a
  # managed, marker-delimited block: append once, leave untouched if present.
  # AGENTS.md is shared project content (like CLAUDE.md), so it stays TRACKED.
  if command -v codex >/dev/null 2>&1; then
    AGENTS="$PROJECT_ROOT/AGENTS.md"
    # Defer to any existing block — ours OR the codebase-memory-mcp installer's
    # (global ~/.codex/AGENTS.md uses the `codebase-memory-mcp:` marker), so a
    # project that already carries either doesn't get duplicate guidance.
    if [ -f "$AGENTS" ] && grep -qE 'metate:codebase-memory|codebase-memory-mcp:' "$AGENTS"; then
      echo "  ✓ Codex AGENTS.md guidance already present — left untouched"
    elif [ -f "$CODEX_RULE" ]; then
      # Separate from existing content with a blank line — but only if the file is
      # already non-empty (the >> below would otherwise create it first).
      [ -s "$AGENTS" ] && echo "" >> "$AGENTS"
      { echo "<!-- metate:codebase-memory start -->"
        cat "$CODEX_RULE"
        echo "<!-- metate:codebase-memory end -->"; } >> "$AGENTS"
      echo "  ✓ added codebase-memory guidance to AGENTS.md (Codex)"
    fi
  fi

  echo "  → index this repo so the graph isn't empty: $CBM_BIN cli index_repository '{\"path\":\"$PROJECT_ROOT\"}'"
else
  echo "  • codebase-memory-mcp not found — review falls back to grep (fine, just slower/coarser)."
  echo "    Install it to give review a structural knowledge graph:"
  echo "      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/main/install.sh | bash"
  echo "    Then re-run this bootstrap to wire it in."
fi

cat <<EOF

✓ bootstrap complete. Next:
  1. Edit .metate/profile.yml → reviewFocus (your invariants), implementer, prep/smoke/aftercare/ship.
  2. Run the pipeline ceremonies in Claude Code, in order:
       metate-prep → (build via implementer) → metate-review → metate-smoke → metate-aftercare → metate-ship
  3. Build through the implementer CLI so it writes .metate/session.json (see metate-review/IMPLEMENTERS.md).
EOF
