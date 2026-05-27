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

Logging, metrics, tracing for production debugging.

## What This Agent Does

Check whether the changes are debuggable in production. When this code fails at
3am, can oncall figure out what happened from logs and metrics alone?

## Process

1. **Identify new code paths that can fail.** For each:
   - Is there a log line that captures the failure with enough context? (request
     ID, entity IDs, relevant state)
   - Is the log level appropriate? (error for failures, warn for degraded, info
     for significant events, debug for detail)
   - Are errors logged at the point of origin, not just propagated silently up
     the stack?

2. **Check for silent failures:**
   - Goroutines or background workers that swallow errors
   - Fire-and-forget operations with no success/failure signal
   - Catch-all error handlers that log generic messages without context
   - Retry loops that exhaust attempts without alerting

3. **Check for missing metrics** (where applicable):
   - New endpoints: request count, latency, error rate?
   - New background jobs: execution count, duration, failure count?
   - New external calls: latency, retry count, circuit breaker state?

4. **Check for log quality:**
   - Do error logs include the values that caused the error? (not just "invalid
     input" — what was the input?)
   - Are structured logging fields used consistently? (not string interpolation)
   - Is sensitive data excluded from logs? (PII, tokens, passwords)
   - Are logs at the right verbosity? (not flooding info level with per-request
     debug data)

5. **Check trace propagation** (if applicable):
   - Is the context/trace ID passed through new function calls?
   - Do new external calls propagate the trace?

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's missing, why it matters for production debugging]
```

BLOCKER: silent failures, completely unobservable new code paths. MINOR:
suboptimal log levels, missing optional metrics.
