---
name: forge-impl-green
description:
  "Drive a PR's linked scenario tests to green — thin chain wrapper over the
  iteration_loop capability."
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "drive forge tests to green"
  - "make linked tests pass"
  - "close the forge chain"
  - "forge impl green"
  - "get to green"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Write
  - Grep
  - Glob
practices:
  - tdd
  - commit-per-iteration
user-invocable: true
---

# /forge-impl-green — chain wrapper around the `iteration_loop` capability

A **thin** chain layer over the `iteration_loop` capability (default `/grind`,
`@orrgal1/grind`). The capability owns the entire fix-to-green loop machinery —
`plan.md`, per-iteration commit, stuck detection, budget. This wrapper adds only
what touches the **forge chain**: resolving `links.json` into the verify command

- protect set, the baseline flake-exit, and the verdict mapping. Local test runs
  only — never pushes, never polls CI; hand off to `/forge-ci-green` for CI.

## Inputs

| Input    | Default               |
| -------- | --------------------- |
| `--slug` | sanitized branch name |
| `max`    | `10`                  |

Prereqs: `$FORGE_ART/branches/<slug>/goals.md` exists with a `- test:`
sub-bullet on every scenario, and `links.json` resolves each scenario to a test
path + function. Missing → exit, point at `/forge` or `/forge-tests`.

## Resolve

1. Resolve slug + worktree + PR per `/forge` rules. Verify prereqs.
2. Resolve the `iteration_loop` capability (`~/.claude/forge/capabilities.toml`;
   default `/grind`; unconfigured → `NEEDS_SETUP cap=iteration_loop`, point at
   `/forge-setup`).

## Baseline & failure handling

Run the linked set once (via the `test` capability) before invoking the loop:

- **Flake-shaped baseline** (intermittent, no plausible code cause) → exit
  `BLOCKED_FLAKY`; flakes are diagnosis-only, not a fix-loop target.
- A failing baseline that looks like **infra** (not a code defect) → consult
  repo playbooks (`/forge-setup` § "Failure recovery — playbooks"): a match
  recovers + retries; an interactive recovery no one completes →
  `BLOCKED_INFRA`.
- Baseline already green → settle `IMPL_GREEN` (refresh `run.json`), no loop.

## Invoke the capability

The wrapper resolves `links.json` into both the verify command and the protect
set, then hands the loop a single self-contained target:

```
<iteration_loop> "drive this PR's linked scenario tests to green — verify: <command that runs exactly the tests linked in links.json, via the repo `test` capability ($FORGE_HOME/commands/test <selectors>), and exits 0 iff they all pass>" \
  protect='<linked test file paths from links.json>,$FORGE_ART/branches/<slug>/{goals.md,links.json,design.md}' \
  slot=impl-green-<slug> \
  max=<N>
```

**Key point:** the loop never knows _which_ tests. The wrapper answers "which
tests" by resolving `links.json` → the verify command (the exact linked
selectors, full set so sibling regressions surface) + the protect set (every
linked test file + the chain-contract surfaces). The loop just drives that one
verify command to exit 0 without editing what it protects.

## On capability settle (chain mapping)

| Capability verdict       | Chain action                                                                                                 |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `SUCCESS`                | settle `IMPL_GREEN`; refresh `run.json` by re-running the linked tests (automatic, never offered)            |
| `BLOCKED` (protect path) | settle `BLOCKED_CONTRACT`, name the contract file (operator revises via `/forge-tests` / `/forge-scenarios`) |
| `BLOCKED` (other)        | settle `RED_PERSISTENT` / `BLOCKED_IMPL` with the failure signature; log to `decisions.md`                   |
| `BUDGET_EXHAUSTED`       | settle verbatim; log to `decisions.md`                                                                       |

The protect set is how the never-touch guard is enforced: a step that can only
go green by editing a linked **test body**, `goals.md`, `links.json`, or
`design.md` stops `BLOCKED` → `BLOCKED_CONTRACT`. A genuinely wrong test is
fixed by re-running `/forge-tests`, never by the loop.

`run.json` refresh runs the **full** linked set so sibling regressions surface,
overwriting `$FORGE_ART/branches/<slug>/run.json`.

## Termination

| Verdict            | Trigger                                             |
| ------------------ | --------------------------------------------------- |
| `IMPL_GREEN`       | loop `SUCCESS` — linked set all `pass` / `skipped`. |
| `BLOCKED_CONTRACT` | loop `BLOCKED` on a protected (contract) path.      |
| `RED_PERSISTENT`   | loop `BLOCKED` on a non-contract failure.           |
| `BUDGET_EXHAUSTED` | `max` reached with failures outstanding.            |
| `BLOCKED_FLAKY`    | flake-shaped baseline.                              |
| `BLOCKED_INFRA`    | infra-shaped baseline, no playbook recovery.        |

On `IMPL_GREEN` → suggest `/forge-proof --embed`.

## Output

```
## /forge-impl-green result

verdict: IMPL_GREEN | BUDGET_EXHAUSTED | BLOCKED_CONTRACT | RED_PERSISTENT | BLOCKED_FLAKY | BLOCKED_INFRA
slug: <branch-slug>
loop: <used>/<max> iterations

remaining failures (if not IMPL_GREEN):
  - SG<n>.<m> — <function> — <last line of failure>

### next move
<one line>

state: $FORGE_ART/branches/<slug>/grind/impl-green-<slug>/ — edit plan.md or re-invoke /forge-impl-green max=<N>.
```

## Next step

Green locally → push + drive CI.

- `/forge-ci-green` — drive CI to green
- `/forge-proof --embed` — re-aggregate + embed in PR body
- `/forge-status` — chain state + drift

## Usage

```
/forge-impl-green                    # loop current branch's linked tests
/forge-impl-green max=20             # raise budget
/forge-impl-green --slug auth-fix    # explicit slug
```
