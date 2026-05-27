# Lens pool

Reusable lens definitions for forge's lens-designed PR review (`/forge-review`,
`/forge-review-green`). One lens per file; the markdown body is fed verbatim
into a reviewer subagent's brief.

This pool ships **inside the forge plugin** — forge has no dependency on any
other review plugin. A host repo may override or extend it by dropping lens
files into `.forge/lenses/` (same schema); forge prefers a
`.forge/lenses/<id>.md` over the bundled one when both exist.

## File layout

One lens per file. Filename = lens id (slug, lowercase, hyphen-separated):

```
lenses/
  README.md                # this file
  clean-code.md            # id: clean-code
  goal-delivery.md         # id: goal-delivery
  ...
```

No numeric prefix — review skills assign positional labels (L0, L1, …) at
composition time, so adding a lens never renumbers existing ones.

## File schema

YAML frontmatter + markdown body.

```markdown
---
id: clean-code
name: Clean Code (Martin)
tags: [code-quality, hygiene, martin]
requires: diff
severity-floor: minor
brief-artifacts: []
introduced-by: forge-review
---

# Clean Code (Martin)

<lens body — principles, smells, severity ladder. Fed verbatim into the subagent
brief.>
```

### Frontmatter fields

| Field             | Type   | Meaning                                                                                                                                                                                                                      |
| ----------------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`              | slug   | Stable identifier. Must match filename (`<id>.md`). Referenced by personas + review skills.                                                                                                                                  |
| `name`            | string | Human-readable label used in consultation-gate proposals and synthesis output.                                                                                                                                               |
| `tags`            | list   | Free-form categorization (`code-quality`, `security`, `chain-semantic`, …). Used by the consultation-gate picker for filtering / suggestion.                                                                                 |
| `requires`        | enum   | What the lens needs to operate: `diff` (PR diff only), `forge-chain` (needs `goals.md` and/or `links.json`), or `both`. A review without a chain MUST skip `forge-chain` lenses.                                             |
| `severity-floor`  | enum   | Lowest severity a finding can carry by default: `blocker`, `major`, `minor`, `nit`. The body may raise above the floor.                                                                                                      |
| `brief-artifacts` | list   | Forge-chain artifacts to inject verbatim into the subagent brief when this lens is selected. Allowed: `goals.md`, `links.json`, `pr-description`, `linked-test-files`, `full-diff`, `commentary-surface`. Empty = diff only. |
| `introduced-by`   | string | Which skill / persona introduced this lens. Free text — helps trace provenance as the pool grows.                                                                                                                            |

### Body

The markdown body after the frontmatter is the **lens text fed verbatim into the
subagent brief**. Write it in the second person ("read every changed function")
or as a checklist. The fan-out agent (`@orrgal1/forge:forge-lens-reviewer`)
treats this text as its operating prompt for the lens.

Keep it self-contained. The agent receives only the lens body plus PR scope +
any `brief-artifacts` payload; it doesn't see this README.

## How consumers reference lenses

A review skill's "always-on" or "designed" lens list cites pool ids:

```
Proposed lenses (M total):
  L0  goal-delivery           (always-on; requires forge-chain)
  L1  scenario-realism        (always-on; requires forge-chain)
  L2  test-match              (always-on; requires forge-chain)
  L3  clean-code              (always-on; baseline)
  ...
```

The L-label is positional within that review; `clean-code` is the stable pool
id.

## Persona references

Persona files (`personas/*.md`, or `.forge/personas/*.md`)
list `lenses:` by id:

```yaml
lenses: [clean-code, robustness, observability, api-design]
```

A persona must only reference lens ids that exist in the pool (bundled or
`.forge/`-supplied); a missing id is a hard error at review time.

## Adding a lens

1. Pick a slug. Reuse existing tag vocabulary so personas can find it by tag.
2. Drop `<slug>.md` here (or in `.forge/lenses/` for a repo-local lens) with
   frontmatter + body.
3. Decide `requires` honestly. A lens that needs `goals.md` but declares
   `requires: diff` silently produces useless findings on chains lacking those
   artifacts.
4. Set `severity-floor` by what the lens catches. Hygiene → `minor`; correctness
   / security → `major` or `blocker`.
5. Wire it into a review skill's default list if it should be always-on. The
   pool itself does not auto-wire lenses.

## Designing per-PR lenses (heuristics)

`/forge-review` designs 1–3 ad-hoc lenses per PR against the diff's risk
surface. These start inline (per-review) and only get promoted into this pool
when the same shape recurs across enough PRs. Common shapes to draw from:

- **Wire contract** — proto slots, reserved ranges, oneof shape, additive-only
  guarantees, API request/response shape.
- **Schema fidelity** — paired schemas (proto ↔ model ↔ TS, OpenAPI ↔ client, DB
  ↔ model) match 1:1: field names, optionality, types.
- **Mapping / dispatch invariants** — every input path projected to an output
  path; XOR / mutual-exclusion enforced; no silent defaults on required fields.
- **Coupling + side-effects** — what calls what, recursion safety, DI points.
- **Test fidelity** — assert observable contract not implementation; coverage
  matrix vs variants; gaps acknowledged explicitly.
- **Naming / public surface** — final names stable after rename rounds; public ↔
  internal names disagree only intentionally.
- **Wire-up symmetry** — when a feature lands at N call sites, every site wired
  up; no "all N forgot" patterns.

**Sizing:** 3–7 designed lenses (with always-on lenses, total lands in the 7–9
sweet spot). **Distinct angles:** each lens must catch something a file-by-file
pass would miss — if two would surface the same finding, merge them.

## Non-goals

- **Not an ordering registry.** No canonical L-numbering; review skills order
  lenses per-invocation.
- **Not a behavior contract.** Lens body wording can be tuned without breaking
  consumers as long as `id` and `requires` stay stable.
- **Not for ad-hoc per-PR designed lenses.** Those are inline; promote to the
  pool only when a shape recurs across PRs.
