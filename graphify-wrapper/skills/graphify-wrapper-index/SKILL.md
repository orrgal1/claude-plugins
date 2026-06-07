---
name: graphify-wrapper-index
description: "Register/remove a named domain index. Discovery via /graphify-wrapper-map; build via /graphify-wrapper-sync."
argument-hint: "<name> <path> [--semantic]  (or: <name> to remove)"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# /graphify-wrapper-index

Manage the set of named domain indexes for this repo. A domain = a `name` + a
repo-relative subtree `path` (e.g. `backend services/backend`). Scoping the
monorepo into domains keeps each graph small and each semantic build cheap.

```bash
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
reg=$(gfx_registry)
[ -f "$reg" ] || { echo "run /graphify-wrapper-setup first"; exit 1; }
```

## Register a domain

Validate and upsert into the registry. `--semantic` marks the domain for full
extract on sync (default AST-only).

```bash
name="$1"; path="$2"; sem=false
case "$*" in *--semantic*) sem=true;; esac
root=$(gfx_this_worktree)
[ -d "$root/$path" ] || { echo "path not found in repo: $path"; exit 1; }
tmp=$(mktemp)
jq --arg n "$name" --arg p "$path" --argjson s "$sem" \
   '.indexes[$n]={path:$p, semantic:$s}' "$reg" > "$tmp" && mv "$tmp" "$reg"
echo "registered '$name' -> $path (semantic=$sem)"
jq '.indexes' "$reg"
```

Then tell the operator to run `/graphify-wrapper-sync $name` to build it.

## Don't know the domains yet?

Use **`/graphify-wrapper-map`** — it analyzes the repo, proposes a focused domain set,
refines it with you interactively, and registers the chosen ones. This skill is
the precise low-level tool for when you already know the `name` and `path`.

## Removing a domain

```bash
tmp=$(mktemp); jq --arg n "$1" 'del(.indexes[$n])' "$reg" > "$tmp" && mv "$tmp" "$reg"
```

(The in-tree `graphify-out/` under that path can be deleted manually if
desired.)
