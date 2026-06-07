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

Every changed code path must produce the correct result under all conditions —
not just the happy path. Logic bugs, error handling, edge cases, nil safety.

## Process

1. **Read every changed function from the diff.** Trace logic line by line —
   execute it mentally with concrete values, don't skim.

2. **For each code path, check:**
   - Logic matches stated intent (PR description, function name, comments)?
   - nil/null/zero/empty inputs?
   - Boundary values (0, 1, max, negative)?
   - Off-by-one (loop bounds, slice indices, ranges)?
   - Concurrent access → data races or inconsistent state?
   - Safe type conversions (int overflow, float precision, string encoding)?

3. **Trace error propagation.** For every error that can occur:
   - Returned, handled, or logged (never silently dropped)?
   - Message has enough context to debug in production?
   - Caller handles this specific error case?
   - Partial failure leaves state inconsistent?

4. **Conditional logic:**
   - All branches reachable? Dead code?
   - Boolean conditions correct (inverted, missed case, && vs ||)?
   - switch/match: every case handled? A default?

5. **Return values:**
   - Right type, value, conditions?
   - Caller can misinterpret (nil vs empty slice)?

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's wrong, why it's wrong, what the correct behavior should be]
```
