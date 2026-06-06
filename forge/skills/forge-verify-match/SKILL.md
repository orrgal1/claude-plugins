---
name: forge-verify-match
description: "Verify test bodies match their scenario when/then + AAA."
argument-hint: "[--slug <name>] [--json]"
triggers:
  - "forge verify match"
  - "do tests match scenarios"
  - "prove when then match"
  - "verify test bodies loyal to when then"
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

# /forge-verify-match — test bodies loyal to when / then

Layer 4 of the attestation chain. For each LINKED scenario, read the full
triangle — scenario text in `goals.md`, `when:` / `then:` comments above the
function, AAA markers + code in the body — and confirm they tie together.

## Inputs

| Input    | Format          | Default               |
| -------- | --------------- | --------------------- |
| `--slug` | `--slug <name>` | sanitized branch name |
| `--json` | flag            | off (console report)  |

Prereqs: at least one LINKED scenario (`/forge-verify-tests` PASS-eligible).
Missing → exit 2 with `BLOCKED_NO_LINKED_TESTS`.

## The check

For each LINKED scenario:

| Verdict        | Meaning                                                                                                                                                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **MATCH**      | `when:` / `then:` comments above the test match the scenario text. AAA markers (`arrange:` / `act:` / `assert:`) present in the body. The `assert:` phase realizes `then:`'s outcome; `arrange:` + `act:` set up the `when:` scenario. |
| **DRIFT**      | Comments match in spirit but a named entity is stale (refactor leftover).                                                                                                                                                              |
| **MISMATCH**   | Comments differ materially from the scenario, OR the AAA body clearly doesn't realize the comments — e.g. `assert:` checks an unrelated surface, `arrange:` sets up a different scenario than `when:` names.                           |
| **NO-COMMENT** | Referenced test exists but carries no `when:` / `then:` comments — re-run `/forge-tests` to annotate.                                                                                                                                  |
| **NO-AAA**     | Referenced test has `when:` / `then:` but lacks AAA markers in the body — body structure can't be proven against the scenario. Re-run `/forge-tests` to annotate.                                                                     |

Test code does **not** carry a `prov: SG<n>.<m>` tag — the back-link lives only
in `goals.md`, keeping committed test code free of references to uncommitted
`.pr-artifacts/` state.

## Process

1. Resolve slug (argument or branch-derived).
2. Read `.pr-artifacts/<slug>/forge/goals.md`. Enumerate LINKED scenarios per
   the linkage rules in `/forge-verify-tests`.
3. For each LINKED scenario, open the referenced test file. Read:
   - `when:` / `then:` comments above the test function (typically two adjacent
     `//` / `#` lines).
   - `// --- arrange:` / `// --- act:` / `// --- assert:` markers inside the
     body (and the code each contains).
4. Verify the triangle:
   - Comments restate the scenario without material loss.
   - `arrange:` + `act:` realize the `when:` setup.
   - `assert:` realizes the `then:` outcome.
   - All three reference the same surface the scenario names.
5. Apply verdict table per scenario. Emit report.

## Report shape

```
# /forge-verify-match result

verdict: PASS | FAIL
slug: <branch-slug>
artifact: .pr-artifacts/<slug>/forge/goals.md

## per-scenario match

| SG    | verdict  | finding                                                                  |
| ----- | -------- | ------------------------------------------------------------------------ |
| SG1.1 | MATCH    | -                                                                        |
| SG2.2 | NO-AAA   | when:/then: present; body has no arrange:/act:/assert: markers           |
| SG3.1 | MISMATCH | then: claims "emits welcome email"; assert checks log line, not the call |

## next move

<one concrete suggestion: re-run /forge-tests to annotate SG2.2; rework assert: in TestLoginSendsWelcomeEmail, …>
```

## --json shape

```json
{
  "verdict": "PASS" | "FAIL",
  "slug": "<slug>",
  "scenarios": [
    {"id": "SG1.1", "verdict": "MATCH", "finding": null},
    {"id": "SG3.1", "verdict": "MISMATCH", "finding": "then: claims 'emits welcome email'; assert checks log line, not the call"}
  ],
  "next_move": "rework assert: in TestLoginSendsWelcomeEmail"
}
```

## Verdict logic

- **PASS** — every LINKED scenario is `MATCH`. Zero `MISMATCH`, `NO-COMMENT`,
  `NO-AAA`.
- **FAIL** — any of the above.
- `DRIFT` alone does not fail the chain but surfaces as a finding.

## Exit codes

- `0` — PASS
- `1` — FAIL
- `2` — prereq missing (`BLOCKED_NO_LINKED_TESTS`)

## Next step

PASS → `/forge-verify-runs`, `/forge-proof`, `/forge-status`.

FAIL → fix per finding, re-run:

- `/forge-tests --refresh SG<n>.<m>` — re-annotate NO-COMMENT / NO-AAA tests
- `/forge-scenarios --goal G<n>` — reword scenario when MISMATCH is on the
  scenario side, not the test
- Operator edit on the test — when MISMATCH is on the test side (rework
  `assert:` to realize the documented `then:`); commit, then re-run

## Usage

```
/forge-verify-match                          # current branch
/forge-verify-match --slug auth-refactor     # explicit slug
/forge-verify-match --json                   # machine-readable
```
