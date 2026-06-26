#!/usr/bin/env bash
# Installer for the three-round-review skill.
#
#   ./install.sh --user              install the engine globally (~/.claude/skills),
#                                    then leave a per-project initializer (`trr-init`)
#   ./install.sh --project [PATH]    install the engine into a project's .claude/skills
#                                    AND run the bootstrap for that project right away
#
# Default scope is --user.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/skills/three-round-review"
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

copy_engine() {  # $1 = destination skills root
  local dest="$1/three-round-review"
  mkdir -p "$dest"
  cp "$SRC"/SKILL.md "$SRC"/IMPLEMENTERS.md "$SRC"/profile.template.yml "$SRC"/bootstrap.sh "$dest/"
  chmod +x "$dest/bootstrap.sh"
  echo "  ✓ engine → $dest"
}

if [ "$SCOPE" = "user" ]; then
  echo "▸ installing engine at USER level"
  copy_engine "$HOME/.claude/skills"

  # Leave a per-project initializer on PATH that runs the global bootstrap.
  BIN="$HOME/.local/bin"; mkdir -p "$BIN"
  cat > "$BIN/trr-init" <<'EOF'
#!/usr/bin/env bash
# Per-project initializer for three-round-review (engine installed user-level).
exec bash "$HOME/.claude/skills/three-round-review/bootstrap.sh" "$@"
EOF
  chmod +x "$BIN/trr-init"
  echo "  ✓ per-project initializer → $BIN/trr-init"
  echo ""
  echo "Engine is global. In ANY project run:  trr-init"
  echo "(ensure $BIN is on your PATH; otherwise run: bash ~/.claude/skills/three-round-review/bootstrap.sh)"
else
  echo "▸ installing engine into PROJECT: $PROJECT"
  copy_engine "$PROJECT/.claude/skills"
  echo "▸ running bootstrap for this project"
  ( cd "$PROJECT" && bash "$PROJECT/.claude/skills/three-round-review/bootstrap.sh" )
fi
