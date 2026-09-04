#!/usr/bin/env bash
# Per-project bootstrap for the `metate` pipeline.
#
# SCOPE CONTRACT: deterministic file provisioning ONLY — prerequisite check, template
# copy, .gitignore/untrack passes, harness rule/agent installs, permission whitelist.
# Anything requiring judgment (gate detection, profile values, profile reconciliation)
# lives in the `metate` wizard skill (Step 2b). Resist growing this file.
#
# Self-contained: works whether the skills are installed user-level or per-project.
#
#   bootstrap.sh             create the profile if absent; never touch an existing one
#   bootstrap.sh --update    refresh installed harness artifacts (cursor reviewer agents).
#                            Profile reconciliation → metate wizard skill (Step 2b).
set -euo pipefail

UPDATE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update) UPDATE=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/yaml.sh"
TEMPLATE="$SCRIPT_DIR/profile.template.yml"
# cursor-rule.mdc and codex-rule.md are rendered from sources/ — run `make render`.
# Do not hand-edit; the verify drift gate enforces parity with sources/.
CURSOR_RULE="$SCRIPT_DIR/cursor-rule.mdc"
CODEX_RULE="$SCRIPT_DIR/codex-rule.md"
CURSOR_AGENTS_SRC="$SCRIPT_DIR/cursor-agents"

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
METATE_DIR="$PROJECT_ROOT/.metate"
PROFILE="$METATE_DIR/profile.yml"

echo "▸ bootstrapping metate in: $PROJECT_ROOT"

# --- required prerequisite: codebase-memory-mcp ----------------------------
# Fail fast before writing anything. Present if the CLI is on PATH OR it's wired
# as an MCP server in a known client config (a client may manage the server
# itself, leaving no binary on PATH).
# Match the full server name (not a loose 'codebase-memory' substring) so a stray
# mention in a config comment doesn't read as present.
cbm_present() {
  command -v codebase-memory-mcp >/dev/null 2>&1 && return 0
  [ -x "$HOME/.local/bin/codebase-memory-mcp" ] && return 0
  for cfg in "$HOME/.claude.json" "$HOME/.cursor/mcp.json" "$HOME/.codex/config.toml" \
             "$HOME/.grok/config.toml"; do
    [ -f "$cfg" ] && grep -qi 'codebase-memory-mcp' "$cfg" && return 0
  done
  return 1
}
if ! cbm_present; then
  echo "✗ required prerequisite missing: codebase-memory-mcp" >&2
  echo "    install it, then re-run this bootstrap:" >&2
  echo "      curl -fsSL https://raw.githubusercontent.com/DeusData/codebase-memory-mcp/7824e505c192023a21b3e90bcb98ca6210629b64/install.sh | bash" >&2
  exit 1
fi

# --- write the profile ------------------------------------------------------
mkdir -p "$METATE_DIR"

FRESH=0
if [ ! -s "$PROFILE" ]; then   # missing or empty → fresh write
  cp "$TEMPLATE" "$PROFILE"
  FRESH=1
  echo "  ✓ wrote $PROFILE (gates are placeholders — the metate wizard skill detects them)"
else
  echo "  ✓ $PROFILE already exists — left untouched (profile reconciliation → metate wizard, Step 2b)"
  # ADR-0001 move 1: state paths are fixed, not config. Under --update, retire the seven
  # path keys MECHANICALLY — a line is deleted only when its value is the default (which is
  # every field profile as of 2026-09-01); a non-default value is reported and left alone.
  # This is the one profile edit bootstrap makes: no judgment is involved.
  if [ "$UPDATE" -eq 1 ]; then
    retired=0; kept=""
    while IFS='|' read -r key def; do
      # match:  [#] key: <def>   with optional quotes and a trailing comment
      pat="^[[:space:]]*#?[[:space:]]*${key}:[[:space:]]*[\"']?${def//\//\\/}[\"']?[[:space:]]*(#.*)?\$"
      if grep -qE "$pat" "$PROFILE"; then
        sed -i.bak -E "/${pat}/d" "$PROFILE" && rm -f "$PROFILE.bak" && retired=$((retired+1))
      fi
    done <<'KEYS'
sessionFile|.metate/session.json
issueLedger|.metate/issues.json
signalsFile|.metate/signals.json
planFile|.metate/plan.md
planFile|.metate/release.json
ledger|.metate/human-gates.json
matrix|
KEYS
    for key in sessionFile issueLedger signalsFile planFile ledger matrix; do
      grep -qE "^[[:space:]]*${key}:" "$PROFILE" && kept="$kept $key"
    done
    [ "$retired" -gt 0 ] && echo "  ✓ retired $retired fixed-path key(s) from profile (ADR-0001 move 1)"
    [ -n "$kept" ] && echo "  ⚠ non-default path key(s) left in profile — state paths are fixed now; review:$kept"
    # ADR-0001 move 2: YAML block nest/rename is python3 (see ADR exception). Missing binary must be loud.
    if ! command -v python3 >/dev/null 2>&1; then
      echo "  ⚠ python3 not found — skipped ADR-0001 profile migration (nest/rename). Install python3 and re-run: metate-init --update" >&2
    else
    # ADR-0001 move 2a: nest top-level reviewer:/review: under build:. Values unchanged.
    if nest_out="$(python3 - "$PROFILE" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
if re.search(r"^build:", text, re.M):
    sys.exit(0)
if not re.search(r"^reviewer:", text, re.M) and not re.search(r"^review:", text, re.M):
    sys.exit(0)
lines = text.splitlines(keepends=True)

def col0_key(line):
    s = line.split("#", 1)[0].rstrip()
    if not s or s[:1] in " \t":
        return None
    m = re.match(r"^([A-Za-z0-9_.-]+):", s)
    return m.group(1) if m else None

def block_at(key):
    start = None
    for i, line in enumerate(lines):
        if col0_key(line) == key:
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if col0_key(lines[j]) is not None:
            end = j
            break
    while end > start + 1:
        prev = lines[end - 1]
        stripped = prev.strip()
        # Drop blanks and column-0 comments (the next section's header). Keep
        # indented comments — they belong to this mapping.
        if not stripped:
            end -= 1
        elif prev[:1] not in " \t" and stripped.startswith("#"):
            end -= 1
        else:
            break
    return start, end

chunks = []
for key in ("reviewer", "review"):
    loc = block_at(key)
    if loc:
        chunks.append((key, loc[0], loc[1], lines[loc[0]:loc[1]]))
if not chunks:
    sys.exit(0)
# Drop extracted ranges from the bottom so earlier indices stay valid.
body = []
for key, _s, _e, block in chunks:
    body.extend(["  " + ln if ln.strip() else ln for ln in block])
header = ["# --- build (metate-build): round 0 writes, rounds 1–3 review\n", "build:\n"]
insert_at = chunks[0][1]
# If a comment line immediately above the first block looks like the old reviewer header, replace it.
ranges = sorted(((s, e) for _k, s, e, _b in chunks), reverse=True)
out = list(lines)
for s, e in ranges:
    del out[s:e]
# After deletions, insert_at still points at the first block's original start only if
# nothing before it was deleted — reviewer is the first chunk, so that holds.
out[insert_at:insert_at] = header + body
open(path, "w").write("".join(out))
print("nested")
PY
)"; then
      [ "$nest_out" = nested ] && echo "  ✓ nested reviewer:/review: under build: (ADR-0001 move 2a)"
    fi
    # ADR-0001 move 2b: rename stage blocks; fold aftercare children under ship.
    if rename_out="$(python3 - "$PROFILE" <<'PY'
import re, sys
path = sys.argv[1]
lines = open(path).read().splitlines(keepends=True)

def col0(line):
    s = line.split("#", 1)[0].rstrip()
    if not s or s[:1] in " \t":
        return None
    m = re.match(r"^([A-Za-z0-9_.-]+):", s)
    return m.group(1) if m else None

def block(key):
    start = None
    for i, ln in enumerate(lines):
        if col0(ln) == key:
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if col0(lines[j]) is not None:
            end = j
            break
    return start, end

notes = []
renames = (("discover", "scope"), ("prep", "start"), ("smoke", "verify"))
for old, new in renames:
    for i, ln in enumerate(lines):
        if col0(ln) == old:
            lines[i] = ln.replace(old + ":", new + ":", 1)
            notes.append(old + "→" + new)
            break

ac = block("aftercare")
sh = block("ship")
if ac and sh:
    ac_s, ac_e = ac
    children = lines[ac_s + 1:ac_e]
    while children:
        prev = children[-1]
        stripped = prev.strip()
        if not stripped:
            children.pop()
        elif prev[:1] not in " \t" and stripped.startswith("#"):
            children.pop()
        else:
            break
    if children and children[-1].strip():
        children.append("\n")
    sh_s, _ = sh
    # delete aftercare first if it sits before ship (it does)
    if ac_s < sh_s:
        del lines[ac_s:ac_e]
        sh_s -= (ac_e - ac_s)
    else:
        del lines[ac_s:ac_e]
        sh = block("ship")
        sh_s = sh[0]
    lines[sh_s + 1:sh_s + 1] = children
    notes.append("aftercare→ship")
if notes:
    open(path, "w").write("".join(lines))
    print(" ".join(notes))
PY
)"; then
      [ -n "$rename_out" ] && echo "  ✓ renamed profile blocks ($rename_out) (ADR-0001 move 2b)"
    fi
    if flat_out="$(python3 - "$PROFILE" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path).read()
new, n = re.subn(r"(?m)^  review:\n    autoFix:", "  autoFix:", text, count=1)
if n:
    open(path, "w").write(new)
    print("flattened")
PY
)"; then
      [ "$flat_out" = flattened ] && echo "  ✓ flattened build.review.autoFix → build.autoFix (ADR-0001 move 3)"
    fi
    dod_sh="$SCRIPT_DIR/../metate/lib/dod.sh"
    if [ -f "$dod_sh" ]; then
      bash "$dod_sh" migrate "$METATE_DIR" || true
    fi
    fi
  fi
fi

# --- gitignore: per-sprint local state + vendored tooling -------------------
GI="$PROJECT_ROOT/.gitignore"

# Append a gitignore rule once (idempotent), then stop tracking anything it now
# covers that a previous install committed. The pattern doubles as a git pathspec.
gi_ignore_untrack() {
  local pat="$1" comment="$2"
  if ! { [ -f "$GI" ] && grep -qxF "$pat" "$GI"; }; then
    { echo "# $comment"; echo "$pat"; } >> "$GI"
    echo "  ✓ added $pat to .gitignore"
  fi
  if [ -n "$(git -C "$PROJECT_ROOT" ls-files "$pat" 2>/dev/null)" ]; then
    # Pipe -z straight to xargs — capturing it in $() strips the null separators.
    git -C "$PROJECT_ROOT" ls-files -z "$pat" \
      | xargs -0 git -C "$PROJECT_ROOT" rm -r --cached --quiet -- \
      && echo "  ✓ untracked previously-committed $pat (commit to finish)"
  fi
}

# Per-sprint local state: these files are runtime-only and never committed, so
# they need the .gitignore entry but no untrack pass — hence hand-rolled rather
# than routed through gi_ignore_untrack (whose untrack step would be a no-op).
if ! { [ -f "$GI" ] && grep -qE '^\.metate/session\.json' "$GI"; }; then
  { echo ""; echo "# metate session handoff"; echo ".metate/session.json"; } >> "$GI"
  echo "  ✓ added .metate/session.json to .gitignore"
fi
if ! { [ -f "$GI" ] && grep -qxF '.metate/.session-start.json' "$GI"; }; then
  { echo "# metate transient session-id capture buffer"; echo ".metate/.session-start.json"; } >> "$GI"
  echo "  ✓ added .metate/.session-start.json to .gitignore"
fi
if ! { [ -f "$GI" ] && grep -qE '^\.metate/dod\.json' "$GI"; }; then
  { echo "# metate DoD ledger (per-sprint; start overwrites)"; echo ".metate/dod.json"; } >> "$GI"
  echo "  ✓ added .metate/dod.json to .gitignore"
fi
# Project-level skill installs are vendored tooling whose source of truth is the
# metate repo — don't track them, or every skill update is noise in this project.
# (.metate/profile.yml stays tracked: it's this project's config.) Skipped for
# user-level installs, where the skills live in ~/.claude/skills and ~/.agents/skills,
# not the project.
if compgen -G "$PROJECT_ROOT/.claude/skills/metate-*" >/dev/null 2>&1; then
  gi_ignore_untrack '.claude/skills/metate-*' 'metate skills are installed tooling (source of truth: metate repo)'
fi
if compgen -G "$PROJECT_ROOT/.agents/skills/metate-*" >/dev/null 2>&1; then
  gi_ignore_untrack '.agents/skills/metate-*' 'metate Codex skills are installed tooling (source of truth: metate repo)'
fi

# --- codebase-memory-mcp: configure (presence guaranteed by the guard above) -
# cbm gives review sub-agents a structural knowledge graph (prefer it over grep).
# CBM_BIN may be empty when a client manages the server itself (no PATH binary);
# that only changes the wording of the messages below, not the wiring.
CBM_BIN="$(command -v codebase-memory-mcp 2>/dev/null || true)"
[ -z "$CBM_BIN" ] && [ -x "$HOME/.local/bin/codebase-memory-mcp" ] && CBM_BIN="$HOME/.local/bin/codebase-memory-mcp"

if [ -n "$CBM_BIN" ]; then
  echo "  ✓ codebase-memory-mcp detected: $CBM_BIN"
else
  echo "  ✓ codebase-memory-mcp detected: registered as an MCP server (CLI not on PATH)"
fi

# The template ships codebaseMemory.enabled: true, so a fresh profile is already
# graph-on. Existing profiles are never clobbered — if a repo was opted out
# (enabled:false), leave that choice and just note it. Scope the check to the
# codebaseMemory block so an unrelated `enabled: true` elsewhere can't mask it.
if [ "$FRESH" = 1 ]; then
  echo "  ✓ codebaseMemory.enabled: true (template default)"
else
  [ "$(yaml_nested_scalar "$PROFILE" codebaseMemory enabled)" = "true" ] \
    || echo "  • existing profile has codebaseMemory.enabled: false — left as-is; set it true to use the graph"
fi

# Report the reviewer backend. Nested under build: after ADR-0001 move 2a; fall back to
# the pre-nest top-level key so a profile that has not been --update'd still prints.
REVIEWER_BACKEND="$(yaml_deep_scalar "$PROFILE" build reviewer backend)"
[ -z "$REVIEWER_BACKEND" ] && REVIEWER_BACKEND="$(yaml_nested_scalar "$PROFILE" reviewer backend)"
echo "  ✓ build.reviewer.backend: ${REVIEWER_BACKEND:-claude} (per-lens overrides optional; see metate-build/REVIEWERS.md)"

# Drop the Cursor rule (idempotent; only if Cursor is installed, never clobber).
if [ -d "$HOME/.cursor" ]; then
  RULE_DIR="$PROJECT_ROOT/.cursor/rules"
  RULE_DEST="$RULE_DIR/codebase-memory.mdc"
  if [ -f "$RULE_DEST" ] && [ "$UPDATE" -eq 0 ]; then
    echo "  ✓ Cursor rule already present — left untouched"
  elif [ -f "$RULE_DEST" ] && [ -f "$CURSOR_RULE" ]; then
    if cmp -s "$CURSOR_RULE" "$RULE_DEST"; then
      echo "  ✓ Cursor rule already current"
    else
      cp "$CURSOR_RULE" "$RULE_DEST"
      echo "  ✓ refreshed Cursor rule: .cursor/rules/codebase-memory.mdc (--update)"
    fi
  elif [ -f "$CURSOR_RULE" ]; then
    mkdir -p "$RULE_DIR"
    cp "$CURSOR_RULE" "$RULE_DEST"
    echo "  ✓ installed Cursor rule: .cursor/rules/codebase-memory.mdc"
  fi
fi
# The Cursor rule is a vendored copy of cursor-rule.mdc — ignore (and untrack)
# it like the skills, so its source of truth stays the metate repo. The guard is
# the file's existence, NOT whether Cursor is installed: that single path is owned
# by codebase-memory, so untracking it is safe however it got there.
if [ -f "$PROJECT_ROOT/.cursor/rules/codebase-memory.mdc" ]; then
  gi_ignore_untrack '.cursor/rules/codebase-memory.mdc' 'codebase-memory Cursor rule is installed tooling (source: metate repo)'
fi

# Drop metate reviewer subagents for Cursor IDE fanOut (idempotent; refresh on --update).
if [ -d "$HOME/.cursor" ] && [ -d "$CURSOR_AGENTS_SRC" ]; then
  AGENTS_DIR="$PROJECT_ROOT/.cursor/agents"
  mkdir -p "$AGENTS_DIR"
  installed=0
  refreshed=0
  for src in "$CURSOR_AGENTS_SRC"/metate-*.md; do
    [ -f "$src" ] || continue
    dest="$AGENTS_DIR/$(basename "$src")"
    if [ -f "$dest" ] && [ "$UPDATE" -eq 0 ]; then
      continue
    fi
    if [ -f "$dest" ]; then
      refreshed=$((refreshed + 1))
    else
      installed=$((installed + 1))
    fi
    cp "$src" "$dest"
  done
  if [ "$installed" -gt 0 ]; then
    echo "  ✓ installed $installed metate reviewer agent(s): .cursor/agents/metate-*.md"
  elif [ "$refreshed" -gt 0 ]; then
    echo "  ✓ refreshed $refreshed metate reviewer agent(s) (--update)"
  else
    echo "  ✓ metate reviewer agents already present — left untouched"
  fi
  gi_ignore_untrack '.cursor/agents/metate-*.md' 'metate reviewer agents are installed tooling (source: metate repo)'
fi

# Codex has no per-rule dir — it reads AGENTS.md. Inject the same guidance as a
# managed, marker-delimited block: append once, leave untouched if present.
# AGENTS.md is shared project content (like CLAUDE.md), so it stays TRACKED.
if command -v codex >/dev/null 2>&1 || command -v grok >/dev/null 2>&1; then
  AGENTS="$PROJECT_ROOT/AGENTS.md"
  # Defer to any existing block — ours OR the codebase-memory-mcp installer's
  # (global ~/.codex/AGENTS.md uses the `codebase-memory-mcp:` marker), so a
  # project that already carries either doesn't get duplicate guidance.
  # Grok also loads AGENTS.md, so the same inject covers both backends.
  if [ -f "$AGENTS" ] && grep -qE 'metate:codebase-memory|codebase-memory-mcp:' "$AGENTS"; then
    echo "  ✓ Codex/Grok AGENTS.md guidance already present — left untouched"
  elif [ -f "$CODEX_RULE" ]; then
    # Separate from existing content with a blank line — but only if the file is
    # already non-empty (the >> below would otherwise create it first).
    [ -s "$AGENTS" ] && echo "" >> "$AGENTS"
    { echo "<!-- metate:codebase-memory start -->"
      cat "$CODEX_RULE"
      echo "<!-- metate:codebase-memory end -->"; } >> "$AGENTS"
    echo "  ✓ added codebase-memory guidance to AGENTS.md (Codex/Grok)"
  else
    echo "  • AGENTS.md guidance skipped — codex-rule.md not found at $CODEX_RULE" >&2
  fi
fi

if [ -n "$CBM_BIN" ]; then
  echo "  → index this repo so the graph isn't empty: $CBM_BIN cli index_repository '{\"path\":\"$PROJECT_ROOT\"}'"
else
  echo "  → index this repo so the graph isn't empty (run codebase-memory's index_repository on: $PROJECT_ROOT)"
fi

# --- autonomous implementer: whitelist the headless subprocess call ---
# Headless implementer CLIs write files + run the gate with no TTY, so each spawn would
# otherwise hit the orchestrator's permission classifier and stall the loop. A session
# can't self-grant this rule (the self-modification guard rightly blocks it) — but this
# installer is user-invoked, so it's the one place that legitimately can. Personal +
# gitignored + opt-in: only when implementer.autonomous is true and backend is recognized.
IMPL_BACKEND="$(yaml_nested_scalar "$PROFILE" implementer backend)"
IMPL_AUTONOMOUS="$(yaml_nested_scalar "$PROFILE" implementer autonomous)"
RULE=""
case "$IMPL_BACKEND" in
  claude) RULE='Bash(claude -p:*)' ;;
  cursor) RULE='Bash(cursor-agent:*)' ;;
  codex)  RULE='Bash(codex:*)' ;;
  grok)   RULE='Bash(grok -p:*)' ;;
esac
if [ "$IMPL_AUTONOMOUS" = "true" ] && [ -z "$RULE" ]; then
  echo "  • autonomous: unrecognized implementer.backend '${IMPL_BACKEND:-<blank>}' — no permission grant written"
fi
if [ "$IMPL_AUTONOMOUS" = "true" ] && [ -n "$RULE" ]; then
  SETTINGS_DIR="$PROJECT_ROOT/.claude"
  SETTINGS="$SETTINGS_DIR/settings.local.json"
  # Already granted in either the committed or the personal settings file? Done.
  if { [ -f "$SETTINGS_DIR/settings.json" ] && grep -qF "$RULE" "$SETTINGS_DIR/settings.json"; } \
     || { [ -f "$SETTINGS" ] && grep -qF "$RULE" "$SETTINGS"; }; then
    echo "  ✓ autonomous: $RULE already whitelisted — left untouched"
  elif [ ! -f "$SETTINGS" ]; then
    mkdir -p "$SETTINGS_DIR"
    cat > "$SETTINGS" <<JSON
{
  "permissions": {
    "allow": [
      "$RULE"
    ]
  }
}
JSON
    echo "  ✓ autonomous: wrote .claude/settings.local.json whitelisting $RULE"
  elif command -v jq >/dev/null 2>&1; then
    STMP="$(mktemp)"
    jq --arg rule "$RULE" '.permissions.allow = ((.permissions.allow // []) + [$rule] | unique)' \
      "$SETTINGS" > "$STMP" && mv "$STMP" "$SETTINGS"
    echo "  ✓ autonomous: merged $RULE into existing .claude/settings.local.json"
  else
    echo "  • autonomous: .claude/settings.local.json exists but jq is missing —" >&2
    echo "    add this rule under permissions.allow yourself: $RULE" >&2
  fi
  # settings.local.json is personal/per-developer — never commit it.
  if ! { [ -f "$GI" ] && grep -qxF '.claude/settings.local.json' "$GI"; }; then
    { echo "# metate autonomous implementer permission (personal, per-developer)"
      echo ".claude/settings.local.json"; } >> "$GI"
    echo "  ✓ added .claude/settings.local.json to .gitignore"
  fi
fi

cat <<EOF

✓ bootstrap complete. Next:
  1. Run the \`metate\` wizard skill in your harness — it detects fastGate/shipGate and
     fills reviewFocus (your invariants), backends, and the stage config with you.
  2. Run the pipeline ceremonies as skills in your harness, in order:
       metate-scope → metate-start → metate-build → metate-verify → metate-ship → metate-ship
  3. metate-build round 0 writes .metate/session.json; rounds 1–3 resume it (see metate-build/IMPLEMENTERS.md).
EOF
