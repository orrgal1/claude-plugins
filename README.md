# orrgal1 — Claude Code plugins

A marketplace of self-contained, repo-agnostic plugins for
[Claude Code](https://claude.com/claude-code). Each plugin adopts into any
repository — none hard-code a project's tooling, and (with one noted exception)
none depend on each other.

New here? Install `welcome` and run `/welcome` for a guided, idempotent
walkthrough from a bare install to a fully wired setup.

## Plugins

| Plugin                                     | Headline              | What it does                                                                                                                                                                                                                                                                                 |
| ------------------------------------------ | --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [**forge**](./forge)                       | `/forge`              | Drives a PR from a one-line brief to **READY** through a proof chain — goals, scenarios, tests, design, impl, lens-designed review, and continuous CI — attesting every step. No hard dependency — restack is configurable (`devloop`'s `/restack` recommended, or a built-in git fallback). |
| [**devloop**](./devloop)                   | `/restack` `/grind`   | Forge's single companion — stacked-PR ops (restack, review, CI), the `/grind` iteration-loop engine, and a diagnostic toolkit (`/root-cause`, `/hypothesize`, `/pepper`, `/trace`). Provides every capability forge consumes; each useful standalone.                                        |
| [**graphify-wrapper**](./graphify-wrapper) | `/graphify-wrapper-*` | Knowledge-graph harness over [graphify](https://github.com/safishamsi/graphify), tuned for monorepos + worktrees — structural search across named domains.                                                                                                                                   |
| [**persona**](./persona)                   | `/load-persona`       | Inlined behavioral persona Claude reads every session — set it up once, swap named personas from a pool.                                                                                                                                                                                     |
| [**welcome**](./welcome)                   | `/welcome`            | Interactive onboarding for this marketplace.                                                                                                                                                                                                                                                 |

Each plugin has its own README (linked above) with the full skill list, model,
and usage.

## Install

Add the marketplace once, then install the plugins you want:

```
/plugin marketplace add orrgal1/claude-plugins
/plugin install forge@orrgal1
/plugin install devloop@orrgal1      # optional: forge's recommended /restack
/plugin install welcome@orrgal1
…
```

Or point Claude Code at a local checkout:

```
git clone git@github.com:orrgal1/claude-plugins.git
claude --plugin-dir claude-plugins/forge --plugin-dir claude-plugins/devloop
```

> `forge` has no hard plugin dependency — it ships a built-in git restack and is
> standalone. Installing `devloop` gives forge its recommended stacked-PR
> `/restack` (wire it via `/forge-setup`). Every plugin is standalone.

## License

[MIT](./LICENSE).
