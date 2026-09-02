#!/usr/bin/env bash
# yaml.sh — dependency-free, indent-walking readers for metate's small YAML files.
# Scalar values are stripped of surrounding quotes and trailing comments.

_yaml_strip() {
  sed -e 's/[[:space:]]*#.*$//' -e 's/[[:space:]]*$//' \
      -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# Top-level scalar: key at column 0.
yaml_scalar() {
  local file="$1" key="$2"
  sed -n "s/^${key}:[[:space:]]*//p" "$file" | head -1 | _yaml_strip
}

# Two-level scalar: parent at column 0, child one indent level under parent.
yaml_nested_scalar() {
  local file="$1" parent="$2" child="$3"
  awk -v p="^${parent}:" -v c="$child" '
    $0 ~ p { f = 1; next }
    f && /^[^[:space:]]/ { f = 0 }
    f && $0 ~ ("^[[:space:]]+" c ":") {
      sub(/^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*/, ""); print; exit
    }
  ' "$file" | _yaml_strip
}

# Three-level scalar: 0 / 2-space / 4-space keys.
yaml_deep_scalar() {
  local file="$1" k1="$2" k2="$3" k3="$4"
  awk -v s="$k1" -v m="$k2" -v f="$k3" '
    $0 ~ ("^" s ":") { in_s = 1; next }
    in_s && /^[a-z]/ { in_s = 0 }
    in_s && $0 ~ ("^  " m ":") { in_m = 1; next }
    in_m && /^  [a-z]/ && $0 !~ /^    / { in_m = 0 }
    in_m && $0 ~ ("^    " f ":") {
      sub(/^    [^:]+:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit
    }
  ' "$file" | _yaml_strip
}

# Three-level field: scalar or trailing `|` block (content at 6-space indent).
yaml_deep_field() {
  local file="$1" k1="$2" k2="$3" k3="$4"
  awk -v s="$k1" -v m="$k2" -v f="$k3" '
    $0 ~ ("^" s ":") { in_s = 1; next }
    in_s && /^[a-z]/ { in_s = 0 }
    in_s && $0 ~ ("^  " m ":") { in_m = 1; next }
    in_m && /^  [a-z]/ && $0 !~ /^    / { in_m = 0 }
    in_m && $0 ~ ("^    " f ":") {
      if ($0 ~ /\|[[:space:]]*$/) { block = 1; next }
      sub(/^    [^:]+:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit
    }
    block {
      if ($0 == "") { print ""; next }
      if ($0 ~ /^      /) { sub(/^      /, ""); print; next }
      exit
    }
  ' "$file"
}

# Block scalar under a top-level `key: |` (2-space-indented body).
yaml_block() {
  local file="$1" key="$2"
  awk -v k="^${key}:" '
    $0 ~ k { f = 1; next }
    f && /^[^[:space:]]/ { f = 0 }
    f { sub(/^  /, ""); print }
  ' "$file"
}

# Immediate child keys (2-space indent) under a top-level section, in file order.
yaml_child_keys() {
  local file="$1" section="$2"
  awk -v s="^${section}:" '
    $0 ~ s { in_s = 1; next }
    in_s && /^[a-z]/ { exit }
    in_s && /^  [A-Za-z0-9_.-]+:/ {
      line = $0; sub(/^  /, "", line); sub(/:.*/, "", line); print line
    }
  ' "$file"
}
