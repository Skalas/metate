#!/usr/bin/env bash
# Contract checks for human-gates + release-plan prose/schemas.
# Invoked by `make test`. Fixtures under tests/contracts/fixtures/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/tests/contracts/fixtures"
die() { echo "  ✗ contracts: $*" >&2; exit 1; }
ok() { echo "  ✓ $*"; }

# --- structural ordering: prep cuts the branch before seeding the tracked ledger ---
# Anchored on ORDER, not wording. Phrase greps were deleted deliberately: a probe that gutted
# four playbooks to frontmatter + five magic tokens passed all of them green, so they reported
# coverage they did not have. Only checks that survive a rewrite of the surrounding prose belong
# here — grep is this repo's sole enforcement, and a false gate is worse than an absent one.
prep_branch_line="$(grep -n '^\*\*Cut the branch\*\*\|^[0-9]\+\. \*\*Cut the branch\*\*' "$ROOT/skills/metate-start/SKILL.md" | head -1 | cut -d: -f1 || true)"
prep_seed_line="$(grep -n '^\*\*Write DoD and seed gates\*\*\|^[0-9]\+\. \*\*Write DoD and seed gates\|^\*\*Seed human gates\*\*\|^[0-9]\+\. \*\*Seed human gates' "$ROOT/skills/metate-start/SKILL.md" | head -1 | cut -d: -f1 || true)"
[ -n "$prep_branch_line" ] && [ -n "$prep_seed_line" ] \
  && [ "$prep_branch_line" -lt "$prep_seed_line" ] \
  || die "prep must cut the branch before seeding human gates (branch@$prep_branch_line seed@$prep_seed_line)"
ok "prep cuts the branch before seeding human gates"

# --- signal ledger: the live file must satisfy the shipped schema ----------
# additionalProperties:false is only a guarantee if something points it at real data.
validate_signals() {
  local file="$1" expect="$2" # expect: ok | bad
  local err rc
  err="$(jq --argjson allowed \
      "$(jq -c '.properties.signals.items.properties | keys' "$ROOT/skills/metate-verify/signal.schema.json")" \
      --argjson required \
      "$(jq -c '.properties.signals.items.required' "$ROOT/skills/metate-verify/signal.schema.json")" \
      --argjson statuses \
      "$(jq -c '.properties.signals.items.properties.status.enum' "$ROOT/skills/metate-verify/signal.schema.json")" '
    if (.signals|type) != "array" then error("signals[] missing") else . end
    | if (keys - ["signals"]) != [] then error("stray top-level key: \((keys - ["signals"])|join(","))") else . end
    | .signals as $s
    | if ($s|map(.id)|unique|length) != ($s|length) then error("duplicate or missing id") else . end
    | reduce $s[] as $e (true;
          ($required - ($e|keys)) as $missing
        | if $missing != [] then error("missing \($missing|join(","))") else . end
        | (($e|keys) - $allowed) as $extra
        | if $extra != [] then error("unknown key \($extra|join(","))") else . end
        | if $e.attribution == "in-diff" and $e.status == "open"
          then error("in-diff may not be open — fix it in-branch, then record it") else . end
        | if ([$e.status] - $statuses) != []
          then error("bad status \($e.status)") else . end
      )
  ' "$file" 2>&1 >/dev/null)" && rc=0 || rc=$?
  if [ "$expect" = ok ]; then
    [ "$rc" = 0 ] || die "expected valid signals in $(basename "$file"): $err"
  else
    [ "$rc" != 0 ] || die "expected invalid signals in $(basename "$file") to fail"
  fi
}

validate_signals "$FIX/signals-valid.json" ok
validate_signals "$FIX/signals-indiff-open.json" bad
validate_signals "$FIX/signals-unknown-key.json" bad
live_note="fixtures only — no .metate/signals.json in this repo"
if [ -f "$ROOT/.metate/signals.json" ]; then
  validate_signals "$ROOT/.metate/signals.json" ok
  live_note="fixtures + this repo's live signals.json"
fi
ok "signal ledger schema ($live_note)"

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

DOD="$ROOT/skills/metate/lib/dod.sh"
bash "$DOD" dod "$FIX/dod-valid.json" >/dev/null \
  || die "dod-valid.json should pass"
bash "$DOD" dod "$FIX/dod-neither.json" >/dev/null 2>&1 \
  && die "dod-neither.json should fail" || true
bash "$DOD" dod "$FIX/dod-both.json" >/dev/null 2>&1 \
  && die "dod-both.json should fail" || true
ok "dod.json (exactly one of command or gate; cut exempt)"

bash "$DOD" gates "$FIX/human-gates-valid.json" >/dev/null \
  || die "legacy gates should pass without --sprint"
bash "$DOD" gates "$FIX/human-gates-valid.json" s71 >/dev/null \
  || die "legacy gates should grandfather when sprint differs"
bash "$DOD" gates "$FIX/human-gates-valid.json" s60 >/dev/null 2>&1 \
  && die "legacy ux type should fail as current-sprint" || true
bash "$DOD" gates "$FIX/human-gates-current.json" s71 >/dev/null \
  || die "current-sprint judgment+steps+expected should pass"
bash "$DOD" gates "$FIX/human-gates-current-no-steps.json" s71 >/dev/null 2>&1 \
  && die "current-sprint missing steps should fail" || true
ok "gate admission (new types + steps/expected; prior sprints grandfathered)"

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
' "$FIX/release-valid.json" || true)"
[ "$recompute_ok" = ok ] || die "release-valid recompute failed: $recompute_ok"

recompute_bad="$(jq -r '
  def strip: sub("^v"; "");
  def parts: strip | split(".") | map(tonumber);
  . as $p
  | ($p.current | parts) as $c
  | (if $p.bump == "minor" then [$c[0], ($c[1]+1), 0] else error("bad bump") end) as $n
  | ("v" + ($n|map(tostring)|join("."))) as $expect
  | if $p.proposed == $expect then "ok" else "mismatch" end
' "$FIX/release-bad-proposed.json" || true)"
[ "$recompute_bad" = mismatch ] || die "release-bad-proposed should mismatch"
ok "release-plan recompute (valid + mismatch rejected)"

# --- exact semver tag filter (aftercare detection) -------------------------
filtered="$(printf '%s\n' 'v1.4.0' 'v1.5.0-rc.1' 'v1.3.0' 'release-2' 'v2.0.0' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
[ "$filtered" = 'v2.0.0' ] || die "semver filter failed (got $filtered)"
ok "exact semver tag filter excludes prereleases"

# --- nest reviewer:/review: under build: (ADR-0001 move 2a) ---------------
# The python lives in bootstrap.sh --update. Extract and run it on a tiny
# profile so a regression that swallows indented comments or implementer: fails here.
nest_in="$(mktemp)"
cat > "$nest_in" <<'YML'
reviewer:
  backend: claude
  # correctness: codex
implementer:
  backend: cursor
review:
  autoFix: blockers
YML
awk '/^import re, sys$/{p=1} p{print} /^print\("nested"\)$/{exit}' \
  "$ROOT/skills/metate-build/bootstrap.sh" > "$nest_in.py"
python3 "$nest_in.py" "$nest_in" >/dev/null
# shellcheck disable=SC1091
. "$ROOT/skills/metate-build/lib/yaml.sh"
[ "$(yaml_deep_scalar "$nest_in" build reviewer backend)" = claude ] \
  || die "nest: build.reviewer.backend lost"
[ "$(yaml_deep_scalar "$nest_in" build review autoFix)" = blockers ] \
  || die "nest: build.review.autoFix lost"
[ "$(yaml_nested_scalar "$nest_in" implementer backend)" = cursor ] \
  || die "nest: implementer.backend moved or lost"
grep -qE '^[[:space:]]+# correctness: codex' "$nest_in" \
  || die "nest: indented comment under reviewer was dropped"
rm -f "$nest_in" "$nest_in.py"
ok "profile nest reviewer/review under build (values + indented comments kept)"
