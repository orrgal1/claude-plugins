# @orrgal1/frugal

Session-activatable cost optimization: a cost-routed subtask tree over native
nested subagents.

`/frugal` switches the session into frugal mode — the main loop (expensive
model) keeps decomposition, synthesis, and verification; every well-bounded
subtask is dispatched to the cheapest **one-shot-confident** model + effort
combo:

- **Model** is passed per-invocation on the Agent tool (`haiku` / `sonnet` /
  `opus` / `fable` — the top two are escalation tiers, never defaults).
- **Effort** is pinned by four generic worker definitions: `worker-low`,
  `worker-medium`, `worker-high`, `worker-xhigh`.

Workers carry the protocol in their own definitions, so it propagates through
recursion (depth cap default 3, native hard max 5): task envelope in, raw
`STATUS:`-prefixed result out, every spawn appended to a per-run JSONL ledger
(`.claude/frugal/<run>/ledger.jsonl`, gitignored), child output verified with a
one-tier escalation ladder.

Triage is deliberately conservative — under-resourcing costs more than it saves:
the expensive orchestrator pays to re-read, re-spec, and re-dispatch a cheap
tier's failure, and an undetected bad result poisons downstream nodes. So
downgrading below sonnet requires a **closed spec** plus a **cheap mechanical
verification**; unsure picks the higher tier; one retry exactly one tier up; two
failures pull the task back into the main loop as a spec problem; a tier that
failed a task class is not retried for similar tasks in the same run.

`/frugal-stats` renders the ledger: subtask tree, tokens by model, estimated
cost vs an all-main-model baseline, and a per-tier failure-rate calibration line
(>10% at a tier = triage too aggressive). Estimates only — authoritative spend
is `/cost` and `/usage`.

## Enforcement

Skill text alone is persuasion — it decays over long sessions and dies in
compaction. Two hooks, both gated on `.claude/frugal/active` (written by
`/frugal`, removed by `--off`, inert otherwise):

- **UserPromptSubmit** — re-injects a terse mode reminder (triage table gist,
  cap, ledger path) every turn while active.
- **PreToolUse** (Edit/Write/NotebookEdit) — soft "delegate instead?" nudge,
  rate-limited to one per 5 minutes, never blocks.

Hooks load at session start — installing/upgrading the plugin mid-session needs
a restart before they arm.

## Components

| Component                  | Role                                                |
| -------------------------- | --------------------------------------------------- |
| `skills/frugal`            | Activate/deactivate the mode; routing table; ledger |
| `skills/frugal-stats`      | Ledger → tree + cost/savings report                 |
| `agents/worker-low..xhigh` | Generic workers, one per effort tier                |
| `hooks/`                   | Enforcement: per-turn reminder + edit-time nudge    |

## Caveats

- Nested subagent spawning is a recent, experimental Claude Code capability
  (depth-capped at 5). If unavailable, the mode degrades to flat depth-1
  delegation — still most of the savings.
- Agent `effort` frontmatter verified honored at the wire level (Claude Code
  2.1.173, via request capture) for both project-level and plugin-shipped agents
  — `effort: low` also disables thinking on the worker. Haiku takes no effort
  parameter at all. If a future runtime regresses this, routing still works on
  model alone.
- Never set `CLAUDE_CODE_SUBAGENT_MODEL` while active — it overrides every
  per-invocation model choice.
- Pricing table in `/frugal-stats` is a point-in-time snapshot; update on
  pricing changes.

No dependency on other plugins.
