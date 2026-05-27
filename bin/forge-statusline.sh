#!/usr/bin/env bash
# forge-statusline — render the current forge state as a single statusline line.
#
# Read by Claude Code via settings.json `statusLine.command`. Outputs one line
# (no trailing newline). Silent (empty) if no forge state exists.
#
# State file: ~/.claude/forge/state.json (last-writer-wins; written by forge
# skills via /forge-line).
#
# Output shape:
#   [forge:<slug>] <phase_id> · <sub> · <HH:MM> · <recap-truncated>
#
# Stale-state handling: if state.json mtime is older than STALE_THRESHOLD_SEC
# (default 900s = 15 min), append " (stale Nmin)" so the operator knows the
# loop has gone quiet.

set -euo pipefail

STATE="${HOME}/.claude/forge/state.json"
STALE_THRESHOLD_SEC="${FORGE_STATUSLINE_STALE_SEC:-900}"
RECAP_MAX="${FORGE_STATUSLINE_RECAP_MAX:-60}"

if [ ! -f "$STATE" ]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[forge] (jq not installed — install via brew/apt to render statusline)"
  exit 0
fi

slug="$(jq -r '.slug // "unknown"' "$STATE" 2>/dev/null)"
phase_id="$(jq -r '.phase_id // "?"' "$STATE" 2>/dev/null)"
sub="$(jq -r '.sub // ""' "$STATE" 2>/dev/null)"
ts="$(jq -r '.ts // ""' "$STATE" 2>/dev/null)"
recap="$(jq -r '.recap // ""' "$STATE" 2>/dev/null)"
verdict="$(jq -r '.verdict // ""' "$STATE" 2>/dev/null)"

if [ -z "$slug" ] || [ "$slug" = "null" ]; then
  exit 0
fi

if [ -n "$ts" ] && [ "$ts" != "null" ]; then
  hm="$(echo "$ts" | sed -E 's/.*T([0-9]{2}):([0-9]{2}).*/\1:\2/')"
else
  hm=""
fi

if [ ${#recap} -gt "$RECAP_MAX" ]; then
  recap="${recap:0:$((RECAP_MAX - 1))}…"
fi

line="[forge:${slug}] ${phase_id}"
[ -n "$sub" ] && [ "$sub" != "null" ] && line="${line} · ${sub}"
[ -n "$hm" ] && line="${line} · ${hm}"
[ -n "$verdict" ] && [ "$verdict" != "null" ] && [ "$verdict" != "in-progress" ] && line="${line} · ${verdict}"
[ -n "$recap" ] && [ "$recap" != "null" ] && line="${line} · ${recap}"

mtime_sec=$(stat -f %m "$STATE" 2>/dev/null || stat -c %Y "$STATE" 2>/dev/null || echo 0)
now_sec=$(date +%s)
age=$((now_sec - mtime_sec))
if [ "$age" -gt "$STALE_THRESHOLD_SEC" ]; then
  age_min=$((age / 60))
  line="${line} (stale ${age_min}min)"
fi

printf '%s' "$line"
