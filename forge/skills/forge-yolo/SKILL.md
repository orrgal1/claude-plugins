---
name: forge-yolo
description:
  "Run the full forge chain with no contract pauses — drive scratch → READY,
  stopping only at genuine blockers. Thin wrapper over /forge --mode yolo."
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

Thin wrapper. Runs the full `/forge` chain in **`yolo` mode**: the goals /
design / scenarios contract gates auto-approve and advance instead of pausing
for operator review, so the run drives straight to a terminal state and stops
**only at genuine halts** (`BLOCKED_*`, `NEEDS_OPERATOR`, `STUCK`).

## Behavior

Invoke `/forge` with `--mode yolo`, **forwarding every argument verbatim**
(`source`, `--slug`, `--base`, `--max-review-cycles`, `--max-impl-iters`,
`--persona`, `--from`, `--until`, `--dry-run`). If the operator passes an
explicit `--mode`, ignore it and use `yolo` (this command's whole purpose).

Everything else is `/forge` exactly — same chain, phases, loop contract, honesty
bright lines, and result summary. See `/forge` § "Yolo mode" for the
contract-gate override. Yolo relaxes **no** bright line and skips **no** halt;
it removes only the three contract pauses.

## Usage

```
/forge-yolo https://jira/FOO-123      # fresh start → READY, no pauses
/forge-yolo                           # resume from earliest unsatisfied, no pauses
/forge-yolo --until tests             # pre-impl TDD lock, no goals/design/scenarios pause
/forge-yolo --from impl               # resume after operator unblocked
/forge-yolo --dry-run                 # plan only
```

Resume sub-commands (`/forge approve`, `/forge iterate`) are not needed in yolo
(no AWAIT settles), but the pushed contract artifacts remain on the PR — review
after the fact and `/forge iterate "<feedback>"` if a gate needs rework.
