#!/bin/bash
# PreToolUse (Edit|Write|NotebookEdit): soft nudge while a frugal run is
# active — never blocks, rate-limited to one nudge per 5 minutes.
set -uo pipefail

cat > /dev/null # consume stdin

root="${CLAUDE_PROJECT_DIR:-$PWD}"
active="$root/.claude/frugal/active"
[ -f "$active" ] || exit 0

run=$(grep '^RUN=' "$active" | head -1 | cut -d= -f2-)
[ -d "$run" ] || exit 0

stamp="$run/.nudge-stamp"
now=$(date +%s)
mt=$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp" 2>/dev/null || echo 0)
[ $((now - mt)) -lt 300 ] && exit 0
touch "$stamp"

cat <<'EOF'
{"continue": true, "systemMessage": "[frugal] inline file edit while frugal mode is active — if this is a well-bounded subtask, dispatch a frugal worker instead (workers/triage table per /frugal). Fine to proceed inline for trivial or never-delegate work. Frugal workers executing an envelope: disregard."}
EOF
exit 0
