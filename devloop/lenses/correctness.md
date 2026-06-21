---
id: correctness
name: Correctness
tags:
  [code-quality, logic, error-handling, ordering, side-effects, blast-radius]
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

6. **Reordering & side-effect order (fingerprint-gated — MAJOR floor).** First,
   fingerprint the diff for a **reorder**: did it _move_ an existing statement /
   call rather than only add or delete one? Signals — a line deleted in one
   position reappears added elsewhere in the same function/scope; two adjacent
   operations swap; a statement migrates across a boundary (before/after a lock,
   guard/early-return, state mutation, `await`, transaction commit/rollback,
   flush, log, or event emit). No reorder → skip this step.

   A reorder is a **behavior change with non-local blast radius**, not a
   refactor. The author likely resequenced to fix one code path; the same
   function often serves others. Treat the new order as guilty until the _other_
   paths are checked — especially in monolithic, side-effect-driven code where
   order _is_ the contract.

   - **Enumerate every path that runs this function** — all callers, all
     branches within it, every input class. Not just the path the PR set out to
     fix.
   - For each, verify the new order preserves the prior contract:
     - Side-effect ordering — does an effect now fire before/after a state it
       used to depend on (validation before mutation, auth before action, read
       before write)?
     - Short-circuit / guard placement — does a moved early-return or guard now
       skip or expose work it used to gate?
     - Resource & transaction boundaries — acquire/release, open/close, begin/
       commit still correctly bracket the moved work on every path?
     - Emission / notification order — events, callbacks, or logs that
       downstream consumers depend on arriving in a fixed sequence.
     - Idempotency / partial-failure — does the new order change what state
       survives a mid-sequence failure or retry?
   - **Severity:** MAJOR for any reorder of operations that share state or carry
     side effects / ordering dependencies — the floor, even when you can't prove
     a break (the burden is on the diff to show the order is free). BLOCKER when
     a concrete sibling path is demonstrably wrong under the new order. Not a
     finding at all only when both operations are provably pure and independent
     — no shared state, no side effects, no data dependency between them.

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MAJOR | MINOR
DETAIL: [what's wrong, why it's wrong, what the correct behavior should be]
```

For a reordering finding, name the moved operation and the sibling paths at
risk:

```
ISSUE: reordered <op> before/after <op> in <function>
FILE: path/to/file.go:42
SEVERITY: MAJOR | BLOCKER
DETAIL: fixes path <X>, but <function> also runs on <Y, Z>; under the new order
        <what breaks on those paths, or what is unverified and why the burden falls on the diff>
```
