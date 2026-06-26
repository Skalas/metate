#!/usr/bin/env bash
# Per-project bootstrap for the `corte` pipeline.
# Scaffolds .corte/profile.yml (gates autodetected) and updates .gitignore.
# Self-contained: works whether the skills are installed user-level or per-project.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/profile.template.yml"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CORTE_DIR="$PROJECT_ROOT/.corte"
PROFILE="$CORTE_DIR/profile.yml"

echo "▸ bootstrapping corte in: $PROJECT_ROOT"

# --- detect the fast + ship gates from project tooling ---------------------
fast="echo 'set fastGate in .corte/profile.yml' && false"
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
mkdir -p "$CORTE_DIR"
if [ -f "$PROFILE" ]; then
  echo "  ✓ $PROFILE already exists — leaving it untouched"
else
  sed -e "s|__FASTGATE__|$(sed_escape "$fast")|" \
      -e "s|__SHIPGATE__|$(sed_escape "$ship")|" "$TEMPLATE" > "$PROFILE"
  echo "  ✓ wrote $PROFILE"
fi

# --- gitignore the session handoff -----------------------------------------
GI="$PROJECT_ROOT/.gitignore"
if ! { [ -f "$GI" ] && grep -qE '^\.corte/session\.json' "$GI"; }; then
  { echo ""; echo "# corte session handoff"; echo ".corte/session.json"; } >> "$GI"
  echo "  ✓ added .corte/session.json to .gitignore"
fi

cat <<EOF

✓ bootstrap complete. Next:
  1. Edit .corte/profile.yml → reviewFocus (your invariants), implementer, prep/smoke/aftercare/ship.
  2. Run the pipeline ceremonies in Claude Code, in order:
       corte-prep → (build via implementer) → corte-review → corte-smoke → corte-aftercare → corte-ship
  3. Build through the implementer CLI so it writes .corte/session.json (see corte-review/IMPLEMENTERS.md).
EOF
