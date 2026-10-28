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

# --- round.sh + dod.sh receipt + pre-push hook (ADR-0005) --------------------
# One throwaway repo walks a whole sprint: bootstrap, review rounds, receipt, push.
ROUND="$ROOT/skills/metate/lib/round.sh"
export METATE_STATE_ROOT="$ST_TMP/round-state"
RT="$ST_TMP/round"
RT_HOME="$ST_TMP/round-home"
rt_git() { git -C "$RT" -c user.email=a@b -c user.name=a "$@"; }
rt_commit() { rt_git add -A && rt_git commit -qm "$1"; }
in_rt() { (cd "$RT" && "$@"); }
must_fail() { if "$@" >/dev/null 2>&1; then return 1; fi; }
tree_field() { in_rt bash "$ROUND" tree main | jq -r ".$1"; }

st_repo "$RT" "https://github.com/Skalas/roundtrip.git"
mkdir -p "$RT/src" "$RT/docs" "$RT_HOME/.local/bin"
# Long enough that an upstream insertion at the top stays outside the 3-line context of the
# sprint's appended lines at the bottom.
printf 'echo hi\n# one\n# two\n# three\n# four\n# five\n' > "$RT/src/app.sh"; echo guide > "$RT/docs/guide.md"; echo readme > "$RT/README.md"
rt_commit base
RT_STATE="$(in_rt bash "$STATE" repo-dir)"
cat > "$RT_STATE/profile.yml" <<'YML'
codebaseMemory:
  enabled: true
reviewFocus: |
  - Never run `rm -rf $HOME` from a hook; "$(quoted)" stays literal.
start:
  baseBranch: main
YML
printf '#!/bin/sh\n' > "$RT_HOME/.local/bin/codebase-memory-mcp"
chmod +x "$RT_HOME/.local/bin/codebase-memory-mcp"
(cd "$RT" && HOME="$RT_HOME" bash "$ROOT/skills/metate-build/bootstrap.sh") >/dev/null \
  || die "bootstrap should succeed in a fresh repo"
rt_commit bootstrap
rt_git checkout -qb feat/receipt
echo 'echo feature' >> "$RT/src/app.sh"
rt_commit feature
RT_SPRINT="$(in_rt bash "$STATE" sprint-dir)"

# tree: code only — docs, README, secrets excluded; untracked code included; real index untouched.
sha0="$(tree_field codeTreeSha)"; patch0="$(tree_field patchId)"
printf '%s' "$sha0" | grep -qE '^[0-9a-f]{40}$' || die "tree: codeTreeSha should be a sha, got '$sha0'"
printf '%s' "$patch0" | grep -qE '^[0-9a-f]{64}$' || die "tree: patchId should be a sha256, got '$patch0'"
must_fail in_rt bash "$ROUND" tree nonexistent-branch \
  || die "tree: an unresolvable base must fail closed, not fall back to HEAD"
rt_git ls-tree -r --name-only "$sha0" | grep -qE '^(docs/|README\.md)' \
  && die "tree: docs/ and README.md must not be hashed" || true
[ "$(tree_field baseSha)" = "$(rt_git merge-base main HEAD)" ] || die "tree: baseSha should be the merge base"
echo more >> "$RT/docs/guide.md"; echo more >> "$RT/README.md"; echo more > "$RT/CHANGELOG.md"
echo 'API_KEY=1' > "$RT/.env.local"; echo pem > "$RT/private.pem"; echo key > "$RT/src/id_ed25519"
[ "$(tree_field codeTreeSha)" = "$sha0" ] || die "tree: docs and untracked secret files must not move codeTreeSha"
[ "$(tree_field patchId)" = "$patch0" ] || die "tree: docs and untracked secret files must not move patchId"
must_fail rt_git cat-file -e "$(rt_git hash-object "$RT/.env.local")" \
  || die "tree: an untracked secret file must never be written to the object store"
rt_git diff --cached --quiet || die "tree: the real index must be left untouched"
# Secret NAMES are exact: code that merely mentions tokens is code, untracked or tracked.
echo 'export const ok = 1' > "$RT/src/token_service.ts"
[ "$(tree_field codeTreeSha)" != "$sha0" ] || die "tree: untracked src/token_service.ts must move codeTreeSha"
[ "$(tree_field patchId)" != "$patch0" ] || die "tree: untracked code must move patchId"
rm -f "$RT/.env.local" "$RT/private.pem" "$RT/src/id_ed25519" "$RT/CHANGELOG.md"
rt_git checkout -q -- docs README.md
rt_commit "token service"
sha0="$(tree_field codeTreeSha)"; patch0="$(tree_field patchId)"
rt_git ls-tree -r --name-only "$sha0" | grep -qx 'src/token_service.ts' \
  || die "tree: tracked src/token_service.ts must be hashed"
# The base defaults to the profile's start.baseBranch.
sed -i.bak 's/^  baseBranch: main$/  baseBranch: feat\/receipt/' "$RT_STATE/profile.yml"
[ "$(in_rt bash "$ROUND" base)" = feat/receipt ] || die "base: should come from start.baseBranch"
[ "$(in_rt bash "$ROUND" tree | jq -r .baseSha)" = "$(rt_git rev-parse HEAD)" ] \
  || die "tree: no BASE should use the profile base"
mv "$RT_STATE/profile.yml.bak" "$RT_STATE/profile.yml"
[ "$(in_rt bash "$ROUND" base)" = main ] || die "base: should read main back from the profile"
[ "$(in_rt bash "$ROUND" tree HEAD | jq -r .patchId)" = empty ] || die "tree: no code diff should give patchId 'empty'"
ok "round.sh tree (code-only codeTreeSha + patchId + baseSha; docs and untracked secrets excluded; profile base)"

# prompt: reviewFocus + Code Discovery + task, with no shell evaluation of their contents.
# The literal $(…) and backticks below ARE the payload under test (hence SC2016).
# shellcheck disable=SC2016
printf 'Task: $(touch %s/pwned) and `touch %s/pwned`\n' "$ST_TMP" "$ST_TMP" > "$ST_TMP/task.md"
in_rt bash "$ROUND" prompt maker "$ST_TMP/maker.md" "$ST_TMP/task.md" || die "prompt maker failed"
# shellcheck disable=SC2016
grep -qF -- '- Never run `rm -rf $HOME` from a hook; "$(quoted)" stays literal.' "$ST_TMP/maker.md" \
  || die "prompt: reviewFocus must be copied verbatim"
grep -qF 'Code Discovery' "$ST_TMP/maker.md" || die "prompt: Code Discovery clause missing"
# shellcheck disable=SC2016
grep -qF 'Task: $(touch' "$ST_TMP/maker.md" || die "prompt: task file missing"
[ -e "$ST_TMP/pwned" ] && die "prompt: task content must never be evaluated" || true
in_rt bash "$ROUND" prompt reviewer "$ST_TMP/reviewer.md" || die "prompt reviewer failed"
grep -qF 'Scrutinize the diff' "$ST_TMP/reviewer.md" || die "prompt: reviewer preamble missing"
must_fail in_rt bash "$ROUND" prompt critic "$ST_TMP/x.md" || die "prompt: unknown role should fail"
must_fail in_rt bash "$ROUND" prompt maker "$ST_TMP/x.md" "$ST_TMP/missing.md" \
  || die "prompt: a missing task file should fail"
ok "round.sh prompt (reviewFocus + clause + task, verbatim, never evaluated)"

# record + adjudicate.
D="$RT_SPRINT/dod.json"
jq -n '{sprint: "receipt", rows: [{id: "T1", title: "receipt", command: "true"}]}' > "$D"
lens() {  # $1 = file, then bucket:file:line:summary ...
  local out="$1"; shift
  [ $# -gt 0 ] || { echo '{"findings": []}' > "$out"; return 0; }
  printf '%s\n' "$@" | jq -R 'split(":") | {bucket: .[0], file: .[1], line: (.[2]|tonumber),
    summary: .[3], consequence: "breaks", rationale: "evidence"}' | jq -s '{findings: .}' > "$out"
}
lens "$ST_TMP/c1.json" "blocker:src/app.sh:2:wrong echo" "warning:src/app.sh:1:style"
lens "$ST_TMP/s1.json" "blocker:src/app.sh:2:wrong echo" "suggestion:src/app.sh:1:rename"
echo 'not json' > "$ST_TMP/broken.json"
in_rt bash "$ROUND" record "$D" --round 1 --gate pending --lens "correctness:$ST_TMP/c1.json" \
  --lens "security:$ST_TMP/s1.json" --lens "elegance:$ST_TMP/broken.json" >/dev/null 2>&1 \
  || die "record: round 1 should record"
r1() { jq -c "$1" "$D"; }
[ "$(r1 '[.rounds[0].findings[].id]')" = '["R1-1","R1-2","R1-3"]' ] || die "record: dedup + ids wrong: $(r1 '.rounds[0].findings')"
[ "$(r1 '[.rounds[0].findings[].disposition] | unique')" = '["open"]' ] || die "record: findings must open as open"
[ "$(r1 '.rounds[0].failedLenses')" = '["elegance"]' ] || die "record: an invalid report must fail its lens"
[ "$(r1 '.rounds[0].lenses')" = '["correctness","elegance","security"]' ] || die "record: lenses wrong"
[ "$(jq -r '.rounds[0].artifactHashes.correctness' "$D")" = "$(shasum -a 256 "$ST_TMP/c1.json" | awk '{print $1}')" ] \
  || die "record: artifact hash mismatch"
[ "$(jq -r '.rounds[0].codeTreeSha' "$D")" = "$sha0" ] || die "record: codeTreeSha should be the reviewed tree"
[ "$(jq -r '.rounds[0].baseSha' "$D")" = "$(rt_git merge-base main HEAD)" ] || die "record: baseSha missing"
[ "$(r1 '.rounds[0].findings[0] | [.consequence, .rationale]')" = '["breaks","evidence"]' ] \
  || die "record: consequence/rationale should be kept"
in_rt bash "$ROUND" record "$D" --round 2 --gate pass >/dev/null 2>&1 \
  && die "record: a new round with no lenses should fail" || true
in_rt bash "$ROUND" record "$D" --round 1 --gate maybe --lens "c:$ST_TMP/c1.json" >/dev/null 2>&1 \
  && die "record: a bad gate should fail" || true
in_rt bash "$ROUND" adjudicate "$D" --round 1 --id R1-2 --disposition declined >/dev/null 2>&1 \
  && die "adjudicate: declining without a rationale should fail" || true
in_rt bash "$ROUND" adjudicate "$D" --round 1 --id R1-9 --disposition fixed >/dev/null 2>&1 \
  && die "adjudicate: an unknown id should fail" || true
in_rt bash "$ROUND" adjudicate "$D" --round 1 --id R1-1 --disposition fixed >/dev/null || die "adjudicate fixed failed"
in_rt bash "$ROUND" adjudicate "$D" --round 1 --id R1-2 --disposition declined --rationale "house style" >/dev/null \
  || die "adjudicate declined failed"
echo 'echo fixed' >> "$RT/src/app.sh"           # the implementer patches R1-1
in_rt bash "$ROUND" record "$D" --round 1 --gate red --lens "correctness:$ST_TMP/c1.json" >/dev/null 2>&1 \
  && die "record: re-reviewing round 1 on a patched tree must need round 2" || true
in_rt bash "$ROUND" record "$D" --round 1 --gate red >/dev/null || die "record: closing round 1 failed"
[ "$(r1 '[.rounds[0].gate, .rounds[0].findings[0].disposition, .rounds[0].findings[1].rationale]')" \
  = '["red","fixed","house style"]' ] || die "record: closing must keep dispositions"
[ "$(r1 '.rounds[0] | [.codeTreeSha, .patchId]')" = "$(jq -nc --arg t "$sha0" --arg p "$patch0" '[$t, $p]')" ] \
  || die "record: closing must keep the reviewed codeTreeSha and patchId"
in_rt bash "$ROUND" record "$D" --round 1 --gate pass >/dev/null 2>&1 \
  && die "record: a closed round must not be rewritten" || true
bash "$DOD" dod "$D" >/dev/null || die "record: dod.json should validate"
rt_commit fix
# Round 2 re-reviews the patched tree; re-recording a pending round keeps its dispositions.
lens "$ST_TMP/c2.json" "blocker:src/app.sh:3:needs quoting"
lens "$ST_TMP/empty.json"
in_rt bash "$ROUND" record "$D" --round 2 --gate pending --lens "correctness:$ST_TMP/c2.json" >/dev/null
in_rt bash "$ROUND" adjudicate "$D" --round 2 --id R2-1 --disposition declined --rationale "quoted upstream" >/dev/null
in_rt bash "$ROUND" record "$D" --round 2 --gate pass --lens "correctness:$ST_TMP/c2.json" \
  --lens "security:$ST_TMP/empty.json" >/dev/null || die "record: re-recording a pending round failed"
[ "$(r1 '.rounds[1].findings[0] | [.disposition, .rationale]')" = '["declined","quoted upstream"]' ] \
  || die "record: re-recording a pending round must preserve dispositions"
ok "round.sh record + adjudicate (dedup, ids, failed lenses, hashes, preserved dispositions)"

# receipt.
receipt() { in_rt bash "$DOD" receipt "$1" main; }
receipt_fails_with() {  # $1 = dod, $2 = expected message fragment
  local err
  if err="$(receipt "$1" 2>&1 >/dev/null)"; then die "receipt should fail: $2"; fi
  printf '%s' "$err" | grep -qF "$2" || die "receipt failed for the wrong reason: $err (wanted: $2)"
}
out="$(receipt "$D")" || die "receipt: a clean final round should pass"
printf '%s' "$out" | grep -qF '## Forensic Receipt' || die "receipt: missing heading"
printf '%s' "$out" | grep -qF -- '- R1: gate=red, lenses=correctness,elegance,security, blockers=1, warnings=1' \
  || die "receipt: per-round summary wrong: $out"
printf '%s' "$out" | grep -qF 'codeTreeSha matches' || die "receipt: tree check not reported"
printf '%s' "$out" | grep -qF "hashes=correctness:$(shasum -a 256 "$ST_TMP/c1.json" | cut -c1-12)," \
  || die "receipt: artifact hashes not surfaced: $out"
echo 'more docs' >> "$RT/docs/guide.md"; echo 'more' >> "$RT/README.md"
receipt "$D" >/dev/null || die "receipt: a docs-only edit after review should pass"
rt_commit "close-out docs"
receipt "$D" >/dev/null || die "receipt: committed close-out docs should pass"
echo 'echo sneaky' >> "$RT/src/app.sh"
receipt_fails_with "$D" "code tree drifted after final review round"
rt_git checkout -q -- src/app.sh
# Variants of the final round, each on a copy of the ledger.
variant() { cp "$D" "$ST_TMP/$1.json"; printf '%s' "$ST_TMP/$1.json"; }
V="$(variant open-blocker)"
in_rt bash "$ROUND" record "$V" --round 3 --gate pass --lens "correctness:$ST_TMP/c2.json" >/dev/null
receipt_fails_with "$V" "final round has blockers that are not declined"
V="$(variant fixed-last)"
in_rt bash "$ROUND" record "$V" --round 3 --gate pending --lens "correctness:$ST_TMP/c2.json" >/dev/null
in_rt bash "$ROUND" adjudicate "$V" --round 3 --id R3-1 --disposition fixed >/dev/null
in_rt bash "$ROUND" record "$V" --round 3 --gate pass >/dev/null
receipt_fails_with "$V" "R3-1 (fixed)"
V="$(variant declined-last)"
in_rt bash "$ROUND" record "$V" --round 3 --gate pending --lens "correctness:$ST_TMP/c2.json" >/dev/null
in_rt bash "$ROUND" adjudicate "$V" --round 3 --id R3-1 --disposition declined --rationale "by design" >/dev/null
in_rt bash "$ROUND" record "$V" --round 3 --gate pass >/dev/null
receipt "$V" >/dev/null || die "receipt: a declined final-round blocker should pass"
V="$(variant failed-lens)"
in_rt bash "$ROUND" record "$V" --round 3 --gate pass --lens "correctness:$ST_TMP/empty.json" \
  --failed-lens security >/dev/null
receipt_fails_with "$V" "final round has failed lenses: security"
V="$(variant red-last)"
in_rt bash "$ROUND" record "$V" --round 3 --gate red --lens "correctness:$ST_TMP/empty.json" >/dev/null
receipt_fails_with "$V" "final round gate is not pass"
V="$(variant prior-open)"
in_rt bash "$ROUND" adjudicate "$V" --round 1 --id R1-1 --disposition open >/dev/null
receipt_fails_with "$V" "earlier rounds left blockers open or deferred: R1-1 (open)"
V="$(variant zero-lenses)"
jq '.rounds[-1].lenses = []' "$D" > "$V"
receipt_fails_with "$V" "final round ran 0 lenses"
V="$(variant unsealed)"
jq '.rounds[-1] |= del(.codeTreeSha)' "$D" > "$V"
bash "$DOD" dod "$V" >/dev/null || die "dod: an unsealed round is still schema-valid"
receipt_fails_with "$V" "final round is unsealed"
V="$(variant no-lenses-key)"
jq '.rounds[-1] |= del(.lenses)' "$D" > "$V"
receipt_fails_with "$V" "final round ran 0 lenses"
# Same base, different tree: a matching patchId must not excuse it (only a rebase may).
V="$(variant same-base)"
jq '.rounds[-1].codeTreeSha = "0000000000000000000000000000000000000000"' "$D" > "$V"
receipt_fails_with "$V" "code tree drifted after final review round"
receipt_fails_with "$FIX/dod-valid.json" "no review rounds recorded"
receipt_fails_with "$FIX/dod-rounds-valid.json" "final round gate is not pass"
V="$(variant bad-types)"
jq '.rounds[0].codeTreeSha = 5' "$D" > "$V"
must_fail bash "$DOD" dod "$V" || die "dod: a non-string codeTreeSha should fail"
jq '.rounds[0].lenses = [1]' "$D" > "$V"
must_fail bash "$DOD" dod "$V" || die "dod: non-string lenses should fail"
jq '.rounds[0].artifactHashes = []' "$D" > "$V"
must_fail bash "$DOD" dod "$V" || die "dod: a non-object artifactHashes should fail"
# A tracked file whose name mentions tokens is code: editing it after review is drift.
echo 'export const ok = 2' >> "$RT/src/token_service.ts"
receipt_fails_with "$D" "code tree drifted after final review round"
rt_git checkout -q -- src/token_service.ts
ok "dod.sh receipt (clean, docs-only, drift, unsealed, open/fixed/declined blockers, failed lens, gate, prior rounds)"

# pre-push: bootstrap installed it; it gates the sprint branch and nothing else.
HOOK="$RT/.git/hooks/pre-push"
{ [ -x "$HOOK" ] && grep -q 'metate:pre-push' "$HOOK"; } || die "bootstrap should install the managed pre-push hook"
git init -q --bare "$ST_TMP/remote.git"
rt_git remote add pushto "$ST_TMP/remote.git"
rt_push() { HOME="$RT_HOME" git -C "$RT" push -q pushto "$1" >/dev/null 2>&1; }
rt_push feat/receipt || die "pre-push: a certified tree should push"
echo 'echo unreviewed' >> "$RT/src/app.sh"; rt_commit unreviewed
rt_push feat/receipt && die "pre-push: an unreviewed commit must be blocked" || true
rt_git reset -q --hard HEAD~1
rt_hook() { (cd "$RT" && .git/hooks/pre-push pushto "$ST_TMP/remote.git" </dev/null) >/dev/null 2>&1; }
rt_hook || die "pre-push: with no ref lines it should certify the current branch"
echo 'echo unreviewed' >> "$RT/src/app.sh"; rt_commit unreviewed
rt_hook && die "pre-push: with no ref lines it must still check HEAD" || true
# Restore the reviewed code in the worktree only: the receipt would match, the pushed HEAD not.
rt_git show HEAD~1:src/app.sh > "$RT/src/app.sh"
rt_push feat/receipt && die "pre-push: uncommitted code hiding an unreviewed commit must be blocked" || true
rt_git reset -q --hard HEAD~1
# A sprint branch pushed from anywhere but its own checkout cannot be certified.
rt_git checkout -q --detach
echo 'detached' >> "$RT/docs/guide.md"; rt_commit "detached docs"
HOME="$RT_HOME" git -C "$RT" push -q pushto HEAD:refs/heads/feat/receipt >/dev/null 2>&1 \
  && die "pre-push: a detached HEAD push to a sprint branch must be blocked" || true
rt_git checkout -q feat/receipt
# The destination is gated too: base content force-pushed onto a sprint branch is not HEAD.
HOME="$RT_HOME" git -C "$RT" push -q pushto +main:refs/heads/feat/receipt >/dev/null 2>&1 \
  && die "pre-push: pushing main onto a sprint branch must be blocked" || true
rt_git checkout -q main
HOME="$RT_HOME" git -C "$RT" push -q pushto +HEAD:refs/heads/feat/receipt >/dev/null 2>&1 \
  && die "pre-push: pushing another checkout's HEAD onto a sprint branch must be blocked" || true
rt_push main || die "pre-push: the base branch has no sprint ledger and should push"
rt_git checkout -q feat/receipt
(cd "$RT" && HOME="$RT_HOME" bash "$ROOT/skills/metate-build/bootstrap.sh") >/dev/null \
  || die "bootstrap re-run should succeed"
grep -q 'metate:pre-push' "$HOOK" || die "bootstrap re-run should refresh the managed hook"
FOREIGN="$ST_TMP/foreign"
st_repo "$FOREIGN" "https://github.com/Skalas/foreign.git"
printf '#!/bin/sh\necho mine\n' > "$FOREIGN/.git/hooks/pre-push"
(cd "$FOREIGN" && HOME="$RT_HOME" bash "$ROOT/skills/metate-build/bootstrap.sh") >/dev/null \
  || die "bootstrap should succeed beside a foreign hook"
[ "$(cat "$FOREIGN/.git/hooks/pre-push")" = "$(printf '#!/bin/sh\necho mine')" ] \
  || die "bootstrap must never overwrite a foreign pre-push hook"
ok "pre-push hook (installed; blocks unreviewed, dirty, detached and cross-branch pushes; no-stdin; skips base; never clobbers)"

# A clean rebase onto an advanced base keeps the reviewed patch: patchId carries the receipt.
rt_git checkout -q main
# Upstream touches an unrelated file AND shifts the reviewed file's line numbers.
echo 'echo upstream' > "$RT/src/upstream.sh"
{ echo '# upstream header'; rt_git show main:src/app.sh; } > "$RT/src/app.sh"
rt_commit upstream
rt_git checkout -q feat/receipt
rt_git rebase -q main >/dev/null 2>&1 || die "rebase onto main should be clean"
[ "$(tree_field codeTreeSha)" != "$(jq -r '.rounds[-1].codeTreeSha' "$D")" ] \
  || die "rebase: the tree should differ after picking up upstream"
out="$(receipt "$D")" || die "receipt: a clean rebase should pass on patchId"
printf '%s' "$out" | grep -qF 'patchId matches' || die "receipt: rebase should be reported as a patchId match"
# The patchId fallback needs the base to have moved FORWARD from the recorded one.
now_patch="$(tree_field patchId)"
future="$(rt_git commit-tree "main^{tree}" -p main -m future)"
V="$(variant rewind)"
jq --arg b "$future" --arg p "$now_patch" '.rounds[-1] += {baseSha: $b, patchId: $p,
  codeTreeSha: "0000000000000000000000000000000000000000"}' "$D" > "$V"
receipt_fails_with "$V" "code tree drifted after final review round"
V="$(variant forward)"
jq --arg b "$(rt_git rev-parse main~1)" --arg p "$now_patch" '.rounds[-1] += {baseSha: $b, patchId: $p,
  codeTreeSha: "0000000000000000000000000000000000000000"}' "$D" > "$V"
receipt "$V" >/dev/null || die "receipt: a forward rebase carrying the reviewed patch should pass"
# patchId is whitespace-exact: `echo feature` -> `echo  feature` after the rebase is drift.
sed -i.bak 's/^echo feature$/echo  feature/' "$RT/src/app.sh" && rm -f "$RT/src/app.sh.bak"
rt_commit "whitespace only"
receipt_fails_with "$D" "code tree drifted after final review round"
rt_git reset -q --hard HEAD~1
receipt "$D" >/dev/null || die "receipt: undoing the whitespace edit should pass again"
# patchId carries context: the same added line moved elsewhere in its file is drift.
grep -vx 'echo feature' "$RT/src/app.sh" > "$RT/src/app.tmp"
{ head -n 2 "$RT/src/app.tmp"; echo 'echo feature'; tail -n +3 "$RT/src/app.tmp"; } > "$RT/src/app.sh"
rm -f "$RT/src/app.tmp"
rt_commit "moved line"
receipt_fails_with "$D" "code tree drifted after final review round"
rt_git reset -q --hard HEAD~1
ok "dod.sh receipt survives a clean rebase (patchId: forward-only base, whitespace-exact, context-anchored)"
unset METATE_STATE_ROOT
