#!/usr/bin/env bash
# profile.sh — shared readers for .metate/profile.yml (yq-backed via yaml.sh)
# Source from shell scripts:  . "$(dirname "$0")/lib/profile.sh"
#
# discover.sources is canonical; discover.signals is accepted as a legacy alias (T7).
: "${PROFILE:?PROFILE must be set before sourcing profile.sh}"

# Repo root for profile-relative paths (e.g. captures.sh signalsFile). Honors explicit export.
: "${PROFILE_ROOT:=$( (
  _d="$(cd "$(dirname "$PROFILE")" && pwd)"
  git -C "$_d" rev-parse --show-toplevel 2>/dev/null || dirname "$_d"
) )}"

# shellcheck disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/yaml.sh"

prof_scalar() { yaml_scalar "$PROFILE" "$1"; }
prof_nested() { yaml_nested_scalar "$PROFILE" "$1" "$2"; }
prof_block() { yaml_block "$PROFILE" "$1"; }
_prof_discover_scalar() { yaml_deep_scalar "$PROFILE" discover "$1" "$2"; }

# Nested under discover.sources.KEY, falling back to legacy discover.signals.KEY.
prof_discover_toggle() {
  local key="$1" v
  v="$(_prof_discover_scalar sources "$key")"
  if [ -n "$v" ]; then
    printf '%s' "$v"
    return 0
  fi
  _prof_discover_scalar signals "$key"
}
