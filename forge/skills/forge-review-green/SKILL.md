---
name: forge-review-green
description:
  "Drive multi-channel review to zero blockers+majors — thin grind wrapper."
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "forge review green"
  - "drive forge review to green"
  - "clear review blockers"
  - "fix review findings"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
user-invocable: true
---

# /forge-review-green — review cycles to zero blockers+majors

A **thin** chain layer over the generic `iteration_loop` capability (default
`/grind`, `@orrgal1/devloop`). grind owns the entire fix-to-green loop — step
dispatch, commit-per-step, stuck detection, budget. This wrapper adds only what
touches the **forge chain**: the contract-protect set, the review-cycle verify
command, finding-status bookkeeping, and the settle→verdict mapping.

**Scope: blocker + major to green.** Those drive the loop; a clean cycle is 0
blocker + 0 major. Minors and nits do **not** gate — they survive to deferral
(below), logged but never blocking the verdict.

## Resolve

1. Resolve the chain — run `~/.claude/forge/bin/forge-resolve.sh --json` and use
   its `forge_art`/`slug`/`worktree`/`chain_present` (worktree-rooted — never
   `ls`/`find` for `branches/<slug>/`, never look under `~/.claude/forge/`);
   resolve the PR per `/forge` rules. Confirm
   `$FORGE_ART/branches/<slug>/{goals.md,links.json}` exist.
2. **Entry condition** (refuse without): `/forge-proof` PASS + linked tests all
   green/skipped (cached OK). Tests red → `/forge-impl-green` first.
3. Resolve the `iteration_loop` capability
   (`~/.claude/forge/capabilities.toml`): override → use it; else fall back to
   the default `/grind` (`@orrgal1/devloop`). Default provider absent & no
   override → refuse
   `PROVIDER_MISSING cap=iteration_loop provider=@orrgal1/devloop` (install it
   or override via `/forge-setup`).

## Invoke the capability

```
<iteration_loop> "drive the multi-channel review to zero open blockers+majors — verify: a /forge-review cycle reports 0 blocker and 0 major findings" \
  protect='$FORGE_ART/branches/<slug>/{goals.md,links.json,design.md},<linked test paths>' \
  slot=review-green-<slug> \
  max=<N>
```

- The **verify** is a `/forge-review` cycle (which itself fans out the `review`
  capability across channels). grind loops fixing findings until a cycle comes
  back with 0 blocker + 0 major. `max` defaults to `5`.
- `protect=` carries the chain-contract surfaces — goals/links/design + every
  test named in `links.json`. A finding targeting any of these can't be fixed
  in-loop; grind stops `BLOCKED` on it (§ Contract findings).

**`/forge-review` fan-out runs in the main thread** — a loop step can't nest
fan-out, so the verify command's `/forge-review` is the controller's.

## Loop guidance (chain bookkeeping the steps follow)

Per cycle, write `$FORGE_ART/branches/<slug>/review/cycle-<N>.md` and **status
every finding** against prior cycles — the drift-control surface:

| Status       | Meaning                                                                      |
| ------------ | ---------------------------------------------------------------------------- |
| `new`        | Surfaced this cycle, not in prior cycles.                                    |
| `addressed`  | Open in prior cycle, now closed. Grounded in a commit / line change since.   |
| `regressed`  | Was `addressed`, defect is back. Requires citation of the regressing change. |
| `reopened`   | Was `addressed`, the fix introduced a different defect. Requires citation.   |
| `persistent` | Open in prior cycle, still open (no fix attempted, or fix didn't land).      |

- **No bare reversal** — `addressed → new` is forbidden; use `regressed` /
  `reopened` with citation.
- **Out-of-PR-scope findings are DEFERRED, not fixed.** Append to `cycle-N.md`
  under `## Deferred (out-of-PR-scope)` with finding id + reason + cited owner
  PR. Minors and nits that survive a green verdict land here too.

### Contract findings (float to operator)

A finding targeting a contract surface (linked test, `goals.md`, `links.json`,
`design.md` — i.e. a `protect=` path) can't be fixed in-loop: grind stops
`BLOCKED` (protected-path edit). The wrapper **floats it to the operator** — it
revises the contract via `/forge-tests` / `/forge-scenarios` / `/forge-goals`,
never a silent severity downgrade or drop.

grind owns the rest of the loop machinery — dispatch, commits, stuck detection,
budget.

## On capability settle (chain mapping)

| grind verdict      | Chain verdict / action                                                            |
| ------------------ | --------------------------------------------------------------------------------- |
| `SUCCESS`          | settle `REVIEW_GREEN` (latest cycle: 0 blocker + 0 major)                         |
| `BLOCKED`          | protected-path → float the contract finding to the operator; else settle verbatim |
| `STUCK`            | settle `STUCK`; common: out-of-scope → defer, un-solveworthy → propose recut      |
| `BUDGET_EXHAUSTED` | settle verbatim — `max` cycles, blockers/majors still open                        |

Append one `decisions.md` line per terminal verdict (cycle count + verdict).

## Next step

- `/forge-proof --embed` — re-aggregate post-review state
- `/forge-review --embed` — embed review block
- `/forge` — close chain · `/forge-status` — chain state + drift

## Usage

```
/forge-review-green                          # current branch's PR
/forge-review-green --slug auth-refactor     # explicit slug
/forge-review-green max=8                     # raise budget (default 5)
```
