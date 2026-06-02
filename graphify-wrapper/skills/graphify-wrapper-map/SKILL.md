---
name: graphify-wrapper-map
description:
  Analyze the repo, propose a small focused set of named domains worth indexing,
  refine them with the operator, and register the chosen ones. The guided front
  door to /graphify-wrapper-index.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - AskUserQuestion
---

# /graphify-wrapper-map

Turn a sprawling repo into a small, deliberate set of domains. The goal is
**focus** — index the few subtrees the operator will actually query, not the
whole tree. Flow: discover → propose → refine → register.

```bash
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
reg=$(gfx_registry)
[ -f "$reg" ] || { echo "run /graphify-wrapper-setup first"; exit 1; }
root=$(gfx_this_worktree)
```

## 1. Discover

Gather structural signals — don't guess. Read the output, then drill into any
parent dir (`services/`, `apps/`, `packages/`, `cmd/`, `libs/`) that clearly
holds multiple independent units.

```bash
cd "$root"
echo "## build roots (dependency boundaries)"
find . -maxdepth 4 \( -name go.mod -o -name package.json -o -name pyproject.toml \
    -o -name pubspec.yaml -o -name Cargo.toml -o -name pom.xml -o -name build.gradle \) \
  -not -path '*/node_modules/*' -not -path '*/.git/*' -not -path '*/vendor/*' \
  | sed 's#^\./##' | sort

echo "## top-level dirs: tracked files + dominant language"
for d in $(git ls-files | awk -F/ 'NF>1{print $1}' | sort -u); do
  n=$(git ls-files "$d" | wc -l | tr -d ' ')
  ext=$(git ls-files "$d" | sed -n 's/.*\.//p' | sort | uniq -c | sort -rn | head -1 \
        | awk '{print $2" ("$1")"}')
  printf '%7s  %-26s  %s\n' "$n" "$d" "$ext"
done

echo "## already registered (skip / refine these)"
gfx_index_names
```

For a candidate path, size it precisely with `git ls-files <path> | wc -l` and
sample its languages before proposing.

## 2. Propose

Synthesize the signals into **≤ ~6 coherent domains**, each a single
repo-relative subtree (graphify indexes one path per graph). Prefer a few medium
domains over one giant or many tiny ones. Group by stack or bounded context
(e.g. `backend`, `frontend`, `mobile`, `protos`, `infra`).

Present a table:

| domain | path | files | language | semantic? | why |
| ------ | ---- | ----- | -------- | --------- | --- |

Rules for the proposal:

- Recommend `semantic: true` **only** for domains the operator will ask
  architecture questions about — it costs serial `sonnet` calls per chunk
  (`claude-cli`). Everything else stays AST-only (free).
- Explicitly list what you're **leaving unindexed** and why (vendored deps,
  generated code, build output, docs, fixtures) — focus is the point.
- Flag overlaps/nesting: two domains must not nest (a parent path's graph would
  re-cover the child). If they do, pick one granularity.
- If a logical domain spans multiple disjoint subtrees, either pick their common
  ancestor or split into two named domains — note the tradeoff.

## 3. Refine (interactive)

Use `AskUserQuestion` to confirm the set and collect edits. Offer the operator
the obvious levers: keep / merge two / split one / rename / change a path / drop
/ toggle semantic. Iterate on the table until they approve. Do **not** touch the
registry before approval.

## 4. Register

Upsert each approved domain. One path per index.

```bash
# repeat per approved domain (name, path, sem in {true,false}):
tmp=$(mktemp)
jq --arg n "$name" --arg p "$path" --argjson s "$sem" \
   '.indexes[$n]={path:$p, semantic:$s}' "$reg" > "$tmp" && mv "$tmp" "$reg"
```

```bash
echo "registered domains:"; jq '.indexes' "$reg"
```

## 5. Next

Point the operator at `/graphify-wrapper-sync` to build all registered domains (AST,
plus semantic where marked), or `/graphify-wrapper-sync <name>` for one. For a large
first domain, suggest an AST-only `/graphify-wrapper-sync <name>` to gauge build time
before committing to a `--semantic` pass.
