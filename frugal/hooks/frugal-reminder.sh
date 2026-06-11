#!/bin/bash
# UserPromptSubmit: re-inject a terse frugal-mode reminder every turn while a
# run is active, so the mode survives long sessions and compaction.
set -uo pipefail

cat > /dev/null # consume stdin

root="${CLAUDE_PROJECT_DIR:-$PWD}"
active="$root/.claude/frugal/active"
[ -f "$active" ] || exit 0

run=$(grep '^RUN=' "$active" | head -1 | cut -d= -f2-)
cap=$(grep '^CAP=' "$active" | head -1 | cut -d= -f2-)
[ -n "$run" ] || exit 0

cat <<EOF
[frugal] mode active — cap ${cap:-3}, ledger $run/ledger.jsonl
Route each subtask to the cheapest tier you're ~90% confident one-shots it; unsure → the higher tier. Downgrade below sonnet only for closed-spec + mechanically-verifiable tasks. mechanical/lookup → worker-low+haiku · bounded impl → worker-low/medium+sonnet (safe default) · hard bounded → worker-high+sonnet · decomposition/design/destructive/synthesis → main loop. Self-contained FRUGAL TASK envelopes; verify child output (never below the work tier); two failures = spec problem → main loop; append a ledger line per dispatch. /frugal --off to deactivate.
EOF
exit 0
