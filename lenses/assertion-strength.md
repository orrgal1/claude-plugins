---
id: assertion-strength
name: Assertion Strength
tags: [tests, assertions, code-quality]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# Assertion Strength

Given that a test exists and exercises the code path, do its assertions actually
**pin the behavior** — or do they only check that _something_ happened?

This lens is orthogonal to its siblings:

- `test-coverage` asks "is each behavioral change tested at all?" A change can
  be COVERED here — a test runs the path — yet its assertions prove almost
  nothing.
- `test-restraint` asks "should this whole test exist?" That lens deletes tests
  that prove nothing; this lens **strengthens the assertions inside tests worth
  keeping**.

Two failure modes:

1. **Shallow assertion** — asserts mere existence (`not nil`, `not empty`,
   `len > 0`, `is defined`, `truthy`) where the correct outcome has a knowable
   shape and content. The right assertion compares the actual value(s) — field
   equality, full-struct equality, set membership — not "something came back".

2. **Redundant assertion** — a nil / existence guard that the **very next line
   already forces**: a deref, field access, index, or a deeper equality assert
   that would itself fail or panic on nil. The guard adds a line and a
   maintenance point but no signal.

## Process

1. **List the asserting statements in every new / changed test.** The assert
   calls themselves — `require.*` / `assert.*` (Go), `assertX` /
   `self.assertEqual` / bare `assert` (Python), `expect().toX` (Vitest/Jest),
   `assertThat` (JUnit), etc. Work from the diff.

2. **Classify each assertion:**
   - **REDUNDANT** — a `NotNil` / `not None` / `toBeDefined` guard immediately
     followed by a statement that derefs the same value (equality on a field, an
     index, a method call). The follow-up already proves non-nil with a clearer
     failure.
   - **SHALLOW** — asserts only existence / non-empty / length / no-error, while
     the outcome has a deterministic, knowable value the test does not pin.
   - **STRONG** — compares the actual shape + content of the result, or
     legitimately guards a real nil branch (see nuance below). Keep.

3. **For each SHALLOW assertion**, name the stronger assertion available: the
   concrete expected value, the field-by-field equality, the element identities
   behind the length check.

4. **For each REDUNDANT assertion**, cite the later line that already exercises
   the nilness, and recommend dropping the guard.

## Pattern smells

- `require.NotNil(t, got)` then `require.Equal(t, want, got.Field)` — the
  `NotNil` is redundant; `Equal` already derefs `got`.
- `assert.NotNil(t, resp)` then `assert.Equal(t, 200, resp.Code)` — redundant
  guard one line above the deref.
- `assert result is not None` then `assert result.foo == bar` (pytest) —
  redundant None-guard; the attribute access already raises on None.
- `require.NoError(t, err)` with no assertion on the return value — the
  no-error-only test (overlaps `test-coverage` WEAK).
- `assert.Len(t, list, 3)` / `expect(list).toHaveLength(3)` with no check on the
  elements — length without content. The contract is usually _which_ elements.
- `assert.NotEmpty(t, result)` / `expect(x).toBeTruthy()` /
  `expect(x).toBeDefined()` where `result` has a fully known expected value —
  assert the value.
- Asserting a collection is non-nil / non-empty but never its contents,
  ordering, or shape.
- Asserting only the **count** of a returned set when the **identity** of the
  elements is the actual contract.

## Nuance — do not over-flag

- A nil guard is **legitimate** when nil is a real, untested branch outcome and
  the guard converts a confusing nil-panic into a clear failure — typically when
  the deref is several lines down, inside a loop, or behind a helper. Flag
  redundancy only when the deref is **immediate** and would fail on the same
  value anyway.
- Don't demand ordered equality on inherently unordered collections (map
  iteration, concurrent results) — assert **set membership** instead.
- Partial assertion is fine when the rest of the value is non-deterministic
  (timestamps, generated ids, addresses). Flag only the **deterministic** fields
  left unasserted, not the volatile ones.
- Golden / snapshot comparisons are strong by default; only flag when a targeted
  field assert would be materially clearer or the snapshot is so broad it would
  pass on a wrong value.

## Output

One finding per weak or redundant assertion:

```
path/to/test_file.go:42: <severity>: <REDUNDANT | SHALLOW> — <what's asserted now>.
  <drop the guard, line N already derefs | assert <stronger form> instead>.
```

## Severity

- **Minor** — a single redundant guard, or one shallow assert where the stronger
  form is a one-liner.
- **Major** — a test's entire assertion block is shallow (only no-error /
  not-nil / length), so it passes against a wrong-shaped or wrong-content result
  and gives false confidence on behavior the PR changed.
- **Blocker** — the PR's central behavioral change is "tested" only by shallow
  assertions, so a regression in the actual output shape or content would not
  fail the suite.
