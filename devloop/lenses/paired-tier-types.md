---
id: paired-tier-types
name: Paired-Tier Type Discipline
tags: [wire-contract, type-discipline, schema-fidelity]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: review
---

# Paired-Tier Type Discipline

When code crosses tier boundaries — proto ↔ pydantic ↔ go ↔ dart, or schema ↔
model ↔ DB — types must align. A `nonce` declared `big.Int` on one side and
`uint64` on the other silently loses precision or accepts malformed values. An
optional field declared `string` + `omitempty` on one side and required on the
other silently coerces empty strings.

`api-design` covers single-tier shape (proto field numbers, REST
backward-compat); this lens covers the **alignment** between paired tiers, where
the mismatch is invisible to either tier alone.

## Process

1. **Identify paired tiers in the diff.** For each new/modified type, list the
   tiers it crosses:
   - proto definition → generated Go / Python / TS / Dart
   - schema → ORM / data model → DB model
   - API request shape → frontend client → backend handler
   - shared library type → CLI command → UI wrapper

2. **For each pair, check type alignment:**
   - **Numeric types.** `nonce` uint64 in proto/Go means uint64 in Pydantic;
     `big.Int` only when the protocol permits >2^63. Mixing forces awkward
     `.String()` ↔ `int.from_str()` plumbing that ages poorly.
   - **Optionality.** `*string` + `omitempty` should match `Optional[str]`
     (omits from JSON when None). Required one side, optional the other → silent
     drop.
   - **Discrimination.** oneof / discriminator unions on the proto side should
     round-trip as tagged-union classes natively, not dicts with sentinel keys.
   - **Container shape.** `map[string]Foo` → `dict[str, FooModel]` /
     `Map<String, Foo>`; `repeated Foo` → `list[FooModel]` / `List<Foo>`. A
     `map[string]any` / `Mapping[str, Any]` usually means the paired type was
     lost in translation.
   - **Enum names.** Same enum across tiers should use the **same value names**
     so no translation dict is needed (see `codebase-idiom`).

3. **For each native type, verify it derives from the contract:**
   - Pydantic class for a paired tier should inherit from the codebase's base
     schema class, not stand alone.
   - Conversion functions (`ToPB` / `FromPB`) should live next to the type they
     convert and consume the canonical contract, not a parallel in-memory shape.

4. **For directional asymmetry, ask if both directions are needed.** A `FromPB`
   in a tier that only consumes the type one-way is dead code (a Go service that
   only emits a proto Safe message doesn't need `safe_intent_frompb.go`).

## Pattern smells

- `big.Int` on a field whose protocol max is `2^64-1` — use uint64.
- `omitempty` on a field declared required by the schema.
- `*string` on a field documented as required.
- Enum-translation dict when the enum values match by name on both sides.
- Discriminator field present in the proto but absent / silently defaulted
  natively.
- `map[string]any` / `Mapping[str, Any]` for a payload with a real shape in
  another tier.
- New `FromPB` / `ToPB` in a tier with no consumer for that direction.

## Severity

- **Minor** — single-tier-pair mismatch with no current consumer (type drift in
  a dormant path).
- **Major** — mismatch that ships will silently misroute data (optional vs
  required), or forces awkward type-juggling at call sites (uint64 vs big.Int).
- **Blocker** — mismatch ships a known data-loss path (precision loss, silent
  enum default), or breaks an in-flight wire contract with an existing consumer.
