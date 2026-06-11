---
name: frugal
description:
  "Activate frugal mode — decompose work into small self-contained subtasks and
  delegate each to the cheapest adequate model+effort worker, tracked in a
  per-run ledger."
argument-hint: "[--cap <N>] [--off]"
triggers:
  - "optimize costs this session"
  - "frugal mode"
  - "cost mode"
  - "delegate to cheaper models"
  - "save tokens by delegating"
user-invocable: true
---

# /frugal — cost-routed subtask tree

Switches the session into frugal mode: the main loop (expensive model) keeps
orchestration, decomposition, synthesis, and final verification; every
well-bounded subtask runs on the cheapest adequate model+effort combo via this
plugin's worker agents. Every spawn lands in a ledger; `/frugal-stats` turns it
into a cost report.

`--off` (or the user asking to stop): deactivate — stop delegating, mark the
root ledger entry `closed`, suggest `/frugal-stats`.

## Activation

1. Create the run dir + ledger:
   - `RUN=.claude/frugal/$(date -u +%Y%m%dT%H%M%SZ)` under the project root;
     `mkdir -p "$RUN"`; ledger is `$RUN/ledger.jsonl`.
   - If the project versions `.claude/`, ensure `.claude/frugal/` is gitignored
     (append to `.gitignore` if missing).
   - Append the root line:
     `{"id":"0","parent":null,"model":"<main model>","effort":"<session effort>","task":"<user's goal, ≤80 chars>","status":"open","ts":"<UTC ISO-8601>"}`
2. Announce: frugal mode on, depth cap (default **3**, `--cap` overrides, hard
   max 5 — the native nesting limit), ledger path.

## While active

For each unit of work, triage before doing it inline:

| Subtask class                                                                                                                 | Dispatch                                                |
| ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| Locate/read/summarize code, grep sweeps, log triage, formatting, boilerplate from exact spec                                  | `worker-low` + `haiku`                                  |
| Bounded single-file edits, tests from a clear scenario, doc updates, simple scripts                                           | `worker-low`/`worker-medium` + `sonnet`                 |
| Multi-file bounded feature slices, debugging with a clear repro, crisp-boundary refactors                                     | `worker-high` + `sonnet`                                |
| Rare: genuinely hard bounded subtask that should still stay out of main context                                               | `worker-xhigh` + `sonnet`, `opus` only if sonnet failed |
| Decomposition, ambiguous design, cross-cutting decisions, user interaction, destructive/irreversible actions, final synthesis | **main loop — never delegated**                         |

Stay inline also when delegation overhead beats the work itself: a single tool
call (one Read, one quick Edit, one short command) is cheaper done directly than
wrapped in an envelope.

### Dispatch mechanics

- Agent tool, `subagent_type` = this plugin's worker (as namespaced in the
  available agent types), `model` passed explicitly every time.
- Independent subtasks go out in parallel — one message, multiple Agent calls.
- Workers start with **zero conversation context**. Envelopes must be
  self-contained: absolute paths, inline excerpts for anything the worker can't
  re-derive from the repo, explicit output spec.

Envelope template (the workers parse this):

```
FRUGAL TASK
node: <child id — children of root are 0.1, 0.2, …; grandchildren 0.1.1, …>
depth: 1/<cap>
ledger: <absolute ledger path>
task: <self-contained work description>
output: <expected shape of the worker's final message>
context: <inline excerpts / file paths>
```

### After each worker returns

1. **Verify** the output against its `output` spec — a worker's `STATUS: ok` is
   a claim, not proof. Failed verification → retry once, one model tier up
   (haiku→sonnet→opus). A second failure → do it in the main loop; never loop at
   the same tier.
2. **Ledger** — append one line using the tool result's usage block:
   `{"id":"0.3","parent":"0","model":"sonnet","effort":"medium","task":"<≤80 chars>","status":"ok|partial|failed","tokens":<subagent_tokens>,"duration_ms":<n>,"ts":"<UTC ISO-8601>"}`

## Guardrails

- **Never set `CLAUDE_CODE_SUBAGENT_MODEL`** while frugal mode is active — it
  silently overrides every per-invocation model choice.
- Don't downgrade correctness-critical judgment: anything whose failure is
  expensive to detect stays at sonnet-or-better with verification, or in the
  main loop.
- Nested spawning is a recent native capability (depth-capped). If a worker
  reports it cannot spawn, continue flat — depth-1 delegation still captures
  most of the savings.
- Workers run at their pinned effort via frontmatter; if the runtime ignores
  agent `effort` frontmatter, routing still works on model alone — note it in
  the ledger run if observed.

## Honesty

- The ledger records what was _attempted_, including `failed` nodes — never drop
  a line because the subtask flopped.
- Savings claims belong to `/frugal-stats`, and they are estimates; the
  authoritative spend is `/cost` and `/usage`.
