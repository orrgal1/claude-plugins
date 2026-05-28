---
name: forge-triage
description: "Classify a failing test — in/out of scope, type, fixable, ignore."
argument-hint: "[--slug <name>] [--failing <list>] [--pr <number>] [--json]"
triggers:
  - "forge triage"
  - "triage failing tests"
  - "what kind of failure is this"
  - "is this in scope"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-triage — classify failures before drilling

Pre-flight gate. Read-only. Asks "what kind of failure is this?" so patch loops
(`/forge-ci-green`, `/forge-impl-green`, `/forge-review-green`) don't drill on
out-of-scope, deferred, flaky, or infra failures.

```
failing list → 5 cheap checks → per-item verdict + resolution
  REAL_BUG | OUT_OF_PR_SCOPE | STACK_DEFERRED_<ref>
  FLAKE_SUSPECT | INFRA_FAILURE | AMBIGUOUS
```

PRs are rarely standalone — always scan for sibling-PR signals.

## Inputs

| Input       | Default                                                       |
| ----------- | ------------------------------------------------------------- |
| `--slug`    | sanitized branch name                                         |
| `--failing` | scrape from `gh pr checks` / `run.json` / latest `cycle-*.md` |
| `--pr`      | auto-detect via `gh pr view`                                  |
| `--base`    | from `gh pr view --json baseRefName`                          |
| `--json`    | off                                                           |

No PR → bail `NO_PR`.

## Process

### 1. Resolve slug + PR + failing list

Failing list sources (cheapest first):

| Source                                | Use for                               |
| ------------------------------------- | ------------------------------------- |
| `gh pr checks <num>` FAILURE-filtered | CI checks (ci-green caller)           |
| `.pr-artifacts/<slug>/forge/run.json` | linked tests with `result != pass`    |
| latest `cycle-*.md` blockers + majors | review findings (review-green caller) |

### 2. Five checks per item

All cheap reads. Verdict is a join — no single signal is sufficient.

**2a. Diff overlap.** `git diff --name-only <base>..HEAD` →
`overlap = none | imports-only | file-touched | symbol-touched`.

**2b. Pass/fail signature.**

| Pattern                                   | Likely                         |
| ----------------------------------------- | ------------------------------ |
| Compile error before any test runs        | `REAL_BUG` (compile)           |
| All tests in package fail, others pass    | `INFRA_FAILURE` (pkg-level)    |
| Subset fail along clean feature axis      | `STACK_DEFERRED_<hint>`        |
| Random subset, no axis                    | `FLAKE_SUSPECT`                |
| Same single test fails across many checks | `REAL_BUG`                     |
| All fail with same error string           | `REAL_BUG` (shared root cause) |

**2c. Stack-scope scan.** Heuristic — no pinned format. Sources: `CLAUDE.md`
(repo + project), top-level docs, `gh pr list --state open` of related branches,
`git log --oneline -50` on base, prior decisions. Failing symbol/feature named
in a sibling PR → `stack_hint = <PR-ref>`. Else `none`.

**2d. Memory consult.** If claude-mem available: `mem-search <failing-symbol>`

- `<feature-keyword>` (60d, top 5). Quote ⚖️ / 🔵 observations. Skip silently if
  unavailable (`mem_available: false`).

**2e. Contract proximity.** Read `links.json`. Failing test in `links.json` →
`contract: true`. Strongly biases against `OUT_OF_PR_SCOPE` /
`STACK_DEFERRED_*`.

### 3. Verdict per item

| Signals                                                             | Verdict                           |
| ------------------------------------------------------------------- | --------------------------------- |
| overlap=none + contract=false + stack_hint=<PR> + signature=feature | `STACK_DEFERRED_<PR>`             |
| overlap=none + contract=false + stack_hint=none + signature=feature | `OUT_OF_PR_SCOPE`                 |
| overlap=imports-only + contract=false + memory hit                  | `OUT_OF_PR_SCOPE` (memory-backed) |
| overlap=none + contract=true                                        | `REAL_BUG` (contract regressed)   |
| signature=compile + overlap=symbol-touched                          | `REAL_BUG`                        |
| signature=random + overlap=none                                     | `FLAKE_SUSPECT`                   |
| signature=pkg-level + overlap=any                                   | `INFRA_FAILURE`                   |
| overlap=symbol-touched + signature=clean                            | `REAL_BUG`                        |
| Multiple verdicts tied                                              | `AMBIGUOUS`                       |

### 4. Resolution per verdict

| Verdict               | Resolution                                                                                         |
| --------------------- | -------------------------------------------------------------------------------------------------- |
| `REAL_BUG`            | enter caller's patch loop                                                                          |
| `OUT_OF_PR_SCOPE`     | propose language-appropriate skip (`t.Skip`, `@pytest.mark.skip`, `.skip()`, `xfail`); cite reason |
| `STACK_DEFERRED_<PR>` | same; cite the named sibling PR as the restorer in the skip comment                                |
| `FLAKE_SUSPECT`       | halt loop; flag as flaky for separate diagnosis (not a fix-loop target)                            |
| `INFRA_FAILURE`       | halt loop; surface to operator                                                                     |
| `AMBIGUOUS`           | float to operator with the full triage table; do not guess                                         |

**Triage proposes; caller applies.** Contract guard wins — a recommended skip on
a contract test (`contract: true`) is refused.

## Report shape

Human (default):

```
FORGE TRIAGE — <slug>  pr: #<num>  base: <base>  failing: <N>

  item:       <test or check name>
  diff:       <none | imports-only | file-touched | symbol-touched>
  signature:  <compile | runtime-all | runtime-subset:<axis> | random | shared-error>
  stack hint: <PR-ref | none>
  memory:     <hit count> (<top observation>)
  contract:   <true | false>
  verdict:    <REAL_BUG | OUT_OF_PR_SCOPE | STACK_DEFERRED_<ref> | FLAKE_SUSPECT | INFRA_FAILURE | AMBIGUOUS>
  resolution: <one-line>

  summary:
    REAL_BUG: <n>  STACK_DEFERRED: <n>  OUT_OF_PR_SCOPE: <n>
    FLAKE_SUSPECT: <n>  INFRA_FAILURE: <n>  AMBIGUOUS: <n>

  recommendation: PROCEED | PROCEED_WITH_SKIPS | HALT_TRIAGE
```

JSON (`--json`) mirrors structure with one entry per failing item.

## Hook from caller skills

Call before iteration when failing set ≥2 OR operator hasn't classified. Branch
on `summary.recommendation`:

- `PROCEED` → enter loop on all items.
- `PROCEED_WITH_SKIPS` → apply recommended skips under contract guard, commit
  (`<skill>: defer <SG/test> per /forge-triage (<verdict>)`), enter loop on
  `REAL_BUG` subset.
- `HALT_TRIAGE` → halt with verdict reason (`BLOCKED_FLAKY`, `BLOCKED_INFRA`,
  `NEEDS_OPERATOR` reason `triage-ambiguous`).

## Honesty

- Never invent a stack hint. Empty grep → `stack_hint = none`.
- Contract tests cannot be `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_*`. That's drift.
- `AMBIGUOUS` is a valid verdict — float, don't guess.
- Memory miss ≠ signal. Other signals decide.
- Stay cheap — 5 probes + one optional mem-search + one PR query. No deep reads.

## Next step

- `PROCEED` → caller enters patch loop.
- `PROCEED_WITH_SKIPS` → caller applies skips, then loops on `REAL_BUG`.
- `HALT_TRIAGE` → caller halts with verdict reason.
- `/forge-status` — confirm chain state after skips.

## Usage

```
/forge-triage                                  # current branch + failing checks
/forge-triage --failing "TestFoo,TestBar"      # explicit list
/forge-triage --pr 21383                       # explicit PR
/forge-triage --json                           # machine-readable
```

## Exit codes

| Code | Meaning                                  |
| ---- | ---------------------------------------- |
| 0    | `recommendation = PROCEED`               |
| 1    | `recommendation = PROCEED_WITH_SKIPS`    |
| 2    | `recommendation = HALT_TRIAGE`           |
| 64   | unrecoverable read error (no PR, no git) |
