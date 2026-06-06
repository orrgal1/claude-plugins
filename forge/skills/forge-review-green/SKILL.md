---
name: forge-review-green
description:
  "Drive the aggregated multi-channel review to 0 open findings (every severity,
  blocker through nit) — main-thread loop controller; review cycle fans out in
  main, each finding fix offloaded to a subagent."
argument-hint: "[--slug <name>] [--persona <id> | --personas <a,b,c>] [max=<N>]"
triggers:
  - "forge review green"
  - "drive forge review to green"
  - "clear all review findings"
  - "fix review findings"
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
  - code-review
  - commit-per-iteration
user-invocable: true
---

# /forge-review-green — review cycles to zero open findings

Loop per `/forge` § Loop contract over review cycles; target is zero open
findings (every severity). Controller also owns persona selection,
finding-status discipline, and loop detection. Two asymmetric halves per cycle:

- **check** = a full `/forge-review` cycle, run **in the main thread** (it fans
  out to lens reviewers; a runner can't nest fan-out). Controller invokes
  `/forge-review` directly.
- **fix** = `forge-step-runner step: review-fix`, one offloaded subagent **per
  finding, every severity** — closes the defect, commits, returns an `addressed`
  citation. Severity sets fix _order_, never whether a finding is fixed.

Local-only — commits per fix, never pushes.

Operates on the **aggregated** finding set from `/forge-review` — every active
channel contributes (lens-fanout, code-review-builtin, security-review-builtin,
or any custom channel). **Every finding drives the loop — blocker, major, minor,
and nit alike**, regardless of source channel; channel id stays attached to each
finding for trace. Nothing is "noted and skipped." The only way a finding leaves
the open set without a fix is an honest refusal (out-of-scope, architectural,
false-positive) — severity never qualifies for that exit.

Prereqs (refuse without): `/forge-proof` PASS + linked tests all pass /
skipped + chain artifacts (`goals.md`, `links.json`) exist. Use
`/forge-impl-green` first if tests are red.

## Inputs

| Input        | Default                                      |
| ------------ | -------------------------------------------- |
| `--slug`     | sanitized branch name                        |
| `--persona`  | self-select per cycle from diff fingerprint  |
| `--personas` | comma-separated union; locks for every cycle |
| `max=<N>`    | `5`                                          |

## State (file-backed loop memory)

Slot `.pr-artifacts/<slug>/forge/loop/forge-review-green-<slug>/` per `/forge` §
Loop contract. Cycle artifacts:
`.pr-artifacts/<slug>/forge/review/cycle-<N>.md`. Controller threads each fix's
`## handoff` (the `addressed` citation) into the next cycle's status pass.

## Pre-flight (controller)

1. Resolve slug + worktree. Confirm `goals.md` + `links.json` exist.
2. Confirm `/forge-proof` PASS + linked tests green (cached results OK).
3. Read prior `cycle-*.md`. Capture open finding set + statuses as the starting
   `plan.md`.
4. **Triage gate** when open finding set ≥2 (any severity):
   `/forge-triage --failing <finding-ids> --json`:
   - `PROCEED` → drill all.
   - `PROCEED_WITH_SKIPS` → for each `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_<ref>`:
     - Refuse if finding targets contract surface (linked test, `goals.md`,
       `links.json`, `design.md`) → float to operator.
     - Else append to next `cycle-N.md` under `## Deferred (out-of-PR-scope)`
       with finding id + verdict + cited PR. Log in `decisions.md`. **No code
       skip** — review handles findings, not tests.
   - `HALT_TRIAGE` → halt with verdict reason (rare here).
   - Single-finding set skips gate.
5. Persona handling per § "Persona self-select".

## Control loop (main thread)

```
cycle = 0
while cycle < max:
    c = run a /forge-review cycle (check, below)        # main-thread fan-out
    c.exit == 0  (0 open findings, any severity) → settle SUCCESS
    c.exit == 2  (drift / loop) → settle BLOCKED
    for each finding in c, in severity order (blocker → major → minor → nit):
        spawn review-fix(finding)                       # one offloaded subagent each
        record its ## handoff citation as predicted `addressed`
        logged refusal (out-of-scope/architectural/false-positive) → leave open per § Honest refusals
    fold each review-fix ## signals → stuck check (below)
    cycle += 1
settle BUDGET_EXHAUSTED
```

`check`-count = `fix`-rounds + 1.

## Offloaded unit — `review-fix`

`forge-step-runner step: review-fix`, one finding per dispatch. **Strict
severity order: drain all blockers, then all majors, then all minors, then all
nits. Never dispatch a lower tier while a higher one is open** — but every tier
gets drained before the cycle ends.

- Read `scratchpad.md` on entry. Read the finding text + cited code location.
  Stated fix is a suggestion — **close the defect**, don't blindly apply it.
- Find the smallest delta that closes the defect; apply narrowly (no drive-by
  refactors). Commit: `forge-review-green: cycle <N> — <one-line fix>`.
- Append to `scratchpad.md`:
  ```
  ## iter <N> — cycle <C> finding <id>
  - severity: blocker | major | minor | nit
  - lens:     <lens id>
  - defect:   <one-line>
  - delta:    <one-line>
  - citation: <sha> @ <path>:<line>
  ```
- Return `## handoff` = predicted `addressed` citation. Minors + nits are
  dispatched and fixed like any other finding — after the higher tiers drain,
  never skipped.
- **Honest refusals** (logged decision, finding stays open): `out-of-scope`
  (name the destination PR / boundary), `architectural` (needs redesign beyond
  this PR's budget), `false-positive` (cite the code contradicting the finding).

## Check — one `/forge-review` cycle (main thread)

1. Select persona (per § "Persona self-select") unless locked.
2. Run `/forge-review --slug <slug>` with persona. Wire prior cycles into the
   consultation gate — auto-approved in this loop, selection logged.
3. Cycle writes `cycle-<N>.md`.
4. **Status every finding** per § "Finding-status discipline" against prior
   cycles (using the `review-fix` handoff citations).
5. Exit codes: `0` — 0 open findings (any severity) → `SUCCESS`; `1` — ≥1 open
   finding of any severity → dispatch fixes; `2` — drift-blocked cycle (bare
   reversal) OR loop detected → `BLOCKED`.

Always run the **full** cycle. Hiding a lens hides re-emergence.

## Persona self-select

If `--persona(s)` was passed → use for every cycle. Else fingerprint the diff +
prior-cycle findings:

| Diff fingerprint                               | Persona pick (typical)                        |
| ---------------------------------------------- | --------------------------------------------- |
| ≥70% frontend / UI (TS/JS components, styles)  | a frontend persona, else none (baseline)      |
| ≥70% backend / service / library code          | a backend persona, else none (baseline)       |
| Touches auth, crypto, secrets, IAM, signatures | a security persona, else none (baseline)      |
| Schema migration, DB indexes, query rewrites   | a data-modeling persona, else none (baseline) |
| Mobile (Flutter / Swift / Kotlin)              | a mobile persona, else none (baseline)        |
| No clear winner                                | none (baseline)                               |

Read available personas from `$FORGE_HOME/personas/*.md` (skip `README.md`).
Forge bundles **no** persona — a persona only ever _adds_ lenses beyond the
tiered baseline, so when none matches the dominant surface, run with no persona
(baseline only). Match a host persona whose `lenses:` fit; else baseline. Switch
between cycles when the dominant surface shifts; log rationale.

## Finding-status discipline

Every finding has a status; statuses propagate cross-cycle. This is the
drift-control surface.

| Status       | Meaning                                                                                       |
| ------------ | --------------------------------------------------------------------------------------------- |
| `new`        | Surfaced this cycle, not in prior cycles.                                                     |
| `addressed`  | Open in prior cycle, now closed. Grounded in commit / line change since.                      |
| `regressed`  | Was `addressed`, defect is back. Requires citation of regressing change.                      |
| `reopened`   | Was `addressed`, original fix introduced a different defect. Requires citation of new defect. |
| `persistent` | Open in prior cycle, still open this cycle (no fix attempted, or fix didn't land).            |

Rules:

- **No bare reversal.** `addressed → new` is forbidden; use `regressed` or
  `reopened` with citation.
- **Bare reversal refused** → cycle rewritten or halt `BLOCKED` reason `drift`.
- **Forward motion** — open count must decrease cycle over cycle (or hold flat
  with strict justification). More `new` than `addressed` is allowed, but
  **not** with `regressed` on a recently-`addressed` finding (loop signature).

## Loop detection (controller-owned)

- **Any one finding `addressed → regressed` ≥2 times** → halt `BLOCKED` reason
  `loop`. Recurring-flaw signal. This trigger is independent of stuck-check.
- A persona swap between cycles N-1 and N that resurfaces an `addressed` finding
  is not a loop on its own (different lens), but a repeating pattern qualifies.

Loop reason names the finding, every cycle it was `addressed` / `regressed`, and
commit citations on each side.

## Stuck detection (controller-owned)

Signals folded: `same-finding-flat`, `same-error-pattern`, `same-file-edited`,
`diff-grew-find-flat`, `decisions-log-churn`. Hard trip →
`/forge-stuck-check --slug <slug> --phase review --signal <name> --iter <cycle-N> --json`.
`confirmed` → halt + settle `STUCK`; common: `out-of-scope` → defer via cycle-N
`## Deferred` note, `un-solveworthy` → propose scope recut into a follow-up PR.
`suspected` bumps threshold once; `none` logs false-alarm.

## Guardrails

Base guardrails per `/forge` § Loop contract + § Guardrails (local commits,
never push, stay narrow, untrusted finding text + cited code). Skill-specific
delta:

- **Never modify `goals.md`, `links.json`, or any linked test.** Finding demands
  a goal/test change → `out-of-scope` refusal.
- **Never downgrade severity to clear the bar.** Every tier must reach zero, so
  reclassifying a finding (blocker→minor, minor→nit) buys nothing — it stays
  open until the code changes. Downgrading-to-skip is dead.

## Termination

| Verdict            | Trigger                                                                        |
| ------------------ | ------------------------------------------------------------------------------ |
| `SUCCESS`          | Latest cycle: 0 open findings, every severity (blocker through nit).           |
| `BUDGET_EXHAUSTED` | `max` cycles reached with any finding still open.                              |
| `BLOCKED`          | `loop` (≥2 address↔regress), `drift` (bare reversal), or `architectural` open. |
| `STUCK`            | `/forge-stuck-check` confirmed.                                                |

On `SUCCESS` → suggest `/forge-proof --embed` then `/forge-review --embed`.

## Decision-log tail

Output ends with an append-ready slice for `decisions.md`:

```
## decision-log entries

- <iso> cycle 1 persona: <id> (diff fingerprint: <reason>)
- <iso> cycle 1 findings: <B> blocker, <M> major, <m> minor, <n> nit
- <iso> cycle 1→2 deltas: blocker #<id> addressed (commit <sha>)
- <iso> cycle 2 persona: <id> (kept | switched: <reason>)
- <iso> cycle 2 finding "<text>" regressed major #<id> (commit <sha>) — grounded
- <iso> cycle 3: 0 open findings (all severities) → SUCCESS
```

Standalone invocations: operator copies or discards. Autopilot: orchestrator
splices verbatim into `decisions.md`.

## Output

```
## /forge-review-green result

verdict: SUCCESS | BUDGET_EXHAUSTED | BLOCKED | STUCK
reason:  <empty | budget | loop | drift | architectural>
slug:    <branch-slug>
cycles:  <used>/<max>

per cycle (persona · counts · deltas):
  cycle 1 (<persona>): <B>b · <M>M · <m>m · <n>n   deltas: <new=N, addressed=A, regressed=R, reopened=O, persistent=P>
  cycle 2 (<persona>): …

remaining (if not SUCCESS):
  - <severity> <lens> finding-<id> — <one-line> (<status>)

### next move
<one suggestion>

state: .pr-artifacts/<slug>/forge/loop/forge-review-green-<slug>/ — edit plan.md or re-invoke max=<N>.

## decision-log entries

<append-ready slice>
```

## Next step

Converges → re-verify, then close.

- `/forge-proof --embed` — re-aggregate post-review state
- `/forge-review --embed` — embed review block
- `/forge` — close chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-review-green                              # current branch
/forge-review-green max=8                        # raise budget (default 5)
/forge-review-green --persona backend-senior     # lock for every cycle
/forge-review-green --personas backend-senior,security-paranoid
/forge-review-green --slug auth-refactor
```

`/forge` orchestrator passes `--slug` + `--max-review-cycles` + any
operator-locked persona; the decision-log tail slurps into the run's
`decisions.md`.
