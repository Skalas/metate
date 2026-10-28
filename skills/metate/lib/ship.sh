#!/usr/bin/env bash
# ship.sh — deterministic merge and milestone-pillar reads for metate-ship.
#
#   ship.sh wait-and-merge PR [BASE] [--base B] [--poll-interval SEC] [--timeout SEC]
#       Wait for CI on PR, then `gh pr merge --merge --match-head-commit` (never squash),
#       retire session files and return to BASE (default: round.sh base). Idempotent: a PR that
#       is already MERGED only runs the cleanup. Prints {"merged":true,"pr":…,"mergeCommit":…,"branch":…}.
#       Exit 1 = a check failed or a precondition broke; exit 2 = timed out waiting for CI.
#   ship.sh next-in-pillar [PILLARS_FILE]    (default: <repo>/docs/pillars.yml)
#       The active pillar (else the first planned one), its pending exit invariants and progress,
#       completed pillars and the next planned one, as JSON. Unknown statuses fail closed.
#
# Fails closed: a red receipt, a dirty tree, a local HEAD that is not the PR head, a head that
# moves mid-poll, or a repo with workflows but no checks after the registration grace.
# METATE_ALLOW_NO_CHECKS=1 accepts a PR that never registers any check.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_POLL_INTERVAL=15
DEFAULT_TIMEOUT=1200
CHECK_REGISTRATION_GRACE=60   # seconds Actions may take to register CheckRuns on a fresh head
GH_ATTEMPTS=3
GH_RETRY_SLEEP=2
MERGE_CONFIRM_ATTEMPTS=3
PR_FIELDS=number,state,headRefName,headRefOid,baseRefName,mergeStateStatus,statusCheckRollup,mergeCommit,url,isCrossRepository
PILLAR_STATUSES='["active","planned","completed"]'
INVARIANT_STATUSES='["pending","verified"]'
EMPTY_PILLARS='{"activePillar":null,"milestoneReadyToClose":false,"completedPillars":[],"nextPlannedPillar":null}'

die() { echo "ship.sh: $*" >&2; exit 1; }

repo_root() { git rev-parse --show-toplevel 2>/dev/null || die "not inside a git worktree"; }

require_seconds() {  # $1 flag, $2 value
  case "$2" in ''|*[!0-9]*|0) die "$1 must be a positive integer of seconds, got '$2'" ;; esac
}

# Transient gh failures (rate limits, network blips) must not abort a 20-minute wait.
gh_retry() {
  local attempt=1
  until "$@"; do
    [ "$attempt" -lt "$GH_ATTEMPTS" ] || return 1
    attempt=$((attempt + 1))
    sleep "$GH_RETRY_SLEEP"
  done
}

pr_view() { gh_retry gh pr view "$PR_NUM" --json "$PR_FIELDS"; }

merged_json() {  # $1 merge oid
  jq -nc --argjson pr "$PR_NUM" --arg oid "$1" --arg branch "$PR_BRANCH" \
    '{merged: true, pr: $pr, mergeCommit: $oid, branch: $branch}'
}

# --- post-merge cleanup ----------------------------------------------------------

# A linked worktree cannot `git switch` to a base branch another worktree holds.
base_checked_out_elsewhere() {
  local here path="" line
  here="$(cd "$(repo_root)" && pwd -P)"
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch refs/heads/$BASE_BRANCH")
        [ "$(cd "$path" 2>/dev/null && pwd -P)" = "$here" ] || return 0 ;;
    esac
  done < <(git worktree list --porcelain)
  return 1
}

return_to_base() {
  if base_checked_out_elsewhere; then
    git fetch -q origin "$BASE_BRANCH"
    git checkout -q --detach "origin/$BASE_BRANCH"
  else
    git switch -q "$BASE_BRANCH"
    git pull -q --ff-only origin "$BASE_BRANCH"
  fi
  if git show-ref --verify --quiet "refs/heads/$PR_BRANCH"; then
    git branch -d "$PR_BRANCH" >/dev/null || die "local $PR_BRANCH is not merged into $BASE_BRANCH — left in place"
  fi
}

# Only our own branch, and only at the merged head: a fork's branch is not ours to delete, and a
# branch that moved after the merge carries work the merge does not.
delete_remote_branch() {
  [ "$IS_CROSS_REPO" != true ] || return 0
  git push -q origin --delete "$PR_BRANCH" --force-with-lease="refs/heads/$PR_BRANCH:$HEAD_OID" \
    >/dev/null 2>&1 || true
}

post_merge_cleanup() {
  delete_remote_branch
  rm -f "$SPRINT_DIR/session.json" "$SPRINT_DIR/.session-start.json"
  return_to_base
}

# GitHub can report the merge a moment after `gh pr merge` returns. Never delete the remote
# branch on an unconfirmed merge: that would close the PR instead of landing it.
confirm_merge_oid() {
  local attempt=1 view
  while :; do
    view="$(gh_retry gh pr view "$PR_NUM" --json state,mergeCommit)" || die "cannot read PR #$PR_NUM after merge"
    if [ "$(jq -r .state <<<"$view")" = MERGED ]; then
      jq -r '.mergeCommit.oid // empty' <<<"$view"
      return 0
    fi
    [ "$attempt" -lt "$MERGE_CONFIRM_ATTEMPTS" ] || die "PR #$PR_NUM did not report MERGED after merge"
    attempt=$((attempt + 1))
    sleep "$POLL_INTERVAL"
  done
}

# --- CI classification -----------------------------------------------------------

# One rollup → {total, checkRuns, pending, failed: [{name,url}]}. CheckRuns carry status and
# conclusion; StatusContexts carry state. Anything not affirmatively green or waiting is a failure.
rollup_summary() {
  jq -c '
    def kind: if (.__typename // "") == "CheckRun" or has("conclusion") or has("status") then "run"
              else "context" end;
    def verdict:
      if kind == "run" then
        if (.status // "" | ascii_upcase) != "COMPLETED" then "pending"
        elif ((.conclusion // "") | ascii_upcase) as $c | ["SUCCESS","NEUTRAL","SKIPPED"] | index($c)
          then "pass" else "fail" end
      else
        ((.state // "") | ascii_upcase) as $s
        | if $s == "PENDING" or $s == "EXPECTED" then "pending"
          elif $s == "SUCCESS" then "pass" else "fail" end
      end;
    (.statusCheckRollup // []) as $r
    | {total: ($r | length),
       checkRuns: ($r | map(select(kind == "run")) | length),
       pending: ($r | map(select(verdict == "pending")) | length),
       failed: ($r | map(select(verdict == "fail")
                 | {name: (.name // .context // "unnamed"), url: (.detailsUrl // .targetUrl // "")}))}
  '
}

# Actions runs for the head when the rollup has no CheckRuns yet: pending | fail | pass | none.
actions_runs_verdict() {  # $1 = `gh run list --json status,conclusion,name,url` output
  jq -r '
    if length == 0 then "none"
    elif any(.[]; (.status // "" | ascii_upcase) != "COMPLETED") then "pending"
    elif all(.[]; ((.conclusion // "") | ascii_upcase) as $c | ["SUCCESS","NEUTRAL","SKIPPED"] | index($c))
      then "pass"
    else "fail" end
  ' <<<"$1"
}

report_failures() {  # $1 summary json
  echo "ship.sh: CI failed on PR #$PR_NUM:" >&2
  jq -r '.failed[] | "  ✗ \(.name) \(.url)"' <<<"$1" >&2
  exit 1
}

# No checks yet on a repo that has workflows: wait out the registration grace, then ask Actions
# directly. Sets VERDICT=pending to keep polling; leaves it alone to let the rollup decide.
await_check_registration() {  # $1 seconds elapsed, $2 rollup total
  local runs
  if [ "$1" -lt "$CHECK_REGISTRATION_GRACE" ]; then VERDICT=pending; return 0; fi
  runs="$(gh_retry gh run list --commit "$HEAD_OID" --json status,conclusion,name,url)" \
    || die "cannot list workflow runs for $HEAD_OID"
  case "$(actions_runs_verdict "$runs")" in
    pending) VERDICT=pending ;;
    pass) ;;
    fail) die "PR #$PR_NUM workflow runs failed for $HEAD_OID (gh run list --commit $HEAD_OID)" ;;
    none) [ "$2" -gt 0 ] || [ "${METATE_ALLOW_NO_CHECKS:-0}" = 1 ] \
            || die "no CI checks registered after ${CHECK_REGISTRATION_GRACE}s on PR #$PR_NUM" ;;
    *) die "cannot classify workflow runs for $HEAD_OID" ;;
  esac
}

# Sets VERDICT=pass|pending, or exits. Runs in the main shell, never inside $(…): a die in a
# subshell would only end the subshell and let the caller fall through to the merge.
ci_verdict() {  # $1 PR json, $2 seconds elapsed
  local pr="$1" ms summary total
  VERDICT=""
  [ "$(jq -r .headRefOid <<<"$pr")" = "$HEAD_OID" ] \
    || die "PR #$PR_NUM headRefOid changed mid-poll (was $HEAD_OID) — re-run after reviewing the new head"
  ms="$(jq -r '.mergeStateStatus // "UNKNOWN"' <<<"$pr")"
  case "$ms" in DIRTY|BEHIND|DRAFT) die "PR #$PR_NUM mergeStateStatus is $ms" ;; esac
  summary="$(rollup_summary <<<"$pr")"
  total="$(jq .total <<<"$summary")"

  if [ "$HAS_WORKFLOWS" -eq 1 ] && [ "$(jq .checkRuns <<<"$summary")" -eq 0 ]; then
    await_check_registration "$2" "$total"
    [ -z "$VERDICT" ] || return 0
  fi
  if [ "$total" -eq 0 ]; then
    case "$ms" in
      UNKNOWN) VERDICT=pending ;;
      CLEAN|HAS_HOOKS|UNSTABLE) VERDICT=pass ;;
      *) die "PR #$PR_NUM mergeStateStatus is $ms" ;;
    esac
    return 0
  fi
  [ "$(jq '.failed | length' <<<"$summary")" -eq 0 ] || report_failures "$summary"
  if [ "$(jq .pending <<<"$summary")" -gt 0 ] || [ "$ms" = UNKNOWN ]; then VERDICT=pending; return 0; fi
  [ "$ms" != BLOCKED ] || die "PR #$PR_NUM mergeStateStatus is BLOCKED with every check complete"
  VERDICT=pass
}

wait_for_green_ci() {  # $1 initial PR json
  local pr="$1" elapsed=0
  while :; do
    ci_verdict "$pr" "$elapsed"
    [ "$VERDICT" = pending ] || return 0
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      echo "ship.sh: timed out waiting for CI checks on PR #$PR_NUM" >&2
      exit 2
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
    pr="$(pr_view)" || die "cannot read PR #$PR_NUM"
  done
}

# --- wait-and-merge --------------------------------------------------------------

parse_merge_args() {
  PR_NUM="" BASE_BRANCH="" POLL_INTERVAL="$DEFAULT_POLL_INTERVAL" TIMEOUT="$DEFAULT_TIMEOUT"
  while [ $# -gt 0 ]; do
    case "$1" in
      --base|--poll-interval|--timeout) [ -n "${2:-}" ] || die "$1 needs a value" ;;
    esac
    case "$1" in
      --base) BASE_BRANCH="$2"; shift ;;
      --poll-interval) POLL_INTERVAL="$2"; shift ;;
      --timeout) TIMEOUT="$2"; shift ;;
      -*) die "wait-and-merge: unknown flag $1" ;;
      *) if [ -z "$PR_NUM" ]; then PR_NUM="$1"
         elif [ -z "$BASE_BRANCH" ]; then BASE_BRANCH="$1"
         else die "wait-and-merge: unexpected argument $1"; fi ;;
    esac
    shift
  done
  case "$PR_NUM" in ''|*[!0-9]*) die "wait-and-merge needs a PR number, got '$PR_NUM'" ;; esac
  require_seconds --poll-interval "$POLL_INTERVAL"
  require_seconds --timeout "$TIMEOUT"
  [ -n "$BASE_BRANCH" ] || BASE_BRANCH="$(bash "$DIR/round.sh" base)"
}

preflight() {
  [ -z "$(git status --porcelain)" ] || die "working tree has uncommitted changes"
  [ "$(git rev-parse HEAD)" = "$HEAD_OID" ] \
    || die "local HEAD does not match remote PR headRefOid ($HEAD_OID) — push first"
  bash "$DIR/dod.sh" receipt "$SPRINT_DIR/dod.json" "$BASE_BRANCH" >&2 \
    || die "forensic receipt is red — no merge"
}

wait_and_merge() {
  local pr state root merge_oid
  parse_merge_args "$@"
  root="$(repo_root)"
  pr="$(pr_view)" || die "cannot read PR #$PR_NUM"
  state="$(jq -r .state <<<"$pr")"
  PR_BRANCH="$(jq -r .headRefName <<<"$pr")"
  HEAD_OID="$(jq -r .headRefOid <<<"$pr")"
  IS_CROSS_REPO="$(jq -r '.isCrossRepository // false' <<<"$pr")"
  SPRINT_DIR="$(bash "$DIR/state.sh" sprint-dir-of "$PR_BRANCH")"
  [ -n "$SPRINT_DIR" ] || die "cannot resolve sprint-dir for $PR_BRANCH"

  case "$state" in
    MERGED)
      merge_oid="$(jq -r '.mergeCommit.oid // empty' <<<"$pr")"
      post_merge_cleanup
      merged_json "$merge_oid"
      return 0 ;;
    CLOSED) die "PR #$PR_NUM is closed without merge" ;;
    OPEN) ;;
    *) die "PR #$PR_NUM has unexpected state '$state'" ;;
  esac

  preflight
  HAS_WORKFLOWS=0
  if compgen -G "$root/.github/workflows/*.yml" >/dev/null \
     || compgen -G "$root/.github/workflows/*.yaml" >/dev/null; then HAS_WORKFLOWS=1; fi
  wait_for_green_ci "$pr"

  gh pr merge "$PR_NUM" --merge --match-head-commit "$HEAD_OID" >&2 || die "gh pr merge #$PR_NUM failed"
  merge_oid="$(confirm_merge_oid)" || exit 1
  post_merge_cleanup
  merged_json "$merge_oid"
}

# --- next-in-pillar --------------------------------------------------------------

# pillars.yml → TSV. P<TAB>id<TAB>title<TAB>horizon<TAB>status, I<TAB>pillar<TAB>id<TAB>status<TAB>desc.
# Indentation is the schema: `  - id:` opens a pillar (fields at 4), `      - id:` opens an exit
# invariant (fields at 8). Quotes are stripped BEFORE comments, so 'M2 (#867)' keeps its (#867).
pillars_tsv() {
  awk -v sq="'" '
    function unquote(v, q,   i, c, out) {
      out = ""
      for (i = 2; i <= length(v); i++) {
        c = substr(v, i, 1)
        if (q == "\"" && c == "\\" && i < length(v)) { i++; out = out substr(v, i, 1); continue }
        if (c == q) {
          if (q == sq && substr(v, i + 1, 1) == sq) { out = out sq; i++; continue }
          break
        }
        out = out c
      }
      return out
    }
    function clean(v,   q) {
      sub(/^[ \t]+/, "", v)
      q = substr(v, 1, 1)
      if (q == sq || q == "\"") v = unquote(v, q)
      else { sub(/[ \t]+#.*$/, "", v); sub(/^#.*$/, "", v) }
      gsub(/\t/, " ", v); sub(/[ \t]+$/, "", v)
      return v
    }
    function indent(s) { match(s, /^ */); return RLENGTH }
    function set_field(level, key, val) { if (level == "p") p[key] = val; else inv[key] = val }
    function flush_inv() {
      if (inv_id != "") print "I\t" p_id "\t" inv_id "\t" inv["status"] "\t" inv["description"]
      inv_id = ""; split("", inv)
    }
    function flush_pillar() {
      flush_inv()
      if (p_id != "") print "P\t" p_id "\t" p["title"] "\t" p["horizon"] "\t" p["status"]
      p_id = ""; split("", p)
    }
    {
      sub(/\r$/, "")
      if (block_key != "") {
        if ($0 ~ /^[ \t]*$/ || indent($0) > block_indent) {
          line = $0; sub(/^[ \t]+/, "", line); gsub(/\t/, " ", line)
          if (line != "") block_val = (block_val == "" ? line : block_val " " line)
          next
        }
        set_field(block_level, block_key, block_val); block_key = ""
      }
    }
    /^  - id:/     { flush_pillar(); v = $0; sub(/^  - id:/, "", v); p_id = clean(v); next }
    /^      - id:/ { flush_inv(); v = $0; sub(/^      - id:/, "", v); inv_id = clean(v); next }
    {
      if ($0 ~ /^    [A-Za-z_]+:/ && p_id != "") { level = "p"; ind = 4 }
      else if ($0 ~ /^        [A-Za-z_]+:/ && inv_id != "") { level = "i"; ind = 8 }
      else next
      key = substr($0, ind + 1); sub(/:.*$/, "", key)
      val = substr($0, ind + 1); sub(/^[A-Za-z_]+:/, "", val)
      if (val ~ /^[ \t]*[>|][-+]?[ \t]*(#.*)?$/) {
        block_key = key; block_level = level; block_indent = ind; block_val = ""
      } else set_field(level, key, clean(val))
    }
    END {
      if (block_key != "") set_field(block_level, block_key, block_val)
      flush_pillar()
    }
  ' "$1"
}

pillars_json() {  # $1 = true when the file has content, so parsing nothing means mis-indentation
  jq -R -s --argjson pstat "$PILLAR_STATUSES" --argjson istat "$INVARIANT_STATUSES" --argjson strict "$1" '
    (split("\n") | map(select(length > 0) | split("\t"))) as $rows
    | ($rows | map(select(.[0] == "P") | {id: .[1], title: .[2], horizon: .[3], status: .[4]})) as $pillars
    | ($rows | map(select(.[0] == "I") | {pillar: .[1], id: .[2], status: .[3], description: (.[4] // "")})) as $invs
    | if $strict and ($pillars | length) == 0
      then error("no pillars parsed from pillars.yml — check indentation") else . end
    | (first($pillars[] | select(.id as $p | $invs | any(.pillar == $p) | not)) // null) as $bare
    | if $strict and $bare
      then error("pillar \($bare.id) has no exit_invariants parsed from pillars.yml — check indentation")
      else . end
    | (first($pillars[] | select(.status as $s | $pstat | index($s) | not)) // null) as $badp
    | if $badp then error("pillar \($badp.id) has unknown status \u0027\($badp.status)\u0027 (want \($pstat | join("|")))")
      else . end
    | (first($invs[] | select(.status as $s | $istat | index($s) | not)) // null) as $badi
    | if $badi then error("invariant \($badi.pillar)/\($badi.id) has unknown status \u0027\($badi.status)\u0027 (want \($istat | join("|")))")
      else . end
    | (first($pillars[] | select(.status == "active")) // first($pillars[] | select(.status == "planned"))
       // null) as $active
    | (if $active == null then null else
        ($invs | map(select(.pillar == $active.id))) as $mine
        | $active + {
            pendingInvariants: ($mine | map(select(.status == "pending") | {id, description})),
            verifiedCount: ($mine | map(select(.status == "verified")) | length),
            totalCount: ($mine | length)}
      end) as $ap
    | ($pillars | map(select(.status == "completed") | {id, title})) as $done
    | {activePillar: $ap,
       milestoneReadyToClose: ($ap != null and $ap.totalCount > 0 and ($ap.pendingInvariants | length) == 0),
       completedPillars: $done,
       nextPlannedPillar: (first($pillars[] | select(.status == "planned" and .id != ($active.id // null))
                           | {id, title}) // null)}
  '
}

next_in_pillar() {
  local file="${1:-$(repo_root)/docs/pillars.yml}" tsv
  if [ ! -f "$file" ]; then echo "$EMPTY_PILLARS"; return 0; fi
  tsv="$(pillars_tsv "$file")" || die "cannot parse $file"
  local strict=false
  grep -qE '^[[:space:]]*[^#[:space:]]' "$file" && strict=true
  printf '%s\n' "$tsv" | pillars_json "$strict" || die "$file failed validation"
}

USAGE="usage: ship.sh wait-and-merge PR [BASE] [--base B] [--poll-interval SEC] [--timeout SEC]
       | next-in-pillar [PILLARS_FILE]"

cmd="${1:-}"
shift || true
case "$cmd" in
  wait-and-merge) wait_and_merge "$@" ;;
  next-in-pillar) next_in_pillar "${1:-}" ;;
  *) die "$USAGE" ;;
esac
