---
name: forge-verify-scenarios
argument-hint: "[--slug <name>] [--json]"
triggers:
  - "forge verify scenarios"
  - "do scenarios cover goals"
  - "audit goal coverage"
  - "verify goal coverage"
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

# /forge-verify-scenarios — scenarios cover goals

Layer 2 of the attestation chain. Reads `goals.md`, emits per-goal coverage
verdict. PASS iff every `Gn` is COVERED.

## Inputs

| Input    | Format          | Default               |
| -------- | --------------- | --------------------- |
| `--slug` | `--slug <name>` | sanitized branch name |
| `--json` | flag            | off (console report)  |

Prereqs: `.pr-artifacts/<slug>/forge/goals.md` exists with ≥1 `^## G\d+ —`
header. Missing → exit 2 with `BLOCKED_NO_GOALS`.

## The check

For each `Gn` enumerated from `goals.md`:

| Verdict     | Meaning                                                                                         |
| ----------- | ----------------------------------------------------------------------------------------------- |
| **COVERED** | `## Scenarios` block present under `Gn` with ≥1 `SG<n>.<m>` entry, all endpoint-observable.     |
| **PARTIAL** | Scenarios present but ≥1 has a vague `then:` OR an internal-only `then:` (not service-surface). |
| **MISSING** | No `## Scenarios` block, or the block is empty.                                                 |

A scenario by definition covers an aspect exposable by hitting the actual
service endpoint. `then:` must name an externally-observable signal — HTTP
response, RPC result, queue message, persisted record, log line, metric, render
output. "Returns from private method X", "internal state Y becomes Z", or
"function W is called" are NOT endpoint-observable and surface as **PARTIAL**.

Plus scenario-side:

| Verdict    | Meaning                                                                                                          |
| ---------- | ---------------------------------------------------------------------------------------------------------------- |
| **ORPHAN** | Scenario lives under a goal that doesn't exist (header missing).                                                 |
| **PARKED** | Scenario lives under a `## Orphan scenarios` block (operator parked a harvested `when:` / `then:` with no goal). |

`PARKED` is **WARN**, not a fail — operator chose to keep the annotation
visible. Surface the count + scenario IDs; do not fail the chain.

## Process

1. Resolve slug (argument or branch-derived).
2. Read `.pr-artifacts/<slug>/forge/goals.md`. Missing → exit 2.
3. Enumerate `Gn` headers. For each, read its `## Scenarios` block.
4. Apply verdict table per goal.
5. Scan all `SG<n>.<m>` entries: any under a missing `Gn` → ORPHAN; any under
   `## Orphan scenarios` → PARKED.
6. Emit report.

## Report shape

```
# /forge-verify-scenarios result

verdict: PASS | FAIL
slug: <branch-slug>
artifact: .pr-artifacts/<slug>/forge/goals.md

## per-goal coverage

| Gn  | verdict   | scenarios       | note                    |
| --- | --------- | --------------- | ----------------------- |
| G1  | COVERED   | SG1.1, SG1.2    | -                       |
| G2  | PARTIAL   | SG2.1           | SG2.1 then: too generic |
| G3  | MISSING   | -               | run /forge-scenarios    |

## scenario-side

orphans: <N>   parked: <N>

## next move

<one concrete suggestion: run /forge-scenarios for G3, tighten SG2.1 then:, …>
```

## --json shape

```json
{
  "verdict": "PASS" | "FAIL",
  "slug": "<slug>",
  "goals": [
    {"id": "G1", "verdict": "COVERED", "scenarios": ["SG1.1", "SG1.2"], "note": null},
    {"id": "G2", "verdict": "PARTIAL", "scenarios": ["SG2.1"], "note": "SG2.1 then: too generic"}
  ],
  "orphans": ["SG9.1"],
  "parked": [],
  "next_move": "run /forge-scenarios for G3"
}
```

## Verdict logic

- **PASS** — every `Gn` is `COVERED`. Zero `MISSING`. Zero `ORPHAN`. (`PARTIAL`
  - `PARKED` are surfaced but do not fail.)
- **FAIL** — any `MISSING` or `ORPHAN`.

## Exit codes

- `0` — PASS
- `1` — FAIL (≥1 layer finding)
- `2` — prereq missing (`BLOCKED_NO_GOALS`)

## Next step

PASS → advance to test linkage.

- `/forge-verify-tests` — next link in the attestation chain
- `/forge-audit` — full chain verdict
- `/forge-status` — chain state + drift

FAIL → fix per finding, then re-run this skill.

- `/forge-scenarios` — draft scenarios for any MISSING goal
- `/forge-scenarios --goal G<n>` — tighten PARTIAL scenarios (vague /
  internal-only `then:`)
- `/forge-goals` — edit a goal whose ORPHAN scenarios point to a missing `Gn`
  header

## Usage

```
/forge-verify-scenarios                          # current branch
/forge-verify-scenarios --slug auth-refactor     # explicit slug
/forge-verify-scenarios --json                   # machine-readable
```
