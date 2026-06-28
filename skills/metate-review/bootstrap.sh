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

if [ ! -s "$PROFILE" ]; then   # missing or empty → fresh write
  cp "$FILLED" "$PROFILE"
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

# --- gitignore the per-sprint local state ----------------------------------
GI="$PROJECT_ROOT/.gitignore"
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

cat <<EOF

✓ bootstrap complete. Next:
  1. Edit .metate/profile.yml → reviewFocus (your invariants), implementer, prep/smoke/aftercare/ship.
  2. Run the pipeline ceremonies in Claude Code, in order:
       metate-prep → (build via implementer) → metate-review → metate-smoke → metate-aftercare → metate-ship
  3. Build through the implementer CLI so it writes .metate/session.json (see metate-review/IMPLEMENTERS.md).
EOF
