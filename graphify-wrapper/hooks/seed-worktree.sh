#!/usr/bin/env bash
# SessionStart hook: make registered domain graphs available in any worktree.
#
# A worktree's graphs live in-tree (gitignored) and so are absent in a fresh
# checkout. This seeds them from the main worktree's graphs when missing — a
# plain copy, cheap and done in the background so session start is never blocked.
# It never *builds*: reconciling a seeded graph to the branch diff stays on-demand
# via /graphify-wrapper-sync. No-op on main, or in a repo that isn't set up.

# Never let a hook failure disrupt the session.
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh" 2>/dev/null || exit 0

reg=$(gfx_registry 2>/dev/null) || exit 0
[ -f "$reg" ] || exit 0
this=$(gfx_this_worktree 2>/dev/null) || exit 0
main=$(gfx_main_worktree 2>/dev/null) || true
[ -n "$this" ] || exit 0
[ -n "$main" ] && [ "$main" != "$this" ] || exit 0   # only non-main worktrees

# Domains missing here but present on main → seed candidates.
todo=()
while IFS= read -r name; do
  [ -n "$name" ] || continue
  path=$(gfx_index_field "$name" path)
  [ -n "$path" ] || continue
  [ -f "$this/$path/graphify-out/graph.json" ] && continue   # already here
  [ -f "$main/$path/graphify-out/graph.json" ] || continue   # nothing to copy
  todo+=("$path")
done < <(gfx_index_names 2>/dev/null)

[ ${#todo[@]} -gt 0 ] || exit 0

# Copy in the background; paths passed as args so spaces are safe.
nohup bash -c '
  main=$1; this=$2; shift 2
  for path in "$@"; do
    src="$main/$path/graphify-out"; dst="$this/$path/graphify-out"
    [ -f "$dst/graph.json" ] && continue
    mkdir -p "$dst" && cp -R "$src/." "$dst/" 2>/dev/null
  done
' _ "$main" "$this" "${todo[@]}" >/dev/null 2>&1 &

echo "graphify-wrapper: seeding ${#todo[@]} domain graph(s) from main into this worktree (background copy). Run /graphify-wrapper-sync to reconcile them to this branch."
exit 0
