---
id: scenario-realism
name: Scenario Realism
tags: [chain-semantic, scenarios, forge]
requires: forge-chain
severity-floor: major
brief-artifacts: [goals.md]
introduced-by: forge-review
---

# Scenario Realism

Each scenario in `goals.md` must cover a real way the goal could fail or
succeed, not just be textually adjacent to it.

- For each `## G\d+` block, walk the `- SG\d+\.\d+` entries.
- For each SG, read its `when:` / `then:` lines. Does it exercise a meaningful
  path to the goal, or restate it?
- Pattern smells:
  - `then:` line paraphrases the goal header.
  - `when:` too narrow ("when user clicks button X with arg Y" →
    integration-test detail, not a goal-shaped scenario).
  - Scenario set leaves an obvious failure mode uncovered (happy path + one
    error path, but the goal implies three error paths).
- **Toothless scenario → major** (scenario exists, fails to cover). Coverage gap
  (named in synthesis as "scenarios miss <axis>") → major.

The brief includes `goals.md` verbatim — the agent needs goal headers +
scenarios under them together.
