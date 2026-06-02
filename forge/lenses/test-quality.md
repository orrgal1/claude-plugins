---
id: test-quality
name: Test Quality (structure · assertions · restraint)
tags: [tests, assertions, restraint, code-quality]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Test Quality

**Is the test built well?** Three axes — assertion strength, structural clarity
(AAA), restraint. A test can be on-target yet prove little, read as mud, or be
pure scaffolding. Audits every new/changed test against all three. Grades
construction; whether a test targets the right scenario `then:` is
`test-match`'s call.

## Axis 1 — Assertion strength

Do the asserts **pin the behavior**, or only check that _something_ happened?

1. **List the asserting statements** in every new/changed test — `require.*` /
   `assert.*` (Go), `assertEqual` / bare `assert` (Python), `expect().toX`
   (Vitest/Jest), `assertThat` (JUnit). Work from the diff.
2. **Classify each:**
   - **SHALLOW** — asserts only existence / non-empty / length / no-error
     (`not nil`, `len > 0`, `toBeTruthy`, `NoError` with no return-value check)
     while the outcome has a deterministic, knowable shape the test never pins.
   - **REDUNDANT** — a nil/existence guard the **very next line already
     forces**: a deref, field access, index, or equality assert that would
     itself fail or panic on nil. A line and a maintenance point, no signal.
   - **STRONG** — compares actual shape + content (field equality, full-struct,
     set membership), or legitimately guards a real nil branch. Keep.
3. For each SHALLOW, name the stronger assertion available. For each REDUNDANT,
   cite the later line that already exercises the nilness and recommend dropping
   the guard.

### Assertion smells

- `require.NotNil(t, got)` then `require.Equal(t, want, got.Field)` — `Equal`
  already derefs `got`.
- `assert result is not None` then `assert result.foo == bar` — attribute access
  already raises on None.
- `require.NoError(t, err)` with no assertion on the return value.
- `assert.Len(t, list, 3)` / `toHaveLength(3)` with no check on the elements.
- `NotEmpty` / `toBeTruthy` / `toBeDefined` where the value is fully known.
- Asserting only the **count** of a returned set when element **identity** is
  the contract.

### Assertion nuance — do not over-flag

- A nil guard is legitimate when nil is a real, untested branch and the deref is
  several lines down, in a loop, or behind a helper. Flag redundancy only when
  the deref is **immediate** and would fail on the same value anyway.
- Don't demand ordered equality on unordered collections — assert **set
  membership**.
- Partial assertion is fine for non-deterministic fields (timestamps, generated
  ids); flag only the **deterministic** fields left unasserted.
- Golden / snapshot comparisons are strong by default; flag only when a targeted
  field assert is materially clearer or the snapshot passes on a wrong value.

## Axis 2 — Structure (AAA)

Can a reader see arrange / act / assert at a glance?

- **Tangled phases** — setup, the call under test, and assertions interleave so
  the reader can't tell what's exercised. The act should be one identifiable
  step between a setup block and an assertion block.
- **Buried act** — the behavior under test is one call lost among incidental
  setup; nothing marks the subject line.
- **Multi-act tests** — arranges/acts/asserts, then acts and asserts again,
  proving several unrelated things. Split, or mark the phases.
- **No naming of intent** — name and body don't convey the scenario. Prefer a
  name (or `when:`/`then:` note) stating scenario + expected outcome.

Recommend AAA section separation (blank line or `// arrange` / `// act` /
`// assert` marker) when the body is non-trivial. Don't demand markers on a
three-line test that's already obvious.

## Axis 3 — Restraint

Does each new test prove something non-trivial, or scaffold behavior the
codebase already trusts? Over-testing is its own tax — files multiply, reviewers
spend cycles, the next pattern instance copies the bloat. Classify each new test
file/case:

- **Trivial getter / setter** — reads what was written. Framework + type system
  already guarantee it.
- **Stub coverage** — calls the function but asserts no non-default outcome. The
  compiler already proved "doesn't panic."
- **Pattern-instance bloat** — suite already has N similar tests for the same
  wiring pattern; this is a copy with a field swapped. N+1 adds maintenance, not
  coverage.
- **Wiring confidence** — exercises that new code is reachable in production.
  Often worth one small test per integration point, not 200 LOC.
- **Real logic** — a non-obvious branch, tricky transform, or invariant only
  this test catches. Keep.

For each non-keep, propose removal, citing the equivalent pattern instance in
the suite. When added to satisfy a coverage gate, ask whether the gate wants the
right _kind_ of coverage — code-coverage % is not behavioral coverage.

### Restraint smells

- A 200-LOC test file for reading + writing a boolean flag where the table
  already has 10 similar flags + tests.
- Test names that paraphrase the function name (`TestIsActiveUser`).
- Parametrized tests where a single case covers the same logic.
- New fixtures copying production setup verbatim — share the fixture if same
  shape.
- A test file not wired into the CI runner / pytest config / `go test` pattern —
  dead code masquerading as coverage.

## Output

One finding per issue, tagged with its axis:

```
path/to/test_file.go:42: <severity>: <ASSERTION | STRUCTURE | RESTRAINT> — <problem>.
  <stronger assert / phase separation / removal + the equivalent already in suite>.
```

## Severity

- **Minor** — a single redundant guard, one shallow assert with a one-line
  stronger form, one tangled small test, one test case to remove.
- **Major** — a test's entire assertion block is shallow (passes against a
  wrong-shaped result → false confidence); an entire test file recommended for
  removal (200+ LOC, no real coverage); structure so tangled the test is
  unmaintainable.
- **Blocker** — the PR's **central** behavioral change is "tested" only by
  shallow assertions, so a regression in output shape/content wouldn't fail the
  suite; or bloat actively hides a real coverage gap (test claims to exercise X
  but only checks setup while the real X path is untested).
