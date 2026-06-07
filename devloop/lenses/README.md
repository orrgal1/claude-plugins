# Lens pool

Reusable lens definitions for forge's lens-designed PR review (`/review`,
the review fix-loop). One lens per file; the markdown body is fed verbatim
into a reviewer subagent's brief.

Ships **inside the forge plugin** — no dependency on any other review plugin. A
host repo overrides/extends by dropping lens files into `.forge/lenses/` (same
schema); forge prefers a `.forge/lenses/<id>.md` over the bundled one.

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
introduced-by: review
---

# Clean Code (Martin)

<lens body — principles, smells, severity ladder. Fed verbatim into the subagent
brief.>
```

### Frontmatter fields

| Field             | Type   | Meaning                                                                                                                                                                                                |
| ----------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `id`              | slug   | Stable identifier. Must match filename (`<id>.md`). Referenced by personas + review skills.                                                                                                            |
| `name`            | string | Human-readable label in consultation-gate proposals + synthesis output.                                                                                                                                |
| `tags`            | list   | Free-form categorization (`code-quality`, `security`, `chain-semantic`, …). Used by the consultation-gate picker for filtering / suggestion.                                                           |
| `requires`        | enum   | What the lens needs: `diff` (PR diff only), `forge-chain` (needs `goals.md` and/or `links.json`), or `both`. A review without a chain MUST skip `forge-chain` lenses.                                  |
| `severity-floor`  | enum   | Lowest default severity: `blocker`, `major`, `minor`, `nit`. The body may raise above the floor.                                                                                                       |
| `brief-artifacts` | list   | Forge-chain artifacts to inject verbatim into the brief when selected. Allowed: `goals.md`, `links.json`, `pr-description`, `linked-test-files`, `full-diff`, `commentary-surface`. Empty = diff only. |
| `introduced-by`   | string | Which skill / persona introduced this lens. Free text — traces provenance.                                                                                                                             |

### Body

The body after the frontmatter is the **lens text fed verbatim into the subagent
brief**. Write it second-person ("read every changed function") or as a
checklist. The fan-out agent (`@orrgal1/devloop:lens-reviewer`) treats this
as its operating prompt.

Keep it self-contained. The agent receives only the lens body plus PR scope +
any `brief-artifacts` payload; it doesn't see this README.

## How consumers reference lenses

A review skill's composed lens list cites pool ids, tagged by selection tier
(see `review-channels/lens-fanout.md` § Selection):

```
Proposed lenses (M total):
  L0  clean-code              (tier-1 core)
  L1  correctness             (tier-1 core)
  L2  goal-delivery           (tier-2 chain; requires forge-chain)
  L3  production-wiring       (tier-3 auto; diff adds new components)
  L4  test-quality            (tier-3 auto; diff changes tests)
  ...
```

The L-label is positional within that review; `clean-code` is the stable pool
id.

## Persona references

Persona files (`personas/*.md`, or `.forge/personas/*.md`) list `lenses:` by id:

```yaml
lenses: [clean-code, robustness, observability, api-design]
```

A persona must only reference lens ids that exist in the pool (bundled or
`.forge/`-supplied); a missing id is a hard error at review time.

## Adding a lens

1. Pick a slug. Reuse existing tag vocabulary so personas find it by tag.
2. Drop `<slug>.md` here (or in `.forge/lenses/` for repo-local) with
   frontmatter + body.
3. Decide `requires` honestly. A lens needing `goals.md` but declaring
   `requires: diff` silently produces useless findings on chains lacking those
   artifacts.
4. Set `severity-floor` by what it catches. Hygiene → `minor`; correctness /
   security → `major` or `blocker`.
5. Wire it into a tier in `review-channels/lens-fanout.md` § Selection — Tier 1
   (always-on core), Tier 2 (chain-conditional), or Tier 3 (a diff-fingerprint
   row, below). The pool does not auto-wire lenses.

## Diff fingerprint → lens

Tier 3 lenses fire only when the diff touches their surface. The dispatcher
fingerprints the diff at composition time; a lens fires if ANY trigger matches.

| Lens                | Fingerprint triggers                                                                                                                                                    |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `production-wiring` | a new interface with an impl, a new constructor/factory, endpoint/route registration, a background job or scheduler entry, a feature-flag definition, or a DB migration |
| `paired-tier-types` | edits to cross-tier type defs: `.proto`, pydantic/dataclass models, ORM schema, OpenAPI specs, generated or hand-written TS API types                                   |
| `api-design`        | public API surface — route definitions, request/response DTOs, exported client methods, versioned endpoints                                                             |
| `observability`     | service code with failure/error paths, async/background work, retries, or outbound external calls (oncall-relevant)                                                     |
| `test-quality`      | any new or changed test file                                                                                                                                            |

Keep triggers conservative — a lens that fires on everything is an expensive
always-on lens. If a surface recurs on most PRs, promote the lens to Tier 1
instead of widening triggers.

## Designing per-PR lenses (heuristics)

With Tier 1–3 covering recurring surfaces, per-PR designed lenses are the
**exception** (0–2) — reach for one only when a PR carries a risk no pool lens
captures. They start inline and get promoted into the pool (and a tier) only
when the same shape recurs. Common shapes:

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

**Sizing:** a review's lens set = Tier 1 core (always) + matched Tier 2/3 +
persona + 0–2 designed. The dispatcher dedups, so the working set stays focused;
no fixed total cap, but each lens costs one parallel subagent and feeds the
all-severity fix loop, so don't add a lens that duplicates a selected one.
**Distinct angles:** each lens must catch something a file-by-file pass would
miss — if two would surface the same finding, merge them.

## Non-goals

- **Not an ordering registry.** No canonical L-numbering; review skills order
  lenses per-invocation.
- **Not a behavior contract.** Lens body wording can be tuned without breaking
  consumers as long as `id` and `requires` stay stable.
- **Not for ad-hoc per-PR designed lenses.** Those are inline; promote to the
  pool only when a shape recurs across PRs.
