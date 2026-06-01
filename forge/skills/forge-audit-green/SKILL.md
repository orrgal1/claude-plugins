---
name: forge-audit-green
description:
  "Drive the forge audit to PASS — main-thread loop controller; each fix + each
  re-audit offloaded to a subagent."
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "forge audit green"
  - "drive forge audit to green"
  - "fix audit findings"
  - "make audit pass"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Agent
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-audit-green — drive structural audit to PASS

Wraps `/forge-audit` in a fix-loop. **This skill is the loop _controller_** per
`/forge` § "Loop contract": it owns iteration count, budget, signals, and the
PASS verdict, and offloads each iteration's two heavy halves to
`forge-step-runner` subagents — the **check** is the `verify` aggregator step
(`/forge-audit` itself), the **fix** is `audit-fix` (one finding's mechanical
delta + commit). Sister to `/forge-ci-green` + `/forge-impl-green`.

## Inputs

| Input     | Default               |
| --------- | --------------------- |
| `--slug`  | sanitized branch name |
| `max=<N>` | `10`                  |

## State (file-backed loop memory)

`.pr-artifacts/<slug>/forge/loop/forge-audit-green-<slug>/` — `plan.md` (one
bullet per open finding) + `scratchpad.md` (append-only `## iter <N>` log).
Every offloaded subagent reads `scratchpad.md` on entry and appends on exit; the
controller threads the check's `## handoff` (smallest blocking set) into each
`audit-fix` brief.

## Chain-contract guard (enforced in `audit-fix`, re-checked by controller)

A per-iteration patch is **refused** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `.pr-artifacts/<slug>/forge/goals.md`   | Goals + scenarios are the spec.                              |
| `.pr-artifacts/<slug>/forge/links.json` | Linkage is the chain — don't repoint to silence Layer-4.     |
| Linked test bodies (assertions)         | `assert:` is the contract. (Comments + AAA markers OK.)      |
| `.pr-artifacts/<slug>/forge/design.md`  | Design records intent; rewriting to absorb Layer-5 is drift. |

Refusal → settle `BLOCKED_CONTRACT`. Operator addresses the contract via
`/forge-scenarios`, `/forge-tests`, `/forge-goals`, `/forge-design`.

Non-contract surfaces (impl source, test `when:` / `then:` comments, AAA
markers, tier notes, coverage map cells for SGs already in `goals.md`) are fair
game.

## Findings → routing (controller reads the check's smallest blocking set)

`/forge-audit` emits `## smallest blocking set` (preserved verbatim in the
check's `## handoff`). The controller routes each row — **mechanical fixes go to
`audit-fix`; everything else is spawned as its own step-runner or halts**:

| Layer + verdict                             | Route                                                                                            |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Layer 1 — structural FAIL (any)             | Halt `BLOCKED_CONTRACT` — goals shape is operator-iterate via `/forge-goals`.                    |
| Layer 1 — loyalty DRIFTED / EXTRA / MISSING | Halt `BLOCKED_CONTRACT` — loyalty fix is `/forge-goals --iterate "<feedback>"`.                  |
| Layer 2 — UNCOVERED                         | Spawn `forge-step-runner step: scenarios` (goal G<n>) once. Halt `BLOCKED_CONTRACT` if unfilled. |
| Layer 3 — UNLINKED                          | Spawn `forge-step-runner step: tests` (SG<n>.<m>) once. Halt `BLOCKED_CONTRACT` on miss.         |
| Layer 3 — STALE                             | Spawn `forge-step-runner step: tests` (`--refresh SG<n>.<m>`) once. Halt on miss.                |
| Layer 3 — TIER-UNIT / TIER-UNKNOWN          | Halt `BLOCKED_CONTRACT` — re-tiering implies behavior change, operator.                          |
| Layer 4 — NO-COMMENT / NO-AAA / DRIFT       | `audit-fix` — mechanical annotation (add `when:`/`then:`, AAA markers, fix stale entity name).   |
| Layer 4 — MISMATCH                          | Halt `BLOCKED_CONTRACT` — `assert:` doesn't realize the scenario; operator picks side.           |
| Layer 5 — ORPHAN-SG                         | Spawn `forge-step-runner step: design` once. Halt `BLOCKED_CONTRACT` if it doesn't cover.        |
| Layer 5 — ORPHAN-ELEMENT / EMPTY-PROVES     | `audit-fix` — edit the component's `proves:` line to cite the right SG(s).                       |
| Layer 5 — DANGLING-SG                       | Halt `BLOCKED_CONTRACT` — map cites a scenario no longer in `goals.md`.                          |
| Layer 6 — STALE / MISSING                   | Spawn one `impl-check` to refresh `run.json`. Tests still red → `BLOCKED_CONTRACT` (behavior).   |
| Layer 6 — DANGLING                          | Spawn `forge-step-runner step: tests` (`--refresh SG<n>.<m>`) once to realign cache.             |
| Layer 6 — FAIL / ERROR                      | Halt `BLOCKED_CONTRACT` — behavior fix is `/forge-impl-green` (its own loop), not annotation.    |
| Tier sanity WARN                            | Skip (not a blocker).                                                                            |
| `tier_reason` missing on non-component      | `audit-fix` — add the reason to the scenario's `- tier:` sub-bullet.                             |

**Same defect 3 iters in a row** → halt `BLOCKED_RECURRENT`.

## Control loop (main thread — never offloaded)

```
resolve slug + worktree; read goals.md (+ links.json) for the allowlist.
missing goals → NO_CHAIN.
iter = 0
while iter < max:
    a = spawn verify step (forge-step-runner)         # the re-audit → smallest blocking set
    a.PASS → invoke /forge-audit --embed once → settle AUDIT_GREEN
    route each finding in a.handoff (table above):
        mechanical → spawn audit-fix(finding)
        routed     → spawn the named step-runner once
        contract   → settle BLOCKED_CONTRACT
    fold subagent ## signals → stuck check (below)
    iter += 1
settle BUDGET_EXHAUSTED
```

Embed (`/forge-audit --embed`) is a one-shot on PASS — no fix-loop, no push.

## Offloaded units

- **check** = `forge-step-runner step: verify` → runs `/forge-audit`, returns
  per-layer verdicts + `## handoff` = the smallest blocking set. Read-only;
  never applies a fix.
- **fix** = `forge-step-runner step: audit-fix` → applies one finding's
  mechanical delta + commit, contract-guarded. Returns the commit + signals.

Commit + decisions log live in `audit-fix`:

```
forge-audit-green: <SG or layer> <one-line fix>
```

`.pr-artifacts/<slug>/forge/decisions.md`:

```
## <iso> — forge-audit-green cycle <N>
- finding: <layer> <verdict> <SG or path>
- fix:     <one-line>
- commit:  <sha>
```

## Stuck detection (controller-owned)

Fold each subagent's `## signals`: `same-finding-recurs`, `same-file-edited`,
`diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
`subagent-same-blocker`. On hard trip →
`/forge-stuck-check --slug <slug> --phase audit --signal <name> --iter <N> --json`:

- `confirmed` → halt loop, settle `STUCK` with the named reason.
- `suspected` → bump threshold once, log, continue.
- `none` → log false-alarm, continue.

## Settle

| Verdict             | Meaning                                      |
| ------------------- | -------------------------------------------- |
| `AUDIT_GREEN`       | `verify` PASS                                |
| `NO_CHAIN`          | no `goals.md` for slug                       |
| `BLOCKED_CONTRACT`  | guard refused OR finding on contract surface |
| `BLOCKED_RECURRENT` | same finding survived 3 iters                |
| `BUDGET_EXHAUSTED`  | hit `max=<N>` without PASS                   |
| `STUCK`             | `/forge-stuck-check` confirmed               |

## Hooks

- `/forge` phase 6 — drives audit to PASS before embed. Skip phase when
  `/forge-status` says `audit.last_verdict=PASS` and no commits since.
- `/forge-status` drift (`pr.no_forge_block`, `goals.uncovered`,
  `links.test_id_missing`) recommends this skill as the fix command.

## Next step

`AUDIT_GREEN` → resume chain.

- `/forge-audit --embed` — write report to PR body
- `/forge-ci-green` — confirm CI stays green after any landed commits
- `/forge-review-green` — semantic review
- `/forge` — close the chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-audit-green                       # current branch
/forge-audit-green --slug auth-refactor  # explicit slug
/forge-audit-green max=20                # raise budget
```
