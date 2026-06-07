---
id: pr-description-fidelity
name: PR Description Fidelity
tags: [pr-hygiene, scope, drift]
requires: diff
severity-floor: blocker
brief-artifacts: [pr-description]
introduced-by: lens-review
---

# PR Description Fidelity

The PR description is part of the artifact under review, not narration around
it. Two axes:

## a. Goal-delivery

Every claimed goal verifiably delivered in the diff.

- Extract goal bullets from the PR description verbatim.
- For each, name the file(s) / symbol(s) where delivery should be visible.
- Spot-check delivery before lens fan-out, or assign as synthesis agent's first
  task.
- **Goal-miss → blocker**, regardless of any other finding's severity.

## b. Description accuracy

Every other claim matches the diff (no narrative drift).

- File list / line counts → match `gh pr diff --name-only` + diff stats.
- Mechanism framing ("X folds into Y", "uses pattern Z") → match the actual code
  shape, not an earlier design revised mid-PR.
- Test-coverage claims → match the actual test file's coverage.
- Backward-compat claims ("strictly additive") → spot-check one representative
  file's pre/post diff.
- Stack-position claims ("Base: PR #N", "PR-X of N-PR stack") → match
  `gh pr view` base ref + stack doc.
- **Drift → major** (not blocker, unless it hides a goal-miss). Author should
  refresh the description before merge so future readers and auto-generated
  changelogs aren't misled.

The brief carries the PR body verbatim in a `## PR description` block. The agent
reads the diff directly to check claim-vs-code.
