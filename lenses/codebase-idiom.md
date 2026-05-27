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

Does the new code converge on an existing pattern in the repository, or does it
invent a parallel mechanism where the established one fits? Reviewers who care
about this lens flag any new shape that duplicates a problem the codebase has
already solved — and they usually cite the canonical site by URL or `path:line`
so the author can copy from it rather than re-derive.

## Process

1. **Identify each new mechanism in the diff.** A new helper, base class,
   conversion function, enum-translation dict, builder, factory, validator —
   anything that solves a problem in a new shape.

2. **For each, search the codebase for the established analogue.**
   - Same problem solved in a sibling file (`<feature>_schemas.py` vs
     `safe_intent_schemas.py`, `transaction_type.go` vs `safe_intent.go`).
   - Conversion / dispatch patterns already in use (enums whose proto + native
     values match by name so no dict translation is needed).
   - Base-class + child-class pattern where the child calls the parent builder
     and adds its own fields, instead of duplicating the parent's wiring.
   - Tier-spanning conversion helpers stored adjacent to the struct they convert
     (each `ToPB` next to its struct, not in a separate file).
   - Cross-tier type discipline already enforced elsewhere — see the
     `paired-tier-types` lens.

3. **For each divergence, decide.**
   - Established pattern fits → flag and cite the canonical example. Promote to
     **major** if the divergence multiplies (new file adds 3+ new dicts where
     same-named enums would have sufficed).
   - Established pattern doesn't fit (new problem shape, new tier, genuinely
     novel mechanism) → no finding; optionally note why divergence is justified
     so future readers don't try to converge back.

## Pattern smells

- Enum-translation dicts where the enum values are already same-named across
  tiers — drop the dict.
- New file holding `*ToPB` / `*FromPB` functions away from the struct they
  convert, when the codebase consistently keeps conversions adjacent to the
  type.
- A new builder that copies the parent class's wiring inline rather than
  delegating to the parent.
- A "FromPB" emitted in a tier (e.g. Go) for a type that has no consumer in that
  direction — convention may say that conversion lives only in the API layer.
- Validation / try-catch added at a layer that already has a generic equivalent
  upstream — silently duplicates handling.

## Heuristics for finding the canonical site

- Search by problem keyword, not solution name. "How does the codebase translate
  `<enum>` between proto and native?" → grep for `_PB_TO_` / `pb_to_` /
  enum-string maps.
- When the author says "I needed a translation map", grep for the most similar
  feature's schema file — they usually didn't need it either.
- Cite the canonical site as `path:line` or repo URL in the finding. The author
  shouldn't have to re-derive the pattern from a hint.

## Severity

- **Minor** — single-instance divergence, easy local fix.
- **Major** — divergence multiplies (new mechanism will be copied by next PR),
  divergence sits at a tier-boundary where it will leak into callers, divergence
  rewrites a builder/factory pattern in a way that other features will not
  match.
- **Blocker** — only when the divergence ships a correctness gap (e.g. a new
  enum translation that silently misses a value the canonical version handles).
