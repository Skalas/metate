#!/usr/bin/env bash
# Installer for the `metate` pipeline skills.
#
#   ./install.sh --user              install the skills globally (~/.claude/skills),
#                                    then leave a per-project initializer (`metate-init`)
#   ./install.sh --project [PATH]    install the skills into a project's .claude/skills
#                                    AND run the bootstrap for that project right away
#   ./install.sh --update [--user|--project [PATH]]
#                                    refresh installed skills to this version; for
#                                    --project also reconcile the profile with the
#                                    template (add new keys, keep existing values)
#
# Run from a local checkout, or straight from GitHub:
#   curl -fsSL https://raw.githubusercontent.com/Skalas/metate/main/install.sh | bash -s -- --user
#
# Default scope is --user.
set -euo pipefail

REPO_URL="${METATE_REPO:-https://github.com/Skalas/metate.git}"
REPO_REF="${METATE_REF:-main}"
SCOPE="user"
PROJECT="$PWD"
UPDATE=0

# Where do the skills come from? A local checkout if this script sits next to a
# skills/ dir; otherwise we clone from GitHub (so `curl … | bash` works).
SELF="${BASH_SOURCE[0]:-$0}"
SELF_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd || true)"
SRC=""
[ -n "${SELF_DIR:-}" ] && [ -d "$SELF_DIR/skills" ] && SRC="$SELF_DIR/skills"

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    SCOPE="user"; shift ;;
    --project) SCOPE="project"; shift; [ $# -gt 0 ] && [[ "$1" != --* ]] && { PROJECT="$1"; shift; } ;;
    --update)  UPDATE=1; shift ;;
    -h|--help) { [ -r "$SELF" ] && sed -n '2,16p' "$SELF"; } || echo "usage: install.sh [--update] [--user | --project [PATH]]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# No local skills/ → fetch them from GitHub into a temp checkout.
if [ -z "$SRC" ]; then
  command -v git >/dev/null 2>&1 || { echo "git is required to install from GitHub" >&2; exit 1; }
  echo "▸ fetching metate ($REPO_REF) from $REPO_URL"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$TMP/metate" >/dev/null 2>&1 \
    || { echo "clone failed: $REPO_URL ($REPO_REF)" >&2; exit 1; }
  SRC="$TMP/metate/skills"
fi

copy_skills() {  # $1 = destination skills root
  local root="$1"
  mkdir -p "$root"
  for dir in "$SRC"/*/; do
    local name; name="$(basename "$dir")"
    # Intentionally replaces any same-named skill in the destination. All metate
    # skills are `metate-`prefixed, so this only clobbers prior metate installs.
    rm -rf "$root/$name"
    cp -R "$dir" "$root/$name"
  done
  [ -f "$root/metate-review/bootstrap.sh" ] && chmod +x "$root/metate-review/bootstrap.sh"
  echo "  ✓ skills → $root/{$(cd "$SRC" && printf '%s,' */ | sed 's:/,:,:g;s:,$::')}"
}

# The bootstrap + profile template ship inside the metate-review skill dir.
# (bootstrap also gitignores project-level skill installs — see metate-review/bootstrap.sh)
BOOTSTRAP_REL="metate-review/bootstrap.sh"

VERB="installing"; [ "$UPDATE" = 1 ] && VERB="updating"

if [ "$SCOPE" = "user" ]; then
  echo "▸ $VERB metate skills at USER level"
  copy_skills "$HOME/.claude/skills"

  # Leave a per-project initializer on PATH that runs the global bootstrap.
  BIN="$HOME/.local/bin"; mkdir -p "$BIN"
  cat > "$BIN/metate-init" <<'EOF'
#!/usr/bin/env bash
# Per-project initializer for metate (skills installed user-level).
exec bash "$HOME/.claude/skills/metate-review/bootstrap.sh" "$@"
EOF
  chmod +x "$BIN/metate-init"
  echo "  ✓ per-project initializer → $BIN/metate-init"
  echo ""
  if [ "$UPDATE" = 1 ]; then
    echo "Skills updated. In each project, reconcile its profile with:  metate-init --update"
  else
    echo "Skills are global. In ANY project run:  metate-init"
  fi
  echo "(ensure $BIN is on your PATH; otherwise: bash ~/.claude/skills/$BOOTSTRAP_REL)"
else
  echo "▸ $VERB metate skills into PROJECT: $PROJECT"
  copy_skills "$PROJECT/.claude/skills"
  echo "▸ running bootstrap for this project"
  if [ "$UPDATE" = 1 ]; then
    ( cd "$PROJECT" && bash "$PROJECT/.claude/skills/$BOOTSTRAP_REL" --update )
  else
    ( cd "$PROJECT" && bash "$PROJECT/.claude/skills/$BOOTSTRAP_REL" )
  fi
fi
