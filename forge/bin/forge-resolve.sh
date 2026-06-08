#!/usr/bin/env bash
# forge-resolve — deterministic resolver for forge repo identity + artifact roots.
#
# Prints the resolved worktree, repo-key, $FORGE_HOME, $FORGE_ART, slug, chain
# root, and chain_present. Mirrors /forge-setup's forge_repo_key / forge_home /
# forge_art logic exactly, so no skill ever has to guess where artifacts live or
# hunt with ls/find. Run from anywhere inside the target worktree.
#
#   forge-resolve.sh [--slug <slug>] [--json|--sh]   (default --json)
#
# Invariant: $FORGE_ART is rooted at the WORKTREE, never under ~/.claude/forge/.
set -euo pipefail

slug_override=""
fmt="json"
while [ $# -gt 0 ]; do
  case "$1" in
    --slug) slug_override="${2:-}"; shift 2 ;;
    --json) fmt="json"; shift ;;
    --sh)   fmt="sh"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "forge-resolve: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- worktree + slug -------------------------------------------------------
if ! worktree="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  echo "forge-resolve: not inside a git worktree (cwd=$(pwd))" >&2; exit 3
fi
branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
# Slug derivation MUST match /forge-start (the dir creator): lowercase, non-alnum
# runs -> '-', strip leading/trailing '-'. --slug or $SLUG override.
slug_override="${slug_override:-${SLUG:-}}"
if [ -n "$slug_override" ]; then
  slug="$slug_override"
else
  slug="$(printf '%s' "$branch" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-//; s/-$//')"
fi

# --- tiny TOML reader: value of <key> in [<section>], '' if absent ---------
toml_get() { # <file> <section> <key>
  awk -v sec="$2" -v key="$3" '
    /^[[:space:]]*\[/ { cur=$0; sub(/^[[:space:]]*\[/,"",cur); sub(/\].*$/,"",cur); next }
    {
      line=$0; sub(/#.*$/,"",line); n=index(line,"=")
      if (n>0 && cur==sec) {
        k=substr(line,1,n-1); v=substr(line,n+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",k); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
        if (k==key) { gsub(/^"|"$/,"",v); print v; exit }
      }
    }' "$1" 2>/dev/null
}

# --- repo-key from origin remote (identity § step 2) -----------------------
key_from_remote() { # <url> -> host/owner/repo  (lowercase, .git stripped)
  local u="$1"; [ -z "$u" ] && return 1
  u="${u%.git}"; u="${u#ssh://}"; u="${u#https://}"; u="${u#http://}"; u="${u#git@}"
  u="${u/:/\/}"   # git@host:owner/repo -> host/owner/repo (first colon -> slash)
  printf '%s' "$u" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9/._-]+#-#g; s#/+#/#g; s#^/+##; s#/+$##'
}
remote_url="$(git remote get-url origin 2>/dev/null || true)"
repo_key_remote="$(key_from_remote "$remote_url" 2>/dev/null || true)"
if [ -z "${repo_key_remote:-}" ]; then
  sha="$( { printf '%s' "$worktree" | shasum -a 256 2>/dev/null || printf '%s' "$worktree" | sha256sum; } | cut -c1-12)"
  repo_key_remote="sha-$sha"
fi

# --- forge_home: env > ~/.claude/forge/<key> > legacy <root>/.forge --------
forge_home="${FORGE_HOME:-$HOME/.claude/forge/$repo_key_remote}"
legacy_home="$worktree/.forge"
toml=""
if [ -f "$forge_home/forge.toml" ]; then
  toml="$forge_home/forge.toml"
elif [ -z "${FORGE_HOME:-}" ] && [ -f "$legacy_home/forge.toml" ]; then
  forge_home="$legacy_home"; toml="$legacy_home/forge.toml"
fi

# canonical_id override relocates the home (identity § step 1)
repo_key="$repo_key_remote"
if [ -n "$toml" ]; then
  cid="$(toml_get "$toml" meta canonical_id)"
  if [ -n "$cid" ]; then
    repo_key="$cid"
    if [ -z "${FORGE_HOME:-}" ] && [ -f "$HOME/.claude/forge/$cid/forge.toml" ]; then
      forge_home="$HOME/.claude/forge/$cid"; toml="$forge_home/forge.toml"
    fi
  fi
fi

ready="false"
[ -n "$toml" ] && [ "$(toml_get "$toml" meta ready)" = "true" ] && ready="true"

# --- forge_art = <worktree>/<prefix?/>.forge  (worktree-rooted, always) ----
prefix=""; [ -n "$toml" ] && prefix="$(toml_get "$toml" artifacts prefix)"
if [ -z "$prefix" ]; then base=".forge"; else base="$prefix/.forge"; fi
forge_art="$worktree/$base"
chain_root="$forge_art/branches/$slug"

chain_present="false"
if [ -d "$chain_root" ] && { [ -f "$chain_root/links.json" ] || [ -f "$chain_root/goals.md" ]; }; then
  chain_present="true"
fi

# Existing chain dirs — reconciliation net if the derived slug ever disagrees
# with what's on disk. Space-separated for --sh; JSON array for --json.
existing=""
if [ -d "$forge_art/branches" ]; then
  for d in "$forge_art"/branches/*/; do
    [ -d "$d" ] || continue
    n="$(basename "$d")"; existing="$existing${existing:+ }$n"
  done
fi
existing_json=""
for n in $existing; do existing_json="$existing_json${existing_json:+, }\"$n\""; done

# --- emit ------------------------------------------------------------------
if [ "$fmt" = "sh" ]; then
  cat <<EOF
FORGE_WORKTREE='$worktree'
FORGE_BRANCH='$branch'
FORGE_SLUG='$slug'
FORGE_REPO_KEY='$repo_key'
FORGE_HOME='$forge_home'
FORGE_TOML='$toml'
FORGE_READY='$ready'
FORGE_ART='$forge_art'
FORGE_CHAIN_ROOT='$chain_root'
FORGE_CHAIN_PRESENT='$chain_present'
FORGE_BRANCHES='$existing'
EOF
else
  cat <<EOF
{
  "worktree": "$worktree",
  "branch": "$branch",
  "slug": "$slug",
  "repo_key": "$repo_key",
  "forge_home": "$forge_home",
  "forge_toml": "$toml",
  "ready": $ready,
  "prefix": "$prefix",
  "forge_art": "$forge_art",
  "chain_root": "$chain_root",
  "chain_present": $chain_present,
  "branches": [$existing_json]
}
EOF
fi
