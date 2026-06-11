---
name: frugal-stats
description:
  "Report a frugal run's subtask tree and estimated cost/savings from its
  ledger."
argument-hint: "[--run <dir>]"
triggers:
  - "how much did frugal mode save"
  - "frugal report"
  - "show the subtask ledger"
  - "cost breakdown of this frugal run"
allowed-tools:
  - Bash
  - Read
  - Glob
user-invocable: true
---

# /frugal-stats — ledger report

Read-only. Aggregates one frugal run's ledger into a tree + cost estimate.

## Locate the ledger

`--run <dir>` if given; else the newest `.claude/frugal/*/ledger.jsonl` under
the project root. No ledger → say so and stop.

## Aggregate

Use `jq`/`awk` over the JSONL — don't do arithmetic in your head:

1. Per node: id, model, effort, status, tokens.
2. Totals: nodes by status; tokens grouped by model.
3. Estimated cost per model — blended $/MTok (assumes ~80% input / 20% output;
   `tokens` is the aggregate `subagent_tokens` figure, unsplit):

   | Model  | Input $/M | Output $/M | Blended $/M |
   | ------ | --------- | ---------- | ----------- |
   | haiku  | 1.00      | 5.00       | 1.80        |
   | sonnet | 3.00      | 15.00      | 5.40        |
   | opus   | 5.00      | 25.00      | 9.00        |
   | fable  | 10.00     | 50.00      | 18.00       |

   Update the table when pricing changes; it is a point-in-time snapshot.

4. Baseline = all delegated tokens priced at the **main model's** blended rate
   (highest listed tier if the main model has no listed price). Estimated saved
   = baseline − estimated actual. A fable baseline is conservative — fable's
   tokenizer counts ~30% more tokens for the same content, so true savings run
   higher than estimated.
5. Calibration: failure rate per tier — (failed+partial)/nodes per model. Over
   ~10% at a tier means the run's triage was too aggressive for that task class;
   recommend shifting it up a tier.

## Report shape

```
FRUGAL-STATS — run: <dir>

  tree:
    0      <main>            open|closed   <task>
    0.1    sonnet/medium     ok      12,345 tok   <task>
    0.1.1  haiku/low         ok       3,210 tok   <task>
    0.2    haiku/low         failed   1,002 tok   <task>

  totals:
    nodes: <N> (<ok>/<partial>/<failed>)
    tokens by model:   haiku <n> · sonnet <n> · opus <n> · fable <n>
    est. delegated cost:  $<x.xx>
    est. all-<main> cost: $<y.yy>
    est. saved:           $<z.zz>  (~<pct>%)
    calibration:          haiku <f>/<n> · sonnet <f>/<n> — ok | too aggressive at <tier>

  caveats: estimates only — blended-rate assumption, no cache discounts,
  excludes main-loop tokens. Authoritative spend: /cost and /usage.
```

## Honesty

- Never present the estimate as actual billing.
- `failed`/`partial` nodes count toward cost — wasted spend is part of the
  report, not hidden.
- Main-loop (orchestrator) tokens are not in the ledger; say so rather than
  implying total session cost.
