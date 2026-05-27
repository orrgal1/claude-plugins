---
id: completeness
name: Completeness
tags: [refactor-safety, callers, dispatch]
requires: diff
severity-floor: blocker
brief-artifacts: []
introduced-by: deep-review
---

# Completeness Lens

Missing callers, type system updates, parallel paths.

## What This Agent Does

Find what the PR forgot to change. The code it did change may be correct — but
are all the places that need to change actually updated?

## Process

1. **For every changed function signature:** grep for all callers. Are they all
   updated? Include both direct callers and indirect callers (via interface
   implementations, function pointers, reflection).

2. **For every new type/enum value:** grep for ALL switch/match/dispatch/map
   sites that branch on that type. Every one must handle the new value. Common
   miss: a new vault type is added to the enum but the type-to-chain mapping,
   balance refresh task dispatcher, and audit log formatter don't handle it.

3. **For every new code path that parallels an existing one:** diff the original
   path's operations against the new path. Are ALL post-operation steps
   included? Common miss: new entity creation path copies the core logic but
   forgets audit logs, risk score updates, notification triggers, or counter
   increments.

4. **For every changed/deprecated field:**
   - Search by field name, type name, AND ticket ID
   - Check serialization/deserialization (JSON tags, proto mappings, Pydantic
     models)
   - Check database queries that filter/project on this field
   - Check UI components that render this field

5. **For every new configuration/flag:** is it set in all environments? (dev,
   staging, production, test fixtures)

6. **For every new interface:** is it instantiated with a real implementation in
   production, not just in tests?

## Output Format

```
ISSUE: [what's missing]
FILE: path/to/file.go:42 (the change that implies the missing update)
MISSING_AT: path/to/other/file.go:88 (where the update should be)
SEVERITY: BLOCKER
DETAIL: [why this location needs updating — what will break without it]
```
