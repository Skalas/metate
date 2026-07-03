#!/usr/bin/env bash
# Render committed harness artifacts from sources/. Idempotent — re-run produces no diff
# when outputs are up to date. Invoked by `make render` and the verify drift gate.
#
#   render.sh                  write all outputs under skills/metate-review/
#   render.sh --list-outputs   print relative output paths (one per line) for Makefile RENDERED
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_ROOT="${RENDER_OUT_ROOT:-$ROOT}"
SRC="$ROOT/sources"
OUT_REVIEW="$RENDER_ROOT/skills/metate-review"
OUT_AGENTS="$OUT_REVIEW/cursor-agents"
OUT_GEN="$OUT_REVIEW/generated"
MANIFEST="$SRC/backends.yml"
VERDICTS_SRC="$SRC/review-loop/verdicts.yml"
EXIT_CRITERIA_SRC="$SRC/review-loop/exit-criteria.md"

# shellcheck disable=SC1091
. "$ROOT/skills/metate-review/lib/yaml.sh"

die() { echo "render: $*" >&2; exit 1; }

manifest_scalar() { yaml_deep_scalar "$MANIFEST" "$1" "$2" "$3"; }
manifest_field() { yaml_deep_field "$MANIFEST" code_discovery "$1" "$2"; }

# agent_file must be a safe basename confined to cursor-agents/.
validate_agent_file() {
  local f="$1"
  [ -n "$f" ] || die "empty agent_file"
  [ "$f" = "$(basename "$f")" ] || die "agent_file must be a bare filename: $f"
  [[ "$f" != *"/"* && "$f" != *".."* ]] || die "unsafe agent_file path: $f"
  case "$f" in
    metate-*-reviewer.md) ;;
    *) die "agent_file must match metate-*-reviewer.md: $f" ;;
  esac
}

list_outputs() {
  local lens agent_file
  printf '%s\n' \
    skills/metate-review/cursor-rule.mdc \
    skills/metate-review/codex-rule.md \
    skills/metate-review/generated/prompt-clause.md \
    skills/metate-review/generated/review-loop-verdict-ids.txt \
    skills/metate-review/generated/exit-criteria.md
  while IFS= read -r lens; do
    [ -n "$lens" ] || continue
    agent_file="$(manifest_scalar reviewers "$lens" agent_file)"
    [ -n "$agent_file" ] || die "missing agent_file for lens $lens"
    printf 'skills/metate-review/cursor-agents/%s\n' "$agent_file"
    printf 'skills/metate-review/generated/lens-prompts/%s.txt\n' "$lens"
  done < <(yaml_child_keys "$MANIFEST" reviewers)
}

render_cursor_rule() {
  local desc title intro fallback
  desc="$(manifest_field cursor_mdc description)"
  title="$(manifest_field cursor_mdc title)"
  intro="$(manifest_field cursor_mdc intro)"
  fallback="$(manifest_field cursor_mdc fallback)"
  {
    echo "---"
    echo "description: $desc"
    echo "alwaysApply: true"
    echo "---"
    echo ""
    echo "$title"
    echo ""
    echo "$intro"
    echo ""
    cat "$SRC/code-discovery/file-rule.md"
    echo ""
    echo "$fallback"
  } > "$OUT_REVIEW/cursor-rule.mdc"
}

render_codex_rule() {
  local title intro fallback
  title="$(manifest_field codex_rule title)"
  intro="$(manifest_field codex_rule intro)"
  fallback="$(manifest_field codex_rule fallback)"
  {
    echo "$title"
    echo ""
    echo "$intro"
    echo ""
    cat "$SRC/code-discovery/file-rule.md"
    echo ""
    echo "$fallback"
  } > "$OUT_REVIEW/codex-rule.md"
}

render_prompt_clause() {
  mkdir -p "$OUT_GEN"
  cp "$SRC/code-discovery/prompt-clause.md" "$OUT_GEN/prompt-clause.md"
}

render_reviewer_agent() {
  local lens="$1"
  local name desc role hint agent_file codex_line when_src
  name="$(manifest_scalar reviewers "$lens" name)"
  desc="$(manifest_scalar reviewers "$lens" description)"
  role="$(manifest_scalar reviewers "$lens" role_noun)"
  hint="$(manifest_scalar reviewers "$lens" code_discovery_hint)"
  agent_file="$(manifest_scalar reviewers "$lens" agent_file)"
  codex_line="$(manifest_scalar reviewers "$lens" codex_lens_line)"
  [ -n "$name" ] && [ -n "$agent_file" ] || die "missing reviewer metadata for $lens"
  validate_agent_file "$agent_file"

  when_src="$SRC/reviewers/when-invoked.md"
  [ "$lens" = elegance ] && when_src="$SRC/reviewers/when-invoked-elegance.md"
  hint_esc="$(printf '%s' "$hint" | sed -e 's/\\/\\\\/g' -e 's/[&|]/\\&/g')"
  when_invoked="$(sed "s|__CODE_DISCOVERY_HINT__|${hint_esc}|g" "$when_src")"

  mkdir -p "$OUT_AGENTS" "$OUT_GEN/lens-prompts"
  {
    echo "---"
    echo "name: $name"
    echo "description: >-"
    echo "  $desc"
    echo "readonly: true"
    echo "---"
    echo ""
    echo "You are a **read-only** metate $role reviewer. You never edit files, run"
    echo "write commands, or apply fixes."
    echo ""
    echo "$when_invoked"
    echo ""
    cat "$SRC/reviewers/$lens.md"
  } > "$OUT_AGENTS/$agent_file"

  printf '%s\n' "$codex_line" > "$OUT_GEN/lens-prompts/$lens.txt"
}

render_review_loop() {
  local skill="$OUT_REVIEW/SKILL.md" tmp
  [ -f "$VERDICTS_SRC" ] || die "missing $VERDICTS_SRC"
  [ -f "$EXIT_CRITERIA_SRC" ] || die "missing $EXIT_CRITERIA_SRC"
  mkdir -p "$OUT_GEN"
  yq eval '.verdicts[]' -r "$VERDICTS_SRC" > "$OUT_GEN/review-loop-verdict-ids.txt"
  cp "$EXIT_CRITERIA_SRC" "$OUT_GEN/exit-criteria.md"
  # SKILL.md lives outside the rendered-artifact tree — patch only on in-place render.
  [ "$RENDER_ROOT" = "$ROOT" ] || return 0
  [ -f "$skill" ] || die "missing $skill for exit-criteria render"
  tmp="$(mktemp)"
  awk -v src="$OUT_GEN/exit-criteria.md" '
    BEGIN { in_block=0; done=0 }
    /<!-- metate:exit-criteria start -->/ {
      print; while ((getline line < src) > 0) print line; close(src)
      in_block=1; next
    }
    /<!-- metate:exit-criteria end -->/ { in_block=0; print; done=1; next }
    !in_block { print }
    END { if (!done) { print "render: exit-criteria markers missing in SKILL.md" > "/dev/stderr"; exit 1 } }
  ' "$skill" > "$tmp" && mv "$tmp" "$skill"
}

extract_exit_criteria() {
  local skill="$ROOT/skills/metate-review/SKILL.md"
  [ -f "$skill" ] || die "missing $skill"
  awk '/<!-- metate:exit-criteria start -->/,/<!-- metate:exit-criteria end -->/' "$skill" | sed '1d;$d'
}

if [ "${1:-}" = "--list-outputs" ]; then
  [ -f "$MANIFEST" ] || die "missing $MANIFEST"
  list_outputs
  exit 0
fi

if [ "${1:-}" = "--extract-exit-criteria" ]; then
  extract_exit_criteria
  exit 0
fi

[ -f "$MANIFEST" ] || die "missing $MANIFEST"

mkdir -p "$OUT_GEN/lens-prompts"
render_cursor_rule
render_codex_rule
render_prompt_clause
while IFS= read -r lens; do
  [ -n "$lens" ] || continue
  render_reviewer_agent "$lens"
done < <(yaml_child_keys "$MANIFEST" reviewers)
render_review_loop

echo "render: wrote harness artifacts under skills/metate-review/"
