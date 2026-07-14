#!/usr/bin/env bash
# Contract checks for human-gates + release-plan prose/schemas.
# Invoked by `make test`. Fixtures under tests/contracts/fixtures/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/tests/contracts/fixtures"
die() { echo "  ✗ contracts: $*" >&2; exit 1; }
ok() { echo "  ✓ $*"; }

# --- prose drift: critical MUST phrases still in the skills -----------------
grep -q 'refs/tags/\$tag\^{commit}' "$ROOT/skills/metate-ship/SKILL.md" \
  || grep -q 'refs/tags/\$tag^{commit}' "$ROOT/skills/metate-ship/SKILL.md" \
  || grep -q '^{commit}' "$ROOT/skills/metate-ship/SKILL.md" \
  || die "ship SKILL.md missing annotated-tag peel (^{commit})"
grep -q '\-\-verify-tag' "$ROOT/skills/metate-ship/SKILL.md" \
  || die "ship SKILL.md missing gh release --verify-tag"
grep -q 'zero-gate' "$ROOT/skills/metate-prep/SKILL.md" \
  || die "prep SKILL.md missing zero-gate seed requirement"
grep -q 'Cut the branch' "$ROOT/skills/metate-prep/SKILL.md" \
  || die "prep SKILL.md missing Cut the branch step"
# branch must be cut before seeding tracked ledger
prep_branch_line="$(grep -n '^\*\*Cut the branch\*\*\|^5\. \*\*Cut the branch\*\*' "$ROOT/skills/metate-prep/SKILL.md" | head -1 | cut -d: -f1)"
prep_seed_line="$(grep -n 'Seed human gates' "$ROOT/skills/metate-prep/SKILL.md" | head -1 | cut -d: -f1)"
[ -n "$prep_branch_line" ] && [ -n "$prep_seed_line" ] \
  && [ "$prep_branch_line" -lt "$prep_seed_line" ] \
  || die "prep must cut the branch before seeding human gates (branch@$prep_branch_line seed@$prep_seed_line)"
grep -q 'Strict entry validation' "$ROOT/skills/metate-smoke/SKILL.md" \
  || die "smoke SKILL.md missing strict entry validation"
grep -q 'fetch first' "$ROOT/skills/metate-aftercare/SKILL.md" \
  || die "aftercare SKILL.md missing fetch-first tag detection"
ok "skill prose contracts present (tag peel, zero-gate, branch-before-seed, strict validate, fetch tags)"

# --- human-gates fixture validator (jq) ------------------------------------
validate_gates() {
  local file="$1" expect="$2" # expect: ok | bad
  local err rc
  err="$(jq '
    def list:
      if type == "array" then .
      elif type == "object" and (.gates|type) == "array" then .gates
      elif type == "object" and (.items|type) == "array" then .items
      else error("gate list missing") end;
    (list) as $g
    | ($g | length) as $n
    | ($g | map(.id) | unique | length) as $uids
    | if $uids != $n then error("duplicate id") else . end
    | reduce $g[] as $e (true;
        if ($e|has("id")|not) or ($e|has("title")|not)
            or ($e|has("type")|not) or ($e|has("status")|not)
            or ($e|has("reason")|not) or ($e|has("sprint")|not)
            or ($e|has("date")|not)
          then error("missing key") else . end
        | if ($e.id|type) != "string" or ($e.id|length) == 0 then error("bad id") else . end
        | if ($e.sprint|type) != "string" or ($e.sprint|length) == 0 then error("bad sprint") else . end
        | if ($e.type != "ux" and $e.type != "live" and $e.type != "graduation" and $e.type != "other")
          then error("bad type") else . end
        | if ($e.status != "open" and $e.status != "approved" and $e.status != "deferred")
          then error("bad status") else . end
        | if $e.status == "deferred" and (($e.reason|type) != "string" or ($e.reason|length) == 0)
          then error("deferred needs reason") else . end
      )
  ' "$file" 2>&1 >/dev/null)" && rc=0 || rc=$?
  if [ "$expect" = ok ]; then
    [ "$rc" = 0 ] || die "expected valid gates in $(basename "$file"): $err"
  else
    [ "$rc" != 0 ] || die "expected invalid gates in $(basename "$file") to fail"
  fi
}

validate_gates "$FIX/human-gates-valid.json" ok
validate_gates "$FIX/human-gates-empty.json" ok
validate_gates "$FIX/human-gates-bad-status.json" bad
validate_gates "$FIX/human-gates-deferred-no-reason.json" bad
ok "human-gates fixtures (valid / empty / bad-status / deferred-no-reason)"

# --- release plan: recompute proposed from current + bump ------------------
recompute_ok="$(jq -r '
  def strip: sub("^v"; "");
  def parts: strip | split(".") | map(tonumber);
  . as $p
  | ($p.current | parts) as $c
  | (if $p.bump == "major" then [($c[0]+1), 0, 0]
     elif $p.bump == "minor" then [$c[0], ($c[1]+1), 0]
     elif $p.bump == "patch" then [$c[0], $c[1], ($c[2]+1)]
     else error("bad bump") end) as $n
  | ("v" + ($n|map(tostring)|join("."))) as $expect
  | if $p.proposed == $expect then "ok" else "mismatch:\($p.proposed)!=\($expect)" end
' "$FIX/release-valid.json")"
[ "$recompute_ok" = ok ] || die "release-valid recompute failed: $recompute_ok"

recompute_bad="$(jq -r '
  def strip: sub("^v"; "");
  def parts: strip | split(".") | map(tonumber);
  . as $p
  | ($p.current | parts) as $c
  | (if $p.bump == "minor" then [$c[0], ($c[1]+1), 0] else error("bad bump") end) as $n
  | ("v" + ($n|map(tostring)|join("."))) as $expect
  | if $p.proposed == $expect then "ok" else "mismatch" end
' "$FIX/release-bad-proposed.json")"
[ "$recompute_bad" = mismatch ] || die "release-bad-proposed should mismatch"
ok "release-plan recompute (valid + mismatch rejected)"

# --- exact semver tag filter (aftercare detection) -------------------------
filtered="$(printf '%s\n' 'v1.4.0' 'v1.5.0-rc.1' 'v1.3.0' 'release-2' 'v2.0.0' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)"
[ "$filtered" = 'v2.0.0' ] || die "semver filter failed (got $filtered)"
ok "exact semver tag filter excludes prereleases"
