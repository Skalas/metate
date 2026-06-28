# reconcile-profile.awk — non-destructive profile/template key merge.
#
#   awk -f reconcile-profile.awk PROFILE TEMPLATE
#
# Emits a reconciled profile on stdout: every line of PROFILE verbatim, plus any
# key present in TEMPLATE but missing from PROFILE, inserted under its parent
# block (nested keys) or appended at root (top-level keys). Existing lines are
# never modified or reordered, so a user's tuned values and comments survive.
# Idempotent: an up-to-date profile comes out byte-identical. The list of
# inserted key paths is written to stderr, one per line, prefixed "+ ".
#
# Indentation defines structure (2 spaces per level, matching the template).
# Comments, blank lines, block scalars and list items ride along inside the
# subtree of the key they belong to — they are never treated as keys themselves.

function indent_of(line,   n) {
  n = 0
  while (substr(line, n + 1, 1) == " ") n++
  return n
}

# The key name on a line, or "" when the line is not a `key:` mapping entry
# (comment, blank, list item `-`, or a block-scalar continuation line).
function key_of(line,   s) {
  s = line
  sub(/^ +/, "", s)
  if (s == "" || s ~ /^#/ || s ~ /^-/) return ""
  if (s !~ /^[A-Za-z0-9_.-]+[ \t]*:/) return ""
  sub(/[ \t]*:.*/, "", s)
  return s
}

# A "fluff" line — blank or comment-only — carries no structure and must not be
# captured as the trailing edge of a key's subtree (it belongs to what follows).
function is_fluff(line) {
  return (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/)
}

# Maintain a path stack keyed by indent; return the dotted path for (indent,key).
# Deletions are gathered first, then applied — modifying an array mid `for-in` is
# undefined in POSIX awk (works on macOS BWK awk, can misbehave on mawk/others).
function path_for(stack, indent, key,   i, p, drop, nd, d) {
  stack[indent] = key
  nd = 0
  for (i in stack) if (i + 0 > indent + 0) drop[++nd] = i
  for (d = 1; d <= nd; d++) delete stack[drop[d]]
  p = ""
  for (i = 0; i <= indent; i += 2)
    if (i in stack && stack[i] != "")
      p = (p == "" ? stack[i] : p "." stack[i])
  return p
}

# Print an inserted key's subtree to stdout and log its path to stderr.
function emit_key(path) {
  print sub_text[path]
  print "+ " path > "/dev/stderr"
}

function parent_of(path,   p) {
  if (path !~ /\./) return ""
  p = path
  sub(/\.[^.]+$/, "", p)
  return p
}

BEGIN { pcount = 0; tcount = 0 }

# ---- pass 1: PROFILE (first file) -----------------------------------------
FNR == NR {
  pcount++
  pline[pcount] = $0
  pind[pcount] = indent_of($0)
  k = key_of($0)
  if (k != "") {
    pp = path_for(pstack, pind[pcount], k)
    ppath[pcount] = pp
    present[pp] = 1
  } else {
    ppath[pcount] = ""
  }
  next
}

# ---- pass 2: TEMPLATE (second file) ---------------------------------------
{
  tcount++
  tline[tcount] = $0
  tind[tcount] = indent_of($0)
  k = key_of($0)
  if (k != "") {
    tp = path_for(tstack, tind[tcount], k)
    tpath[tcount] = tp
    tline_of[tp] = tcount
    tindent_of[tp] = tind[tcount]
    torder[++tn] = tp
  } else {
    tpath[tcount] = ""
  }
}

# ---- emit -----------------------------------------------------------------
END {
  # Subtree of a template key = its line plus all following deeper-indented
  # lines, captured verbatim — but with trailing fluff (blank lines and the next
  # block's section-header comments) trimmed, so an inserted block never drags in
  # content that already belongs to a sibling.
  for (i = 1; i <= tcount; i++) {
    p = tpath[i]
    if (p == "") continue
    last = i
    j = i + 1
    while (j <= tcount) {
      if (key_of(tline[j]) != "" && tind[j] <= tindent_of[p]) break
      if (!is_fluff(tline[j])) last = j
      j++
    }
    s = tline[i]
    for (m = i + 1; m <= last; m++) s = s "\n" tline[m]
    sub_text[p] = s
  }

  # Which missing template keys are subtree ROOTS (their parent is not itself
  # missing) — only those get inserted; their descendants come along in the text.
  for (t = 1; t <= tn; t++) {
    p = torder[t]
    if (present[p]) continue
    par = parent_of(p)
    if (par != "" && !present[par]) continue   # ancestor handles it
    if (par == "")
      root_missing[++rm] = p
    else
      child_missing[par] = (par in child_missing ? child_missing[par] "\n" : "") p
  }

  # For each parent that is missing template children, find the last profile
  # line of its block and schedule the children to be injected after that line.
  for (i = 1; i <= pcount; i++) {
    p = ppath[i]
    if (p == "" || !(p in child_missing)) continue
    end = i
    j = i + 1
    while (j <= pcount && pind[j] > pind[i]) { end = j; j++ }
    inject_at[end] = (end in inject_at ? inject_at[end] "\n" : "") child_missing[p]
  }

  # Stream the profile, injecting missing children right after each parent block.
  for (i = 1; i <= pcount; i++) {
    print pline[i]
    if (i in inject_at) {
      n = split(inject_at[i], kids, "\n")
      for (c = 1; c <= n; c++) emit_key(kids[c])
    }
  }

  # Append missing top-level keys at root.
  for (c = 1; c <= rm; c++) emit_key(root_missing[c])
}
