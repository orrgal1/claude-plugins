# orrgal1 — Claude Code plugins

A marketplace of self-contained, repo-agnostic plugins for
[Claude Code](https://claude.com/claude-code). Each plugin adopts into any
repository — none hard-code a project's tooling, and (with one noted exception)
none depend on each other.

New here? Install `welcome` and run `/welcome` for a guided, idempotent
walkthrough from a bare install to a fully wired setup.

## Plugins

| Plugin                                     | Headline              | What it does                                                                                                                                                                                        |
| ------------------------------------------ | --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [**forge**](./forge)                       | `/forge`              | Drives a PR from a one-line brief to **READY** through a proof chain — goals, scenarios, tests, design, impl, continuous CI, and lens-designed review — attesting every step. Depends on `devloop`. |
| [**devloop**](./devloop)                   | `/restack` `/deslop`  | Stacked-PR dev loop — restack a PR (or a whole stack) onto its base, and strip AI slop from a diff.                                                                                                 |
| [**diagnose**](./diagnose)                 | `/root-cause`         | Portable diagnostic toolkit — hypothesis-driven RCA, log peppering, and context-safe trace capture.                                                                                                 |
| [**ralph**](./ralph)                       | `/ralph`              | Bounded-autonomy iteration loop — grind a verifiable target to green, committing each step, stopping at success or budget.                                                                          |
| [**graphify-wrapper**](./graphify-wrapper) | `/graphify-wrapper-*` | Knowledge-graph harness over [graphify](https://github.com/safishamsi/graphify), tuned for monorepos + worktrees — structural search across named domains.                                          |
| [**persona**](./persona)                   | `/load-persona`       | Inlined behavioral persona Claude reads every session — set it up once, swap named personas from a pool.                                                                                            |
| [**reviewable**](./reviewable)             | `/reviewable-*`       | Reviewable.io automation via `agent-browser` — read threads, draft replies, batch-publish.                                                                                                          |
| [**welcome**](./welcome)                   | `/welcome`            | Interactive onboarding for this marketplace.                                                                                                                                                        |

Each plugin has its own README (linked above) with the full skill list, model,
and usage.

## Install

Add the marketplace once, then install the plugins you want:

```
/plugin marketplace add orrgal1/claude-plugins
/plugin install forge@orrgal1
/plugin install devloop@orrgal1      # forge dependency
/plugin install welcome@orrgal1
…
```

Or point Claude Code at a local checkout:

```
git clone git@github.com:orrgal1/claude-plugins.git
claude --plugin-dir claude-plugins/forge --plugin-dir claude-plugins/devloop
```

> `forge` calls `devloop`'s `/restack`; install both. Every other plugin is
> standalone.

## License

[MIT](./LICENSE).
