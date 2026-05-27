---
id: correctness
name: Correctness
tags: [code-quality, logic, error-handling]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# Correctness Lens

Logic bugs, error handling, edge cases, nil safety.

## What This Agent Does

Verify that every changed code path produces the correct result under all
conditions — not just the happy path.

## Process

1. **Read every changed function/method from the diff.** For each, trace the
   logic line by line. Don't skim — execute it mentally with concrete values.

2. **For each code path, check:**
   - Does the logic match the stated intent (PR description, function name,
     comments)?
   - What happens with nil/null/zero/empty inputs?
   - What happens at boundary values (0, 1, max, negative)?
   - Are off-by-one errors possible (loop bounds, slice indices, ranges)?
   - Can concurrent access cause data races or inconsistent state?
   - Are type conversions safe (int overflow, float precision, string encoding)?

3. **Trace error propagation.** For every error that can occur:
   - Is it returned, handled, or logged? (never silently dropped)
   - Does the error message include enough context to debug in production?
   - Does the caller handle this specific error case?
   - Can a partial failure leave state inconsistent?

4. **Check conditional logic:**
   - Are all branches reachable? Is there dead code?
   - Are boolean conditions correct? (easy to invert, miss a case, use && vs ||)
   - For switch/match: is every case handled? Is there a default?

5. **Verify return values:**
   - Right type, right value, right conditions
   - Can the caller misinterpret the return? (e.g., returning nil vs empty
     slice)

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's wrong, why it's wrong, what the correct behavior should be]
```
