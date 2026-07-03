#!/usr/bin/env bash
# trusted-review-text.sh — load reviewer instruction text from a trusted source.
# Source after ROOT, BASE_BRANCH, and die() are set (codex-review.sh).
#
# Touched reviewer-instruction paths (inside merge-base→working-tree review scope)
# must never be read from the working tree or from branch HEAD — only merge-base,
# or a bundled install copy outside the reviewed diff (user-level skills, or
# METATE_TRUSTED_SKILL_ROOT).

_review_diff_touches() {
  local rel="$1" merge_base
  : "${ROOT:?ROOT must be set}"
  : "${BASE_BRANCH:?BASE_BRANCH must be set}"
  merge_base="$(git -C "$ROOT" merge-base "$BASE_BRANCH" HEAD 2>/dev/null || true)"
  if [ -n "$merge_base" ] && ! git -C "$ROOT" diff --quiet "$merge_base" -- "$rel" 2>/dev/null; then
    return 0
  fi
  # Untracked (non-ignored) paths are in review scope the same as merge-base→WT diff.
  git -C "$ROOT" ls-files --others --exclude-standard -- "$rel" | grep -q .
}

_bundled_suffix() {
  case "$1" in
    skills/metate-review/*) printf '%s' "${1#skills/metate-review/}" ;;
    *) die "trusted_review_text: unsupported instruction path: $1" ;;
  esac
}

# If abs_path lies under ROOT, return its repo-relative path; else empty.
_repo_relpath() {
  local abs="$1" root prefix
  root="$(cd "$ROOT" && pwd)"
  abs="$(cd "$(dirname "$abs")" && pwd)/$(basename "$abs")"
  prefix="$root/"
  case "$abs" in
    "$prefix"*) printf '%s' "${abs#"$prefix"}" ;;
    *) printf '' ;;
  esac
}

# Emit bundled file at root/suffix when that copy is not branch-controlled.
_try_bundled_at() {
  local root="$1" suffix="$2" rel="$3" candidate rep
  candidate="$root/$suffix"
  [ -f "$candidate" ] || return 1
  rep="$(_repo_relpath "$candidate")"
  if [ -n "$rep" ] && _review_diff_touches "$rep"; then
    return 1
  fi
  cat "$candidate"
}

_load_trusted_bundled() {
  local rel="$1" suffix root
  suffix="$(_bundled_suffix "$rel")"

  for root in "${METATE_TRUSTED_SKILL_ROOT:-}" \
              "${HOME:+$HOME/.agents/skills/metate-review}" \
              "${HOME:+$HOME/.claude/skills/metate-review}"; do
    [ -n "$root" ] || continue
    if _try_bundled_at "$root" "$suffix" "$rel"; then
      return 0
    fi
  done

  # Script dir is trusted only when it lives outside the repo under review.
  if [ -n "${METATE_REVIEW_SCRIPT_DIR:-}" ]; then
    root="$(cd "$METATE_REVIEW_SCRIPT_DIR" && pwd)"
    case "$root" in
      "$(cd "$ROOT" && pwd)"/*) ;;
      *)
        if _try_bundled_at "$root" "$suffix" "$rel"; then
          return 0
        fi
        ;;
    esac
  fi
  return 1
}

trusted_review_text() {
  local rel="$1"
  local merge_base
  local wt="$ROOT/$rel"
  : "${ROOT:?ROOT must be set}"
  : "${BASE_BRANCH:?BASE_BRANCH must be set}"
  [ -n "$rel" ] || die "trusted_review_text: empty path"
  case "$rel" in
    ../*|*/../*|/*) die "trusted_review_text: unsafe path: $rel" ;;
  esac

  if _review_diff_touches "$rel"; then
    merge_base="$(git -C "$ROOT" merge-base "$BASE_BRANCH" HEAD 2>/dev/null || true)"
    if [ -n "$merge_base" ] && git -C "$ROOT" cat-file -e "$merge_base:$rel" 2>/dev/null; then
      git -C "$ROOT" show "$merge_base:$rel"
      return 0
    fi
    if _load_trusted_bundled "$rel"; then
      return 0
    fi
    die "reviewer instruction $rel is in the review diff but has no trusted revision (missing at merge-base; install metate user-level or set METATE_TRUSTED_SKILL_ROOT)"
  fi

  [ -f "$wt" ] || die "missing reviewer instruction file: $rel (run make render)"
  cat "$wt"
}
