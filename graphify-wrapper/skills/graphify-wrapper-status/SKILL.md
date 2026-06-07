---
name: graphify-wrapper-status
description: "Show registered domain indexes and their freshness for this worktree."
allowed-tools:
  - Bash
---

# /graphify-wrapper-status

Report the graphify-wrapper state for this repo + worktree.

```bash
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
reg=$(gfx_registry)
[ -f "$reg" ] || { echo "not set up — run /graphify-wrapper-setup"; exit 0; }

this=$(gfx_this_worktree); main=$(gfx_main_worktree)
echo "repo_key   : $(gfx_repo_key)"
echo "backend    : $(gfx_backend)"
echo "this wt    : $this"
echo "main wt    : ${main:-<none>}$([ "$this" = "$main" ] && echo '  (this is main)')"
echo "registry   : $reg"
echo

head=$(git -C "$this" rev-parse HEAD 2>/dev/null)
printf '%-14s %-28s %-9s %-8s %-8s %s\n' INDEX PATH SEMANTIC GRAPH FRESH BUILT
for name in $(gfx_index_names); do
  path=$(gfx_index_field "$name" path)
  sem=$(gfx_index_field "$name" semantic)
  g="$this/$path/graphify-out/graph.json"
  if [ -f "$g" ]; then
    read -r nodes built <<<"$(jq -r '"\(.nodes|length) \(.built_at_commit // "?")"' "$g" 2>/dev/null)"
    ts=$(date -r "$g" '+%Y-%m-%d %H:%M' 2>/dev/null)
    if [ -z "$head" ] || [ "$built" = "?" ]; then fresh="?"
    elif [ "$built" = "$head" ]; then fresh="current"
    else fresh="behind"; fi
    printf '%-14s %-28s %-9s %-8s %-8s %s\n' "$name" "$path" "$sem" "${nodes}n" "$fresh" "$ts"
  else
    printf '%-14s %-28s %-9s %-8s %-8s %s\n' "$name" "$path" "$sem" "-" "-" "(not built here)"
  fi
done
```

- `(not built here)` → run `/graphify-wrapper-sync <name>` (seeds from main if
  available, else builds fresh). A SessionStart hook also auto-seeds missing
  graphs in the background.
- `FRESH = behind` → the graph's `built_at_commit` is behind HEAD. A
  SessionStart hook auto-runs an AST `graphify update` on drifted, affected
  domains; or run `/graphify-wrapper-sync <name>` now. The semantic layer isn't
  auto-refreshed — use `--semantic` when you need fresh community naming.
