# @orrgal1/frugal

Session-activatable cost optimization: a cost-routed subtask tree over native
nested subagents.

`/frugal` switches the session into frugal mode — the main loop (expensive
model) keeps decomposition, synthesis, and verification; every well-bounded
subtask is dispatched to the cheapest adequate **model + effort** combo:

- **Model** is passed per-invocation on the Agent tool (`haiku` / `sonnet` /
  `opus`).
- **Effort** is pinned by four generic worker definitions: `worker-low`,
  `worker-medium`, `worker-high`, `worker-xhigh`.

Workers carry the protocol in their own definitions, so it propagates through
recursion (depth cap default 3, native hard max 5): task envelope in, raw
`STATUS:`-prefixed result out, every spawn appended to a per-run JSONL ledger
(`.claude/frugal/<run>/ledger.jsonl`, gitignored), child output verified with a
one-tier escalation ladder.

`/frugal-stats` renders the ledger: subtask tree, tokens by model, estimated
cost vs an all-main-model baseline. Estimates only — authoritative spend is
`/cost` and `/usage`.

## Components

| Component                  | Role                                                |
| -------------------------- | --------------------------------------------------- |
| `skills/frugal`            | Activate/deactivate the mode; routing table; ledger |
| `skills/frugal-stats`      | Ledger → tree + cost/savings report                 |
| `agents/worker-low..xhigh` | Generic workers, one per effort tier                |

## Caveats

- Nested subagent spawning is a recent, experimental Claude Code capability
  (depth-capped at 5). If unavailable, the mode degrades to flat depth-1
  delegation — still most of the savings.
- Agent `effort` frontmatter honored per current docs; if a runtime ignores it
  for plugin agents, routing still works on model alone.
- Never set `CLAUDE_CODE_SUBAGENT_MODEL` while active — it overrides every
  per-invocation model choice.
- Pricing table in `/frugal-stats` is a point-in-time snapshot; update on
  pricing changes.

No dependency on other plugins.
