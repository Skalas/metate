#!/usr/bin/env bash
# Resolve where metate keeps its state (ADR-0003 phase 2).
#
# State lives OFF the repo, under ~/.metate/repos/<repo-key>/, so a repo carries no
# metate files at all and two worktrees can run two sprints without colliding.
#
#   state.sh key                 print <repo-key>
#   state.sh repo-dir            print (and create) the repo-scoped dir
#   state.sh sprint-dir          print (and create) the dir for THIS worktree's sprint
#   state.sh where               human-readable summary — state is invisible to `git status`
#   state.sh migrate [root]      move a legacy in-repo .metate/ into the new layout
#
# Two keys, because they answer different questions:
#   repo-key    from `origin`, so every worktree AND every clone of a project agree.
#               ssh and https URLs for the same repo MUST resolve identically.
#   sprint-key  the current branch. Git refuses one branch in two worktrees, so this
#               is collision-free by construction.
set -euo pipefail

ROOT_DIR="${METATE_STATE_ROOT:-$HOME/.metate}"

die() { echo "state.sh: $*" >&2; exit 1; }

# Slugify to one path segment: keep [A-Za-z0-9._-], collapse the rest to '-'.
slug() { printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '-' | sed -E 's/-+/-/g; s/^-|-$//g'; }

# Stable short digest, using the git we already require.
digest() { printf '%s' "$1" | git hash-object --stdin | cut -c1-12; }

# The main worktree's path — shared by every linked worktree, so a remote-less repo
# still gets ONE repo-key across all of its worktrees.
main_worktree() {
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  case "$common" in
    */.git) dirname "$common" ;;
    *) printf '%s' "$common" ;;   # bare repo: the git dir itself
  esac
}

repo_key() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$url" ]; then
    # Normalize so git@host:owner/repo.git and https://host/owner/repo.git agree.
    url="${url%.git}"; url="${url%/}"
    url="${url#ssh://}"; url="${url#git://}"; url="${url#https://}"; url="${url#http://}"
    url="${url#*@}"                 # drop user@ / credentials
    url="$(printf '%s' "$url" | sed 's/:/\//')"   # scp-style host:path -> host/path
    slug "$url"
    return 0
  fi
  local main; main="$(main_worktree)" || die "not a git repository"
  printf 'path-%s' "$(digest "$main")"
}

sprint_key() {
  local branch
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [ -n "$branch" ]; then slug "$branch"; return 0; fi
  printf 'detached-%s' "$(digest "$(pwd)")"      # no branch: keep this worktree separate
}

repo_dir() { local d; d="$ROOT_DIR/repos/$(repo_key)"; mkdir -p "$d"; printf '%s' "$d"; }
sprint_dir() { local d; d="$(repo_dir)/sprints/$(sprint_key)"; mkdir -p "$d"; printf '%s' "$d"; }

# Files that belong to ONE sprint; everything else under .metate/ is repo-scoped.
is_sprint_file() {
  case "$1" in
    plan.md|dod.json|session.json|release.json|.session-start.json) return 0 ;;
    *) return 1 ;;
  esac
}

where() {
  local rd sd
  rd="$(repo_dir)"; sd="$(sprint_dir)"
  echo "repo-key    $(repo_key)"
  echo "sprint-key  $(sprint_key)"
  echo "repo dir    $rd"
  echo "sprint dir  $sd"
  echo "sprint files $(find "$sd" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
  echo "repo files   $(find "$rd" -maxdepth 1 -type f -exec basename {} \; 2>/dev/null | sort | tr '\n' ' ')"
}

# Move a legacy in-repo .metate/ into the new layout. Never clobbers: an existing
# destination file is left alone and the source is reported, not deleted.
migrate() {
  local root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  local legacy="$root/.metate"
  [ -d "$legacy" ] || { echo "  ✓ no legacy .metate/ in $root"; return 0; }
  local rd sd moved=0 kept=0
  rd="$(repo_dir)"; sd="$(sprint_dir)"
  local f name dest
  for f in "$legacy"/* "$legacy"/.session-start.json; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if is_sprint_file "$name"; then dest="$sd/$name"; else dest="$rd/$name"; fi
    if [ -e "$dest" ]; then
      echo "  • $name already present at destination — left in place, source kept"
      kept=$((kept + 1))
    else
      mv "$f" "$dest"
      moved=$((moved + 1))
    fi
  done
  echo "  ✓ moved $moved file(s) out of $legacy"
  [ "$kept" -eq 0 ] && rmdir "$legacy" 2>/dev/null && echo "  ✓ removed empty $legacy"
  return 0
}

case "${1:-}" in
  key)        repo_key; echo ;;
  repo-dir)   repo_dir; echo ;;
  sprint-dir) sprint_dir; echo ;;
  where)      where ;;
  migrate)    shift; migrate "${1:-}" ;;
  *) die "usage: state.sh {key|repo-dir|sprint-dir|where|migrate [root]}" ;;
esac
