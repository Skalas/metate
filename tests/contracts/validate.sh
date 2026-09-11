#!/usr/bin/env bash
# Contract checks for human-gates + release-plan prose/schemas.
# Invoked by `make test`. Fixtures under tests/contracts/fixtures/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIX="$ROOT/tests/contracts/fixtures"
die() { echo "  ✗ contracts: $*" >&2; exit 1; }
ok() { echo "  ✓ $*"; }

# --- Doc-as-Code: contracts and their documentation ship in the same diff ---
# Compare the merge base to the tracked working tree (committed + index + unstaged).
# Disable rename detection so moving a contract away still counts as a deletion.
validate_doc_as_code() {
  local repo="$1" base="$2" ancestor paths path contract=0 docs=0
  ancestor="$(git -C "$repo" merge-base "$base" HEAD)" || return 1
  paths="$(mktemp)" || return 1
  if ! git -C "$repo" diff --no-renames --name-only -z "$ancestor" -- > "$paths"; then
    rm -f "$paths"
    return 1
  fi
  while IFS= read -r -d '' path; do
    case "$path" in
      *.schema.json|profile.template.yml|*/profile.template.yml|sources/*|skills/metate/lib/*)
        contract=1 ;;
    esac
  done < "$paths"
  # A deleted doc cannot satisfy the invariant; untracked docs must be staged first.
  if ! git -C "$repo" diff --no-renames --diff-filter=AMT --name-only -z "$ancestor" -- > "$paths"; then
    rm -f "$paths"
    return 1
  fi
  while IFS= read -r -d '' path; do
    case "$path" in docs/*|README.md) docs=1 ;; esac
  done < "$paths"
  rm -f "$paths"
  if [ "$contract" -eq 1 ] && [ "$docs" -eq 0 ]; then
    echo "Doc-as-Code: contract/schema changes require an update in docs/ or README.md (stage new docs)." >&2
    return 1
  fi
}

# A PR merges into the remote target, so measure against origin/<branch> and not a local
# branch of the same name that may be stale. This is also what CI needs: GITHUB_BASE_REF is
# a bare branch name, and an Actions checkout usually carries only the remote-tracking ref.
# Only plain branch names are rewritten — HEAD, a sha and any revision expression are taken
# as given, since origin/HEAD generally exists and would otherwise hijack them. An
# unresolvable name is handed back untouched so the merge base fails closed.
resolve_doc_base() {
  local repo="$1" ref="$2"
  case "$ref" in
    HEAD*|*/*|*[~^:@]*) ;;
    *)
      if git -C "$repo" rev-parse --verify -q "refs/remotes/origin/$ref^{commit}" >/dev/null; then
        echo "origin/$ref"
        return
      fi ;;
  esac
  echo "$ref"
}

# Supply the actual PR target when it differs from main. Fail closed on missing refs.
DOC_BASE="$(resolve_doc_base "$ROOT" "${METATE_DOC_BASE:-${GITHUB_BASE_REF:-main}}")"
validate_doc_as_code "$ROOT" "$DOC_BASE" || die "Doc-as-Code failed against $DOC_BASE"
ok "Doc-as-Code ($DOC_BASE merge base through tracked working tree)"

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
# The live ledger is off-repo now (ADR-0003), so resolve it rather than guessing a path.
LIVE_SIGNALS="$( (cd "$ROOT" && bash "$ROOT/skills/metate/lib/state.sh" repo-dir) || true )/signals.json"
live_note="fixtures only — no live signals.json for this repo"
if [ -f "$LIVE_SIGNALS" ]; then
  validate_signals "$LIVE_SIGNALS" ok
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

bash "$DOD" dod "$FIX/dod-rounds-valid.json" >/dev/null \
  || die "dod-rounds-valid.json should pass"
bash "$DOD" dod "$FIX/dod-rounds-declined-no-rationale.json" >/dev/null 2>&1 \
  && die "a declined finding with no rationale should fail" || true
ok "dod rounds[] ledger (declines carry a rationale; rounds-less dod still valid)"

# --- state.sh: off-repo layout (ADR-0003 phase 2) ---------------------------
STATE="$ROOT/skills/metate/lib/state.sh"
ST_TMP="$(mktemp -d)"
trap 'rm -rf "$ST_TMP"' EXIT
export METATE_STATE_ROOT="$ST_TMP/state"
st_repo() {  # $1 = dir, $2 = origin url (empty for none)
  git init -qb main "$1"
  [ -n "${2:-}" ] && git -C "$1" remote add origin "$2"
  git -C "$1" -c user.email=a@b -c user.name=a commit -q --allow-empty -m init
}
# Exercise the real git diff check, including committed, staged and unstaged edits.
st_repo "$ST_TMP/doc-code" ""
DC="$ST_TMP/doc-code"
mkdir -p "$DC/docs" "$DC/sources" "$DC/skills/metate/lib" "$DC/skills/metate-build"
for path in sample.schema.json skills/metate-build/profile.template.yml sources/prompt.md skills/metate/lib/check.sh docs/contract.md README.md ordinary.txt; do
  echo original > "$DC/$path"
done
git -C "$DC" add .
git -C "$DC" -c user.email=a@b -c user.name=a commit -qm fixtures
git -C "$DC" branch doc-base
validate_doc_as_code "$DC" doc-base || die "unchanged tree should pass"
echo changed >> "$DC/ordinary.txt"
validate_doc_as_code "$DC" doc-base || die "non-contract changes should pass"
for path in sample.schema.json skills/metate-build/profile.template.yml sources/prompt.md skills/metate/lib/check.sh; do
  git -C "$DC" reset --hard -q doc-base
  echo changed >> "$DC/$path"
  if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "$path without docs should fail"; fi
  echo updated >> "$DC/docs/contract.md"
  validate_doc_as_code "$DC" doc-base || die "$path with docs should pass"
done
git -C "$DC" reset --hard -q doc-base
echo changed >> "$DC/sample.schema.json"
git -C "$DC" add sample.schema.json
if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "staged schema without docs should fail"; fi
git -C "$DC" -c user.email=a@b -c user.name=a commit -qm schema
if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "committed schema without docs should fail"; fi
rm "$DC/docs/contract.md"
if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "deleted docs should not satisfy gate"; fi
echo updated >> "$DC/README.md"
validate_doc_as_code "$DC" doc-base || die "README update should satisfy gate"
git -C "$DC" add .
git -C "$DC" -c user.email=a@b -c user.name=a commit -qm docs
validate_doc_as_code "$DC" doc-base || die "committed schema with docs should pass"
git -C "$DC" reset --hard -q doc-base
git -C "$DC" mv sample.schema.json ordinary.json
if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "renamed-away schema should fail without docs"; fi
echo new > "$DC/docs/new.md"
if validate_doc_as_code "$DC" doc-base 2>/dev/null; then die "untracked docs should not satisfy gate"; fi
git -C "$DC" add docs/new.md
validate_doc_as_code "$DC" doc-base || die "staged new docs should satisfy gate"
if validate_doc_as_code "$DC" missing-ref 2>/dev/null; then die "missing base should fail closed"; fi
# The remote target wins over a same-named local branch, and CI's bare ref resolves at all.
git -C "$DC" update-ref refs/remotes/origin/ci-base doc-base
git -C "$DC" branch -q both doc-base
git -C "$DC" update-ref refs/remotes/origin/both doc-base
git -C "$DC" update-ref refs/remotes/origin/HEAD doc-base
[ "$(resolve_doc_base "$DC" both)" = origin/both ] || die "origin/ should win over a local branch"
[ "$(resolve_doc_base "$DC" ci-base)" = origin/ci-base ] || die "bare CI ref should resolve to origin/"
[ "$(resolve_doc_base "$DC" doc-base)" = doc-base ] || die "local-only ref should pass through"
[ "$(resolve_doc_base "$DC" missing-ref)" = missing-ref ] || die "unresolvable ref should pass through"
# origin/HEAD exists in most clones; revisions must not be rewritten through it.
for rev in HEAD HEAD~1 origin/doc-base "$(git -C "$DC" rev-parse doc-base)"; do
  [ "$(resolve_doc_base "$DC" "$rev")" = "$rev" ] || die "revision $rev should be taken as given"
done
validate_doc_as_code "$DC" "$(resolve_doc_base "$DC" ci-base)" || die "origin/ base should be usable"
ok "Doc-as-Code fixtures (contract paths, diff states, README, deletion, rename, new docs, base refs)"

st_repo "$ST_TMP/ssh"   "git@github.com:Skalas/metate.git"
st_repo "$ST_TMP/https" "https://github.com/Skalas/metate.git"
[ "$(cd "$ST_TMP/ssh" && bash "$STATE" key)" = "$(cd "$ST_TMP/https" && bash "$STATE" key)" ] \
  || die "ssh and https clones of one repo must resolve to the same repo-key"
st_repo "$ST_TMP/other" "https://github.com/Skalas/brain-mcp.git"
[ "$(cd "$ST_TMP/other" && bash "$STATE" key)" != "$(cd "$ST_TMP/ssh" && bash "$STATE" key)" ] \
  || die "different repos must not share a repo-key"
ok "state repo-key (ssh/https agree; distinct repos differ)"

( cd "$ST_TMP/ssh" && git checkout -qb sprint-a \
  && git worktree add -q "$ST_TMP/wt-b" -b sprint-b ) >/dev/null 2>&1
A_REPO="$(cd "$ST_TMP/ssh" && bash "$STATE" repo-dir)"
B_REPO="$(cd "$ST_TMP/wt-b" && bash "$STATE" repo-dir)"
A_SPR="$(cd "$ST_TMP/ssh" && bash "$STATE" sprint-dir)"
B_SPR="$(cd "$ST_TMP/wt-b" && bash "$STATE" sprint-dir)"
[ "$A_REPO" = "$B_REPO" ] || die "worktrees of one repo must share the repo dir"
[ "$A_SPR" != "$B_SPR" ] || die "parallel worktree sprints must not share a sprint dir"
st_repo "$ST_TMP/nr" ""
git -C "$ST_TMP/nr" worktree add -q "$ST_TMP/nr-wt" -b other >/dev/null 2>&1
[ "$(cd "$ST_TMP/nr" && bash "$STATE" key)" = "$(cd "$ST_TMP/nr-wt" && bash "$STATE" key)" ] \
  || die "remote-less worktrees must still share one repo-key"
ok "state sprint-key (worktrees share repo dir, isolate sprint dir; no-remote case)"

st_repo "$ST_TMP/mig" "https://github.com/Skalas/demo.git"
mkdir -p "$ST_TMP/mig/.metate"
( cd "$ST_TMP/mig" && git checkout -qb feat/x ) >/dev/null 2>&1
for f in profile.yml signals.json human-gates.json; do echo '{}' > "$ST_TMP/mig/.metate/$f"; done
for f in plan.md dod.json session.json; do echo '{}' > "$ST_TMP/mig/.metate/$f"; done
( cd "$ST_TMP/mig" && bash "$STATE" migrate ) >/dev/null
M_REPO="$(cd "$ST_TMP/mig" && bash "$STATE" repo-dir)"
M_SPR="$(cd "$ST_TMP/mig" && bash "$STATE" sprint-dir)"
for f in profile.yml signals.json human-gates.json; do
  [ -f "$M_REPO/$f" ] || die "migrate: $f should be repo-scoped"; done
for f in plan.md dod.json session.json; do
  [ -f "$M_SPR/$f" ] || die "migrate: $f should be sprint-scoped"; done
[ -d "$ST_TMP/mig/.metate" ] && die "migrate should remove the emptied legacy dir" || true
ok "state migrate (splits legacy .metate/ by lifetime; removes the empty dir)"

# The playbooks read state through $STATE/$SPRINT. A hardcoded .metate/ path in one of
# them is the split-brain failure: tooling moved, prose did not. Structural, not phrasal.
straggler=0
for f in "$ROOT"/skills/metate*/SKILL.md "$ROOT"/skills/metate-build/IMPLEMENTERS.md \
         "$ROOT"/skills/metate-build/REVIEWERS.md; do
  grep -q '\.metate/' "$f" && { echo "  ✗ $(basename "$(dirname "$f")")/$(basename "$f") hardcodes .metate/"; straggler=1; }
done
[ "$straggler" -eq 0 ] || die "playbooks must resolve state via state.sh (\$STATE / \$SPRINT)"
for f in "$ROOT"/skills/metate*/SKILL.md; do
  grep -q 'lib/state.sh env' "$f" || die "$(basename "$(dirname "$f")")/SKILL.md never resolves state"
done
grep -q 'lib/state.sh claim-plan' "$ROOT/skills/metate-start/SKILL.md" \
  || die "metate-start must claim the pending plan after the branch cut"
ok "playbooks resolve state via state.sh (no hardcoded .metate/; start claims the plan)"

st_repo "$ST_TMP/plan" "https://github.com/Skalas/planflow.git"
( cd "$ST_TMP/plan" && eval "$(bash "$STATE" env)" \
  && [ -n "${STATE:-}" ] && [ -n "${SPRINT:-}" ] ) || die "state.sh env must export STATE and SPRINT"
P_REPO="$(cd "$ST_TMP/plan" && bash "$STATE" repo-dir)"
echo "# plan" > "$P_REPO/plan.md"                       # scope writes it on the base branch
( cd "$ST_TMP/plan" && git checkout -qb feat/thing && bash "$STATE" claim-plan ) >/dev/null 2>&1
P_SPR="$(cd "$ST_TMP/plan" && bash "$STATE" sprint-dir)"
[ -f "$P_SPR/plan.md" ] || die "claim-plan must move the pending plan into the sprint"
[ -f "$P_REPO/plan.md" ] && die "claim-plan must not leave the pending plan behind" || true
( cd "$ST_TMP/plan" && bash "$STATE" claim-plan ) >/dev/null 2>&1 \
  || die "claim-plan must be idempotent once the sprint owns a plan"
( cd "$ST_TMP/plan" && git worktree add -q "$ST_TMP/plan-wt" -b feat/second ) >/dev/null 2>&1
( cd "$ST_TMP/plan-wt" && bash "$STATE" claim-plan ) >/dev/null 2>&1 \
  && die "a second sprint must not inherit another sprint's plan" || true
ok "state env + claim-plan (plan is repo-scoped until the branch cut, then sprint-owned)"
unset METATE_STATE_ROOT

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
