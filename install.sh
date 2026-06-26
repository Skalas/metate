#!/usr/bin/env bash
# Installer for the `corte` pipeline skills.
#
#   ./install.sh --user              install the skills globally (~/.claude/skills),
#                                    then leave a per-project initializer (`corte-init`)
#   ./install.sh --project [PATH]    install the skills into a project's .claude/skills
#                                    AND run the bootstrap for that project right away
#
# Default scope is --user.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/skills"
SCOPE="user"
PROJECT="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --user)    SCOPE="user"; shift ;;
    --project) SCOPE="project"; shift; [ $# -gt 0 ] && [[ "$1" != --* ]] && { PROJECT="$1"; shift; } ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

copy_skills() {  # $1 = destination skills root
  local root="$1"
  mkdir -p "$root"
  for dir in "$SRC"/*/; do
    local name; name="$(basename "$dir")"
    rm -rf "$root/$name"
    cp -R "$dir" "$root/$name"
  done
  [ -f "$root/corte-review/bootstrap.sh" ] && chmod +x "$root/corte-review/bootstrap.sh"
  echo "  ✓ skills → $root/{$(cd "$SRC" && printf '%s,' */ | sed 's:/,:,:g;s:,$::')}"
}

# The bootstrap + profile template ship inside the corte-review skill dir.
BOOTSTRAP_REL="corte-review/bootstrap.sh"

if [ "$SCOPE" = "user" ]; then
  echo "▸ installing corte skills at USER level"
  copy_skills "$HOME/.claude/skills"

  # Leave a per-project initializer on PATH that runs the global bootstrap.
  BIN="$HOME/.local/bin"; mkdir -p "$BIN"
  cat > "$BIN/corte-init" <<'EOF'
#!/usr/bin/env bash
# Per-project initializer for corte (skills installed user-level).
exec bash "$HOME/.claude/skills/corte-review/bootstrap.sh" "$@"
EOF
  chmod +x "$BIN/corte-init"
  echo "  ✓ per-project initializer → $BIN/corte-init"
  echo ""
  echo "Skills are global. In ANY project run:  corte-init"
  echo "(ensure $BIN is on your PATH; otherwise: bash ~/.claude/skills/$BOOTSTRAP_REL)"
else
  echo "▸ installing corte skills into PROJECT: $PROJECT"
  copy_skills "$PROJECT/.claude/skills"
  echo "▸ running bootstrap for this project"
  ( cd "$PROJECT" && bash "$PROJECT/.claude/skills/$BOOTSTRAP_REL" )
fi
