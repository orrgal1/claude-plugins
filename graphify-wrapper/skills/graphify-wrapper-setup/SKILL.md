---
name: graphify-wrapper-setup
description: "One-time per-machine/per-repo setup for the graphify wrapper."
allowed-tools:
  - Bash
  - Read
  - Edit
---

# /graphify-wrapper-setup

Make a repo ready for graphify-wrapper. Idempotent — safe to re-run.

```bash
. "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
```

## 1. Ensure the CLI

The PyPI package is `graphifyy` (double-y); the binary is `graphify`.

```bash
command -v graphify >/dev/null || uv tool install graphifyy
graphify --version
```

If `uv` is missing, stop and tell the operator to install it (`brew install uv`)
— do not fall back to a global `pip install`.

## 2. Never-commit guard (global gitignore)

Graphs live in-tree at `<path>/graphify-out/`. Keep them out of every repo via
the operator's **global** gitignore so a host repo's tracked files are never
touched and nothing can be pushed.

```bash
gi=$(git config --global --get core.excludesfile || echo "$HOME/.config/git/ignore")
mkdir -p "$(dirname "$gi")"
git config --global core.excludesfile "$gi"
grep -qxF 'graphify-out/' "$gi" 2>/dev/null || printf 'graphify-out/\n' >> "$gi"
echo "global gitignore: $gi"
```

## 3. Init the per-repo registry

The central home holds **only** the registry (graphs stay in-tree). Keyed by git
identity, so every worktree of this repo shares it.

```bash
home=$(gfx_home); reg=$(gfx_registry)
mkdir -p "$home"
if [ ! -f "$reg" ]; then
  jq -n \
    --arg key "$(gfx_repo_key)" \
    --arg main "$(gfx_main_worktree)" \
    --arg branch "$(gfx_default_branch)" \
    '{repo_key:$key, main_worktree:$main, default_branch:$branch, backend:"claude-cli", cli_model:"sonnet", indexes:{}}' \
    > "$reg"
fi
cat "$reg"
```

## 4. Pick a semantic backend

`--semantic` builds need a backend. Default is `claude-cli` (routes through the
local `claude` CLI on the operator's Pro/Max plan — **no API key**, billed to
the plan). The `claude-cli` path defaults to **Opus** (overkill for
structured-JSON extraction), so the registry pins `cli_model: "sonnet"`;
`/graphify-wrapper-sync --semantic` exports it as `GRAPHIFY_CLAUDE_CLI_MODEL`. If an API
key is already in the env, prefer it (faster, parallel):

```bash
if   [ -n "${ANTHROPIC_API_KEY:-}" ]; then b=claude
elif [ -n "${GEMINI_API_KEY:-}${GOOGLE_API_KEY:-}" ]; then b=gemini
elif [ -n "${OPENAI_API_KEY:-}" ]; then b=openai
elif [ -n "${DEEPSEEK_API_KEY:-}" ]; then b=deepseek
else b=claude-cli; fi
reg=$(gfx_registry); tmp=$(mktemp)
jq --arg b "$b" '.backend=$b' "$reg" > "$tmp" && mv "$tmp" "$reg"
echo "semantic backend: $b"
```

## 5. Report

Tell the operator setup is done and suggest next steps:

- `/graphify-wrapper-index <name> <path>` to register a domain (or `/graphify-wrapper-index`
  with no args to have me analyze the repo and suggest domains).
- `/graphify-wrapper-sync` to build/refresh the current worktree's indexes.

Do **not** build any index here — that is `/graphify-wrapper-index` + `/graphify-wrapper-sync`.
