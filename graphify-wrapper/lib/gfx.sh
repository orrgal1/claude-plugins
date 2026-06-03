#!/usr/bin/env bash
# graphify-wrapper shared helpers.
#   source it:  . "${CLAUDE_PLUGIN_ROOT}/lib/gfx.sh"
# Repo-keyed central home holds only the registry; graphs live in-tree
# (gitignored) at <path>/graphify-out/ per graphify's native layout.

# Canonical repo id, stable across all worktrees (derived from git identity).
gfx_repo_key() {
  local url
  url=$(git remote get-url origin 2>/dev/null || true)
  if [ -n "$url" ]; then
    printf '%s\n' "$url" | sed -E \
      -e 's#\.git$##' \
      -e 's#^[a-z]+://##' \
      -e 's#^[^@]*@##' \
      -e 's#^[^:/]*[:/]##' \
      -e 's#/#__#g'
  else
    git rev-parse --git-common-dir 2>/dev/null | shasum -a 256 | cut -c1-12
  fi
}

# Central home (registry only). Override with GRAPHIFY_HOME.
gfx_home() { printf '%s\n' "${GRAPHIFY_HOME:-$HOME/.claude/graphify/$(gfx_repo_key)}"; }
gfx_registry() { printf '%s\n' "$(gfx_home)/registry.json"; }

gfx_default_branch() {
  local b
  b=$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null); b=${b#origin/}
  if [ -z "$b" ]; then
    for c in main master; do
      git show-ref -q --verify "refs/remotes/origin/$c" 2>/dev/null && { b=$c; break; }
    done
  fi
  printf '%s\n' "${b:-main}"
}

# Absolute path of the worktree checked out on the default branch (seed source).
gfx_main_worktree() {
  local def; def=$(gfx_default_branch)
  git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$def" '
    /^worktree /{wt=$2}
    /^branch /{ if ($2==b){print wt; exit} }'
}

# Path of the current worktree root.
gfx_this_worktree() { git rev-parse --show-toplevel 2>/dev/null; }

# Backend for --semantic builds; defaults to claude-cli (no API key, plan-billed).
gfx_backend() {
  local r; r=$(gfx_registry)
  if [ -f "$r" ]; then
    jq -r '.backend // empty' "$r" 2>/dev/null && return 0
  fi
  printf 'claude-cli\n'
}

# Model for the claude-cli semantic backend. graphify's claude-cli path defaults
# to Opus (overkill for structured-JSON extraction); we pin sonnet.
gfx_cli_model() {
  local r; r=$(gfx_registry)
  if [ -f "$r" ]; then
    jq -r '.cli_model // "sonnet"' "$r" 2>/dev/null && return 0
  fi
  printf 'sonnet\n'
}

# File globs excluded from semantic `extract`. graphify reads docs AND images as
# text and asks the LLM to graph them — but SVG markup (path/base64 data) and
# decoded binary bytes are token-heavy noise with zero architectural signal, and
# big image-stuffed chunks are what time out. Default to dropping image/asset
# files; override per-repo with a JSON `.extract_excludes` array in the registry.
gfx_extract_excludes() {
  local r; r=$(gfx_registry)
  if [ -f "$r" ] && jq -e '(.extract_excludes // empty) | type == "array"' "$r" >/dev/null 2>&1; then
    jq -r '.extract_excludes[]' "$r" 2>/dev/null && return 0
  fi
  printf '%s\n' '*.svg' '*.png' '*.jpg' '*.jpeg' '*.gif' '*.webp' '*.bmp' '*.ico' '*.tiff' '*.heic'
}

# Per-chunk token budget for the claude-cli backend. graphify hardcodes the
# `claude -p` subprocess timeout at 600s (--api-timeout governs only HTTP API
# backends), so oversized chunks time out. Cap chunk size below graphify's 60k
# default so each call finishes under the wall. Override with `.cli_token_budget`.
gfx_cli_token_budget() {
  local r; r=$(gfx_registry)
  if [ -f "$r" ]; then
    jq -r '.cli_token_budget // "20000"' "$r" 2>/dev/null && return 0
  fi
  printf '20000\n'
}

# jq read of an index field:  gfx_index_field <name> <field>
gfx_index_field() {
  jq -r --arg n "$1" --arg f "$2" '.indexes[$n][$f] // empty' "$(gfx_registry)" 2>/dev/null
}

gfx_index_names() { jq -r '.indexes | keys[]' "$(gfx_registry)" 2>/dev/null; }
