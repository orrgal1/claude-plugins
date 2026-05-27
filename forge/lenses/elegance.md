---
id: elegance
name: Elegance + Maintainability
tags: [code-quality, design, architecture]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Elegance + Maintainability

Whether the shape of the change matches the shape of the problem. Future-reader
cost. The lens that catches over-engineering and under-engineering both.

- Right abstraction layer — is the new function / type / interface at the layer
  where it belongs, or one above / below?
- Simplicity vs cleverness — does a simpler shape exist that reads as well or
  better? Reach-for-pattern smells (factory for one type, interface for one
  implementation, generic for one caller).
- Premature abstraction — extracting a base class / mixin / utility before the
  second caller exists.
- Intent clarity — can a future reader infer the why without consulting the PR
  description? Names, structure, and small comments at non-obvious seams should
  carry the intent.
- Test sufficiency for refactor confidence — a stranger should be able to
  refactor the new code with the test suite as a safety net. Tests that lock in
  implementation detail rob future refactors of that confidence.
- Cohesion / coupling — does the change strengthen module boundaries or smear
  them? A change that adds a sixth caller to a function across three packages is
  a coupling signal.

**Severity:** elegance findings are major when they predict future rework (a
premature abstraction, a misplaced layer); minor when they predict only future
friction.
