---
name: forge-stuck-check
description: "Detect if the forge chain is looping in a rabbit hole."
argument-hint:
  "[--slug <name>] [--phase <phase>] [--signal <name>] [--iter <N>] [--json]"
triggers:
  - "forge stuck check"
  - "am i stuck"
  - "am i in a rabbit hole"
  - "rabbit hole check"
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

# /forge-stuck-check — in-loop rabbit-hole detector

Read-only, in-loop: "am I making progress, or stuck?"

Called when a Layer 1 signal trips inside a patch loop. Classifies the stuck
state, recommends halt vs continue. Verdict flow:

```
loop iteration N → Layer 1 hard signal → /forge-stuck-check
  → none      → continue at current threshold
  → suspected → bump threshold once, continue, log
  → confirmed → halt STUCK with named reason
```

## Inputs

| Input      | Default                              |
| ---------- | ------------------------------------ |
| `--slug`   | sanitized branch name                |
| `--phase`  | infer from `decisions.md` tail       |
| `--signal` | strongest tripped signal in counters |
| `--iter`   | infer from receipt / loop scratchpad |
| `--json`   | off                                  |

Phase values: `impl` | `ci-green` | `proof` | `temper` | `review`.

## Layer 1 signal table (caller owns counters)

| Signal                              | Hard        | Soft   | Most-likely reason                    |
| ----------------------------------- | ----------- | ------ | ------------------------------------- |
| same scenario, pass-count flat      | ≥3          | 2      | wrong-assumption / unclear-goal       |
| same error string                   | ≥3          | 2      | wrong-assumption                      |
| same file edited per phase          | ≥4          | 3      | oscillation / missing-context         |
| diff bytes grow, pass-count flat    | trend       | —      | impl bloat / wrong-assumption         |
| test/contract edit refused by guard | ≥1          | —      | contract-drift attempt / out-of-scope |
| decisions-log entries in phase      | > 2× median | > 1.5× | over-deciding / unclear-goal          |
| re-read same file mid-iter          | ≥2          | —      | context-confusion                     |
| search queries grow, new files = 0  | trend       | —      | dead-end / missing-context            |
| CI fails same check, fresh push     | ≥3          | 2      | wrong-cause / out-of-scope            |
| subagent same blocker, retry        | ≥2          | —      | spinning                              |

Soft trip → continue + log. Hard trip → call this skill.

## Process

1. Resolve slug, phase, iter (args or scan `decisions.md` tail + loop state).
2. Read cheap context — `decisions.md` tail, `git log --oneline` since phase
   start, `git diff --stat`, last subagent receipt, `run.json`, latest cycle
   file. No file-by-file analysis.
3. Score 0-3 per root cause:

   | Root cause         | Evidence                                                         |
   | ------------------ | ---------------------------------------------------------------- |
   | `missing-context`  | search churn, re-reads, decisions churn, named unknown           |
   | `wrong-assumption` | error string unchanged, same file edited, "should be X" pattern  |
   | `unclear-goal`     | `then:` ambiguous, decisions oscillating between interpretations |
   | `un-solveworthy`   | iter budget >50%, file count growing, no test movement           |
   | `out-of-scope`     | diff overlap with failing test = none, sibling-PR hint           |

   Top score with margin ≥1 → name it. Tie → `ambiguous`.

4. Verdict:
   - `confirmed` — top score ≥2, margin ≥1, AND hard signal tripped.
   - `suspected` — top score ≥2 OR soft signal tripped; no hard signal.
   - `none` — top ≤1 across all (likely benign).
   - `ambiguous` → `suspected` with reason `ambiguous`.

5. Action map:

   | Verdict + reason                 | Caller action                                                   |
   | -------------------------------- | --------------------------------------------------------------- |
   | `confirmed` + `missing-context`  | halt `STUCK` — surface the named unknown                        |
   | `confirmed` + `wrong-assumption` | halt `STUCK` — name assumption + cheap verification             |
   | `confirmed` + `unclear-goal`     | halt `STUCK` — route to `/forge-goals` or `/forge-scenarios`    |
   | `confirmed` + `un-solveworthy`   | halt `STUCK` — propose scenario drop / defer                    |
   | `confirmed` + `out-of-scope`     | halt `STUCK` — propose skipping/deferring the out-of-scope item |
   | `suspected` + any                | continue + raise tripped signal's threshold by +1 + log         |
   | `none`                           | continue at current threshold                                   |

6. Emit report.

## Report shape

Human (default):

```
FORGE STUCK-CHECK — <slug>  phase: <phase>  iter: <N>

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
  "slug": "<slug>",
  "phase": "<phase>",
  "iter": 7,
  "triggered_by": { "signal": "same-error-string", "severity": "hard" },
  "scores": {
    "missing_context": 1,
    "wrong_assumption": 3,
    "unclear_goal": 1,
    "un_solveworthy": 0,
    "out_of_scope": 0
  },
  "verdict": "confirmed",
  "reason": "wrong-assumption",
  "named": "assuming X handles Y; error string suggests X never receives Y",
  "recommendation": { "action": "halt-STUCK", "next": "<one-line>" }
}
```

## Honesty

- `named` must be one concrete line. Vague "something off" → lower verdict.
- Soft signals never `confirmed`. Confirming requires hard trip + score ≥2.
- High counters without category fit = `none`. Long loop ≠ stuck.
- Stay cheap — tail / log / one `--stat` / one receipt. No deep reads.

## Hook from autopilot

Autopilot doesn't call this directly; the patch loop owns counters. Runner
receipts with `verdict: confirmed` bubble up as `STUCK` halts. In
Bias-to-progress: `suspected` ≠ halt; `confirmed` halts with the named reason.
After a halt + operator action, `/forge-status` re-assesses.

## Usage

```
/forge-stuck-check                                       # infer phase + signal
/forge-stuck-check --phase impl --signal same-error      # explicit
/forge-stuck-check --json                                # machine-readable
```

## Exit codes

| Code | Meaning                  |
| ---- | ------------------------ |
| 0    | `verdict = none`         |
| 1    | `verdict = suspected`    |
| 2    | `verdict = confirmed`    |
| 64   | unrecoverable read error |
