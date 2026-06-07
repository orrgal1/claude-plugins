---
name: forge-verify-tests
description: "Verify each scenario is attached to a real test."
argument-hint: "[--slug <name>] [--json]"
triggers:
  - "forge verify tests"
  - "do tests cover scenarios"
  - "prove scenario linkage"
  - "verify test linkage"
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

# /forge-verify-tests — scenarios attached to real tests

Layer 3 of the attestation chain. For each `SG<n>.<m>`, confirm a real test file

- function exists and tier is component-or-higher (unit rejected).

## Inputs

| Input    | Format          | Default               |
| -------- | --------------- | --------------------- |
| `--slug` | `--slug <name>` | sanitized branch name |
| `--json` | flag            | off (console report)  |

Prereqs: `$FORGE_ART/branches/<slug>/goals.md` with ≥1 scenario. Missing → exit
2 with `BLOCKED_NO_SCENARIOS`.

## The check

For each `SG<n>.<m>` enumerated from `goals.md`, read the nested `- test:`
sub-bullet under the scenario. The path is canonically inline-coded between
backticks; strip them when resolving:

| Verdict      | Meaning                                                                                      |
| ------------ | -------------------------------------------------------------------------------------------- |
| **LINKED**   | `- test:` sub-bullet present under the scenario; `<path>` exists; `<func>` is defined in it. |
| **STALE**    | `- test:` sub-bullet present but `<path>` or `<func>` no longer exists (refactor drift).     |
| **UNLINKED** | Scenario in `goals.md` has no `- test:` sub-bullet — `/forge-tests` hasn't attached it yet.  |

Plus proof-cache side (cross-check vs `links.json` when present):

| Verdict      | Meaning                                                                                           |
| ------------ | ------------------------------------------------------------------------------------------------- |
| **DANGLING** | `links.json` entry for a scenario that's no longer in `goals.md`.                                 |
| **DESYNC**   | `links.json` and the `- test:` sub-bullet in `goals.md` disagree about `test_path` or `function`. |

`links.json` is the proof cache, not the canonical link. On disagreement
`goals.md` wins; surface as `DESYNC` and offer to re-run `/forge-tests` to
rebuild the cache.

## Tier check

Scenarios cover behavior exposable by hitting the actual service endpoint — so
the linked test must be **component** or higher (integration, e2e, blackbox).
Unit-tier tests don't exercise the endpoint surface and can't attest a scenario.

For each LINKED scenario, read the `- tier: <tier>` sub-bullet directly under
the `- test:` sub-bullet:

| Verdict          | Meaning                                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------------------- |
| **TIER-OK**      | `tier` is `component`, `integration`, `e2e`, or `blackbox`.                                                 |
| **TIER-UNIT**    | `tier: unit` — scenario is mis-tiered. FAIL.                                                                |
| **TIER-MISSING** | No `- tier:` sub-bullet. Defaults to `component` for the check, but surface as a finding to annotate.       |
| **TIER-UNKNOWN** | `tier` value is not in the allowed set (`unit \| component \| integration \| e2e \| qa \| blackbox`). FAIL. |

`tier: e2e` or `qa` without a `tier_reason` is a **WARN**, not a fail —
component is the default; operator owes a one-liner when deviating up.

## Process

Per scenario, resolve `<path>::<func>` (confirm path exists, function defined)
and apply the link + tier verdict tables. Cross-check against `links.json` when
present for DESYNC / DANGLING.

## Report shape

```
# /forge-verify-tests result

verdict: PASS | FAIL
slug: <branch-slug>
artifact: $FORGE_ART/branches/<slug>/goals.md

## scenario linkage

| SG    | verdict  | test                                                | tier      |
| ----- | -------- | --------------------------------------------------- | --------- |
| SG1.1 | LINKED   | pkg/auth/login_component_test.go:TestLogin_Rejects… | component |
| SG1.2 | UNLINKED | -                                                   | -         |
| SG2.1 | STALE    | pkg/auth/refresh_…_test.go (function not found)     | component |

## tier sanity

| SG    | tier | reason          | flag                                              |
| ----- | ---- | --------------- | ------------------------------------------------- |
| SG3.1 | e2e  | crosses bff→nf  | -                                                 |
| SG2.1 | unit | (n/a)           | FAIL: scenarios require component tier or higher  |

## links.json cross-check

dangling: <N>   desync: <N>

## next move

<one concrete suggestion: run /forge-tests for SG1.2; refresh links.json for SG2.1; re-tier SG2.1 to component, …>
```

## --json shape

```json
{
  "verdict": "PASS" | "FAIL",
  "slug": "<slug>",
  "scenarios": [
    {"id": "SG1.1", "verdict": "LINKED", "test_path": "pkg/auth/login_test.go", "function": "TestLogin_Rejects", "tier": "component", "tier_verdict": "TIER-OK"},
    {"id": "SG2.1", "verdict": "STALE", "test_path": "pkg/auth/refresh_test.go", "function": "TestRefresh", "tier": "unit", "tier_verdict": "TIER-UNIT"}
  ],
  "dangling": [],
  "desync": [],
  "next_move": "run /forge-tests for SG1.2"
}
```

## Verdict logic

- **PASS** — every scenario is `LINKED`; zero `STALE`, `UNLINKED`, `DESYNC`,
  `DANGLING`; zero `TIER-UNIT` or `TIER-UNKNOWN`.
- **FAIL** — any of the above.
- `TIER-MISSING` is a finding (annotate or default to `component`) but does not
  fail when the rest of the linkage is clean.
- `e2e` / `qa` without `tier_reason` is a WARN, not a fail.

## Exit codes

- `0` — PASS
- `1` — FAIL
- `2` — prereq missing (`BLOCKED_NO_SCENARIOS`)

## Next step

PASS → `/forge-verify-match`, `/forge-proof`, `/forge-status`.

FAIL → fix per finding, re-run:

- `/forge-tests` — attach a test for any UNLINKED scenario
- `/forge-tests --refresh SG<n>.<m>` — re-resolve STALE / DESYNC links after a
  refactor
- `/forge-tests --retier SG<n>.<m> component` — re-tier any TIER-UNIT scenario
  to component (or higher)
- `/forge-scenarios --goal G<n>` — drop / replace any DANGLING scenario from the
  proof cache

## Usage

```
/forge-verify-tests                          # current branch
/forge-verify-tests --slug auth-refactor     # explicit slug
/forge-verify-tests --json                   # machine-readable
```
