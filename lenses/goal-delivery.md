---
id: goal-delivery
name: Goal Delivery + PR-Description Fidelity
tags: [chain-semantic, goals, forge]
requires: forge-chain
severity-floor: blocker
brief-artifacts: [goals.md, pr-description]
introduced-by: forge-review
---

# Goal Delivery + PR-Description Fidelity

Two sub-axes:

**a. Goal delivery.** Every `## G\d+ — <name>` entry in `goals.md` verifiably
delivered in the diff.

- Extract goal headers + (main)/(secondary) tags from `goals.md`.
- For each goal, name the file(s) / symbol(s) where delivery should be visible
  in the diff.
- Goal-miss → **blocker**, regardless of severity of any other finding.

**b. PR description ↔ goals.md drift.** The PR body's claims match `goals.md`'s
goals (no narrative drift between the forge artifact and the human-readable
summary).

- PR body's goal/feature list → match `goals.md` headers semantically. Renamed /
  reframed → flag.
- File list / line counts → match `gh pr diff --name-only` + diff stats.
- Mechanism / framing claims → match the actual code shape.
- Stack-position claims (`Base: PR #N`) → match `gh pr view` base ref.
- Drift → **major**. Unless the drift hides a goal-miss (then blocker).

The brief includes `goals.md` verbatim in a `## Goals` block and the PR body
verbatim in a `## PR description` block.
