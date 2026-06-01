---
name: forge-ci-green
description:
  "Drive PR CI to green — main-thread loop controller; each fix + each CI
  snapshot offloaded to a subagent; controller owns the inter-tick wait."
argument-hint: "[--slug <name>] [--watch] [max=<N>]"
triggers:
  - "forge ci green"
  - "drive ci to forge green"
  - "make pr ci green"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Agent
  - ScheduleWakeup
  - Monitor
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-ci-green — drive CI to green, chain-aware

Runs the forge **loop contract** (`/forge` § "Loop contract") against GitHub PR
CI. **This skill is the loop _controller_** — it owns iteration count, budget,
signals, the green verdict, and **the inter-tick wait**, and offloads each
iteration's two heavy halves to `forge-step-runner` subagents: **`ci-check`**
(mergeability gate + three-probe snapshot + classify → verdict) and **`ci-fix`**
(diagnose one failing run, minimal fix, commit + push). Two CI-specific traits
carry over — poll-based verify (CI can't compress to one exit code) and
push-per-iteration (CI can't verify a local commit) — plus a chain-contract
guard, forge-tagged commits, and decisions-log integration.

## Inputs

| Input     | Default                                   |
| --------- | ----------------------------------------- |
| `--slug`  | sanitized branch name                     |
| `--watch` | off — fix-and-push loop active            |
| `max=<N>` | `10`                                      |
| `<check>` | positional — narrow the loop to one check |

No PR → settle `NO_PR`. `mergeable=CONFLICTING` or
`mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → settle `BLOCKED_RESTACK`. No chain
→ pass-through mode (run the CI loop without chain bookkeeping; warn once).

## State (file-backed loop memory)

`.pr-artifacts/<slug>/forge/loop/forge-ci-green-<slug>/` — `plan.md` +
`scratchpad.md`. Every offloaded subagent reads `scratchpad.md` on entry,
appends on exit; the controller threads each `ci-check` `## handoff` (failing
runs) into the `ci-fix` brief and each `ci-fix` `## handoff` (pushed HEAD sha)
into the next `ci-check`.

## Chain-contract guard (enforced in `ci-fix`, re-checked by controller)

A per-iteration patch is **refused** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `.pr-artifacts/<slug>/forge/goals.md`   | Goals + scenarios are the spec.                              |
| `.pr-artifacts/<slug>/forge/links.json` | Linkage is the chain.                                        |
| Test files named in `links.json`        | Linked tests are contract — failing CI means impl regressed. |
| `.pr-artifacts/<slug>/forge/design.md`  | Design records intent.                                       |

Refusal → `BLOCKED_CONTRACT`. Operator revises via `/forge-tests` /
`/forge-scenarios`. Non-contract surfaces (impl, deps, CI config, docs) are fair
game.

## Pre-flight (controller)

1. Resolve slug + worktree.
   `gh pr view --json number,mergeable,mergeStateStatus` → pre-flight (see
   Inputs). Read `links.json` → build the contract-file allowlist passed to
   every `ci-fix`.
2. **Triage gate** (skip if `--watch` or single trivial check):

   ```
   gh pr checks <num> --json name,conclusion | failing list
   /forge-triage --failing <list> --json
   ```

   Branch on `recommendation` (controller-owned — main thread):
   - `PROCEED` → continue.
   - `PROCEED_WITH_SKIPS` → for each `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_<ref>`:
     - Refuse if test path in `links.json` → halt `BLOCKED_CONTRACT`.
     - Else dispatch one `ci-fix` to apply the language-appropriate skip (Go
       `t.Skip`, py `@pytest.mark.skip` / `xfail`, TS `.skip(...)`) with verdict
       comment + sibling PR ref. Commit:
       `forge-ci-green: defer <test> per /forge-triage (<verdict>)`.
     - Enter the loop with the `REAL_BUG` subset only.
   - `HALT_TRIAGE` → verdict-named halt:
     - `FLAKE_SUSPECT` → `BLOCKED_FLAKY` (flakes are diagnosis-only — not a
       fix-loop target).
     - `INFRA_FAILURE` → `BLOCKED_INFRA`.
     - `AMBIGUOUS` → `NEEDS_OPERATOR` reason `triage-ambiguous`.

## Control loop (main thread — never offloaded)

```
iter = 0
while iter < max:
    v = spawn ci-check                         # mergeability + 3-probe snapshot → verdict
    v.BLOCKED_RESTACK → settle BLOCKED_RESTACK
    v.GREEN → spawn impl-check to refresh run.json (chain mode) → settle CI_GREEN
    v.GATED → stop + surface the gate (out-of-band of the CI fix flow)
    v.RUNNING → WAIT (below), continue           # do NOT count an iteration
    v.RED → act-vs-wait judgment (below):
              act  → spawn ci-fix(v.handoff failing runs); iter += 1
              wait → WAIT, continue
    fold v.signals → stuck check (below)
settle BUDGET_EXHAUSTED
```

Under `--watch`, the controller never spawns `ci-fix` — it loops `ci-check` +
WAIT and reports the terminal verdict (GREEN / GATED / still-RED) without
fixing.

**WAIT** (controller-owned): bounded sleep ~120–180s to keep the prompt cache
warm — `ScheduleWakeup` under `/loop`, else `Monitor` with an until-loop. Don't
handroll a `Bash` poll predicate (a naive `until pending==0` deadlocks on
perpetual-pending manual gates). Re-enter at the next `ci-check` after wakeup.

**Act-vs-wait** is the controller's judgment per tick: act when the failure is
self-contained and unrelated to what's still running; wait when in-flight jobs
touch the same surface (one fix with the full set beats two pushes), or the
failures look flake-suspicious. If unsure, wait one more tick.

## Offloaded unit — `ci-check`

`forge-step-runner step: ci-check`. No edits, no push, no waiting.

1. **Mergeability gate**:
   `gh pr view --json mergeable,mergeStateStatus,headRefOid`. `CONFLICTING` or
   `mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → `BLOCKED_RESTACK` (pushes
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

`forge-step-runner step: ci-fix` with the controller-supplied failing run(s).

- Read `scratchpad.md` on entry. Identify the failing run(s)
  (`gh run view <id> --log-failed`), read the failure (strongest signal first),
  pull artifacts if needed.
- Apply the **minimal** in-scope fix; verify locally via the
  `test`/`build`/`lint` capability when reproducible. Chain-contract guard each
  diff.
- **Commit one focused commit + push once** (no force, no rebase, no
  `--no-verify`). The push re-triggers CI; the next `ci-check` picks up the new
  run.
- Append `## iter <N>` (check / cause / fix / commit) to `scratchpad.md` +
  `decisions.md`:

  ```
  ## <iso> — forge-ci-green cycle <N>
  - check:  <name>
  - cause:  <one-line>
  - fix:    <one-line>
  - commit: <sha>
  ```

## Post-success — refresh `run.json` (chain mode)

On `CI_GREEN`, the controller spawns one `impl-check` (no fix) to re-run linked
tests locally and overwrite `run.json` — clears `run.stale` drift on the next
phase.

## Stuck detection (controller-owned)

Fold each subagent's `## signals`: `same-check-fails`, `same-error-string`,
`same-file-edited`, `diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
`subagent-same-blocker`. On hard trip →
`/forge-stuck-check --slug <slug> --phase ci-green --signal <name> --iter <N> --json`:

- `confirmed` → halt, settle `STUCK` with reflect's reason.
- `suspected` → bump threshold once, log, continue.
- `none` → log false-alarm, continue.

## Settle

| Verdict            | Meaning                                        |
| ------------------ | ---------------------------------------------- |
| `CI_GREEN`         | all required checks pass; `run.json` refreshed |
| `NO_PR`            | no PR for branch                               |
| `BLOCKED_RESTACK`  | PR not mergeable                               |
| `BLOCKED_CONTRACT` | guard refused                                  |
| `BUDGET_EXHAUSTED` | hit `max=<N>` without converging               |
| `FLAKY_DETECTED`   | loop settled on a flake-suspect failure        |
| `RED_PERSISTENT`   | loop stuck — red checks won't clear            |

## Hooks

- `/forge` phase 5.5 — post-impl CI before audit-green.
- `/forge` phase 6.5 / 9 — post-audit-embed CI re-confirm; final CI on
  post-review HEAD.
- `/forge-status` drift `pr.ci_failing` recommends this skill.

Both phases skip when `/forge-status` reports `pr.ci=pass` and no commits since
last green.

## Next step

CI green → resume the chain.

- `/forge-audit --embed` — post-impl path
- `/forge-review` — post-audit path
- `/forge` — close chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-ci-green                              # current branch's PR
/forge-ci-green --slug auth-refactor         # explicit slug
/forge-ci-green --watch                      # poll-only, no fixes
/forge-ci-green max=20                       # raise budget
/forge-ci-green "go unittests"               # narrow to one check
```
