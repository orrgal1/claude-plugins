# @orrgal1/devloop

Repo-agnostic dev-loop + tooling skills for
[Claude Code](https://claude.com/claude-code) — stacked-PR ops, a bounded
iteration-loop engine, and a diagnostic toolkit. It is **forge's single
companion plugin**: forge resolves every agent capability it consumes (the
iteration loop, the PR ops, the diagnostics) to a skill here. Each skill is also
useful standalone, with no forge involved.

It infers PR topology from GitHub (`gh`) by default and falls back to raw git
analysis (tracked upstreams, merge-bases) when `gh` is unavailable. No
dependency on other plugins.

## Skills

### Stacked-PR ops

| Skill          | Purpose                                                                                                                                                                                        |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/restack`     | Bring a PR's base into its branch — **sync the base with upstream first**, then merge (default) or rebase (`--rebase`). Stops on conflict; never force-pushes a base.                          |
| `/restack-all` | `/restack` across an entire stack, **bottom-up** — each PR onto its just-updated base. Stops at the first broken layer.                                                                        |
| `/deslop`      | Strip AI slop from a PR diff — delete code-restating comments, cap survivors at one line, collapse over-complex local code (reusing `/simplify`). `--protect <globs>` spares designated files. |
| `/pr-brief`    | Write/refresh a tight 1–3 sentence PR description, idempotently spliced into a marker-bounded body region.                                                                                     |

### Review + CI

| Skill             | Purpose                                                                                                                                                                 |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/review`         | Multi-channel PR review — parallel lens fan-out (lens-reviewer agent + lens pool) + always-on `/code-review` and `/security-review` → one verdict.                      |
| `/review-watch`   | Persistent PR monitor firing a `--on-trigger` handler on each new review-like event; re-arms until stopped.                                                             |
| `/address-review` | Drive externally-submitted reviewer feedback to resolution — intake, triage, fix-walk under `--protect`, reply/resolve, re-request.                                     |
| `/request-review` | Rank the most relevant peer reviewer by signal precedence and, gated, mark ready + request.                                                                             |
| `/author-review`  | Guide the author's self-review — structured diff walkthrough + manual-verification pass (via a repo how-to), each embeddable as an idempotent collapsible body section. |
| `/ci-green`       | Drive a GitHub PR's CI to green — bounded fix-to-green loop, optional `--until-merge` monitor.                                                                          |
| `/find-blocker`   | Classify whether a PR is held by an external blocker (red/behind base, infra, sibling PR); emit a neutral, waitable condition spec.                                     |

### Iteration loop + diagnostics

| Skill          | Purpose                                                                                                                                                                             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/grind`       | General bounded-autonomy iteration loop toward any verifiable target — grind to green, commit each step, stop at success/budget. Designed to be wrapped by more specific fix-loops. |
| `/stuck-check` | In-loop rabbit-hole detector — score loop signals, return continue / raise-threshold / halt.                                                                                        |
| `/root-cause`  | Hypothesis-driven root-cause analysis with parallel fan-out.                                                                                                                        |
| `/hypothesize` | Lighter 2–4 candidate hypothesis loop with one cheap experiment per round.                                                                                                          |
| `/pepper`      | Scatter uniquely-marked trace logs through suspect code, run the repro, grep, iterate, clean up.                                                                                    |
| `/trace`       | Route verbose process output to disk and grep it instead of polluting agent context.                                                                                                |

## Usage

```
/restack                         # restack the current branch's PR on its base
/restack-all                     # restack the whole stack
/deslop                          # de-slop the current PR's diff
/review                          # multi-channel review of the current PR
/grind "<verifiable target>"     # grind any target to green
/root-cause                      # find the root cause of a bug, flake, or regression
```

`/restack` honors your merge-vs-rebase preference (persona / git discipline);
with none stated it merges. Requires `git` and, for topology inference, the `gh`
CLI.

## License

[MIT](../LICENSE).
