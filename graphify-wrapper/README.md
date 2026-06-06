# @orrgal1/graphify-wrapper

A thin, repo-agnostic harness over the
[graphify](https://github.com/safishamsi/graphify) knowledge-graph CLI, tuned
for **monorepos + git worktrees**. It abstracts the rough edges: where the graph
lives, how worktrees inherit it, how it stays current, and how to scope a huge
repo into queryable domains.

## Model

- **Named domain indexes.** A monorepo is split into domains — a `name` + a
  repo-relative subtree `path` (e.g. `backend services/backend`). Each domain is
  its own small graph, so semantic builds stay cheap and queries stay focused.
- **Graphs live in-tree** at `<path>/graphify-out/`, which is graphify's native
  layout. They are added to your **global** gitignore, so they are never
  committed to any repo and can't be pushed.
- **Registry, not graphs, is central.**
  `~/.claude/graphify/<repo-key>/registry.json` lists the domains. The key
  derives from git remote identity, so every worktree of the repo shares one
  registry.
- **Worktree seeding.** A fresh worktree copies the main worktree's graph for a
  domain, then AST-reconciles the branch diff — inheriting main's expensive
  (possibly semantic) layer for free. A `SessionStart` hook does the copy half
  automatically (background, never a build), so graphs are present in any
  worktree without thinking about it.
- **Drift auto-refresh.** A `SessionStart` hook also compares each graph's
  `built_at_commit` to `HEAD` and, for any domain the delta touched, runs an AST
  `update` in the background — so graphs track the tree after a merge/pull
  without a manual sync. `/graphify-wrapper-status` shows a `FRESH` column
  (`current` / `behind`).
- **On-demand semantic.** The automatic actions are AST-only (seed-copy +
  `update`); the semantic LLM pass never runs on its own — you invoke
  `--semantic` when you want fresh community naming.
- **AST default, semantic opt-in.** `update` (AST, free) is the default;
  `--semantic` runs `extract` via the `claude-cli` backend (your Claude Code
  plan — no API key, billed to the plan) or any configured API backend.

## Skills

| Skill                      | Purpose                                                                                                                |
| -------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `/graphify-wrapper-setup`  | Install the CLI, gitignore `graphify-out/` globally, init the per-repo registry, pick a semantic backend. Idempotent.  |
| `/graphify-wrapper-map`    | Analyze the repo, propose a focused set of domains, refine interactively, register the chosen ones. Guided front door. |
| `/graphify-wrapper-index`  | Precise register/remove of a domain (`name path [--semantic]`) when you already know it.                               |
| `/graphify-wrapper-sync`   | Build/refresh the current worktree's indexes on demand. Seeds from main when absent. `--semantic` for full extract.    |
| `/graphify-wrapper-query`  | Route a question to a domain's graph (`query`/`affected`/`path`/`explain`).                                            |
| `/graphify-wrapper-status` | List registered domains and their per-worktree freshness.                                                              |

## Typical flow

```
/graphify-wrapper-setup
/graphify-wrapper-map                   # analyze, propose & register domains (guided)
/graphify-wrapper-index backend services/backend --semantic   # or register one directly
/graphify-wrapper-sync                  # build all (AST), semantic where marked
/graphify-wrapper-query backend "where do we validate inbound webhooks?"
```

Requires `uv` (for `uv tool install graphifyy`), `git`, `jq`. No dependency on
other plugins.

## License

[MIT](../LICENSE).
