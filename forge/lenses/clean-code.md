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
per-line decisions that determine whether a future reader can absorb the diff
without re-deriving its intent. Architectural / cross-module choices live in the
`elegance` lens; this one is the in-the-small layer. Commentary review is
delegated to the `commentary` lens; stay at policy level here.

Draws from Martin's canonical checklist:

- **Meaningful names** — intention-revealing, pronounceable, searchable; avoid
  encoded names (Hungarian, type prefixes), abbreviations, single-letter names
  outside tiny scopes, and disinformation (a list named `accounts` that holds
  account IDs).
- **Small functions** — each function does one thing at one level of
  abstraction. Long functions split. Few arguments — 0 ideal, then 1, then 2; 3+
  a smell. **Flag arguments banned** (booleans that change the function's
  behavior — split into two functions).
- **No side effects in queries** — a function named `is_valid` does not mutate
  state. Command-query separation.
- **Comments compensate for failure to express in code** — prefer renaming /
  extracting over commenting. Acceptable comments: legal headers, intent the
  code can't carry, warnings of consequence, TODOs (with owner / date), public
  API documentation. Banned: redundant comments restating the code, misleading
  comments, journal comments, commented-out code, attributions ("/_ Bob _/").
- **Formatting that aids reading** — vertical openness between concepts,
  vertical density within a concept, related concepts near each other, variable
  declared close to use, instance variables grouped at top, function ordering
  (caller above callee).
- **Error handling is first-class** — exceptions over return codes; don't return
  null (return empty collection or use Optional/Result); don't pass null. Don't
  swallow exceptions silently.
- **Boundaries** — third-party APIs wrapped at the boundary so they don't leak
  into business logic. Tests for the boundary wrapper, not the third party.
- **Tests are first-class code** — F.I.R.S.T. (fast, independent, repeatable,
  self-validating, timely). Tests as readable and maintained as production code.
  One concept per test (one assertion per test is the textbook ideal, but
  tier-dependent). Note: Martin centers his examples on unit tests, but do
  **not** import that tier preference — flag how the test is written (clarity,
  isolation, brittleness, mock-mania), not which tier it sits at.
- **Code smells** — long parameter lists, large classes, primitive obsession,
  data clumps, feature envy, switch statements (especially on type tags),
  shotgun surgery, divergent change, speculative generality, dead code, lazy
  class. Each one a named smell from the book — call it by name.

This is not a typo-pass — call out the named principle that's violated, not just
the symptom. "Function `do_thing` takes a boolean flag — flag-argument smell;
split into `do_thing_a` and `do_thing_b`" beats "consider refactoring this
function".

**Severity:** Clean Code findings are typically minor — local hygiene fixes.
Promote to major when the smell will compound: a 5-argument function whose call
sites multiply, a deeply nested set of conditionals about to spawn more
branches, a swallowed exception in a hot path. Promote to blocker only when the
violation hides a correctness risk (returning null for a never-null contract,
swallowing an exception that masks data loss).
