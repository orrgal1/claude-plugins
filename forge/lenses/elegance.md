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

Does the shape of the change match the shape of the problem? Future-reader cost.
Catches over-engineering and under-engineering both.

- Right abstraction layer — is the new function / type / interface where it
  belongs, or one above / below?
- Simplicity vs cleverness — does a simpler shape read as well or better?
  Reach-for-pattern smells (factory for one type, interface for one impl,
  generic for one caller).
- Premature abstraction — extracting a base class / mixin / utility before the
  second caller exists.
- Intent clarity — can a future reader infer the why without the PR description?
  Names, structure, small comments at non-obvious seams should carry intent.
- Test sufficiency for refactor confidence — a stranger should be able to
  refactor with the suite as a safety net. Tests locking in implementation
  detail rob future refactors of that confidence.
- Cohesion / coupling — does the change strengthen module boundaries or smear
  them? A sixth caller to a function across three packages is a coupling signal.

**Severity:** major when they predict future rework (premature abstraction,
misplaced layer); minor when they predict only future friction.
