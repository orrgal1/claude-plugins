---
name: load-persona
description:
  "Load a named persona from the plugin's builtin pool into
  ~/.claude/persona.md."
argument-hint: "[name]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
---

# /load-persona

Load a persona from the plugin's builtin pool into `~/.claude/persona.md`.

The pool lives at `${CLAUDE_PLUGIN_ROOT}/personas/`. Each `<name>.md` is a
complete persona. Loading one overwrites `~/.claude/persona.md` and ensures
`~/.claude/CLAUDE.md` imports it (same as `/setup-persona`).

## Usage

- `/load-persona` — list available personas.
- `/load-persona <name>` — load `personas/<name>.md` into
  `~/.claude/persona.md`.

## Run

```bash
set -euo pipefail

NAME="${1:-}"
POOL="${CLAUDE_PLUGIN_ROOT}/personas"
PERSONA="$HOME/.claude/persona.md"
CLAUDE_MD="$HOME/.claude/CLAUDE.md"
MARK_BEGIN="<!-- BEGIN @orrgal1/persona — managed; do not edit this line -->"
MARK_END="<!-- END @orrgal1/persona -->"

if [ -z "$NAME" ]; then
  echo "Available personas in $POOL:"
  for f in "$POOL"/*.md; do
    [ -e "$f" ] || { echo "  (none)"; break; }
    echo "  $(basename "$f" .md)"
  done
  echo
  echo "Load one with: /load-persona <name>"
  exit 0
fi

SRC="$POOL/$NAME.md"
if [ ! -f "$SRC" ]; then
  echo "no such persona: $NAME"
  echo "available: $(cd "$POOL" && ls *.md 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')"
  exit 1
fi

mkdir -p "$HOME/.claude"

# Back up the current persona before overwriting.
if [ -f "$PERSONA" ]; then
  cp "$PERSONA" "$PERSONA.bak"
  echo "backed up existing persona to $PERSONA.bak"
fi

cp "$SRC" "$PERSONA"
echo "loaded persona '$NAME' into $PERSONA"

# Ensure CLAUDE.md imports @persona.md.
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

- Loading overwrites `~/.claude/persona.md`; the prior file is saved to
  `persona.md.bak` first. Restore by copying it back.
- To author a new pool entry, drop a `<name>.md` into the plugin's `personas/`
  directory (or copy your current persona there).
- The pool ships with the plugin; `templates/default.md` is the `/setup-persona`
  bootstrap default, separate from the pool.
