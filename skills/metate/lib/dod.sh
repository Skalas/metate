#!/usr/bin/env bash
# dod.sh — jq+bash validators for dod.json and human-gates.json (paths from state.sh).
# Shipped beside the metate skill; start runs it on write, verify and ship on read.
#
#   dod.sh dod   FILE
#   dod.sh gates FILE [CURRENT_SPRINT]   # CURRENT_SPRINT entries need type/steps/expected
#   dod.sh migrate DIR                   # issues.json + smoke-matrix.json → dod.json
#   dod.sh receipt FILE [BASE_BRANCH]    # (BASE defaults to profile start.baseBranch, else main)
#                                        # forensic receipt: fails closed unless the final
#                                        # review round certifies THIS code tree (ADR-0005)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
die() { echo "dod.sh: $*" >&2; exit 1; }
cmd="${1:-}"
shift || true

validate_dod() {
  local file="$1"
  [ -f "$file" ] || die "missing $file"
  jq -e '
    . as $doc
    | if (.sprint|type) != "string" or (.sprint|length) == 0 then error("sprint missing") else . end
    | if (.rows|type) != "array" then error("rows[] missing") else . end
    | if (keys - ["sprint","rows","rounds"]) != [] then error("stray top-level key") else . end
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
    | ($doc.rounds // []) as $rounds
    | if ($rounds|type) != "array" then error("rounds must be an array") else . end
    | if ($rounds|map(.n)|unique|length) != ($rounds|length) then error("duplicate round n") else . end
    | reduce $rounds[] as $rd (true;
        if ($rd.n|type) != "number" or $rd.n < 1 or ($rd.n|floor) != $rd.n
          then error("round n must be a positive integer") else . end
        | if ($rd.gate != "pass" and $rd.gate != "red" and $rd.gate != "pending")
          then error("round \($rd.n) gate must be pass|red|pending") else . end
        | if ($rd.findings|type) != "array" then error("round \($rd.n) needs findings[]") else . end
        | reduce ("codeTreeSha", "patchId", "baseSha") as $k (.;
            if ($rd|has($k)) and ($rd[$k]|type) != "string"
            then error("round \($rd.n) \($k) must be a string") else . end)
        | reduce ("lenses", "failedLenses") as $k (.;
            if ($rd|has($k)) and (($rd[$k]|type) != "array" or ($rd[$k]|map(type == "string")|all|not))
            then error("round \($rd.n) \($k) must be an array of strings") else . end)
        | if ($rd|has("artifactHashes")) and ($rd.artifactHashes|type) != "object"
          then error("round \($rd.n) artifactHashes must be an object") else . end
        | if ($rd.findings|map(.id)|unique|length) != ($rd.findings|length)
          then error("round \($rd.n) has duplicate finding ids") else . end
        | reduce $rd.findings[] as $f (true;
            if ($f.id|type) != "string" or ($f.id|length) == 0 then error("finding needs id") else . end
            | if ($f.summary|type) != "string" or ($f.summary|length) == 0
              then error("finding \($f.id) needs summary") else . end
            | if ($f|has("consequence")) and ($f.consequence|type) != "string"
              then error("finding \($f.id) consequence must be a string") else . end
            | ($f.bucket // "") as $b
            | if $b != "blocker" and $b != "warning" and $b != "suggestion"
              then error("finding \($f.id) bad bucket") else . end
            | ($f.disposition // "") as $d
            | if $d != "fixed" and $d != "declined" and $d != "deferred" and $d != "open"
              then error("finding \($f.id) bad disposition") else . end
            | if $d == "declined" and (($f.rationale|type) != "string" or ($f.rationale|length) == 0)
              then error("declined finding \($f.id) needs rationale") else . end
          )
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
    echo "dod.sh: not migrated — $unbound row(s) have neither command nor gate. Write the sprint's dod.json binding each T-row to a command or a human gate (metate-start step 7), then delete issues.json / smoke-matrix.json." >&2
    return 0
  fi
}

# The first reason the final round cannot certify the sprint, or "" when it can. A blocker in
# the final round must be declined: one marked fixed was patched AFTER the fan-out, so no
# reviewer ever saw the fix. Earlier rounds may close blockers as fixed — a later round re-reviewed.
receipt_problem() {
  jq -r '
    def unresolved(ok): [.findings[] | select(.bucket == "blocker" and (.disposition | IN(ok) | not))
                         | "\(.id) (\(.disposition))"] | join(", ");
    ((.rounds // []) | sort_by(.n)) as $rounds
    | if ($rounds | length) == 0 then "no review rounds recorded"
      else $rounds[-1] as $last
        | ([$rounds[:-1][] | unresolved("fixed", "declined")] | map(select(. != "")) | join(", ")) as $prior
        | if $last.gate != "pass" then "final round gate is not pass (R\($last.n): \($last.gate))"
          elif (($last.failedLenses // []) | length) > 0
            then "final round has failed lenses: \($last.failedLenses | join(", "))"
          elif (($last.lenses // []) | length) == 0 then "final round ran 0 lenses"
          elif ($last.codeTreeSha // "") == ""
            then "final round is unsealed (no codeTreeSha) — record it with round.sh"
          elif ($last | unresolved("declined")) != ""
            then "final round has blockers that are not declined (a fix needs a re-review round): \($last | unresolved("declined"))"
          elif $prior != "" then "earlier rounds left blockers open or deferred: \($prior)"
          else "" end
      end
  ' "$1"
}

final_round_field() { jq -r --arg k "$2" '(.rounds | sort_by(.n) | .[-1][$k]) // ""' "$1"; }

# Pass when the working tree still IS the reviewed tree, or — only when the merge base moved
# FORWARD (a rebase onto newer upstream, never a rewind) — still carries the reviewed patch.
# Prints how it matched.
receipt_tree_match() {
  local file="$1" base="$2" want_tree want_patch want_base now now_tree now_base
  want_tree="$(final_round_field "$file" codeTreeSha)"
  want_patch="$(final_round_field "$file" patchId)"
  want_base="$(final_round_field "$file" baseSha)"
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "receipt: cannot verify the code tree outside a git worktree"
  now="$(bash "$DIR/round.sh" tree "$base")"
  now_tree="$(jq -r .codeTreeSha <<<"$now")"
  now_base="$(jq -r .baseSha <<<"$now")"
  if [ "$now_tree" = "$want_tree" ]; then echo "codeTreeSha matches"; return 0; fi
  if [ -n "$want_base" ] && [ "$now_base" != "$want_base" ] \
     && git merge-base --is-ancestor "$want_base" "$now_base" 2>/dev/null \
     && [ -n "$want_patch" ] && [ "$(jq -r .patchId <<<"$now")" = "$want_patch" ]; then
    echo "patchId matches (rebased onto $base)"; return 0
  fi
  die "receipt: code tree drifted after final review round (expected $want_tree, got $now_tree)"
}

print_receipt() {  # $1 file, $2 tree-match note
  jq -r --arg match "$2" '
    (.rounds | sort_by(.n)) as $r | $r[-1] as $last
    | def count(b): [.findings[] | select(.bucket == b)] | length;
    "## Forensic Receipt", "",
    "| field | value |", "|---|---|",
    "| Sprint | \(.sprint) |",
    "| Total rounds | \($r | length) |",
    "| Final gate | \($last.gate) |",
    "| Code tree SHA | \($last.codeTreeSha // "—") |",
    "| Patch ID | \($last.patchId // "—") |",
    "| Tree check | \($match) |", "",
    ($r[] | "- R\(.n): gate=\(.gate), lenses=\((.lenses // []) | join(",") | if . == "" then "—" else . end), blockers=\(count("blocker")), warnings=\(count("warning"))"
      + ((.artifactHashes // {}) | to_entries | map("\(.key):\(.value[:12])") | join(",")
         | if . == "" then "" else ", hashes=\(.)" end))
  ' "$1"
}

receipt() {
  local file="$1" base="${2:-}" problem match
  validate_dod "$file" || die "receipt: $file is not a valid dod.json"
  problem="$(receipt_problem "$file")"
  [ -z "$problem" ] || die "receipt: $problem"
  [ -n "$base" ] || base="$(bash "$DIR/round.sh" base)"
  match="$(receipt_tree_match "$file" "$base")"
  print_receipt "$file" "$match"
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
  receipt)
    [ $# -ge 1 ] || die "usage: dod.sh receipt FILE [BASE_BRANCH]"
    receipt "$1" "${2:-}"
    ;;
  *) die "usage: dod.sh dod FILE | gates FILE [SPRINT] | migrate DIR | receipt FILE [BASE]" ;;
esac
