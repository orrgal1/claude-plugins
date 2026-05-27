---
id: robustness
name: Robustness
tags: [code-quality, robustness, error-paths]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Robustness

The failure modes the happy path doesn't reveal. Stability + robustness against
the inputs the author didn't think to test.

- Error path completeness — every error is either handled, propagated, or
  explicitly swallowed with a documented reason. No silent catches.
- Boundary inputs — empty / null / zero / max-size / negative / unicode / mixed
  case / leading-trailing whitespace. Each one a potential silent failure.
- Concurrency hazards — shared mutable state across goroutines / tasks / async
  paths; missing locks; race-prone caches; ordering assumptions.
- Resource handling — file handles closed on every path; connections returned to
  the pool; cancellation propagated; goroutine / task leaks.
- Retry / backoff / timeout — every external call has a bounded wait, and
  retries don't pile up failure on the upstream.
- Idempotency / replay safety — operations that could be retried after a partial
  success do not double-charge / double-write / corrupt state.
- Observability under failure — errors carry enough context that the on-call
  engineer can root-cause without re-running the failing input.

**Severity:** robustness findings are blocker when the diff ships a known
silent-failure path (unhandled error → wrong result), major when it ships a
fragile path (unbounded retry, missing timeout), minor when the gap is cosmetic
(vague error message).
