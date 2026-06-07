---
name: forge-verify-runs
description: "Verify linked scenario tests pass."
argument-hint: "[--slug <name>] [--json]"
triggers:
  - "forge verify runs"
  - "do linked tests pass"
  - "verify linked tests green"
  - "prove run.json"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
practices:
  - code-review
  - tdd
user-invocable: true
---

# /forge-verify-runs — linked tests pass

Final layer of the attestation chain. Static read of
`$FORGE_ART/branches/<slug>/run.json` (written by `/forge-impl-green`). Confirms
every linked test was `pass` (or `skipped`) on the last run. Never executes the
suite — for a live run, call `/forge-impl-green --watch` first.

## Inputs

| Input    | Format          | Default               |
| -------- | --------------- | --------------------- |
| `--slug` | `--slug <name>` | sanitized branch name |
| `--json` | flag            | off (console report)  |

Prereqs: `$FORGE_ART/branches/<slug>/run.json` exists. Missing → exit 2 with
`BLOCKED_NO_RUN`.

## The check

For each LINKED `SG<n>.<m>` in `goals.md`, look up its result in `run.json`:

| Verdict      | Meaning                                                                                                 |
| ------------ | ------------------------------------------------------------------------------------------------------- |
| **PASS**     | `run.json` has a result for this SG; status is `pass` or `skipped`.                                     |
| **FAIL**     | `run.json` has a result; status is `fail`.                                                              |
| **ERROR**    | `run.json` has a result; status is `error` (compile error, fixture issue, runner crash — wrong reason). |
| **MISSING**  | Scenario is LINKED in `goals.md` but absent from `run.json` — `/forge-impl-green` hasn't seen it.       |
| **STALE**    | `run.json` mtime is older than the linked test file's mtime — last run does not reflect current code.   |
| **DANGLING** | `run.json` has a result for an SG no longer in `goals.md`.                                              |

`SKIPPED` = PASS for the chain verdict — operator explicitly opted the scenario
out at runtime (e.g. environment-gated). Surface the count.

## Process

Per LINKED scenario in `goals.md`, look up its result in `run.json` and apply
the verdict table. STALE compares `run.json` mtime against each linked test
file's mtime; DANGLING is a `run.json` entry with no matching scenario.

## Report shape

```
# /forge-verify-runs result

verdict: PASS | FAIL
slug: <branch-slug>
artifact: $FORGE_ART/branches/<slug>/run.json
run timestamp: <iso>

## per-scenario result

| SG    | verdict | last result              |
| ----- | ------- | ------------------------ |
| SG1.1 | PASS    | pass                     |
| SG1.2 | FAIL    | fail (1 assertion)       |
| SG2.1 | ERROR   | compile error            |
| SG3.1 | MISSING | not in run.json          |
| SG4.2 | STALE   | pkg/x/x_test.go newer    |

## summary

passed: <N>   failed: <N>   errored: <N>   skipped: <N>   missing: <N>   stale: <N>   dangling: <N>

## next move

<one concrete suggestion: run /forge-impl-green to refresh run.json; debug SG1.2 failure; …>
```

## --json shape

```json
{
  "verdict": "PASS" | "FAIL",
  "slug": "<slug>",
  "run_timestamp": "<iso>",
  "scenarios": [
    {"id": "SG1.1", "verdict": "PASS", "status": "pass"},
    {"id": "SG1.2", "verdict": "FAIL", "status": "fail", "last_line": "1 assertion"}
  ],
  "summary": {"passed": 5, "failed": 1, "errored": 0, "skipped": 0, "missing": 0, "stale": 0, "dangling": 0},
  "next_move": "debug SG1.2 failure"
}
```

## Verdict logic

- **PASS** — every LINKED scenario is `PASS` (or `SKIPPED`). Zero `FAIL`,
  `ERROR`, `MISSING`, `STALE`, `DANGLING`.
- **FAIL** — any of the above.

## Exit codes

- `0` — PASS
- `1` — FAIL
- `2` — prereq missing (`BLOCKED_NO_RUN`)

## Next step

PASS → chain attested:

- `/forge-proof` — re-aggregate, with `--embed` write the report into the PR
  body
- `/forge-status` — confirm chain state, check drift
- `/forge` — close the chain if PR is ready (CI-green + review-green still
  required separately)

FAIL → fix per finding, re-run:

- `/forge-impl-green` — refresh STALE `run.json`; drive FAIL / ERROR scenarios
  green
- `/forge-impl-green --watch` — confirm green without changing impl
- `/forge-tests --refresh SG<n>.<m>` — drop DANGLING entries by realigning the
  cache to current `goals.md`

## Usage

```
/forge-verify-runs                          # current branch
/forge-verify-runs --slug auth-refactor     # explicit slug
/forge-verify-runs --json                   # machine-readable
```
