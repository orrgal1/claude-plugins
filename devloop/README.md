# @orrgal1/devloop

Thin, repo-agnostic dev-loop skills for **stacked-PR work** in
[Claude Code](https://claude.com/claude-code). It keeps a PR (or a whole stack)
in sync with its base, and strips AI slop from a diff before review.

It infers PR topology from GitHub (`gh`) by default and falls back to raw git
analysis (tracked upstreams, merge-bases) when `gh` is unavailable. No
dependency on other plugins.

## Skills

| Skill          | Purpose                                                                                                                                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `/restack`     | Bring a PR's base into its branch — **fetch + sync the base with upstream first**, then merge (default) or rebase (`--rebase` opt-in, or per your standing preference). Stops on conflict; pushes once at the end (never force-pushes the base). |
| `/restack-all` | `/restack` across an entire stack, **bottom-up** — each PR onto its just-updated base, so changes propagate up the stack. Stops at the first broken layer.                                                                                       |
| `/deslop`      | Scan a PR's diff and strip AI slop — delete comments that restate the code, cap survivors at one line, and collapse over-complex local code (reusing the built-in `/simplify` pass). Touches only changed hunks; behavior must not change.       |

## Usage

```
/restack                         # restack the current branch's PR on its base
/restack 1234                    # by PR number / URL / branch
/restack --rebase                # rebase instead of merge
/restack-all                     # restack the whole stack containing this branch
/deslop                          # de-slop the current PR's diff
```

`/restack` honors your merge-vs-rebase preference (persona / git discipline);
with none stated it merges. Requires `git` and, for topology inference, the `gh`
CLI.

## License

[MIT](../LICENSE).
