# @orrgal1/persona

A simple **inlined persona** for [Claude Code](https://claude.com/claude-code).
Behavioral guidance — tone, git discipline, output style, boundaries — lives in
a single file at `~/.claude/persona.md` that Claude reads on **every session**
via an `@persona.md` import in `~/.claude/CLAUDE.md`.

No skill-chain, no `@-import` ladder, no indirection: the persona content lives
inline in `persona.md`, so to change behavior you edit that one file. No
dependency on other plugins.

## How it works

- `/setup-persona` writes `~/.claude/persona.md` (from the default template if
  missing) and ensures `~/.claude/CLAUDE.md` `@`-imports it. **Idempotent** —
  safe to re-run; it won't clobber an existing persona.
- `/load-persona` swaps in a named persona from the plugin's builtin pool
  (`personas/`), overwriting `~/.claude/persona.md` and wiring the import the
  same way.
- From then on, every new Claude Code session loads the persona automatically.

## Skills

| Skill            | Purpose                                                                               |
| ---------------- | ------------------------------------------------------------------------------------- |
| `/setup-persona` | One-shot, idempotent setup — write `persona.md` + wire the `CLAUDE.md` import.        |
| `/load-persona`  | List available personas, or `/load-persona <name>` to load one from the builtin pool. |

## Usage

```
/setup-persona            # first-time setup (idempotent)
/load-persona             # list builtin personas
/load-persona orrgal      # load a named persona
```

Then edit `~/.claude/persona.md` directly anytime to tune behavior.

## License

[MIT](../LICENSE).
