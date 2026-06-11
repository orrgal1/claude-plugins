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

`--off` (or the user asking to stop): deactivate — remove
`.claude/frugal/active` (silences the enforcement hooks), stop delegating, mark
the root ledger entry `closed`, suggest `/frugal-stats`.

## Activation

1. Create the run dir + ledger:
   - `RUN=.claude/frugal/$(date -u +%Y%m%dT%H%M%SZ)` under the project root;
     `mkdir -p "$RUN"`; ledger is `$RUN/ledger.jsonl`.
   - If the project versions `.claude/`, ensure `.claude/frugal/` is gitignored
     (append to `.gitignore` if missing).
   - Append the root line:
     `{"id":"0","parent":null,"model":"<main model>","effort":"<session effort>","task":"<user's goal, ≤80 chars>","status":"open","ts":"<UTC ISO-8601>"}`
2. Arm the enforcement hooks — write `.claude/frugal/active` (two lines):

   ```
   RUN=<absolute run dir>
   CAP=<cap>
   ```

3. Announce: frugal mode on, depth cap (default **3**, `--cap` overrides, hard
   max 5 — the native nesting limit), ledger path.

## While active

### The routing question

For each unit of work ask: **what is the cheapest tier I am ~90% confident will
one-shot this?** — not "what might manage it." Unsure between two tiers → the
higher one. If you can't write a crisp envelope for the task, that uncertainty
IS the classification: it is not delegable downward.

Misclassification is asymmetric, and the asymmetry is not about worker tokens:

- **Over-resourcing** wastes a bounded, known amount of cheap worker tokens
  (tiers sit ~3× apart).
- **Under-resourcing** wastes orchestrator cycles — the expensive main model
  reads the failed output, re-diagnoses, re-specs, re-dispatches, and its
  context grows permanently. A failed cheap attempt costs more in main-loop
  tokens than it saved in worker tokens, and an UNDETECTED bad result poisons
  every downstream node.

Play it safe: never bet a subtask on a tier to chase savings.

### Downgrade gates

A task may run below `sonnet` + `worker-medium` ONLY if both hold:

1. **Closed spec** — the envelope's `task` + `output` can be written with zero
   judgment calls left to the worker: inputs enumerated, paths absolute, output
   shape deterministic, one obvious approach. If your draft envelope needs
   "investigate", "figure out", "as appropriate", or "clean up", the gate
   failed.
2. **Cheap mechanical verification** — there is a check for the result (test
   passes, grep count, diff shape, schema match) the dispatching side can run
   without redoing the work. Unverifiable output never goes to a cheap tier.

### Tier guide (examples — the gates are the rules)

| Tier                              | One-shot-confident for                                                                                            |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `haiku` + `worker-low`            | Enumerable lookups, reads/summaries with stated targets, format conversion, boilerplate from exact spec           |
| `sonnet` + `worker-low`/`-medium` | **Safe default for all bounded work** — few-file edits with clear acceptance, tests from a written scenario, docs |
| `sonnet` + `worker-high`          | Multi-file bounded slices, debugging with a reliable repro, crisp-boundary refactors                              |
| `opus`/`fable` + `worker-xhigh`   | Escalation destinations — almost never a first dispatch                                                           |
| main loop — never delegated       | Decomposition, ambiguous design, judgment calls, user interaction, destructive/irreversible actions, synthesis    |

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
   a claim, not proof. Verification runs mechanically or at the dispatching tier
   — never below the tier that did the work.
2. **Ledger** — append one line using the tool result's usage block:
   `{"id":"0.3","parent":"0","model":"sonnet","effort":"medium","task":"<≤80 chars>","status":"ok|partial|failed","tokens":<subagent_tokens>,"duration_ms":<n>,"ts":"<UTC ISO-8601>"}`

### Anti-spin rules

- Failed verification → retry once, exactly one tier up
  (haiku→sonnet→opus→fable). Never retry at the same tier.
- **Two failures = spec problem.** If the escalated attempt also fails, do NOT
  try a third model — pull the task into the main loop and re-examine the
  decomposition and envelope. Capability is rarely the issue twice; the spec
  usually is.
- **No re-descend.** Once a tier fails a task class in this run, route similar
  tasks one tier higher for the rest of the run. The ledger's `failed`/`partial`
  lines are your memory — consult them before classifying.
- Calibrate: if `/frugal-stats` shows >10% failed+partial at a tier, triage is
  too aggressive — shift that task class up a tier.

## Enforcement

The skill text persuades; the plugin's hooks enforce — both keyed on
`.claude/frugal/active`, inert without it:

- **UserPromptSubmit** re-injects a terse mode reminder every turn, so frugal
  behavior survives long sessions and compaction.
- **PreToolUse** (Edit/Write/NotebookEdit) emits a soft delegate-instead nudge,
  rate-limited to one per 5 minutes. It never blocks — trivial and
  never-delegate work proceeds inline; the ledger is what exposes habitual
  bypassing.

Hooks load at session start: if the plugin was installed mid-session, they arm
on the next restart — say so when activating.

## Guardrails

- **Never set `CLAUDE_CODE_SUBAGENT_MODEL`** while frugal mode is active — it
  silently overrides every per-invocation model choice.
- Don't downgrade correctness-critical judgment: anything whose failure is
  expensive to detect stays at sonnet-or-better with verification, or in the
  main loop.
- Nested spawning is a recent native capability (depth-capped). If a worker
  reports it cannot spawn, continue flat — depth-1 delegation still captures
  most of the savings.
- Workers run at their pinned effort via frontmatter — verified at the wire
  level on Claude Code 2.1.173 for plugin-shipped agents (`effort: low` also
  disables thinking; haiku takes no effort parameter). If a future runtime
  regresses this, routing still works on model alone — note it in the ledger run
  if observed.

## Honesty

- The ledger records what was _attempted_, including `failed` nodes — never drop
  a line because the subtask flopped.
- Savings claims belong to `/frugal-stats`, and they are estimates; the
  authoritative spend is `/cost` and `/usage`.
