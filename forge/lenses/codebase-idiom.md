---
id: codebase-idiom
name: Codebase Idiom / Pattern Convergence
tags: [code-quality, convergence, pattern-recurrence]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Codebase Idiom / Pattern Convergence

Does the new code converge on an existing pattern, or invent a parallel
mechanism where the established one fits? Flag any new shape that duplicates a
problem the codebase already solved — and cite the canonical site by URL or
`path:line` so the author copies from it rather than re-derives.

## Process

1. **Identify each new mechanism in the diff.** A new helper, base class,
   conversion function, enum-translation dict, builder, factory, validator —
   anything solving a problem in a new shape.

2. **For each, search for the established analogue:**
   - Same problem in a sibling file (`<feature>_schemas.py` vs
     `safe_intent_schemas.py`, `transaction_type.go` vs `safe_intent.go`).
   - Conversion / dispatch patterns in use (enums whose proto + native values
     match by name so no dict is needed).
   - Base-class + child-class pattern where the child calls the parent builder
     and adds its own fields, not duplicating the parent's wiring.
   - Tier-spanning conversion helpers stored adjacent to the struct they convert
     (each `ToPB` next to its struct, not in a separate file).
   - Cross-tier type discipline already enforced elsewhere — see the
     `paired-tier-types` lens.

3. **For each divergence, decide:**
   - Established pattern fits → flag and cite the canonical example. Promote to
     **major** if the divergence multiplies (new file adds 3+ dicts where
     same-named enums would suffice).
   - Established pattern doesn't fit (new shape, new tier, novel mechanism) → no
     finding; optionally note why divergence is justified.

## Pattern smells

- Enum-translation dicts where enum values are already same-named across tiers —
  drop the dict.
- New file holding `*ToPB` / `*FromPB` away from the struct they convert, when
  the codebase keeps conversions adjacent.
- A new builder copying the parent class's wiring inline rather than delegating.
- A `FromPB` emitted in a tier (e.g. Go) for a type with no consumer in that
  direction — convention may put conversion only in the API layer.
- Validation / try-catch at a layer that already has a generic equivalent
  upstream — silently duplicates handling.

## Heuristics for finding the canonical site

- Search by problem keyword, not solution name. "How does the codebase translate
  `<enum>` between proto and native?" → grep `_PB_TO_` / `pb_to_` / enum maps.
- When the author says "I needed a translation map", grep the most similar
  feature's schema file — they usually didn't need it either.
- Cite the canonical site as `path:line` or repo URL. Don't make the author
  re-derive the pattern from a hint.

## Severity

- **Minor** — single-instance divergence, easy local fix.
- **Major** — divergence multiplies (next PR copies it), sits at a tier-boundary
  where it leaks into callers, or rewrites a builder/factory pattern other
  features won't match.
- **Blocker** — only when the divergence ships a correctness gap (a new enum
  translation that silently misses a value the canonical version handles).
