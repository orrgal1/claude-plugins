---
id: api-design
name: API Design
tags: [api, compatibility, naming]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: deep-review
---

# API Design Lens

Naming, consistency, backward compatibility.

## What This Agent Does

Review API surface changes (proto definitions, REST endpoints, GraphQL schemas,
exported Go types, React component props) for design quality and compatibility.

## Process

1. **Identify all API surface changes in the diff.** This includes:
   - Proto message/service/RPC definitions
   - REST endpoint paths, methods, request/response bodies
   - Exported Go types, interfaces, function signatures
   - React component props and public APIs
   - Python Pydantic models that map to external contracts

2. **Check naming:**
   - Consistent with existing conventions in the codebase? (grep for similar
     names)
   - Clear and unambiguous? Would a consumer understand without reading the
     implementation?
   - Follows language/framework conventions? (e.g., Go exported names, proto
     field naming)

3. **Check backward compatibility:**
   - Proto: field numbers unchanged? Enum zero value is UNKNOWN/UNSPECIFIED?
     Deprecated fields marked, not removed?
   - REST: existing fields preserved? New required fields have defaults or are
     additive?
   - Can existing clients continue to work without changes?
   - Are breaking changes flagged and intentional?

4. **Check design quality:**
   - Does the API expose implementation details that should be internal?
   - Are there unnecessary optional fields that should be required (or vice
     versa)?
   - Is the granularity right? (not too coarse, not too chatty)
   - Does it follow existing patterns in the codebase? (e.g., uses oneof for
     type discrimination, not optional fields with nil checks)

5. **Check extensibility:**
   - Can this API evolve without breaking changes?
   - Are there sealed assumptions that will need breaking changes later?
   - Enums: is there room for new values without restructuring?

## Output Format

```
ISSUE: [description]
FILE: path/to/file.proto:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's wrong, what the API should look like, why]
```
