---
id: test-coverage
name: Test Coverage
tags: [tests, coverage]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# Test Coverage Lens

Behavioral coverage — do tests prove the changes are correct?

## What This Agent Does

This lens is NOT about line coverage. It's about whether tests **prove the
behavioral change is correct**.

## Process

1. **Identify every behavioral change** in the PR — new code paths, changed
   conditions, modified return values, new error cases, changed side effects.
   Work from the diff, not just the file list.

2. **For each behavioral change, find the test that exercises it.** Not "a test
   that touches this file" — the specific test that:
   - Sets up the precondition for the new/changed behavior
   - Triggers the exact code path
   - Asserts the expected outcome of the change (not just "no error")

3. **Flag gaps** where a behavioral change has no corresponding test, or where a
   test exists but doesn't actually verify the changed behavior. Common patterns
   to catch:
   - Test calls the function but doesn't assert the new field/value/behavior
   - Test asserts "no error" but doesn't verify the output changed correctly
   - Test covers the happy path but not the new error case added in this PR
   - Test existed before and still passes, but no longer exercises the changed
     logic (stale test that gives false confidence)
   - New enum/type value added but not present in any test fixture

## Output Format

For each behavioral change:

```
CHANGE: [description of behavioral change]
FILE: path/to/changed/file.go:42
TEST: path/to/test_file.go:TestFunctionName — [COVERED | GAP | WEAK]
DETAIL: [why it's covered / what's missing / why the test is weak]
```

- **COVERED** — a test specifically exercises this change and asserts the
  outcome
- **GAP** — no test exercises this behavioral change
- **WEAK** — a test exists but doesn't meaningfully prove correctness (e.g.,
  asserts no error but not the actual result)
