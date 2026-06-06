# @orrgal1/welcome

Onboarding for the **orrgal1** marketplace. `/welcome` runs an interactive,
idempotent walkthrough that takes a new operator from a bare
[Claude Code](https://claude.com/claude-code) install to a fully wired setup,
then prints a usage guide for every plugin in the marketplace.

No dependency on other plugins — it's the front door, not a runtime dependency.

## What `/welcome` walks you through

1. **Prerequisites** — `gh` CLI, SSH git remotes.
2. **Recommended 3rd-party plugins** — claude-mem, caveman, context7, the
   official bundle.
3. **Persona** — set up the inlined `persona.md`.
4. **graphify-wrapper** — install the knowledge-graph CLI and register domains.
5. **Per-repo forge setup** — map the current repo's tooling into `$FORGE_HOME`.
6. **Usage guide** — a printed cheat-sheet for every orrgal1 plugin.

Every step is **idempotent** and detects what's already done, so re-running
`/welcome` only fills the gaps. Jump straight to a step with an optional
argument.

## Usage

```
/welcome                # full guided walkthrough (resumes where you left off)
/welcome forge          # jump to a named step
```

## License

[MIT](../LICENSE).
