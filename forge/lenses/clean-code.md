---
id: clean-code
name: Clean Code (Martin)
tags: [code-quality, hygiene, martin]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Clean Code (Martin)

Local hygiene per Robert C. Martin's _Clean Code_ — the per-function, per-name,
per-line decisions that let a future reader absorb the diff without re-deriving
intent. Architectural / cross-module choices live in `elegance`; commentary in
`commentary`. Stay at the in-the-small policy layer here.

Martin's canonical checklist:

- **Meaningful names** — intention-revealing, pronounceable, searchable; avoid
  encoded names (Hungarian, type prefixes), abbreviations, single-letter names
  outside tiny scopes, and disinformation (a list named `accounts` holding
  account IDs).
- **Small functions** — one thing at one level of abstraction. Long functions
  split. Few arguments — 0 ideal, then 1, then 2; 3+ a smell. **Flag arguments
  banned** (booleans that switch behavior — split into two functions).
- **No side effects in queries** — `is_valid` does not mutate state.
  Command-query separation.
- **Comments compensate for failure to express in code** — prefer renaming /
  extracting. Acceptable: legal headers, intent the code can't carry, warnings
  of consequence, TODOs (owner / date), public API docs. Banned: redundant
  comments restating code, misleading comments, journal comments, commented-out
  code, attributions ("/_ Bob _/").
- **Formatting that aids reading** — vertical openness between concepts,
  vertical density within a concept, related concepts near each other, variable
  declared close to use, instance variables grouped at top, caller above callee.
- **Error handling is first-class** — exceptions over return codes; don't return
  null (empty collection or Optional/Result); don't pass null; don't swallow
  exceptions silently.
- **Boundaries** — third-party APIs wrapped at the boundary so they don't leak
  into business logic. Test the wrapper, not the third party.
- **Tests are first-class code** — F.I.R.S.T. (fast, independent, repeatable,
  self-validating, timely). As readable and maintained as production code. One
  concept per test (one-assertion is the textbook ideal, but tier-dependent).
  Martin centers his examples on unit tests, but do **not** import that tier
  preference — flag how the test is written (clarity, isolation, brittleness,
  mock-mania), not which tier it sits at.
- **Code smells** — long parameter lists, large classes, primitive obsession,
  data clumps, feature envy, switch statements (especially on type tags),
  shotgun surgery, divergent change, speculative generality, dead code, lazy
  class. Call each named smell by name.

Not a typo-pass — call out the violated principle, not just the symptom.
"Function `do_thing` takes a boolean flag — flag-argument smell; split into
`do_thing_a` / `do_thing_b`" beats "consider refactoring this function".

**Severity:** typically minor — local hygiene. Promote to major when the smell
compounds: a 5-argument function whose call sites multiply, a deeply nested
conditional about to spawn branches, a swallowed exception in a hot path.
Blocker only when the violation hides a correctness risk (returning null for a
never-null contract, swallowing an exception that masks data loss).
