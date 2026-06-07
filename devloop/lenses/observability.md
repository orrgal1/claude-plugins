---
id: observability
name: Observability
tags: [ops, logging, metrics, tracing]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# Observability Lens

When this code fails at 3am, can oncall figure out what happened from logs and
metrics alone?

## Process

1. **New code paths that can fail.** For each:
   - A log line capturing the failure with enough context (request ID, entity
     IDs, relevant state)?
   - Appropriate log level (error/warn/info/debug)?
   - Errors logged at origin, not propagated silently up the stack?

2. **Silent failures:**
   - Goroutines/background workers that swallow errors
   - Fire-and-forget ops with no success/failure signal
   - Catch-all handlers logging generic messages without context
   - Retry loops exhausting attempts without alerting

3. **Missing metrics** (where applicable):
   - New endpoints: request count, latency, error rate?
   - New background jobs: execution count, duration, failure count?
   - New external calls: latency, retry count, circuit breaker state?

4. **Log quality:**
   - Error logs include the values that caused the error (not just "invalid
     input" — what input)?
   - Structured fields used consistently (not string interpolation)?
   - Sensitive data excluded (PII, tokens, passwords)?
   - Right verbosity (not flooding info with per-request debug)?

5. **Trace propagation** (if applicable):
   - Context/trace ID passed through new calls?
   - New external calls propagate the trace?

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's missing, why it matters for production debugging]
```

BLOCKER: silent failures, completely unobservable new code paths. MINOR:
suboptimal log levels, missing optional metrics.
