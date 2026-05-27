---
id: production-wiring
name: Production Wiring
tags: [ops, wiring, bootstrap]
requires: diff
severity-floor: blocker
brief-artifacts: []
introduced-by: deep-review
---

# Production Wiring Lens

Interfaces instantiated, constructors called, flags set.

## What This Agent Does

Verify that new code is actually reachable in production. Code that compiles and
passes tests can still be dead in production if it's not wired up.

## Process

1. **New interfaces/abstractions:** for each new interface or abstract type
   introduced:
   - Is there a concrete implementation?
   - Is that implementation instantiated in production code (not just tests)?
   - Is it injected/registered in the right place (DI container, constructor,
     factory)?

2. **New constructors:** for each new constructor or factory function:
   - Is it called from production code?
   - If it replaces an old constructor, are all production call sites updated?
   - Are new optional parameters actually passed in production? (common miss:
     `NewFooWithBar()` exists but production still calls `NewFoo()`)

3. **New endpoints/RPCs:**
   - Registered in the router/server?
   - Auth middleware attached?
   - Rate limiting configured?
   - Documentation updated (OpenAPI, proto)?

4. **New background jobs/workers:**
   - Registered in the scheduler/runner?
   - Started in the service bootstrap?
   - Monitored (health check, metrics)?

5. **Feature flags:**
   - If the feature has a flag, is it enabled in the right environments?
   - Is there a kill switch for the new behavior?
   - Is the default value correct for production?

6. **Configuration:**
   - New config values added to all environments? (dev, staging, prod)
   - Sensible defaults for missing config?
   - Config validation at startup?

7. **Database/migration wiring:**
   - Migration files registered in `*_db_definitions.py`?
   - New collections/indexes created?
   - Migration order correct relative to code that depends on it?

## Output Format

```
ISSUE: [what's not wired]
FILE: path/to/file.go:42 (the new code)
EXPECTED_AT: path/to/bootstrap.go (where it should be wired)
SEVERITY: BLOCKER
DETAIL: [why this means the code won't run in production]
```

All production wiring findings are BLOCKER — unwired code is dead code.
