---
name: forge-ci-green
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
  - ScheduleWakeup
  - Monitor
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-ci-green — drive CI to green, chain-aware

Runs the forge **loop contract** (`/forge` § "Loop contract") against GitHub PR
CI, with two CI-specific overrides — **poll-based verify** (CI can't compress to
one exit code) and **push-per-iteration** (CI can't verify a local commit). Adds
a chain-contract guard + forge-tagged commits + decisions-log integration so the
CI loop slots into the forge chain without smuggling scope.

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

## Chain-contract guard

Each per-iteration patch is checked before it lands. **Refuse** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `.pr-artifacts/<slug>/forge/goals.md`   | Goals + scenarios are the spec.                              |
| `.pr-artifacts/<slug>/forge/links.json` | Linkage is the chain.                                        |
| Test files named in `links.json`        | Linked tests are contract — failing CI means impl regressed. |
| `.pr-artifacts/<slug>/forge/design.md`  | Design records intent.                                       |

Refusal → `BLOCKED_CONTRACT`. Operator revises via `/forge-tests` /
`/forge-scenarios`. Non-contract surfaces (impl, deps, CI config, docs) are fair
game.

## Process

1. Resolve slug + worktree (per `/forge-status` § 1).
   `gh pr view --json number,mergeable,mergeStateStatus` → pre-flight (see
   Inputs). Read `links.json` → build contract-file allowlist.

2. **Triage gate** (skip if `--watch` or single trivial check):

   ```
   gh pr checks <num> --json name,conclusion | failing list
   /forge-triage --failing <list> --json
   ```

   Branch on `recommendation`:
   - `PROCEED` → continue.
   - `PROCEED_WITH_SKIPS` → for each `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_<ref>`:
     - Refuse if test path in `links.json` → halt `BLOCKED_CONTRACT`.
     - Else apply language-appropriate skip (Go `t.Skip`, py `@pytest.mark.skip`
       / `xfail`, TS `.skip(...)`) with verdict comment + sibling PR ref.
       Commit: `forge-ci-green: defer <test> per /forge-triage (<verdict>)`.
     - Enter step 3 with `REAL_BUG` subset only.
   - `HALT_TRIAGE` → verdict-named halt:
     - `FLAKE_SUSPECT` → `BLOCKED_FLAKY` (flakes are diagnosis-only — not a
       fix-loop target; surface for separate handling).
     - `INFRA_FAILURE` → `BLOCKED_INFRA`.
     - `AMBIGUOUS` → `NEEDS_OPERATOR` reason `triage-ambiguous`.

3. **Run the CI loop** (budget = `max`, optional focus `<check>`). Each
   iteration: **poll-verify → if red, diagnose + fix + push → re-poll**. Every
   per-iteration patch passes the chain-contract guard before it lands.

   **Poll-based verify** (never `gh pr checks --watch` / `--fail-fast` — the
   first hides parallel failures, the second blocks with no room to reason):
   1. **Mergeability gate** (per tick):
      `gh pr view --json mergeable,mergeStateStatus,headRefOid`. `CONFLICTING`
      or `mergeStateStatus ∈ {DIRTY,BEHIND,UNKNOWN}` → stop (`BLOCKED_RESTACK`):
      pushes against this state may produce zero workflow runs, so checks read
      stale.
   2. **Snapshot via three probes** (not one — each covers a blind spot):
      - **A** required check-runs: `gh pr checks <num>` (job-level state).
      - **B** workflow runs for HEAD:
        `gh run list --commit "$(git rev-parse HEAD)" --limit 50 --json status,conclusion,workflowName`
        — catches dispatched-but-jobless runs Probe A can't see.
      - **C** merge-gate readiness:
        `gh pr view --json mergeable,mergeStateStatus,reviewDecision` +
        unresolved-thread count (GraphQL `reviewThreads`) — catches non-CI
        gates.
   3. **Classify:** _running_ (any check in flight, or any workflow
      `status != completed`) → wait; _red_ (any
      `conclusion ∈ {failure,cancelled,timed_out,action_required}`) → fix;
      _CI-green-but-gated_ (zero running/red but Probe C shows
      `mergeStateStatus ∉ {CLEAN,HAS_HOOKS}` — unresolved threads, missing
      approval, pending external status contexts like `code-review/*` or
      review-tool bots) → **stop** and surface the gate (out-of-band of the CI
      fix flow); _green_ (zero running/red + Probe C clean) → verify exits 0 →
      `SUCCESS`.
   4. **Wait** between ticks with a bounded sleep (~120–180s, keep prompt cache
      warm). Use `ScheduleWakeup` under `/loop`, else `Monitor` with an
      until-loop — don't handroll a `Bash` poll predicate (a naive
      `until pending==0` deadlocks on perpetual-pending manual gates). Re-enter
      at the mergeability gate after each wakeup.

   **Act-vs-wait** is a judgment call per tick: act when the failure is
   self-contained and unrelated to what's still running; wait when in-flight
   jobs touch the same surface (one fix with the full set beats two pushes), or
   the failures look flake-suspicious. If unsure, wait one more tick.

   **Per-iteration implementer** (when red): identify the failing run(s)
   (`gh run view <id> --log-failed`), read the failure (strongest signal first),
   pull artifacts if needed, apply the **minimal** in-scope fix, verify locally
   via the `test`/`build`/`lint` capability when reproducible, then **commit one
   focused commit + push once** (no force, no rebase, no `--no-verify`). The
   push re-triggers CI; the poll loop picks up the new run.

4. **Statusline + Layer 1 signals** —
   `/forge-line --phase-id ci-green --sub "<check> iter <N>/<M>"` per iter.
   Track: `same-check-fails`, `same-error-string`, `same-file-edited`,
   `diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
   `subagent-same-blocker`. On hard trip →
   `/forge-stuck-check --slug <slug> --phase ci-green --signal <name> --iter <N> --json`:
   - `confirmed` → halt, settle `STUCK` with reflect's reason.
   - `suspected` → bump threshold once, log, continue.
   - `none` → log false-alarm, continue.

5. **Per-iteration bookkeeping** (chain mode):

   ```
   commit: forge-ci-green: <short fix>
   decisions.md:
     ## <iso> — forge-ci-green cycle <N>
     - check:  <name>
     - cause:  <one-line>
     - fix:    <one-line>
     - commit: <sha>
   ```

6. **Post-success — refresh `run.json`** (chain mode only). Re-run linked tests
   locally (same dispatch as `/forge-impl-green`) and overwrite `run.json`.
   Clears `run.stale` drift on the next phase.

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
