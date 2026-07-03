#!/usr/bin/env bash
# captures.sh — read-side helpers for signalsFile (tier-1 captures).
# Source after profile.sh (uses prof_scalar and PROFILE_ROOT from profile.sh).

# Resolved absolute path to signalsFile, or empty when unset/blank.
signals_file_path() {
  local rel
  rel="$(prof_scalar signalsFile)"
  [ -n "$rel" ] || return 0
  printf '%s/%s' "${PROFILE_ROOT:-.}" "${rel#./}"
}

# Count open captures. Absent file, empty file, invalid JSON, or no open rows → 0 (not an error).
count_open_captures() {
  local path count
  path="$(signals_file_path)"
  [ -n "$path" ] || { echo 0; return 0; }
  [ -f "$path" ] || { echo 0; return 0; }
  [ -s "$path" ] || { echo 0; return 0; }
  count="$(jq -r '
    if type == "array" then
      [.[] | select((.status // "open") == "open")] | length
    else 0 end
  ' "$path" 2>/dev/null || echo 0)"
  echo "${count:-0}"
}
