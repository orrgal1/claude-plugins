---
name: stuck-check
description: "Detect if an iterate-to-green loop is stuck in a rabbit hole."
argument-hint: "[--signal <name>] [--iter <N>] [--json]"
triggers:
  - "am i stuck in this loop"
  - "is this loop a rabbit hole"
  - "loop not making progress"
  - "rabbit hole check"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
user-invocable: true
---

# /stuck-check — in-loop rabbit-hole detector

Read-only. Answers one question for any iterate-to-green loop: "am I making
progress, or stuck?"

Call it when a loop signal trips. It scores the stuck state and returns a
verdict + one concrete action:

```
loop iteration N → signal trips → /stuck-check
  → none      → continue at current threshold
  → suspected → bump threshold once, continue
  → confirmed → halt STUCK with named reason
```

## Inputs

The loop owns its own counters and scratchpad; pass what you have.

| Input      | Default                              |
| ---------- | ------------------------------------ |
| `--signal` | strongest tripped signal in counters |
| `--iter`   | current iteration number             |
| `--json`   | off                                  |

## Signals (caller owns counters)

Generic signals any iterate-to-green loop accumulates. Soft trip → continue +
log. Hard trip → call this skill.

| Signal                              | Hard  | Soft | Most-likely reason            |
| ----------------------------------- | ----- | ---- | ----------------------------- |
| same failure signature repeats      | ≥3    | 2    | wrong-assumption              |
| same file edited, result flat       | ≥4    | 3    | oscillation / missing-context |
| diff grew, pass-count flat          | trend | —    | bloat / wrong-assumption      |
| no recorded learning across iters   | ≥3    | 2    | spinning / missing-context    |
| search churn, no new files touched  | trend | —    | dead-end / missing-context    |
| decisions logged, no behavior moved | trend | —    | over-deciding / unclear-goal  |

## Process

1. Read cheap loop state — recent scratchpad/log tail, `git log --oneline` and
   `git diff --stat` since the loop began, plus passed-in counters. No
   file-by-file analysis.
2. Score 0-3 per root cause:

   | Root cause         | Evidence                                                     |
   | ------------------ | ------------------------------------------------------------ |
   | `missing-context`  | search churn, re-reads, no learning recorded, named unknown  |
   | `wrong-assumption` | failure signature unchanged, same file edited, "should be X" |
   | `unclear-goal`     | target ambiguous, decisions oscillating between readings     |
   | `un-solveworthy`   | iter budget >50% spent, diff growing, no result movement     |
   | `out-of-scope`     | edits don't overlap the failing thing                        |

   Top score with margin ≥1 → name it. Tie → `ambiguous`.

3. Verdict:
   - `confirmed` — top score ≥2, margin ≥1, AND a hard signal tripped.
   - `suspected` — top score ≥2 OR a soft signal tripped; no hard signal.
   - `none` — top ≤1 across all (likely benign).
   - `ambiguous` → `suspected` with reason `ambiguous`.

4. Action:

   | Verdict     | Caller action                                       |
   | ----------- | --------------------------------------------------- |
   | `confirmed` | halt `STUCK` — surface the named reason + next step |
   | `suspected` | continue + raise tripped signal's threshold by +1   |
   | `none`      | continue at current threshold                       |

5. Emit report.

## Report shape

Human (default):

```
STUCK-CHECK — iter: <N>

  triggered by: <signal>  (hard | soft)

  scores:
    missing-context:   <0-3>  <one-line evidence>
    wrong-assumption:  <0-3>  <one-line evidence>
    unclear-goal:      <0-3>  <one-line evidence>
    un-solveworthy:    <0-3>  <one-line evidence>
    out-of-scope:      <0-3>  <one-line evidence>

  verdict:  <none | suspected | confirmed>
  reason:   <top category | ambiguous>
  named:    <one-line specific finding>

  recommendation:
    action:  <continue | continue-raise-threshold | halt-STUCK>
    next:    <one-line caller action>
```

JSON (`--json`):

```json
{
  "iter": 7,
  "triggered_by": { "signal": "same-failure-signature", "severity": "hard" },
  "scores": {
    "missing_context": 1,
    "wrong_assumption": 3,
    "unclear_goal": 1,
    "un_solveworthy": 0,
    "out_of_scope": 0
  },
  "verdict": "confirmed",
  "reason": "wrong-assumption",
  "named": "assuming X handles Y; failure suggests X never receives Y",
  "recommendation": { "action": "halt-STUCK", "next": "<one-line>" }
}
```

## Honesty

- `named` must be one concrete line. Vague "something off" → lower the verdict.
- Soft signals never `confirmed`. Confirming requires a hard trip + score ≥2.
- High counters without a category fit = `none`. A long loop ≠ stuck.
- Stay cheap — tail / log / one `--stat`. No deep reads.

## Exit codes

| Code | Meaning                  |
| ---- | ------------------------ |
| 0    | `verdict = none`         |
| 1    | `verdict = suspected`    |
| 2    | `verdict = confirmed`    |
| 64   | unrecoverable read error |
