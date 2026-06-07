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

Find what the PR forgot to change. The changed code may be correct — but are all
the places that need to change actually updated? Missing callers, type-system
updates, parallel paths.

## Process

1. **Every changed function signature:** grep all callers — direct and indirect
   (interface implementations, function pointers, reflection). All updated?

2. **Every new type/enum value:** grep ALL switch/match/dispatch/map sites that
   branch on that type. Every one must handle the new value. Common miss: a new
   vault type added to the enum but the type-to-chain mapping, balance-refresh
   dispatcher, and audit-log formatter don't handle it.

3. **Every new code path paralleling an existing one:** diff the original path's
   operations against the new path. ALL post-operation steps included? Common
   miss: new entity-creation path copies core logic but forgets audit logs, risk
   score updates, notification triggers, or counter increments.

4. **Every changed/deprecated field:**
   - Search by field name, type name, AND ticket ID
   - Check serialization (JSON tags, proto mappings, Pydantic models)
   - Check DB queries that filter/project on the field
   - Check UI components that render it

5. **Every new configuration/flag:** set in all environments (dev, staging,
   production, test fixtures)?

6. **Every new interface:** instantiated with a real implementation in
   production, not just tests?

## Output Format

```
ISSUE: [what's missing]
FILE: path/to/file.go:42 (the change that implies the missing update)
MISSING_AT: path/to/other/file.go:88 (where the update should be)
SEVERITY: BLOCKER
DETAIL: [why this location needs updating — what will break without it]
```
