#!/usr/bin/env bash
# dod.sh — jq+bash validators for .metate/dod.json and .metate/human-gates.json.
# Shipped beside the metate skill; start runs it on write, verify and ship on read.
#
#   dod.sh dod   FILE
#   dod.sh gates FILE [CURRENT_SPRINT]   # CURRENT_SPRINT entries need type/steps/expected
#   dod.sh migrate DIR                   # issues.json + smoke-matrix.json → dod.json
set -euo pipefail

die() { echo "dod.sh: $*" >&2; exit 1; }
cmd="${1:-}"
shift || true

validate_dod() {
  local file="$1"
  [ -f "$file" ] || die "missing $file"
  jq -e '
    if (.sprint|type) != "string" or (.sprint|length) == 0 then error("sprint missing") else . end
    | if (.rows|type) != "array" then error("rows[] missing") else . end
    | if (keys - ["sprint","rows"]) != [] then error("stray top-level key") else . end
    | (.rows|map(.id)|unique|length) as $u
    | if $u != (.rows|length) then error("duplicate or missing id") else . end
    | reduce .rows[] as $r (true;
        if ($r.id|type) != "string" or ($r.id|length) == 0 then error("bad id") else . end
        | if ($r.title|type) != "string" or ($r.title|length) == 0 then error("bad title") else . end
        | ($r.status // "") as $st
        | if $st != "" and $st != "cut" then error("bad status") else . end
        | if $st == "cut" then
            if (($r.reason|type) != "string" or ($r.reason|length) == 0)
              then error("cut needs reason") else . end
          else
            (($r|has("command")) and ($r.command|type)=="string" and ($r.command|length)>0) as $c
            | (($r|has("gate")) and ($r.gate|type)=="string" and ($r.gate|length)>0) as $g
            | if ($c and $g) or (($c|not) and ($g|not))
              then error("row \($r.id) needs exactly one of command or gate") else . end
          end
      )
  ' "$file" >/dev/null
}

validate_gates() {
  local file="$1"
  local current="${2:-}"
  [ -f "$file" ] || die "missing $file"
  jq -e --arg current "$current" '
    def list:
      if type == "object" and (.gates|type) == "array" then .gates
      elif type == "array" then .
      elif type == "object" and (.items|type) == "array" then .items
      else error("gate list missing") end;
    def old_type: . == "ux" or . == "live" or . == "graduation" or . == "other";
    def new_type: . == "judgment" or . == "device" or . == "external" or . == "acceptance";
    (list) as $g
    | if ($g|map(.id)|unique|length) != ($g|length) then error("duplicate id") else . end
    | reduce $g[] as $e (true;
        if ($e|has("id")|not) or ($e|has("title")|not)
            or ($e|has("type")|not) or ($e|has("status")|not)
            or ($e|has("reason")|not) or ($e|has("sprint")|not)
            or ($e|has("date")|not)
          then error("missing key") else . end
        | if ($e.id|type) != "string" or ($e.id|length) == 0 then error("bad id") else . end
        | if ($e.sprint|type) != "string" or ($e.sprint|length) == 0 then error("bad sprint") else . end
        | if $e.status != "open" and $e.status != "approved" and $e.status != "deferred"
          then error("bad status") else . end
        | if $e.status == "deferred" and (($e.reason|type) != "string" or ($e.reason|length) == 0)
          then error("deferred needs reason") else . end
        | ($current != "" and $e.sprint == $current) as $now
        | if $now then
            if ($e.type|new_type|not) then error("bad type") else . end
            | if (($e.steps|type) != "array" or ($e.steps|length) == 0
                  or ($e.steps|map(type=="string" and length>0)|all|not))
              then error("current-sprint gate needs non-empty steps") else . end
            | if (($e.expected|type) != "string" or ($e.expected|length) == 0)
              then error("current-sprint gate needs expected") else . end
          else
            if (($e.type|old_type|not) and ($e.type|new_type|not)) then error("bad type") else . end
          end
      )
  ' "$file" >/dev/null
}

migrate() {
  local dir="$1"
  local issues="$dir/issues.json"
  local matrix="$dir/smoke-matrix.json"
  local out="$dir/dod.json"
  [ -f "$issues" ] || [ -f "$matrix" ] || return 0
  local iss_tmp mat_tmp tmp
  iss_tmp="$(mktemp)"; mat_tmp="$(mktemp)"; tmp="$(mktemp)"
  if [ -f "$issues" ]; then cat "$issues" > "$iss_tmp"; else echo '{}' > "$iss_tmp"; fi
  if [ -f "$matrix" ]; then cat "$matrix" > "$mat_tmp"; else echo '{"rows":[]}' > "$mat_tmp"; fi
  jq -n --slurpfile iss "$iss_tmp" --slurpfile mat "$mat_tmp" '
    (if $iss|length > 0 then $iss[0] else {} end) as $issues
    | (if $mat|length > 0 then $mat[0] else {rows: []} end) as $matrix
    | ($issues.sprint // $matrix.sprint // "") as $sprint
    | ($matrix.rows // []) as $m
    | ($m | map({key: .id, value: .}) | from_entries) as $byid
    | ($issues.issues // []) as $open
    | ($issues.deferred // []) as $cut
    | {
        sprint: $sprint,
        rows: (
          ($open | map(
            . as $r
            | {id: ($r.id|tostring), title: ($r.title // ($r.id|tostring))}
            + (if $r.number then {tracker: ("#" + ($r.number|tostring))} else {} end)
            + (if ($byid[$r.id].command // "") != "" then {command: $byid[$r.id].command} else {} end)
          ))
          + ($cut | map(
            . as $r
            | {id: ($r.id|tostring), title: ($r.title // ($r.id|tostring)),
               status: "cut", reason: (if ($r.reason|type)=="string" and ($r.reason|length)>0 then $r.reason else "cut" end)}
            + (if $r.number then {tracker: ("#" + ($r.number|tostring))} else {} end)
          ))
          + ($m | map(select(.id as $id | ($open + $cut | map(.id) | index($id) | not))
            | {id: .id, title: (.title // .id), command: .command}))
        )
      }
  ' > "$tmp"
  rm -f "$iss_tmp" "$mat_tmp"
  if validate_dod "$tmp" 2>/dev/null; then
    mv "$tmp" "$out"
    rm -f "$issues" "$matrix"
    echo "dod.sh: migrated → $out (sources removed)"
  else
    local unbound
    unbound="$(jq -r '[.rows[]|select(.status!="cut" and (has("command")|not) and (has("gate")|not))]|length' "$tmp")"
    rm -f "$tmp"
    echo "dod.sh: not migrated — $unbound row(s) have neither command nor gate. Write .metate/dod.json binding each T-row to a command or a human gate (metate-start step 7), then delete issues.json / smoke-matrix.json." >&2
    return 0
  fi
}

case "$cmd" in
  dod)
    [ $# -ge 1 ] || die "usage: dod.sh dod FILE"
    validate_dod "$1"
    echo "  ✓ dod $1"
    ;;
  gates)
    [ $# -ge 1 ] || die "usage: dod.sh gates FILE [CURRENT_SPRINT]"
    validate_gates "$1" "${2:-}"
    echo "  ✓ gates $1${2:+ (sprint $2)}"
    ;;
  migrate)
    [ $# -ge 1 ] || die "usage: dod.sh migrate DIR"
    migrate "$1"
    ;;
  *) die "usage: dod.sh dod FILE | gates FILE [SPRINT] | migrate DIR" ;;
esac
