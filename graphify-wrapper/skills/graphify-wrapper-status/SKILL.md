---
name: graphify-wrapper-status
description:
  Show the repo's registered domain indexes and their freshness for the current
  worktree — which graphs exist here, when built, and whether seeded from main.
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

printf '%-14s %-30s %-9s %-8s %s\n' INDEX PATH SEMANTIC GRAPH BUILT
for name in $(gfx_index_names); do
  path=$(gfx_index_field "$name" path)
  sem=$(gfx_index_field "$name" semantic)
  g="$this/$path/graphify-out/graph.json"
  if [ -f "$g" ]; then
    built=$(date -r "$g" '+%Y-%m-%d %H:%M' 2>/dev/null)
    nodes=$(jq '.nodes | length' "$g" 2>/dev/null)
    printf '%-14s %-30s %-9s %-8s %s\n' "$name" "$path" "$sem" "${nodes}n" "$built"
  else
    printf '%-14s %-30s %-9s %-8s %s\n' "$name" "$path" "$sem" "-" "(not built here)"
  fi
done
```

If a registered domain shows `(not built here)`, tell the operator to run
`/graphify-wrapper-sync <name>` — it will seed from main if available, else build fresh.
