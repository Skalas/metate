#!/usr/bin/env bash
# round.sh — script-owned review rounds (ADR-0005). The orchestrator never hand-writes rounds[].
#
#   round.sh tree [BASE]           {"codeTreeSha":…,"patchId":…,"baseSha":…} for the working tree
#   round.sh base                  the base branch: profile start.baseBranch, else main
#   round.sh prompt maker|reviewer OUT [TASK_FILE]
#   round.sh record DOD --round N --gate pass|red|pending [--base BRANCH]
#                   [--lens NAME:JSON ...] [--failed-lens NAME ...]
#   round.sh adjudicate DOD --round N --id ID --disposition fixed|declined|deferred|open
#                   [--rationale TEXT]
#
# codeTreeSha hashes CODE only: close-out docs written after the final round (docs/, README.md,
# CHANGELOG.md) must not void the receipt. UNTRACKED files named like secrets (.env, *.pem,
# id_rsa, …) are never staged, so hashing never writes their content into the object store.
# Tracked files are always hashed, whatever their name: they are the repository's code.
# patchId is the sha256 of the canonical baseSha..codeTreeSha code diff, where baseSha is the
# merge base. It lets a receipt survive a clean rebase — and only a rebase, i.e. a moved
# baseSha. A plain BASE prefers origin/BASE — after `git rebase origin/main` local main is stale.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$DIR/../../metate-build"
FALLBACK_BASE=main
DOC_PATHS=(docs README.md CHANGELOG.md)
SECRET_GLOBS=('.env' '.env.*' '*.env' '*.envrc' '.netrc' '.npmrc' '.git-credentials'
  '*.pem' '*.key' '*.p12' '*.pfx' '*.jks' '*.keystore'
  'id_rsa*' 'id_dsa*' 'id_ecdsa*' 'id_ed25519*'
  'credentials.json' 'secrets.json' 'secrets.yml' 'secrets.yaml')
GATES="pass|red|pending"
DISPOSITIONS="fixed|declined|deferred|open"

die() { echo "round.sh: $*" >&2; exit 1; }

TMP_PATHS=()
cleanup() { [ ${#TMP_PATHS[@]} -eq 0 ] || rm -rf "${TMP_PATHS[@]}"; }
trap cleanup EXIT

# --- tree identity ------------------------------------------------------------

# Profile start.baseBranch, so tree, record and receipt agree on one base without flags.
default_base() {
  local profile base=""
  profile="$(bash "$DIR/state.sh" repo-dir 2>/dev/null)/profile.yml" || profile=""
  if [ -f "$profile" ]; then
    # shellcheck disable=SC1091  # sibling skill dir, resolved at run time
    . "$BUILD_DIR/lib/yaml.sh"
    base="$(yaml_nested_scalar "$profile" start baseBranch)"
  fi
  printf '%s\n' "${base:-$FALLBACK_BASE}"
}

doc_pathspecs() {  # $1 = "" | "exclude,"
  local p
  for p in "${DOC_PATHS[@]}"; do printf ':(%stop)%s\n' "$1" "$p"; done
}

secret_exclude_pathspecs() {
  local p
  for p in "${SECRET_GLOBS[@]}"; do printf ':(exclude,top,glob)**/%s\n' "$p"; done
}

code_tree_sha() {
  local top git_index tmp_index doc_excludes=() doc_paths=() secret_excludes=() line sha
  top="$(git rev-parse --show-toplevel)" || die "not inside a git worktree"
  git_index="$(git rev-parse --path-format=absolute --git-path index)"
  tmp_index="$(mktemp)"
  if [ -f "$git_index" ]; then cp "$git_index" "$tmp_index"; else rm -f "$tmp_index"; fi
  while IFS= read -r line; do doc_excludes+=("$line"); done < <(doc_pathspecs "exclude,")
  while IFS= read -r line; do doc_paths+=("$line"); done < <(doc_pathspecs "")
  while IFS= read -r line; do secret_excludes+=("$line"); done < <(secret_exclude_pathspecs)
  # Tracked edits first (every name), then untracked files minus secret names: `add -u` never
  # adds a new path, and the second pass cannot touch a tracked secret-named file's entry.
  # Usually run inside $(…), where the EXIT trap does not reach: clean up explicitly.
  sha="$(
    export GIT_INDEX_FILE="$tmp_index"
    cd "$top"
    [ -f "$tmp_index" ] || git read-tree --empty
    git add -u -- . "${doc_excludes[@]}"
    git add -A -- . "${doc_excludes[@]}" "${secret_excludes[@]}"
    git rm --cached -r -f -q --ignore-unmatch -- "${doc_paths[@]}" >/dev/null
    git write-tree
  )" || { rm -f "$tmp_index"; die "could not hash the working tree"; }
  rm -f "$tmp_index"
  printf '%s\n' "$sha"
}

resolve_base() {
  local ref="$1"
  case "$ref" in
    HEAD*|*/*|*[~^:@]*) ;;
    *) git rev-parse --verify -q "refs/remotes/origin/$ref^{commit}" >/dev/null && ref="origin/$ref" ;;
  esac
  printf '%s' "$ref"
}

# Diffing against the hashed tree (not the worktree) keeps patchId over exactly the paths
# codeTreeSha covers, untracked code included.
# Not `git patch-id`: it ignores whitespace, and whitespace is semantics (`rm -rf "$P"/tmp` vs
# `rm -rf "$P" /tmp`, a dedented Python line). The canonical form is the full binary diff with
# 3 lines of context, minus only what a clean rebase moves: `index` blob ids and the numeric
# coordinates of `@@` headers. Context anchors each hunk to the code around it (an added line
# moved elsewhere in its file changes the digest); `--binary` keeps binary edits in it.
patch_id_between() {  # $1 = base commit, $2 = code tree
  local doc_excludes=() line diff id
  while IFS= read -r line; do doc_excludes+=("$line"); done < <(doc_pathspecs "exclude,")
  diff="$(mktemp)"
  git -C "$(git rev-parse --show-toplevel)" diff --no-color --no-ext-diff --no-renames --binary -U3 \
    "$1" "$2" -- . "${doc_excludes[@]}" \
    | sed -E '/^index [0-9a-f]+\.\.[0-9a-f]+/d; s/^@@ -[0-9,]+ \+[0-9,]+ @@/@@ @@/' > "$diff"
  if [ -s "$diff" ]; then id="$(file_sha256 "$diff")"; else id=empty; fi
  rm -f "$diff"
  printf '%s\n' "$id"
}

tree_json() {
  local base merge_base tree
  base="$(resolve_base "${1:-$(default_base)}")"
  # No fallback to HEAD: that would make baseSha HEAD and patchId "empty", and the next commit
  # would compare a fresh empty diff against a stale one. An unknown base is an error.
  merge_base="$(git merge-base "$base" HEAD 2>/dev/null)" \
    || die "cannot resolve merge-base against '$base'"
  tree="$(code_tree_sha)"
  printf '{"codeTreeSha":"%s","patchId":"%s","baseSha":"%s"}\n' \
    "$tree" "$(patch_id_between "$merge_base" "$tree")" "$merge_base"
}

# --- prompt assembly ------------------------------------------------------------
# Written with cat/printf only: reviewFocus routinely quotes `backticks` and $VARS, and a
# double-quoted heredoc or "$(…)" prompt string would execute them.

role_preamble() {
  case "$1" in
    maker)    echo "Your change must hold every invariant below; violating one is a blocker." ;;
    reviewer) echo "Scrutinize the diff against every invariant below; a violation is a blocker." ;;
    *) die "role must be maker|reviewer, got '$1'" ;;
  esac
}

assemble_prompt() {
  local role="$1" out="$2" task="${3:-}" profile focus preamble
  preamble="$(role_preamble "$role")"
  profile="$(bash "$DIR/state.sh" repo-dir)/profile.yml"
  [ -f "$profile" ] || die "missing $profile — run the metate wizard"
  # shellcheck disable=SC1091  # sibling skill dir, resolved at run time
  . "$BUILD_DIR/lib/yaml.sh"
  focus="$(yaml_block "$profile" reviewFocus)"
  [ -n "$focus" ] || die "reviewFocus is empty in $profile — run the metate wizard"
  [ -z "$task" ] || [ -f "$task" ] || die "missing task file $task"
  {
    printf '## Project invariants (reviewFocus)\n\n%s\n\n%s\n' "$preamble" "$focus"
    if [ "$(yaml_nested_scalar "$profile" codebaseMemory enabled)" != false ]; then
      printf '\n'; cat "$BUILD_DIR/generated/prompt-clause.md"
    fi
    if [ -n "$task" ]; then printf '\n'; cat "$task"; fi
  } > "$out"
}

# --- dod.json writes ------------------------------------------------------------

file_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  else sha256sum "$1" | awk '{print $1}'; fi
}

lens_report_ok() {
  jq -e '(.findings|type) == "array"
         and all(.findings[]; (.summary|type) == "string" and (.summary|length) > 0
                 and (.bucket == "blocker" or .bucket == "warning" or .bucket == "suggestion"))' \
    "$1" >/dev/null 2>&1
}

json_strings() { jq -n '$ARGS.positional' --args "$@"; }

# Validate the candidate before it replaces anything: a bad write never lands.
commit_dod() {  # $1 = dod path, $2 = candidate
  bash "$DIR/dod.sh" dod "$2" >/dev/null || die "refusing to write an invalid $1"
  mv "$2" "$1"
}

require_value() { [ -n "${2:-}" ] || die "$1 needs a value"; }

require_round_number() {
  case "$1" in ''|*[!0-9]*|0) die "--round must be a positive integer, got '$1'" ;; esac
}

record_round() {
  local dod="$1"; shift
  local n="" gate="" base="" specs=() failed=()
  while [ $# -gt 0 ]; do
    require_value "$1" "${2:-}"
    case "$1" in
      --round) n="$2" ;;
      --gate) gate="$2" ;;
      --base) base="$2" ;;
      --lens) specs+=("$2") ;;
      --failed-lens) failed+=("$2") ;;
      *) die "record: unknown arg $1" ;;
    esac
    shift 2
  done
  [ -f "$dod" ] || die "missing $dod"
  require_round_number "$n"
  case "|$GATES|" in *"|$gate|"*) ;; *) die "--gate must be $GATES, got '$gate'" ;; esac

  local prior_gate
  prior_gate="$(jq -r --argjson n "$n" '[(.rounds // [])[] | select(.n == $n) | .gate][0] // ""' "$dod")"
  case "$prior_gate" in
    ''|pending) ;;
    *) die "round $n is already closed (gate=$prior_gate) — record round $((n + 1)) instead" ;;
  esac

  local candidate
  candidate="$(mktemp "$dod.XXXXXX")"
  TMP_PATHS+=("$candidate")
  if [ ${#specs[@]} -eq 0 ] && [ ${#failed[@]} -eq 0 ]; then
    [ -n "$prior_gate" ] || { die "a new round needs at least one --lens or --failed-lens"; }
    close_round "$dod" "$n" "$gate" > "$candidate"
  else
    local tree
    tree="$(tree_json "$base")"
    [ -z "$prior_gate" ] || require_same_tree "$dod" "$n" "$tree"
    write_round "$dod" "$n" "$gate" "$tree" "${#specs[@]}" ${specs[@]+"${specs[@]}"} \
      ${failed[@]+"${failed[@]}"} > "$candidate"
  fi
  commit_dod "$dod" "$candidate"
  echo "  ✓ round $n recorded (gate=$gate) → $dod"
}

# Re-recording a pending round re-runs its lenses on the tree it opened on. A patched tree is
# a new review: it gets round N+1, or a fix could overwrite the stamp of the round it answers.
require_same_tree() {  # $1 dod, $2 n, $3 tree json
  local opened now
  opened="$(jq -r --argjson n "$2" '[.rounds[] | select(.n == $n) | .codeTreeSha][0] // ""' "$1")"
  now="$(jq -r .codeTreeSha <<<"$3")"
  [ -z "$opened" ] || [ "$opened" = "$now" ] \
    || die "round $2 was opened on tree $opened but the tree is now $now — record round $(($2 + 1)) instead"
}

# Closing a pending round keeps the tree it REVIEWED. Re-stamping here would certify a patch
# the fan-out never saw — exactly the gap the receipt exists to close.
close_round() {  # $1 dod, $2 n, $3 gate
  jq --argjson n "$2" --arg gate "$3" \
    '.rounds |= map(if .n == $n then .gate = $gate else . end)' "$1"
}

write_round() {  # $1 dod, $2 n, $3 gate, $4 tree json, $5 #specs, then specs…, then failed names…
  local dod="$1" n="$2" gate="$3" tree="$4" nspecs="$5"; shift 5
  local work names=() failed=() spec name file hash i=0
  work="$(mktemp -d)"
  TMP_PATHS+=("$work")
  : > "$work/reports.jsonl"; : > "$work/hashes.jsonl"
  while [ "$i" -lt "$nspecs" ]; do
    spec="$1"; shift; i=$((i + 1))
    case "$spec" in *:*) ;; *) die "--lens wants NAME:JSON, got '$spec'" ;; esac
    name="${spec%%:*}"; file="${spec#*:}"
    [ -n "$name" ] || die "--lens wants NAME:JSON, got '$spec'"
    names+=("$name")
    if [ -f "$file" ] && lens_report_ok "$file"; then
      hash="$(file_sha256 "$file")"
      jq -c --arg lens "$name" '{lens: $lens, findings: .findings}' "$file" >> "$work/reports.jsonl"
      jq -nc --arg k "$name" --arg v "$hash" '{key: $k, value: $v}' >> "$work/hashes.jsonl"
    else
      echo "round.sh: lens $name has no valid report at $file — recorded as failed" >&2
      failed+=("$name")
    fi
  done
  for name in "$@"; do names+=("$name"); failed+=("$name"); done
  jq --argjson n "$n" --arg gate "$gate" --argjson tree "$tree" \
     --argjson lenses "$(json_strings ${names[@]+"${names[@]}"} | jq 'unique')" \
     --argjson failed "$(json_strings ${failed[@]+"${failed[@]}"} | jq 'unique')" \
     --slurpfile reports "$work/reports.jsonl" --slurpfile hashes "$work/hashes.jsonl" '
    def key: [.file, .line, .summary] | tojson;
    ([(.rounds // [])[] | select(.n == $n)][0].findings // []
      | map({key: key, value: {disposition, rationale}}) | from_entries) as $prior
    | (reduce ($reports | map(.findings[]) | .[]) as $f ([];
        if any(.[]; key == ($f | key)) then . else . + [$f] end)) as $unique
    | ($unique | to_entries | map(
        .value as $f | ($prior[$f | key] // {}) as $p
        | {id: "R\($n)-\(.key + 1)", file: ($f.file // ""), line: ($f.line // 0),
           bucket: $f.bucket, summary: $f.summary}
        + (if $f.consequence then {consequence: $f.consequence} else {} end)
        + (if $p.disposition == "declined" then {rationale: $p.rationale}
           elif $f.rationale then {rationale: $f.rationale} else {} end)
        + {disposition: ($p.disposition // "open")})) as $findings
    | {n: $n, gate: $gate, codeTreeSha: $tree.codeTreeSha, patchId: $tree.patchId,
       baseSha: $tree.baseSha,
       lenses: $lenses, failedLenses: $failed, artifactHashes: ($hashes | from_entries),
       findings: $findings} as $round
    | .rounds = ([(.rounds // [])[] | select(.n != $n)] + [$round] | sort_by(.n))
  ' "$dod"
}

adjudicate() {
  local dod="$1"; shift
  local n="" id="" disposition="" rationale=""
  while [ $# -gt 0 ]; do
    require_value "$1" "${2:-}"
    case "$1" in
      --round) n="$2" ;;
      --id) id="$2" ;;
      --disposition) disposition="$2" ;;
      --rationale) rationale="$2" ;;
      *) die "adjudicate: unknown arg $1" ;;
    esac
    shift 2
  done
  [ -f "$dod" ] || die "missing $dod"
  require_round_number "$n"
  [ -n "$id" ] || die "adjudicate needs --id"
  case "|$DISPOSITIONS|" in *"|$disposition|"*) ;; *) die "--disposition must be $DISPOSITIONS, got '$disposition'" ;; esac
  [ "$disposition" != declined ] || [ -n "$rationale" ] || die "declining $id needs --rationale"
  jq -e --argjson n "$n" --arg id "$id" \
    'any((.rounds // [])[] | select(.n == $n) | .findings[]; .id == $id)' "$dod" >/dev/null \
    || die "no finding $id in round $n"
  local candidate
  candidate="$(mktemp "$dod.XXXXXX")"
  TMP_PATHS+=("$candidate")
  jq --argjson n "$n" --arg id "$id" --arg d "$disposition" --arg r "$rationale" '
    .rounds |= map(if .n != $n then . else
      .findings |= map(if .id != $id then . else
        .disposition = $d | if $r != "" then .rationale = $r else . end end) end)
  ' "$dod" > "$candidate"
  commit_dod "$dod" "$candidate"
  echo "  ✓ $id → $disposition"
}

USAGE="usage: round.sh tree [BASE] | base | prompt maker|reviewer OUT [FILE]
       | record DOD --round N --gate $GATES [--base B] [--lens NAME:JSON ...] [--failed-lens NAME ...]
       | adjudicate DOD --round N --id ID --disposition $DISPOSITIONS [--rationale TEXT]"

cmd="${1:-}"
shift || true
case "$cmd" in
  tree)       tree_json "${1:-}" ;;
  base)       default_base ;;
  prompt)     [ $# -ge 2 ] || die "$USAGE"; assemble_prompt "$@" ;;
  record)     [ $# -ge 1 ] || die "$USAGE"; record_round "$@" ;;
  adjudicate) [ $# -ge 1 ] || die "$USAGE"; adjudicate "$@" ;;
  *) die "$USAGE" ;;
esac
