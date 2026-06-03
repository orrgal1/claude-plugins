#!/usr/bin/env bash
# SessionStart hook: refresh domain graphs whose built_at_commit has drifted from
# HEAD (e.g. after a merge/pull/checkout moved the tree). AST-only — runs
# `graphify update` (free, diff-aware), never the semantic LLM pass. Scoped to
# domains the built→HEAD delta actually touched, and the whole detection+refresh
# runs in the background so session start is never blocked (reading provenance
# from a large graph.json can take a moment). No-op when nothing drifted, when
# graphify is absent, or in a repo that isn't set up.

. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh" 2>/dev/null || exit 0
command -v graphify >/dev/null 2>&1 || exit 0
reg=$(gfx_registry 2>/dev/null) || exit 0
[ -f "$reg" ] || exit 0
this=$(gfx_this_worktree 2>/dev/null) || exit 0
[ -n "$this" ] || exit 0
names=$(gfx_index_names 2>/dev/null)
[ -n "$names" ] || exit 0

GFX_LIB="${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh" nohup bash -c '
  . "$GFX_LIB" 2>/dev/null || exit 0
  this=$1; shift
  cd "$this" 2>/dev/null || exit 0                      # gfx_/git resolve to this worktree
  head=$(git rev-parse HEAD 2>/dev/null) || exit 0
  [ -n "$head" ] || exit 0
  for name in "$@"; do
    path=$(gfx_index_field "$name" path); [ -n "$path" ] || continue
    g="$this/$path/graphify-out/graph.json"; [ -f "$g" ] || continue   # missing → seed hook
    built=$(jq -r ".built_at_commit // empty" "$g" 2>/dev/null)
    [ -n "$built" ] || continue                          # no provenance → leave alone
    [ "$built" = "$head" ] && continue                   # current → skip
    # If built is a real commit, only refresh when the delta touches this path.
    if git rev-parse --verify -q "$built^{commit}" >/dev/null 2>&1; then
      [ -n "$(git diff --name-only "$built" "$head" -- "$path" 2>/dev/null)" ] || continue
    fi
    graphify update "$this/$path" >/dev/null 2>&1        # AST reconcile; never semantic
  done
' _ "$this" $names >/dev/null 2>&1 &

exit 0
