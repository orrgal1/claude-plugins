---
name: forge-impl-green
description:
  "Drive linked scenario tests to green — main-thread loop controller; each fix
  + each green-check offloaded to a subagent."
argument-hint: "[--slug <name>] [--scenario SG<n>.<m>] [max=<N>]"
triggers:
  - "drive forge tests to green"
  - "make linked tests pass"
  - "close the forge chain"
  - "forge impl green"
  - "get to green"
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
  - commit-per-iteration
user-invocable: true
---

# /forge-impl-green — drive linked tests to green

Loop per `/forge` § Loop contract. Target: the linked tests. Fix =
**`impl-fix`** (one narrow delta + commit); check = **`impl-check`** (run linked
tests, write `run.json`, return verdict). Local test runs only — never pushes,
never polls CI; hand off to `/forge-ci-green` for CI.

## Inputs

| Input        | Default                                         |
| ------------ | ----------------------------------------------- |
| `--slug`     | sanitized branch name                           |
| `--scenario` | all failing scenarios (narrow with `SG<n>.<m>`) |
| `max`        | `10`                                            |

Prereqs: `$FORGE_ART/branches/<slug>/goals.md` exists with `- test:` sub-bullets
on every scenario. Missing → exit, point at `/forge` or `/forge-tests`.

## State (file-backed loop memory)

Slot `$FORGE_ART/branches/<slug>/loop/forge-impl-green-<slug>/` per `/forge` §
Loop contract. `plan.md` — one bullet per failing `REAL_BUG` scenario.

## Pre-flight (controller)

1. Resolve slug + worktree. Verify prereqs.
2. **Baseline `impl-check`** (first subagent) → fresh failing set.
3. **Flake-shaped baseline** (intermittent, no code change plausibly caused it)
   → exit `BLOCKED_FLAKY`; flakes are diagnosis-only, not a fix-loop target.
4. **Triage gate** when failing set ≥2: `/forge-triage --failing <list> --json`
   (controller-owned — main thread).
   - `PROCEED` → continue.
   - `PROCEED_WITH_SKIPS` → for each `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_<ref>`:
     - In `links.json` → halt `BLOCKED_CONTRACT` (chain guard wins).
     - Else dispatch one `impl-fix` to apply skip/defer with verdict comment +
       sibling PR ref. Commit:
       `forge-impl-green: defer <SG> per /forge-triage (<verdict>)`.
   - `HALT_TRIAGE` → halt verdict-named (`BLOCKED_FLAKY`, `BLOCKED_INFRA`,
     `NEEDS_OPERATOR` reason `triage-ambiguous`). Exception: an
     `INFRA_FAILURE recovery=<name>` (triage matched a playbook) → run that
     playbook (recover + retry per `/forge-setup` § "Failure recovery —
     playbooks"); only halt `BLOCKED_INFRA` if recovery fails or is an
     interactive playbook under yolo/unattended.
   - Single-test failures skip this gate.
5. Seed `plan.md` (one bullet per failing `REAL_BUG` scenario, isolated first).

## Control loop (main thread — never offloaded)

```
iter = 0
while iter < max:
    v = baseline (iter 0) | spawn impl-check          # heavy verify → subagent
    if v.verdict == SUCCESS:        settle SUCCESS
    if v.verdict == ERROR:          settle BLOCKED     # wrong-reason (exit 2)
    fold v.signals into history → stuck check (below)  # cheap, controller-owned
    spawn impl-fix(failing set, handoff)               # heavy fix → subagent
    iter += 1
settle BUDGET_EXHAUSTED                                # max hit, target unmet
```

`impl-check` runs once per iteration _before_ the fix, so check-count =
fix-count + 1. Controller threads `v`'s `## handoff` (failing set + last-failure
line) into the `impl-fix` brief, and the fix's `## handoff` into the next
`impl-check`.

## Offloaded unit — `impl-check`

Read-only w.r.t. source; the only write is `run.json`. Dispatched as
`forge-step-runner step: impl-check`.

- Read `goals.md` scenarios + `- test:` / `- tier:` sub-bullets (strip
  backticks). Run them via the `test` capability
  (`$FORGE_HOME/commands/test <selector>`, per `/forge` § "Repo tooling").
- Always run the **full** linked set per tick — sibling regressions must
  surface. Aggregate to `$FORGE_ART/branches/<slug>/run.json` (overwrite).
- Append a `## iter <N>` check line to `scratchpad.md`.

Exit codes → verdict returned to the controller:

- `0` — every result `pass` or `skipped` → `SUCCESS`.
- `1` — ≥1 `fail`, OR a panic / exception carrying the literal marker
  `forge-tests: unimplemented` from a `/forge-tests` step-3b scaffold. The
  marker counts as `fail`; the next `impl-fix` fills that surface.
- `2` — ≥1 `error` (compile / fixture / runner) **not carrying the unimplemented
  marker** → `ERROR`. Controller settles `BLOCKED`. Wrong-reason — scaffold
  missed a shape, impl regressed one, or the runner is broken; operator decides.

## Offloaded unit — `impl-fix`

One iteration's delta. Dispatched as `forge-step-runner step: impl-fix` with the
controller-supplied failing set.

- Read `scratchpad.md` + `plan.md` on entry (prior attempts, learnings).
- Pick one failing scenario (controller-narrowed; isolated-first), read its
  `then:`, apply the **smallest** impl-source delta. May run that single
  scenario locally to sanity its own change; authoritative green is the next
  `impl-check`.
- Commit one focused commit: `forge-impl-green: SG<n>.<m> — <fix>`.
- Append `## iter <N>` (tried / result / learned / plan-delta) to
  `scratchpad.md`; tick the `plan.md` item.

### Guardrails (both units)

Base guardrails per `/forge` § Loop contract + § Guardrails (local commits,
never push, untrusted failing-test text, stay in failing surface).
Skill-specific delta:

- **Never modify test bodies.** Tests encode the `then:`. Genuinely wrong test →
  re-run `/forge-tests`. Reshaping a test breaks Layer 4 on next proof.
- **Never modify `goals.md` or `links.json`** during the loop.

## Stuck detection (controller-owned)

Signals folded across iterations: `same-scenario-flat`, `same-error-string`,
`same-file-edited`, `diff-grew-pass-flat`, `contract-guard-refused`,
`decisions-log-churn`. On hard trip →
`/forge-stuck-check --slug <slug> --phase impl --signal <name> --iter <N> --json`
→ `confirmed` settles `STUCK` (reflect's reason); `suspected` bumps threshold
once; `none` logs false-alarm.

## Termination

| Verdict            | Trigger                                                               |
| ------------------ | --------------------------------------------------------------------- |
| `SUCCESS`          | `impl-check` returns all `pass` / `skipped`.                          |
| `BUDGET_EXHAUSTED` | `max` reached with failures outstanding.                              |
| `BLOCKED`          | Wrong-reason error (exit 2), 3 no-progress iters, contract-guard hit. |
| `STUCK`            | `/forge-stuck-check` confirmed.                                       |

On `SUCCESS` → suggest `/forge-proof --embed`.

## Output

```
## /forge-impl-green result

verdict: SUCCESS | BUDGET_EXHAUSTED | BLOCKED | STUCK
iterations: <used>/<max>   (checks: <c>, fixes: <f>)
slug: <branch-slug>
last batch: <P>/<total> passed

remaining failures (if not SUCCESS):
  - SG<n>.<m> — <function> — <last line of failure>

### next move
<one line>

state: $FORGE_ART/branches/<slug>/loop/forge-impl-green-<slug>/ — edit plan.md or re-invoke max=<N>.
```

## Next step

Green locally → push + drive CI.

- `/forge-ci-green` — drive CI to green
- `/forge-proof --embed` — re-aggregate + embed in PR body
- `/forge-status` — chain state + drift

## Usage

```
/forge-impl-green                   # loop current branch's linked tests
/forge-impl-green max=20            # raise budget
/forge-impl-green --scenario SG2.1  # narrow to one scenario
```
