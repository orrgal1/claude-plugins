---
name: forge-proof-green
description: "Drive the forge proof to PASS."
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "forge proof green"
  - "drive forge proof to green"
  - "fix proof findings"
  - "make proof pass"
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

# /forge-proof-green — drive structural proof to PASS

Loop per `/forge` § Loop contract. Target: `/forge-proof` PASS. Check = the
`verify` aggregator step (`/forge-proof` itself); fix = `proof-fix` (one
finding's mechanical delta + commit).

## Inputs

| Input     | Default               |
| --------- | --------------------- |
| `--slug`  | sanitized branch name |
| `max=<N>` | `10`                  |

## State (file-backed loop memory)

Slot `$FORGE_ART/branches/<slug>/loop/forge-proof-green-<slug>/` per `/forge` §
Loop contract. `plan.md` — one bullet per open finding. Controller threads the
check's `## handoff` (smallest blocking set) into each `proof-fix` brief.

## Chain-contract guard (enforced in `proof-fix`, re-checked by controller)

A per-iteration patch is **refused** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `$FORGE_ART/branches/<slug>/goals.md`   | Goals + scenarios are the spec.                              |
| `$FORGE_ART/branches/<slug>/links.json` | Linkage is the chain — don't repoint to silence Layer-4.     |
| Linked test bodies (assertions)         | `assert:` is the contract. (Comments + AAA markers OK.)      |
| `$FORGE_ART/branches/<slug>/design.md`  | Design records intent; rewriting to absorb Layer-5 is drift. |

Refusal → settle `BLOCKED_CONTRACT`. Operator addresses the contract via
`/forge-scenarios`, `/forge-tests`, `/forge-goals`, `/forge-design`.

Non-contract surfaces (impl source, test `when:` / `then:` comments, AAA
markers, tier notes, coverage map cells for SGs already in `goals.md`) are fair
game.

## Findings → routing (controller reads the check's smallest blocking set)

`/forge-proof` emits `## smallest blocking set` (preserved verbatim in the
check's `## handoff`). The controller routes each row — **mechanical fixes go to
`proof-fix`; everything else is spawned as its own step-runner or halts**:

| Layer + verdict                             | Route                                                                                            |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Layer 1 — structural FAIL (any)             | Halt `BLOCKED_CONTRACT` — goals shape is operator-iterate via `/forge-goals`.                    |
| Layer 1 — loyalty DRIFTED / EXTRA / MISSING | Halt `BLOCKED_CONTRACT` — loyalty fix is `/forge-goals --iterate "<feedback>"`.                  |
| Layer 2 — UNCOVERED                         | Spawn `forge-step-runner step: scenarios` (goal G<n>) once. Halt `BLOCKED_CONTRACT` if unfilled. |
| Layer 3 — UNLINKED                          | Spawn `forge-step-runner step: tests` (SG<n>.<m>) once. Halt `BLOCKED_CONTRACT` on miss.         |
| Layer 3 — STALE                             | Spawn `forge-step-runner step: tests` (`--refresh SG<n>.<m>`) once. Halt on miss.                |
| Layer 3 — TIER-UNIT / TIER-UNKNOWN          | Halt `BLOCKED_CONTRACT` — re-tiering implies behavior change, operator.                          |
| Layer 4 — NO-COMMENT / NO-AAA / DRIFT       | `proof-fix` — mechanical annotation (add `when:`/`then:`, AAA markers, fix stale entity name).   |
| Layer 4 — MISMATCH                          | Halt `BLOCKED_CONTRACT` — `assert:` doesn't realize the scenario; operator picks side.           |
| Layer 5 — ORPHAN-SG                         | Spawn `forge-step-runner step: design` once. Halt `BLOCKED_CONTRACT` if it doesn't cover.        |
| Layer 5 — ORPHAN-ELEMENT / EMPTY-PROVES     | `proof-fix` — edit the component's `proves:` line to cite the right SG(s).                       |
| Layer 5 — DANGLING-SG                       | Halt `BLOCKED_CONTRACT` — map cites a scenario no longer in `goals.md`.                          |
| Layer 6 — STALE / MISSING                   | Spawn one `impl-check` to refresh `run.json`. Tests still red → `BLOCKED_CONTRACT` (behavior).   |
| Layer 6 — DANGLING                          | Spawn `forge-step-runner step: tests` (`--refresh SG<n>.<m>`) once to realign cache.             |
| Layer 6 — FAIL / ERROR                      | Halt `BLOCKED_CONTRACT` — behavior fix is `/forge-impl-green` (its own loop), not annotation.    |
| Tier sanity WARN                            | Skip (not a blocker).                                                                            |
| `tier_reason` missing on non-component      | `proof-fix` — add the reason to the scenario's `- tier:` sub-bullet.                             |

**Same defect 3 iters in a row** → halt `BLOCKED_RECURRENT`.

## Control loop (main thread — never offloaded)

```
resolve slug + worktree; read goals.md (+ links.json) for the allowlist.
missing goals → NO_CHAIN.
iter = 0
while iter < max:
    a = spawn verify step (forge-step-runner)         # the re-prove → smallest blocking set
    a.PASS → invoke /forge-proof --embed once → settle PROOF_GREEN
    route each finding in a.handoff (table above):
        mechanical → spawn proof-fix(finding)
        routed     → spawn the named step-runner once
        contract   → settle BLOCKED_CONTRACT
    fold subagent ## signals → stuck check (below)
    iter += 1
settle BUDGET_EXHAUSTED
```

Embed (`/forge-proof --embed`) is a one-shot on PASS — no fix-loop, no push.
`/forge-proof` is the aggregator over verify-\* skills + inline L5 design; it
doubles as the loop's **check** — controller never calls per-layer skills
directly.

## Offloaded units

- **check** = `forge-step-runner step: verify` → runs `/forge-proof`, returns
  per-layer verdicts + `## handoff` = the smallest blocking set. Read-only.
- **fix** = `forge-step-runner step: proof-fix` → one finding's mechanical delta
  - commit, contract-guarded. Returns commit + signals.

Commit + decisions log live in `proof-fix`:

```
forge-proof-green: <SG or layer> <one-line fix>
```

`$FORGE_ART/branches/<slug>/decisions.md`:

```
## <iso> — forge-proof-green cycle <N>
- finding: <layer> <verdict> <SG or path>
- fix:     <one-line>
- commit:  <sha>
```

## Stuck detection (controller-owned)

Signals folded: `same-finding-recurs`, `same-file-edited`,
`diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
`subagent-same-blocker`. On hard trip →
`/forge-stuck-check --slug <slug> --phase proof --signal <name> --iter <N> --json`
→ `confirmed` settles `STUCK` (named reason); `suspected` bumps threshold once;
`none` logs false-alarm.

## Settle

| Verdict             | Meaning                                      |
| ------------------- | -------------------------------------------- |
| `PROOF_GREEN`       | `verify` PASS                                |
| `NO_CHAIN`          | no `goals.md` for slug                       |
| `BLOCKED_CONTRACT`  | guard refused OR finding on contract surface |
| `BLOCKED_RECURRENT` | same finding survived 3 iters                |
| `BUDGET_EXHAUSTED`  | hit `max=<N>` without PASS                   |
| `STUCK`             | `/forge-stuck-check` confirmed               |

## Hooks

- `/forge` phase 6 — drives proof to PASS before embed. Skip phase when
  `/forge-status` says `proof.last_verdict=PASS` and no commits since.
- `/forge-status` drift (`pr.no_forge_block`, `goals.uncovered`,
  `links.test_id_missing`) recommends this skill as the fix command.

## Next step

`PROOF_GREEN` → resume chain.

- `/forge-proof --embed` — write report to PR body
- `/forge-ci-green` — confirm CI stays green after any landed commits
- `/forge-review-green` — semantic review
- `/forge` — close the chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-proof-green                       # current branch
/forge-proof-green --slug auth-refactor  # explicit slug
/forge-proof-green max=20                # raise budget
```
