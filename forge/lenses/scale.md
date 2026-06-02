---
id: scale
name: Scale
tags: [performance, scale, ops]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# Scale Lens

Will the changes hold up under production load — not just test data? Pagination,
batch operations, hot-path performance.

## Process

1. **Unbounded operations.** For each query, API call, or loop:
   - What happens at 10x, 100x, 1000x the expected data?
   - Pagination? A limit? A timeout?
   - Can one request trigger an unbounded DB scan or in-memory collection?

2. **Database operations:**
   - Queries inside loops — batch instead? (`insert_many`, `BulkUpdate`, `IN`)
   - Missing indexes — does the query filter on indexed fields?
   - Complex `$or`/`$ne` queries — can timeout in prod; simplify to equality?
   - Unbounded `find()` without limit — can return millions

3. **Hot paths:**
   - Called per-request? Per-event? Per-user?
   - Expensive ops on hot paths: deep copies, JSON marshal, reflection, regex
     compilation, DB queries
   - Allocations in tight loops — pre-allocate or reuse?

4. **Concurrency:**
   - Is concurrency actually needed? Sequential is simpler, often fast enough.
   - If concurrent: bounded goroutines? Semaphore or worker pool?
   - Unbounded goroutine spawning (one per item in an unbounded list)

5. **External calls:**
   - Timeouts on all HTTP/gRPC clients?
   - Retry with backoff (not unbounded retries)?
   - Circuit breakers for degraded dependencies?

6. **Memory:**
   - Loading entire collections — can this stream?
   - Caching without eviction — grows unbounded?
   - Large objects copied unnecessarily

## Output Format

```
ISSUE: [description]
FILE: path/to/file.go:42
SEVERITY: BLOCKER | MINOR
LOAD: [what happens at scale — "1000 vaults: N+1 queries, ~1000 DB calls"]
FIX: [specific remediation]
```

BLOCKER: unbounded operations, N+1 queries, missing pagination on external APIs.
MINOR: suboptimal but bounded, premature optimization opportunities.
