---
id: test-restraint
name: Test Restraint
tags: [tests, restraint, code-quality]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Test Restraint

The dual of `test-coverage`. That lens asks "is each behavioral change tested?"
This lens asks "does each new test prove something non-trivial, or is it
scaffolding for behavior the codebase already trusts?"

Over-testing is its own tax — test files multiply, reviewers spend cycles on
them, and the next pattern instance copies the bloat. A test that exercises
behavior the existing test suite already covers, or scaffolds a 200-LOC fixture
to verify a single boolean toggle, is a candidate for removal.

## Process

1. **List every new test file / new test case in the diff.** For each, ask what
   behavior it claims to exercise.

2. **For each test, classify:**
   - **Trivial getter / setter** — read what was written, verify it's the same
     value. The framework + type system already guarantees this.
   - **Stub coverage** — test calls the function but doesn't assert any
     non-default outcome (no error, no panic). The compiler already proved
     "doesn't panic."
   - **Pattern-instance bloat** — the codebase already has N similar tests for
     the same wiring pattern; this is a copy of the most recent one, with the
     field name swapped. Adding N+1 doesn't add coverage; it adds maintenance.
   - **Wiring confidence** — exercises that the new code is reachable in
     production. Often legitimately worth a single small test (one wiring test
     per integration point) but not 200 LOC.
   - **Real logic** — exercises a non-obvious branch, a tricky transform, an
     invariant only this test would catch. Keep.

3. **For each non-keep classification:**
   - Propose removal, citing the equivalent pattern instance already in the
     suite if applicable.
   - When the test was added to satisfy a coverage gate, ask whether the gate
     itself is asking for the right kind of coverage — code-coverage % is not
     behavioral coverage.

## Pattern smells

- A 200-LOC test file for reading + writing a boolean flag in a feature flag
  table that already has 10 similar flags + tests.
- Tests where every assert is "no error" with no return-value check.
- Test names that paraphrase the function name (`TestIsActiveUser` →
  `is_active_user`).
- Parametrized tests where a single case covers the same logic.
- New test fixtures that copy production setup verbatim — if it's the same
  shape, share the fixture.
- A model_test.go whose only non-trivial logic is checking that the model
  collects the right `Recipient` / address — the rest is mechanical and better
  covered by the schema's parser tests.

## Heuristics for spotting bloat

- Count similar test patterns in the codebase. If `<feature>_flag_test.go` files
  already exist for ≥5 flags and they all follow the same shape, the new one is
  scaffolding.
- Look for "I don't think anything even runs these UTs" — if a test file isn't
  wired into the CI runner / pytest config / go test pattern, it's dead code
  masquerading as coverage.
- Cross-reference with `test-coverage` findings — if the lens flagged a GAP
  somewhere else in the same diff, the over-tested area is spending budget that
  should have gone there.

## Severity

- **Minor** — single test case to remove, no impact on suite runtime.
- **Major** — entire test file recommended for removal (200+ LOC, no real
  coverage), or test bloat will be copied by the next pattern instance.
- **Blocker** — only when the bloat actively hides a real coverage gap (e.g.
  test claims to exercise behavior X but actually only checks setup, while the
  real X path is untested).
