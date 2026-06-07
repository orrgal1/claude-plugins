---
name: ci-green
description:
  "Drive a GitHub PR's CI to green — bounded fix loop, optional
  continuous-until-merge monitor."
argument-hint:
  "[--pr <num>] [--watch] [--until-merge] [--protect <globs>] [--state <dir>]
  [--on-green <cmd>] [max=<N>] [<check>] [stop]"
triggers:
  - "drive ci to green"
  - "make pr ci green"
  - "keep ci green until merge"
  - "fix the failing ci"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Agent
  - ScheduleWakeup
  - Monitor
  - TaskStop
user-invocable: true
---

# /ci-green — drive a PR's CI to green

Bounded fix-to-green loop against a GitHub PR's CI. Check = **`ci-check`**
(mergeability gate + three-probe snapshot + classify → verdict); fix =
**`ci-fix`** (diagnose one failing run, minimal fix, commit + push). The
controller owns the inter-tick wait; verify is poll-based (CI can't compress to
one exit code); **push per iteration** (CI can't verify a local commit).

Repo-agnostic and standalone — no dependency on any other plugin or on a forge
chain. Generic extension points (`--protect`, `--state`, `--on-green`) let a
caller layer its own policy on top without re-implementing the loop.

## Inputs

| Input           | Default                                                             |
| --------------- | ------------------------------------------------------------------- |
| `--pr`          | the branch's PR (`gh pr view`)                                      |
| `--watch`       | off — poll + report only, no fixes                                  |
| `--until-merge` | off — **continuous** mode: stay armed until the PR merges (§ below) |
| `--protect`     | comma-globs `ci-fix` must never touch → settle `BLOCKED_PROTECTED`  |
| `--state`       | loop-memory dir (scratchpad + status.json); default a neutral cache |
| `--on-green`    | shell command run on each transition to green (caller post-hook)    |
| `max=<N>`       | `10` (per fix-to-green episode)                                     |
| `<check>`       | positional — narrow the loop to one check                           |
| `stop`          | stop the running `--until-merge` monitor for this PR and exit       |

No PR → settle `NO_PR`. `mergeable=CONFLICTING` or
`mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → the per-iteration base-sync clears
a stale base; a genuine conflict settles `BLOCKED_REBASE_CONFLICT`.

## State (file-backed loop memory)

Under `--state <dir>` (default a neutral cache): `scratchpad.md` (per-iteration
log) + `status.json` (continuous-mode heartbeat). The controller threads each
`ci-check` `## handoff` (failing runs) into the `ci-fix` brief and each `ci-fix`
`## handoff` (pushed HEAD sha) into the next `ci-check`.

## Protected paths (`--protect`)

A per-iteration patch is **refused** if it would touch any `--protect` glob (the
caller's contract surfaces — e.g. spec files, linked tests). Refusal → settle
`BLOCKED_PROTECTED` naming the offending path; the caller decides how to revise.
Without `--protect`, every non-CI-config surface is fair game.

## Pre-flight (controller)

0. `stop` arg → resolve PR, `TaskStop` the `--until-merge` monitor for this PR,
   mark `status.json` `armed:false`, report, exit.
1. Resolve PR. `gh pr view --json number,mergeable,mergeStateStatus` →
   pre-flight (see Inputs). `--until-merge` with a monitor already live for this
   PR → report "already armed", exit (no double-arm).

## Control loop (main thread — never offloaded)

```
iter = 0
while iter < max:
    base-sync (below)                          # always sync base into branch first
    v = spawn ci-check                         # mergeability + 3-probe snapshot → verdict
    v.BLOCKED_REBASE → settle BLOCKED_REBASE
    v.GREEN → run --on-green (if set) → settle CI_GREEN
    v.GATED → stop + surface the gate (out-of-band of the CI fix flow)
    v.RUNNING → WAIT (below), continue           # do NOT count an iteration
    v.RED → act-vs-wait judgment (below):
              act  → spawn ci-fix(v.handoff failing runs); iter += 1
              wait → WAIT, continue
    fold v.signals → stuck check (below)
settle BUDGET_EXHAUSTED
```

**Base-sync (every iteration, controller-owned).** At the top of each iteration
— before `ci-check` — bring the base into the branch so CI always evaluates
against the current base and base-introduced breakage surfaces here, not after
merge. Use `/restack` if available, else plain git (`git fetch <remote> <base>`
→ merge `<remote>/<base>` into the branch). No new base commits → no-op (HEAD
unchanged, nothing pushed). A merge **conflict** → settle
`BLOCKED_REBASE_CONFLICT` (genuine — caller resolves; do not loop). A sync that
advances HEAD pushes once (merge, never force to a shared base) and re-triggers
CI; the same-iteration `ci-check` reads the synced HEAD. This proactively clears
`mergeStateStatus=BEHIND` rather than settling `BLOCKED_REBASE` for a stale
base.

Under `--watch`, the controller never spawns `ci-fix` — it loops `ci-check` +
WAIT and reports the terminal verdict (GREEN / GATED / still-RED) without
fixing.

## Continuous mode (`--until-merge`)

A **persistent** controller that keeps the PR's CI green from the first green
through **merge**. Armed once and lifetime-bound to the PR: it ends when the PR
is **merged or closed**, or on `stop` / `TaskStop`. Never self-terminates on
green — green is the steady state it maintains, not an exit.

Outer loop (background, controller-owned WAIT between passes):

```
last_green = HEAD-at-arm
loop:
    PR merged/closed?  → settle MERGED, terminate
    snapshot HEAD + ci-check verdict
    HEAD == last_green AND GREEN     → idle (WAIT), loop      # nothing changed
    HEAD advanced OR RED OR RUNNING  → run the inner fix-to-green loop
                                       (the § "Control loop", bounded by max);
                                       on CI_GREEN → last_green = HEAD; run --on-green
    GATED → surface the gate, keep armed (don't fix non-CI gates), loop
```

**Re-arms on every new HEAD even after green** — a follow-up push, a
per-iteration base-sync, or a manual commit each re-triggers the inner fix loop;
CI is driven back to green and `last_green` advances. There is no "final" CI
check — the monitor _is_ the check, continuously.

- **Status file** (`<state>/status.json`) for any external consumer:
  `{ "head": "<sha>", "verdict": "GREEN|RED|RUNNING|GATED", "since": "<iso>", "armed": true }`.
- A genuine `BLOCKED_REBASE_CONFLICT` / `BLOCKED_PROTECTED` inside an episode
  pauses fixing and surfaces (keeps armed); the caller resolves, the next HEAD
  re-fires.

**WAIT** (controller-owned): bounded sleep ~120–180s to keep the prompt cache
warm — `ScheduleWakeup` under `/loop`, else `Monitor` with an until-loop. Don't
handroll a `Bash` poll predicate (a naive `until pending==0` deadlocks on
perpetual-pending gates). Re-enter at the next `ci-check` after wakeup.

**Act-vs-wait** is the controller's judgment per tick: act when the failure is
self-contained and unrelated to what's still running; wait when in-flight jobs
touch the same surface (one fix with the full set beats two pushes), or the
failures look flake-suspicious. If unsure, wait one more tick.

## Offloaded unit — `ci-check`

Dispatch an `Agent` (read-only — no edits, no push, no waiting):

1. **Mergeability gate**:
   `gh pr view --json mergeable,mergeStateStatus,headRefOid`. `CONFLICTING` or
   `mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → `BLOCKED_REBASE` (pushes
   against this state may produce zero workflow runs → stale checks).
2. **Snapshot via three probes** (each covers a blind spot):
   - **A** required check-runs: `gh pr checks <num>` (job-level state).
   - **B** workflow runs for HEAD:
     `gh run list --commit "$(git rev-parse HEAD)" --limit 50 --json status,conclusion,workflowName`
     — catches dispatched-but-jobless runs Probe A can't see.
   - **C** merge-gate readiness:
     `gh pr view --json mergeable,mergeStateStatus,reviewDecision` +
     unresolved-thread count (GraphQL `reviewThreads`) — catches non-CI gates.
3. **Classify → verdict**: _RUNNING_ (any check in flight / any workflow
   `status != completed`); _RED_ (any
   `conclusion ∈ {failure,cancelled,timed_out,action_required}`); _GATED_ (zero
   running/red but Probe C shows `mergeStateStatus ∉ {CLEAN,HAS_HOOKS}` —
   unresolved threads, missing approval, pending external contexts like
   `code-review/*` or review-tool bots); _GREEN_ (zero running/red + Probe C
   clean).
4. `## handoff`: for RED, failing run(s) + first failure line; for GATED, the
   gate kind.

## Offloaded unit — `ci-fix`

Dispatch an `Agent` with the controller-supplied failing run(s):

- Read `scratchpad.md` on entry. Identify the failing run(s)
  (`gh run view <id> --log-failed`), read the failure (strongest signal first),
  pull artifacts if needed.
- Apply the **minimal** in-scope fix; verify locally (build/test/lint) when
  reproducible. Refuse any diff touching a `--protect` glob →
  `BLOCKED_PROTECTED`.
- **Commit one focused commit + push once** (no force, no rebase, no
  `--no-verify`). The push re-triggers CI; the next `ci-check` picks up the new
  run.
- Append `## iter <N>` (check / cause / fix / commit) to `scratchpad.md`:

  ```
  ## <iso> — ci-green cycle <N>
  - check:  <name>
  - cause:  <one-line>
  - fix:    <one-line>
  - commit: <sha>
  ```

## Stuck detection (controller-owned)

Signals folded: `same-check-fails`, `same-error-string`, `same-file-edited`,
`diff-grew-pass-flat`, `protect-refused` (hard at 1), `subagent-same-blocker`.
On a hard trip, settle `RED_PERSISTENT` with the repeated signal as the reason
rather than burning the remaining budget.

## Settle

| Verdict                   | Meaning                                                            |
| ------------------------- | ------------------------------------------------------------------ |
| `CI_GREEN`                | all required checks pass                                           |
| `NO_PR`                   | no PR for branch                                                   |
| `BLOCKED_REBASE`          | PR not mergeable                                                   |
| `BLOCKED_REBASE_CONFLICT` | the per-iteration base-sync hit a merge conflict — caller resolves |
| `BLOCKED_PROTECTED`       | a fix would touch a `--protect` path                               |
| `BUDGET_EXHAUSTED`        | hit `max=<N>` without converging                                   |
| `RED_PERSISTENT`          | loop stuck — red checks won't clear                                |
| `MERGED`                  | `--until-merge` monitor ended — PR merged/closed                   |

Each settle prints structured output (`verdict`, evidence, the failing run(s) /
gate kind) so a caller can branch on it — e.g. map `BLOCKED_REBASE` to its own
external-block recovery, or surface `BLOCKED_PROTECTED` to a contract owner.

## Usage

```
/ci-green                                    # current branch's PR
/ci-green --pr 512                           # explicit PR
/ci-green --watch                            # poll-only, no fixes
/ci-green --until-merge                      # continuous: keep CI green until merge
/ci-green --until-merge stop                 # stop the continuous monitor
/ci-green --protect '**/goals.md,test/**'    # never touch these while fixing
/ci-green max=20                             # raise budget
/ci-green "go unittests"                     # narrow to one check
```
