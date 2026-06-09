---
name: forge-review
description:
  "Chain-aware PR review — thin wrapper over the review capability, adding the
  proof gate, chain lenses, and forge verdict ladder."
argument-hint:
  "[PR# or branch] [--slug <name>] [--channels <ids>] [--add-channel <id>]...
  [--drop-channel <id>]... [--persona <id> | --personas <a,b,c> | --no-persona]
  [--embed]"
triggers:
  - "forge review"
  - "review the forge chain"
  - "lens review with forge"
  - "channel review"
  - "multi-channel pr review"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
practices:
  - code-review
user-invocable: true
---

# /forge-review — chain wrapper around the `review` capability

A **thin** chain layer over the chain-blind `review` capability (default
`/review`, `@orrgal1/devloop`). The capability owns the whole engine — channel
selection, the lens fan-out, the built-in `/code-review` + `/security-review`
channels, the gate, normalize/aggregate/synthesize, and `--embed`. This wrapper
adds only what's **forge-chain**: the proof precondition, the chain context +
chain lenses, chain-located state, and forge's richer verdict ladder.

Most flags (`--channels`, `--add-channel`, `--drop-channel`, `--channel … --…`,
`--persona`/`--personas`/`--no-persona`, `--embed`, a PR#/branch) pass straight
through.

## Resolve

1. Resolve the chain — run `~/.claude/forge/bin/forge-resolve.sh --json` and use
   its `forge_art`/`slug`/`worktree`/`chain_present` (worktree-rooted — never
   `ls`/`find` for `branches/<slug>/`, never look under `~/.claude/forge/`);
   resolve the PR per `/forge` rules.
2. Resolve the `review` capability (`~/.claude/forge/capabilities.toml`):
   override → use it; else fall back to the default `/review`
   (`@orrgal1/devloop`). Default provider absent & no override → refuse
   `PROVIDER_MISSING cap=review provider=@orrgal1/devloop` (install it or
   override via `/forge-setup`). No built-in substitute.

## Proof gate (chain)

Run `/forge-proof` (cached if recent). **FAIL** → refuse, point at the report;
settle `INCOMPLETE` (review not run). PASS → continue. Ground truth for the
review is the chain (`goals.md`, `links.json`, linked tests), not the PR body.

## Invoke the capability

Supply the chain context + the forge chain lenses, and point state at the chain:

```
/review [PR# or branch] \
  --context-lens-dir <forge plugin>/lenses \         # goal-delivery, scenario-realism, test-match
  --context goals=$FORGE_ART/branches/<slug>/goals.md \
  --context links=$FORGE_ART/branches/<slug>/links.json \
  --state $FORGE_ART/branches/<slug>/ \
  [passthrough flags]
```

The chain lenses (`goal-delivery`, `scenario-realism`, `test-match`) are the
Tier-2 context lenses the capability's `lens-fanout` channel fires **because**
the chain context is supplied; no chain context → they don't fire and review
still runs Tier 1 + Tier 3 + persona. Repo-supplied channels/lenses under
`$FORGE_HOME/review-channels/` + `$FORGE_HOME/lenses/` are passed through as the
override dirs too.

## Verdict (chain ladder)

Map the capability's verdict onto `/forge`'s wrap-verdict ladder:

| Capability verdict | Chain conditions                                       | forge verdict      |
| ------------------ | ------------------------------------------------------ | ------------------ |
| (proof FAIL)       | wrap skipped, review not run                           | `INCOMPLETE`       |
| `CLEAN`            | proof PASS + linked tests pass/skip                    | `READY`            |
| `CLEAN`            | proof PASS but ≥1 linked test `fail` / `error`         | `RED_BAR`          |
| `REVIEW_BLOCKED`   | proof PASS, tests pass, ≥1 blocker/major (any channel) | `REVIEWED_BLOCKED` |

`REVIEWED_BLOCKED` → `/forge-review-green` drives the blocking set to zero, then
re-run `/forge-review`, re-wrap.

## Embed

Pass `--embed` through. The capability writes the synthesis into its own
collapsible block in the PR body, a **sibling** of the proof block (never
nested) per `/forge-brief` § Body-layout contract — it preserves the brief and
the proof block verbatim.

## Next step

- `READY` (all channels clean) → `/forge` (or autopilot continues).
- `REVIEWED_BLOCKED` → `/forge-review-green` to drive to green.
- `/forge-status` — chain state + drift.

## Usage

```
/forge-review                                   # current branch's PR + chain
/forge-review 21228                             # PR by number
/forge-review --embed                           # also embed in PR body
/forge-review --add-channel security-review-builtin --channel security-review-builtin --scope src/auth
/forge-review --persona backend-senior
```
