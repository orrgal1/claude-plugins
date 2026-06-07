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

Review API surface changes (proto, REST, GraphQL, exported Go types, React
props, Pydantic contract models) for design quality and compatibility.

## Process

1. **Identify all API surface changes in the diff:**
   - Proto message/service/RPC definitions
   - REST endpoint paths, methods, request/response bodies
   - Exported Go types, interfaces, function signatures
   - React component props and public APIs
   - Pydantic models mapping to external contracts

2. **Check naming:**
   - Consistent with existing conventions? (grep for similar names)
   - Clear and unambiguous without reading the implementation?
   - Follows language/framework conventions (Go exported names, proto fields)?

3. **Check backward compatibility:**
   - Proto: field numbers unchanged? Enum zero value UNKNOWN/UNSPECIFIED?
     Deprecated fields marked, not removed?
   - REST: existing fields preserved? New required fields additive/defaulted?
   - Can existing clients work without changes?
   - Breaking changes flagged and intentional?

4. **Check design quality:**
   - Exposes implementation detail that should be internal?
   - Optional fields that should be required (or vice versa)?
   - Right granularity (not too coarse, not too chatty)?
   - Follows codebase patterns (oneof for type discrimination, not optional
     fields + nil checks)?

5. **Check extensibility:**
   - Can this evolve without breaking changes?
   - Sealed assumptions needing breaking changes later?
   - Enums: room for new values without restructuring?

## Output Format

```
ISSUE: [description]
FILE: path/to/file.proto:42
SEVERITY: BLOCKER | MINOR
DETAIL: [what's wrong, what the API should look like, why]
```
