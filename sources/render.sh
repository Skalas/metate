#!/usr/bin/env bash
# Render committed harness artifacts from sources/. Idempotent — re-run produces no diff
# when outputs are up to date. Invoked by `make render` and the verify drift gate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER_ROOT="${RENDER_OUT_ROOT:-$ROOT}"
SRC="$ROOT/sources"
OUT_REVIEW="$RENDER_ROOT/skills/metate-review"
OUT_AGENTS="$OUT_REVIEW/cursor-agents"
OUT_GEN="$OUT_REVIEW/generated"
MANIFEST="$SRC/backends.yml"

# shellcheck disable=SC1091
. "$ROOT/skills/metate-review/lib/yaml.sh"

die() { echo "render: $*" >&2; exit 1; }

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

yaml_nested_scalar() { yaml_deep_scalar "$MANIFEST" "$1" "$2" "$3"; }
yaml_cd_field() { yaml_deep_field "$MANIFEST" code_discovery "$1" "$2"; }

render_cursor_rule() {
  local desc title intro fallback
  desc="$(yaml_cd_field cursor_mdc description)"
  title="$(yaml_cd_field cursor_mdc title)"
  intro="$(yaml_cd_field cursor_mdc intro)"
  fallback="$(yaml_cd_field cursor_mdc fallback)"
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
  title="$(yaml_cd_field codex_rule title)"
  intro="$(yaml_cd_field codex_rule intro)"
  fallback="$(yaml_cd_field codex_rule fallback)"
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
  name="$(yaml_nested_scalar reviewers "$lens" name)"
  desc="$(yaml_nested_scalar reviewers "$lens" description)"
  role="$(yaml_nested_scalar reviewers "$lens" role_noun)"
  hint="$(yaml_nested_scalar reviewers "$lens" code_discovery_hint)"
  agent_file="$(yaml_nested_scalar reviewers "$lens" agent_file)"
  codex_line="$(yaml_nested_scalar reviewers "$lens" codex_lens_line)"
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
    echo "---"
    echo ""
    echo "You are a metate $role reviewer. Report findings only — do not edit files or apply fixes."
    echo ""
    echo "$when_invoked"
    echo ""
    cat "$SRC/reviewers/$lens.md"
  } > "$OUT_AGENTS/$agent_file"

  printf '%s\n' "$codex_line" > "$OUT_GEN/lens-prompts/$lens.txt"
}

[ -f "$MANIFEST" ] || die "missing $MANIFEST"

mkdir -p "$OUT_GEN/lens-prompts"
render_cursor_rule
render_codex_rule
render_prompt_clause
while IFS= read -r lens; do
  [ -n "$lens" ] || continue
  render_reviewer_agent "$lens"
done < <(yaml_child_keys "$MANIFEST" reviewers)

echo "render: wrote harness artifacts under skills/metate-review/"
