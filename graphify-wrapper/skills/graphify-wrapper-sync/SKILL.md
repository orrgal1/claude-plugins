---
name: graphify-wrapper-sync
description:
  On-demand refresh of the current worktree's domain indexes — AST-only by
  default, --semantic for full extract. Seeds a fresh worktree by copying main's
  graph then reconciling the branch diff. No background hooks.
argument-hint: "[<name> — defaults to all registered] [--semantic]"
allowed-tools:
  - Bash
---

# /graphify-wrapper-sync

Bring this worktree's graphs up to date with its files, on demand. This is the
only thing that builds graphs.

```bash
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
reg=$(gfx_registry)
[ -f "$reg" ] || { echo "run /graphify-wrapper-setup first"; exit 1; }
this=$(gfx_this_worktree); main=$(gfx_main_worktree)
sem=false; case "$*" in *--semantic*) sem=true;; esac
target="${1:-}"; case "$target" in --*) target="";; esac   # ignore flags as name
names=$(if [ -n "$target" ]; then echo "$target"; else gfx_index_names; fi)
[ -n "$names" ] || { echo "no indexes registered — run /graphify-wrapper-index"; exit 1; }
```

## Per-index loop

For each name, resolve its subtree, then build. The rule:

- **Refresh** if a graph already exists at `<path>/graphify-out/`.
- **Seed then refresh** if not, and this worktree is _not_ the main one and main
  has a graph for that domain: copy main's graph in first so the worktree
  inherits main's (expensive, possibly semantic) layer, then AST-reconcile the
  branch diff cheaply.
- **Build from scratch** otherwise.

```bash
backend=$(gfx_backend)
# Image/asset files graphify would otherwise read as text "docs" — token noise
# with no architectural signal, and the source of oversized chunks that time out.
exc_args=(); while IFS= read -r p; do [ -n "$p" ] && exc_args+=(--exclude "$p"); done < <(gfx_extract_excludes)
for name in $names; do
  path=$(gfx_index_field "$name" path)
  [ -n "$path" ] || { echo "skip '$name': not registered"; continue; }
  want_sem=$(gfx_index_field "$name" semantic)
  if [ "$sem" = true ] || [ "$want_sem" = true ]; then do_sem=true; else do_sem=false; fi
  dst="$this/$path"; out="$dst/graphify-out"
  [ -d "$dst" ] || { echo "skip '$name': $path absent in this worktree"; continue; }

  # Seed from main if this worktree has no graph yet.
  if [ ! -f "$out/graph.json" ] && [ -n "$main" ] && [ "$main" != "$this" ] \
     && [ -f "$main/$path/graphify-out/graph.json" ]; then
    echo "[$name] seeding from main worktree"
    mkdir -p "$out" && cp -R "$main/$path/graphify-out/." "$out/"
  fi

  if [ "$do_sem" = true ]; then
    # claude-cli defaults to Opus; pin the registry model (sonnet) for extraction.
    # Its subprocess timeout is a fixed 600s, so cap chunk size for this backend.
    budget_args=()
    if [ "$backend" = claude-cli ]; then
      export GRAPHIFY_CLAUDE_CLI_MODEL="$(gfx_cli_model)"
      budget_args=(--token-budget "$(gfx_cli_token_budget)")
    fi
    echo "[$name] semantic extract ($backend${GRAPHIFY_CLAUDE_CLI_MODEL:+/$GRAPHIFY_CLAUDE_CLI_MODEL}) on $path"
    graphify extract "$dst" --backend "$backend" "${exc_args[@]}" "${budget_args[@]}"
  else
    echo "[$name] AST update on $path"
    graphify update "$dst"
  fi
done
```

## Notes

- `update` is AST-only and free; `extract` runs the LLM backend. `claude-cli` is
  serial — a large `--semantic` domain is slow and consumes plan quota. Prefer
  scoping semantic to the domains that need architecture answers.
- `extract` sends docs **and images** to the LLM as text. SVG markup and decoded
  binary bytes are pure token noise (and the cause of oversized chunks that time
  out), so semantic builds exclude image/asset globs by default — see
  `gfx_extract_excludes`. Override per-repo with an `.extract_excludes` array in
  the registry (replaces the default set; list every glob you want dropped).
- The `claude-cli` backend's per-chunk subprocess timeout is a fixed 600s
  (graphify hardcodes it; `--api-timeout` only affects HTTP API backends), so
  large chunks fail. Semantic builds on this backend cap `--token-budget` (see
  `gfx_cli_token_budget`, default 20000) so each chunk finishes in time.
  Override with `.cli_token_budget` in the registry.
- A semantic build seeded onto a worktree is reconciled by AST `update` on later
  plain syncs; the named/semantic layer goes stale until the next `--semantic`
  run. Re-run with `--semantic` when you need fresh community naming.
- Graphs are gitignored (`/graphify-wrapper-setup` step 2) so nothing here is
  committable.

## Report

Print one line per index: action taken (seed/refresh/scratch, AST/semantic),
node+edge counts from the build output, and the `graph.json` path.
