---
name: forge-yolo
description: "Full forge chain with no contract pauses (/forge --mode yolo)."
argument-hint:
  "[<source>] [--slug <name>] [--max-review-cycles <N>] [--persona <id>] [--from
  <phase>] [--until <phase>]"
triggers:
  - "forge yolo"
  - "forge no pauses"
  - "forge drive all the way"
  - "forge skip approvals"
allowed-tools:
  - Skill
user-invocable: true
---

# /forge-yolo — forge with no contract pauses

Thin wrapper. Runs the full `/forge` chain in **`yolo` mode**: the ground /
goals / design / scenarios contract gates auto-approve and advance instead of
pausing for operator review, so the run drives straight to a terminal state and
stops **only at genuine halts** (`BLOCKED_*`, `NEEDS_OPERATOR`, `STUCK`) — plus
the two READY-region **author gestures** yolo never performs autonomously: the
author-review gate (`AWAIT_AUTHOR_REVIEW`) and the ready-for-review request
(`AWAIT_REVIEW_REQUEST`).

## Behavior

Invoke `/forge` with `--mode yolo`, **forwarding every argument verbatim**
(`source`, `--slug`, `--base`, `--max-review-cycles`, `--max-impl-iters`,
`--persona`, `--from`, `--until`, `--dry-run`). If the operator passes an
explicit `--mode`, ignore it and use `yolo` (this command's whole purpose).

Everything else is `/forge` exactly — same chain, phases, loop contract, honesty
bright lines, and result summary. See `/forge` § "Yolo mode" for the
contract-gate override.

Because no gate pauses, keep the **in-session todo list** current at every phase
transition — it is the operator's only live progress signal in this mode
(`/forge` § "Progress todos").

## Usage

```
/forge-yolo https://jira/FOO-123      # fresh start → READY, no pauses
/forge-yolo                           # resume from earliest unsatisfied, no pauses
/forge-yolo --until tests             # pre-impl TDD lock, no ground/goals/design/scenarios pause
/forge-yolo --from impl               # resume after operator unblocked
/forge-yolo --dry-run                 # plan only
```

Resume sub-commands (`/forge approve`, `/forge iterate`) are not needed for the
four contract gates in yolo (they auto-approve), but the two READY-region author
gates still settle and wait for `/forge approve`. The pushed contract artifacts
also remain on the PR — review after the fact and `/forge iterate "<feedback>"`
if a gate needs rework.
