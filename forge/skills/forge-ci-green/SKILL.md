---
name: forge-ci-green
description: "Drive PR CI to green."
argument-hint: "[--slug <name>] [--watch] [--until-merge] [max=<N>] [stop]"
triggers:
  - "forge ci green"
  - "drive ci to forge green"
  - "make pr ci green"
  - "keep ci green until merge"
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
  - TaskStop
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-ci-green — drive CI to green, chain-aware

Loop per `/forge` § Loop contract against GitHub PR CI. Check = **`ci-check`**
(mergeability gate + three-probe snapshot + classify → verdict); fix =
**`ci-fix`** (diagnose one failing run, minimal fix, commit + push). CI-specific
overrides: controller owns **the inter-tick wait**; verify is poll-based (CI
can't compress to one exit code); **push per iteration** (CI can't verify a
local commit) — overriding the contract's never-push.

## Inputs

| Input           | Default                                                             |
| --------------- | ------------------------------------------------------------------- |
| `--slug`        | sanitized branch name                                               |
| `--watch`       | off — poll + report only, no fixes                                  |
| `--until-merge` | off — **continuous** mode: stay armed until the PR merges (§ below) |
| `max=<N>`       | `10` (per fix-to-green episode)                                     |
| `<check>`       | positional — narrow the loop to one check                           |
| `stop`          | stop the running `--until-merge` monitor for this PR and exit       |

No PR → settle `NO_PR`. `mergeable=CONFLICTING` or
`mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → the per-iteration restack clears a
stale base; a genuine conflict settles `BLOCKED_RESTACK_CONFLICT`. No chain →
pass-through mode (run the CI loop without chain bookkeeping; warn once).

## State (file-backed loop memory)

Slot `$FORGE_ART/branches/<slug>/loop/forge-ci-green-<slug>/` per `/forge` §
Loop contract. Controller threads each `ci-check` `## handoff` (failing runs)
into the `ci-fix` brief and each `ci-fix` `## handoff` (pushed HEAD sha) into
the next `ci-check`.

## Chain-contract guard (enforced in `ci-fix`, re-checked by controller)

A per-iteration patch is **refused** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `$FORGE_ART/branches/<slug>/goals.md`   | Goals + scenarios are the spec.                              |
| `$FORGE_ART/branches/<slug>/links.json` | Linkage is the chain.                                        |
| Test files named in `links.json`        | Linked tests are contract — failing CI means impl regressed. |
| `$FORGE_ART/branches/<slug>/design.md`  | Design records intent.                                       |

Refusal → `BLOCKED_CONTRACT`. Operator revises via `/forge-tests` /
`/forge-scenarios`. Non-contract surfaces (impl, deps, CI config, docs) are fair
game.

## Pre-flight (controller)

0. `stop` arg → resolve slug, `TaskStop` the `--until-merge` monitor for this
   PR, mark `status.json` `armed:false`, report, exit.
1. Resolve slug + worktree.
   `gh pr view --json number,mergeable,mergeStateStatus` → pre-flight (see
   Inputs). Read `links.json` → build the contract-file allowlist passed to
   every `ci-fix`. `--until-merge` with a monitor already live for this PR →
   report "already armed", exit (no double-arm).
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
     - `INFRA_FAILURE` → `BLOCKED_INFRA`, **unless** triage returned
       `recovery=<name>` (a matched playbook): run that playbook best-effort
       (recover + retry per `/forge-setup` § "Failure recovery — playbooks");
       halt `BLOCKED_INFRA` only if the recovery itself fails (e.g. an
       interactive auth no one completed).
     - `AMBIGUOUS` → `NEEDS_OPERATOR` reason `triage-ambiguous`.

## Control loop (main thread — never offloaded)

```
iter = 0
while iter < max:
    restack (below)                            # always sync base into branch first
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

**Restack (every iteration, controller-owned).** At the top of each iteration —
before `ci-check` — run the **configured `restack` capability**
(`[restack].skill`, e.g. `/restack`; else a wired command/instructions; else
forge's built-in git fallback — see `/forge-setup` § restack) to fetch and bring
the base into the branch, so CI always evaluates against the current base and
base-introduced breakage surfaces here, not after merge. No new base commits →
no-op (HEAD unchanged, nothing pushed). A merge **conflict** → settle
`BLOCKED_RESTACK_CONFLICT` (genuine — operator resolves; do not loop). A restack
that advances HEAD pushes once (merge per operator preference, never force to a
shared base) and re-triggers CI; the same-iteration `ci-check` reads the
restacked HEAD. This proactively clears `mergeStateStatus=BEHIND` rather than
settling `BLOCKED_RESTACK` for a simply-stale base.

Under `--watch`, the controller never spawns `ci-fix` — it loops `ci-check` +
WAIT and reports the terminal verdict (GREEN / GATED / still-RED) without
fixing.

## Continuous mode (`--until-merge`)

A **persistent** controller that keeps the PR's CI green from the first green
through **merge** — forge's standing guarantee, not a one-shot phase. Armed once
(by `/forge` after the first `CI_GREEN`, phase 7.5) and lifetime-bound to the
PR: it ends when the PR is **merged or closed**, or on `stop` / `TaskStop`.
Never self-terminates on green — green is the steady state it maintains, not an
exit.

Outer loop (background, controller-owned WAIT between passes):

```
last_green = HEAD-at-arm
loop:
    PR merged/closed?  → settle MERGED, terminate
    snapshot HEAD + ci-check verdict
    HEAD == last_green AND GREEN     → idle (WAIT), loop      # nothing changed
    HEAD advanced OR RED OR RUNNING  → run the inner fix-to-green loop
                                       (the § "Control loop", bounded by max);
                                       on CI_GREEN → last_green = HEAD
    GATED → surface the gate, keep armed (don't fix non-CI gates), loop
```

**Re-arms on every new HEAD even after green** — a review-fix push, a a
per-iteration restack, a base sync, or a manual commit each re-triggers the
inner fix loop; CI is driven back to green and `last_green` advances. There is
no "final" CI check — the monitor _is_ the check, continuously.

- **Mode-aware fixing.** `yolo` / unattended / `auto` → drives to green (spawns
  `ci-fix`). `manual` → runs as `--watch` (report red, no autonomous fix) to
  respect manual's pause-every-phase contract.
- **Coalesce with review.** While `/forge-review-green` (phase 8) is mid-push,
  defer one pass so one settled HEAD is fixed, not a half-pushed one. Single
  fix-to-green episode at a time.
- **Status file** for the orchestrator + `/forge-status`:
  `$FORGE_ART/branches/<slug>/loop/ci-green-continuous/status.json`
  `{ "head": "<sha>", "verdict": "GREEN|RED|RUNNING|GATED", "since": "<iso>", "armed": true }`.
  READY reads this instead of running a separate phase-9 loop.
- A genuine `BLOCKED_RESTACK_CONFLICT` / `BLOCKED_CONTRACT` inside an episode
  pauses fixing and surfaces (keeps armed); the operator resolves, the next HEAD
  re-fires.

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
phase. This refresh is **automatic, not offered** (per `/forge` § "Bias to
progress" — keep metadata current): it runs even when it must first bring up
local test infra (non-destructive), and is never surfaced as an optional "want
me to refresh run.json?" question. Skip only when `run.json` is already fresh
for HEAD (no commits since last green).

## Stuck detection (controller-owned)

Signals folded: `same-check-fails`, `same-error-string`, `same-file-edited`,
`diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
`subagent-same-blocker`. On hard trip →
`/forge-stuck-check --slug <slug> --phase ci-green --signal <name> --iter <N> --json`
→ `confirmed` settles `STUCK` (reflect's reason); `suspected` bumps threshold
once; `none` logs false-alarm.

## Settle

| Verdict                    | Meaning                                                            |
| -------------------------- | ------------------------------------------------------------------ |
| `CI_GREEN`                 | all required checks pass; `run.json` refreshed                     |
| `NO_PR`                    | no PR for branch                                                   |
| `BLOCKED_RESTACK`          | PR not mergeable                                                   |
| `BLOCKED_RESTACK_CONFLICT` | the per-iteration restack hit a merge conflict — operator resolves |
| `BLOCKED_CONTRACT`         | guard refused                                                      |
| `BUDGET_EXHAUSTED`         | hit `max=<N>` without converging                                   |
| `FLAKY_DETECTED`           | loop settled on a flake-suspect failure                            |
| `RED_PERSISTENT`           | loop stuck — red checks won't clear                                |
| `MERGED`                   | `--until-merge` monitor ended — PR merged/closed                   |

## External-block recognizer (waitable settles)

`BLOCKED_RESTACK` (base behind / red) and `BLOCKED_INFRA` (triage
`INFRA_FAILURE`) are _external_ — resolved by a base PR going green or an
incident clearing, not by a fix here. Per `/forge` § "External-block
recognizer", instead of plain-settling: run the `find_blocker` capability
(`/find-blocker --hint <verdict> --json --out $FORGE_ART/branches/<slug>/blocker/last.json`);
on a confirmed peripheral blocker, mode-gate the dispatch of
`/forge-wait-for --condition <spec> --from ci` (`yolo`/unattended → auto
restack+resume; `auto`/`manual` → surface the command, settle as-is).
`BLOCKED_FLAKY` is diagnosis-only — **never** waitable; `BLOCKED_CONTRACT` and
`BLOCKED_RESTACK_CONFLICT` (a real merge conflict from the per-iteration
restack) are genuine — **never** waitable.

## Hooks

- `/forge` phase 5.5 — post-impl CI before proof-green (one-shot).
- `/forge` phase 6.5 — post-proof-embed CI re-confirm (one-shot).
- `/forge` phase 7.5 — on the first `CI_GREEN`, forge arms this skill
  `--until-merge` in the background; it keeps CI green through review and
  beyond, re-arming on every new HEAD until the PR merges. **There is no
  separate final CI phase** — the continuous monitor replaces it.
- `/forge-status` reads the continuous monitor's `status.json`; drift
  `pr.ci_failing` recommends this skill.

One-shot phases skip when `/forge-status` reports `pr.ci=pass` and no commits
since last green.

## Next step

CI green → resume the chain.

- `/forge-proof --embed` — post-impl path
- `/forge-review` — post-proof path
- `/forge` — close chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-ci-green                              # current branch's PR
/forge-ci-green --slug auth-refactor         # explicit slug
/forge-ci-green --watch                      # poll-only, no fixes
/forge-ci-green --until-merge                # continuous: keep CI green until merge
/forge-ci-green --until-merge stop           # stop the continuous monitor
/forge-ci-green max=20                       # raise budget
/forge-ci-green "go unittests"               # narrow to one check
```
