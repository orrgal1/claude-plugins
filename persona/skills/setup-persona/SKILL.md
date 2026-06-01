---
name: setup-persona
argument-hint: ""
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# /setup-persona

One-shot, idempotent setup of an **inlined** persona for Claude Code.

The persona is just a single file at `~/.claude/persona.md` whose contents
Claude reads on every session via an `@persona.md` import in
`~/.claude/CLAUDE.md`. No skill-chain, no `@-import` ladder — edit the persona
file directly to change behavior.

## What it does

1. If `~/.claude/persona.md` is missing, write the default template from this
   plugin (`templates/default.md`) to it.
2. If `~/.claude/CLAUDE.md` is missing, create it with a single `@persona.md`
   line.
3. If `CLAUDE.md` exists but has no `@persona.md` reference, append a marked
   block that imports it. Idempotent — re-running is a no-op.
4. Print the final state so the operator can confirm.

## Run

```bash
set -euo pipefail

PERSONA="$HOME/.claude/persona.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TEMPLATE="${CLAUDE_PLUGIN_ROOT}/templates/default.md"
MARK_BEGIN="<!-- BEGIN @orrgal1/persona — managed; do not edit this line -->"
MARK_END="<!-- END @orrgal1/persona -->"

mkdir -p "$HOME/.claude"

# 1. persona.md — write default if missing
if [ ! -f "$PERSONA" ]; then
  cp "$TEMPLATE" "$PERSONA"
  echo "wrote $PERSONA from default template"
else
  echo "kept existing $PERSONA ($(wc -l < "$PERSONA") lines)"
fi

# 2/3. CLAUDE.md — ensure @persona.md import exists
if [ ! -f "$CLAUDE_MD" ]; then
  cat > "$CLAUDE_MD" <<EOF
$MARK_BEGIN
@persona.md
$MARK_END
EOF
  echo "created $CLAUDE_MD with @persona.md import"
elif grep -qE '^[[:space:]]*@persona\.md[[:space:]]*$' "$CLAUDE_MD"; then
  echo "kept existing $CLAUDE_MD (already imports @persona.md)"
else
  printf '\n%s\n@persona.md\n%s\n' "$MARK_BEGIN" "$MARK_END" >> "$CLAUDE_MD"
  echo "appended @persona.md import block to $CLAUDE_MD"
fi

echo
echo "--- $PERSONA (first 20 lines) ---"
head -20 "$PERSONA"
```

## Notes

- The persona is **inlined**: everything Claude needs lives in `persona.md`. No
  `skills-inline` fence, no `@-import` ladder, no per-skill renderer.
- To change behavior, edit `~/.claude/persona.md` directly.
- To reset to the default template, delete `~/.claude/persona.md` and re-run
  `/setup-persona`.
- The plugin does not touch any other file under `~/.claude/`.
