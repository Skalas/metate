#!/usr/bin/env bash
# Per-project bootstrap for the `metate` pipeline.
# Scaffolds .metate/profile.yml (gates autodetected) and updates .gitignore.
# Self-contained: works whether the skills are installed user-level or per-project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/profile.template.yml"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
METATE_DIR="$PROJECT_ROOT/.metate"
PROFILE="$METATE_DIR/profile.yml"

echo "▸ bootstrapping metate in: $PROJECT_ROOT"

# --- detect the fast + ship gates from project tooling ---------------------
fast="echo 'set fastGate in .metate/profile.yml' && false"
ship="$fast"
has_make_verify() { [ -f "$PROJECT_ROOT/Makefile" ] && grep -qE '^verify:' "$PROJECT_ROOT/Makefile"; }

if   [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ]; then
  fast="pnpm lint && pnpm test && pnpm build"
  ship=$(has_make_verify && echo "make verify" || echo "pnpm verify")
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
echo "  detected fastGate: $fast"

# --- write the profile (never clobber an existing one) ---------------------
# Escape chars that are special in a sed replacement (\, &) and our | delimiter.
sed_escape() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }
mkdir -p "$METATE_DIR"
if [ -f "$PROFILE" ]; then
  echo "  ✓ $PROFILE already exists — leaving it untouched"
else
  sed -e "s|__FASTGATE__|$(sed_escape "$fast")|" \
      -e "s|__SHIPGATE__|$(sed_escape "$ship")|" "$TEMPLATE" > "$PROFILE"
  echo "  ✓ wrote $PROFILE"
fi

# --- gitignore the session handoff -----------------------------------------
GI="$PROJECT_ROOT/.gitignore"
if ! { [ -f "$GI" ] && grep -qE '^\.metate/session\.json' "$GI"; }; then
  { echo ""; echo "# metate session handoff"; echo ".metate/session.json"; } >> "$GI"
  echo "  ✓ added .metate/session.json to .gitignore"
fi

cat <<EOF

✓ bootstrap complete. Next:
  1. Edit .metate/profile.yml → reviewFocus (your invariants), implementer, prep/smoke/aftercare/ship.
  2. Run the pipeline ceremonies in Claude Code, in order:
       metate-prep → (build via implementer) → metate-review → metate-smoke → metate-aftercare → metate-ship
  3. Build through the implementer CLI so it writes .metate/session.json (see metate-review/IMPLEMENTERS.md).
EOF
