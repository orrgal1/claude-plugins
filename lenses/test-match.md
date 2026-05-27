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

Each test referenced by an `SG` entry in `goals.md` (or by `links.json`)
actually exercises its scenario, beyond carrying matching `when:` / `then:`
comment tags.

- For each linked test:
  - Read the full test body (not just the `when:` / `then:` comments).
  - Walk the AAA section (arrange / act / assert). If AAA markers absent → flag
    as major (already a `/forge-audit` NO-AAA condition, but re-confirmed here
    in case the chain was reviewed post-verify drift).
  - Ask: do the asserts observably check the `then:` clause, or do they assert
    implementation detail orthogonal to the scenario?
  - Ask: does the arrange-act match the `when:` clause, or is the test
    exercising a different path?
- Pattern smells:
  - Test name + tags match, but assertions check internal state instead of the
    `then:` outcome.
  - Test exercises a happy path the `when:` clause never said it would.
  - Test relies on a mock that bypasses the actual mechanism the scenario was
    supposed to prove.
- **Match miss → major** (test exists, fails to prove). Borderline / "tests
  the right thing but weakly" → minor.

The brief includes `links.json` plus the file paths of every linked test. The
agent reads the test files directly.
