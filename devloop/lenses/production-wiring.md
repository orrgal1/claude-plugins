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

Verify new code is reachable in production. Code that compiles and passes tests
can still be dead if it's not wired up.

## Process

1. **New interfaces/abstractions:** for each new interface or abstract type:
   - A concrete implementation?
   - Instantiated in production code (not just tests)?
   - Injected/registered in the right place (DI container, constructor,
     factory)?

2. **New constructors:** for each new constructor or factory:
   - Called from production code?
   - If it replaces an old one, all production call sites updated?
   - New optional params actually passed in production? (common miss:
     `NewFooWithBar()` exists but production still calls `NewFoo()`)

3. **New endpoints/RPCs:** registered in the router/server? Auth middleware
   attached? Rate limiting? Docs updated (OpenAPI, proto)?

4. **New background jobs/workers:** registered in the scheduler/runner? Started
   in service bootstrap? Monitored (health check, metrics)?

5. **Feature flags:** enabled in the right environments? Kill switch? Default
   value correct for production?

6. **Configuration:** new values added to all environments (dev, staging, prod)?
   Sensible defaults for missing config? Validated at startup?

7. **Database/migration wiring:** migration files registered in
   `*_db_definitions.py`? New collections/indexes created? Migration order
   correct relative to dependent code?

## Output Format

```
ISSUE: [what's not wired]
FILE: path/to/file.go:42 (the new code)
EXPECTED_AT: path/to/bootstrap.go (where it should be wired)
SEVERITY: BLOCKER
DETAIL: [why this means the code won't run in production]
```

All production wiring findings are BLOCKER — unwired code is dead code.
