#!/usr/bin/env bash
# yaml.sh — yq-backed readers for metate's small YAML files.
# Scalar values are stripped of surrounding quotes and trailing comments.
# Malformed YAML fails loudly (non-zero + stderr), never a silent empty read.

_yaml_strip() {
  sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
      -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

_yaml_die() {
  echo "yaml.sh: $*" >&2
  exit 1
}

# yq rejects tab indentation; expand only leading-whitespace tabs (not in scalar content).
_yaml_expand_tabs() {
  awk '{
    prefix = ""; rest = $0
    while (match(rest, /^[\t ]/)) {
      c = substr(rest, 1, 1)
      if (c == "\t") prefix = prefix "  "
      else prefix = prefix c
      rest = substr(rest, 2)
    }
    print prefix rest
  }' "$1"
}

_yaml_require_yq() {
  command -v yq >/dev/null 2>&1 || _yaml_die "required tool missing: yq (https://github.com/mikefarah/yq)"
}

# Validate file parses as YAML before any read.
_yaml_validate_file() {
  local file="$1"
  [ -f "$file" ] || _yaml_die "file not found: $file"
  local err
  err="$(_yaml_expand_tabs "$file" | yq eval '.' - 2>&1 >/dev/null)" || _yaml_die "malformed YAML in $file: ${err:-parse error}"
}

# Run yq on expanded input; die with context on failure.
_yaml_run_yq() {
  local file="$1" expr="$2" desc="$3"
  _yaml_require_yq
  _yaml_validate_file "$file"
  local err out
  err="$(mktemp)"
  out="$(_yaml_expand_tabs "$file" | yq eval "$expr" -r - 2>"$err")" || {
    local msg; msg="$(cat "$err")"; rm -f "$err"
    _yaml_die "yq failed $desc on $file ($expr): $msg"
  }
  rm -f "$err"
  printf '%s' "$out"
}

# yq path read; missing keys → empty stdout, malformed file → die.
_yaml_read() {
  local file="$1" path="$2" out
  out="$(_yaml_run_yq "$file" "$path" "reading")"
  case "$out" in
    null|'') return 0 ;;
    *) printf '%s' "$out" ;;
  esac
}

# Top-level scalar: key at column 0.
yaml_scalar() {
  local file="$1" key="$2"
  _yaml_read "$file" ".$key" | head -1 | _yaml_strip
}

# Two-level scalar: parent.child
yaml_nested_scalar() {
  local file="$1" parent="$2" child="$3"
  _yaml_read "$file" ".$parent.$child" | head -1 | _yaml_strip
}

# Three-level scalar: k1.k2.k3
yaml_deep_scalar() {
  local file="$1" k1="$2" k2="$3" k3="$4"
  _yaml_read "$file" ".$k1.$k2.$k3" | head -1 | _yaml_strip
}

# Three-level field: scalar or trailing `|` block.
yaml_deep_field() {
  local file="$1" k1="$2" k2="$3" k3="$4"
  _yaml_read "$file" ".$k1.$k2.$k3"
}

# Block scalar under a top-level `key: |` (body at one indent).
yaml_block() {
  local file="$1" key="$2"
  _yaml_read "$file" ".$key"
}

# Immediate child keys under a top-level section, in document order.
yaml_child_keys() {
  local file="$1" section="$2"
  _yaml_run_yq "$file" ".$section | to_entries | .[].key" "listing keys under $section"
}

# Resolve sources/backends.yml for reviewer-lens enumeration.
backends_manifest_path() {
  local script_dir="${1:-}" root="${2:-}" c
  for c in "${METATE_BACKENDS_MANIFEST:-}" \
           "${root:+$root/sources/backends.yml}" \
           "${script_dir:+$script_dir/../../sources/backends.yml}"; do
    [ -n "$c" ] && [ -f "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# Canonical reviewer lens order (matches sources/backends.yml declaration order).
YAML_REVIEWER_LENS_ORDER=(correctness security elegance)

# Shipped lens ids from generated/lens-prompts/*.txt (basename order).
_yaml_shipped_lens_ids() {
  local dir="$1" f base
  for f in "$dir"/*.txt; do
    [ -f "$f" ] || continue
    base="$(basename "$f" .txt)"
    [ -n "$base" ] && printf '%s\n' "$base"
  done
}

# Assert canonical order covers exactly the shipped .txt set (no silent drops).
_yaml_assert_lens_order() {
  local dir="$1"
  local -a shipped=() canon=("${YAML_REVIEWER_LENS_ORDER[@]}") id
  while IFS= read -r id; do
    [ -n "$id" ] && shipped+=("$id")
  done < <(_yaml_shipped_lens_ids "$dir" | sort)
  if [ "${#shipped[@]}" -eq 0 ]; then
    _yaml_die "no reviewer lens .txt files in $dir (need generated/lens-prompts/*.txt or sources/backends.yml)"
  fi
  if [ "${#shipped[@]}" -ne "${#canon[@]}" ]; then
    _yaml_die "reviewer lens mismatch: shipped ${#shipped[@]} .txt file(s) in $dir, YAML_REVIEWER_LENS_ORDER has ${#canon[@]}"
  fi
  local s c
  s="$(printf '%s\n' "${shipped[@]}")"
  for c in "${canon[@]}"; do
    printf '%s\n' "$s" | grep -qxF "$c" || _yaml_die "reviewer lens '$c' in YAML_REVIEWER_LENS_ORDER has no $dir/${c}.txt"
  done
}

# Reviewer lens ids from backends.yml (manifest order), or generated/*.txt fallback.
reviewer_lenses() {
  local manifest="${1:-}" script_dir="${2:-}" lens dir
  if [ -z "$manifest" ]; then
    manifest="$(backends_manifest_path "$script_dir" "${ROOT:-}")" || true
  fi
  if [ -n "$manifest" ] && [ -f "$manifest" ]; then
    yaml_child_keys "$manifest" reviewers
    return 0
  fi
  dir="${script_dir}/generated/lens-prompts"
  _yaml_assert_lens_order "$dir"
  for lens in "${YAML_REVIEWER_LENS_ORDER[@]}"; do
    [ -f "$dir/${lens}.txt" ] && printf '%s\n' "$lens"
  done
}
