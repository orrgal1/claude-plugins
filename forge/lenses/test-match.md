---
id: test-match
name: Test Match
tags: [chain-semantic, tests, forge]
requires: forge-chain
severity-floor: major
brief-artifacts: [links.json, linked-test-files]
introduced-by: forge-review
---

# Test Match

Each test referenced by an `SG` entry in `goals.md` (or by `links.json`) must
actually exercise its scenario, beyond carrying matching `when:` / `then:` tags.

- For each linked test:
  - Read the full test body, not just the `when:` / `then:` comments.
  - Walk the AAA section. AAA markers absent → flag **major** (already a
    `/forge-audit` NO-AAA condition; re-confirmed here in case of post-verify
    drift).
  - Do the asserts observably check the `then:` clause, or assert implementation
    detail orthogonal to the scenario?
  - Does arrange-act match the `when:` clause, or exercise a different path?
- Pattern smells:
  - Name + tags match, but assertions check internal state, not the `then:`
    outcome.
  - Test exercises a happy path the `when:` clause never said it would.
  - Test relies on a mock that bypasses the mechanism the scenario should prove.
- **Match miss → major** (test exists, fails to prove). Borderline / "tests the
  right thing but weakly" → minor.

The brief includes `links.json` plus every linked test's path. The agent reads
the test files directly.
