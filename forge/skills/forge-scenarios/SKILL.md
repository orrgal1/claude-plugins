---
name: forge-scenarios
argument-hint: "[--slug <name>] [--goal G<n>]"
triggers:
  - "forge scenarios"
  - "draft scenarios for goals"
  - "cover goals with scenarios"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
practices:
  - tdd
user-invocable: true
---

# /forge-scenarios — scenarios per goal

Second link. Scenarios live **inline** under the goal they cover — one file, one
source of truth.

## Scenario shape

```
- SG<n>.<m>
  - when: <one-sentence situation>
  - then: <one-sentence observable outcome>
  - test: `<relative/path/to_test.go>::<TestFunctionName>`
  - tier: <component|integration|e2e|blackbox|qa>
```

Sub-bullets, not bare indented `key: value` — prettier (the markdown formatter
on most pre-commit hooks) reflows bare indented continuation lines into one
wrapped paragraph and destroys the scenario. Sub-bullets are prettier-safe.

`test:` path wrapped in backticks — inline code spans never wrap, so the path
stays atomic across prettier's 80-col reflow.

Before `/forge-tests` runs: header + `when:` + `then:` only. After: append
`- test:` + `- tier:`. **Test code carries only `when:` / `then:` comments**;
the back-link lives in `goals.md`, not in test source.

Parsers tolerate any whitespace inside each line. Downstream regexes accept
canonical + legacy bare-indented form:

- scenario header: `^- SG\d+\.\d+\s*$`
- when line: `^\s+(-\s+)?when:\s+.+$`
- then line: `^\s+(-\s+)?then:\s+.+$`
- test line: ``^\s+(-\s+)?test:\s+`?\S+::\S+`?\s*$``
- tier line: `^\s+(-\s+)?tier:\s+\S+\s*$`

ID = `SG<n>.<m>`: `SG2.1` is the first scenario under `G2`. Hierarchy keeps goal
link explicit, survives goal additions, and lets downstream skills enumerate by
grep (`^- SG\d+\.\d+`). `when:` / `then:` content rules in § "What goes into
`when:` / `then:`".

## Coverage rule

Scenarios are complete when:

- Every `Gn` has ≥1 scenario.
- No scenario is orphaned (every lives under a real `Gn`).
- Each `then:` is specific enough to be observed. "Works correctly" doesn't
  count — name the surface.

## Scope rule — endpoint behavior only

A scenario describes a high-level concern. By definition, the `then:` is
exposable by hitting the actual service endpoint — HTTP response, RPC result,
queue message, persisted record, log line, metric, render output.

NOT scenarios:

- "Returns from private method X with value Y." Internal mechanic.
- "Field `cache.lastRefresh` becomes Z." Internal state.
- "Function W is called." Implementation detail.

If the only honest `then:` is internal, it's not a scenario — it's a unit-level
concern. Promote the closest endpoint-visible consequence into the `then:`, or
drop the scenario.

Consequence: every scenario gets a **component-or-higher tier test**.
`/forge-tests` rejects unit-tier attachment for any SG. `/forge-audit`
re-checks; this skill establishes on first authoring.

## Process

1. Resolve slug (argument, branch, or the only
   `.pr-artifacts/*/forge/goals.md`).
2. Read `goals.md`. Enumerate `Gn` via `^## G\d+ —`. Missing file → exit "run
   /forge-goals first".
3. **Harvest** existing `when:` / `then:` from the PR diff (see § "Harvest"
   below) — operators often write annotations before formalizing.
4. **For each goal** (or `--goal G<n>` only):
   - Read existing `## Scenarios` block if present (edit mode).
   - Pre-fill from harvested scenarios matching this goal.
   - Draft new scenarios as needed (see § "Sizing").
   - Renumber within-goal: `SG<n>.1`, `SG<n>.2`, …; existing IDs stable, new
     ones append.
5. Surface orphan harvest matches; block write until each is resolved.
6. **Write scenarios inline** in canonical sub-bullet shape. Insert
   `## Scenarios` block immediately under each goal's body.
7. **Forge narration** — between goal body and `## Scenarios`, add a
   `### How the scenarios prove this` section. Plain-English paragraph tying SGs
   (`SG<n>.<m>` or ranges like `SG1.1–SG1.5`) to the goal's end-state.
   Reviewer-facing only — not parsed by downstream skills. Rewrite when
   scenarios change.
8. **Publish goals.md** (only-goals-tracked policy):

   ```bash
   gi=".pr-artifacts/.gitignore"
   gm=".pr-artifacts/${slug}/forge/goals.md"
   if [ ! -f "$gi" ]; then
     cat > "$gi" <<'EOF'
   # Forge: ignore everything under <slug>/forge/ except shared review surfaces.
   */forge/*
   !*/forge/goals.md
   !*/forge/design.md
   EOF
   fi
   if git check-ignore -q "$gm"; then
     git add -f "$gi" "$gm"
     git commit -m "forge-scenarios: update review artifact"
   fi
   ```

9. Recap — per-goal counts (harvested vs new), orphan resolutions, then
   `→ /forge-tests next`.

## Harvest

Operators often write `when:` / `then:` on tests before formalizing. Don't make
them re-state.

**Scope:** PR diff only (`gh pr diff --name-only` filtered to test paths +
non-test files where the diff added annotations to an existing test). Out: tests
that already had `when:` / `then:` before this PR opened.

**Extract:** language-aware grep for the `when:` / `then:` annotation shape
directly above a test function. Capture `{file, function, when, then}`. If a
prior chain run already linked this test (look up path in existing `goals.md`),
trust the link.

**Match each candidate to a goal:**

- **CONFIDENT** — `then:` directly observes the goal's end-state. Auto-assign.
- **LIKELY** — plausible match but two+ goals could own it. Ask operator.
- **ORPHAN** — no goal credibly covers this `then:`.

**Orphan resolution** (blocks write):

```
N existing test annotations don't match any goal:

  [1] path/to/foo_test.go::TestFoo_RejectsEmpty
      when: input is empty   then: returns ErrEmpty

For each:
  [a] add a new goal (routes back to /forge-goals)
  [b] map to an existing goal (specify which)
  [c] drop (stale / out of scope)
  [d] keep as orphan — TODO under ## Orphan scenarios (WARN at audit, no block)
```

Choice `[a]` halts, re-run `/forge-goals` first. Choice `[d]` is the escape
hatch.

**Promote to scenarios** — CONFIDENT + LIKELY-accepted candidates:

- Allocate next `SG<n>.<m>` under matched goal.
- Promote `when:` / `then:` verbatim.
- Cache back-link in `.pr-artifacts/<slug>/forge/.harvest.json`:

  ```json
  {
    "SG1.2": {
      "test_path": "pkg/foo/foo_test.go",
      "function": "TestFoo_RejectsEmpty",
      "source": "harvest"
    }
  }
  ```

  `/forge-tests` reads this and skips its search step.

## Sizing — right-size, not maximize

Target the **smallest set that proves the goal**. The chain proves the feature,
not characterizes every code path; branch coverage is a separate concern.

Typical goal: **2-5 scenarios**. Wider needs justification — every scenario
encodes a distinct observable outcome. Same surface + same `then:` with
different inputs → merge.

Checklist for completeness (not a quota — skip ones that don't apply):

- **Happy path** — canonical situation. Almost always exactly one.
- **Stated edges** — edges the goal explicitly names. One per stated edge.
- **Implicit edges** — boundaries that change observable behavior. Skip ones the
  happy path already covers.
- **State variations** — only when the goal references a state machine and
  states produce different outcomes.
- **Negative-space** — when the goal's surface must visibly refuse.

Self-check per candidate scenario:

1. Does reviewer learn something new from this `then:`?
2. Can this merge with another by parameterizing?
3. If removed, would the chain visibly miss a property the goal claims?

No / yes / no → don't add.

Signals: <2 on non-trivial goal = under-specified; >5 = goal too big (route to
`/forge-goals` to split) or you're enumerating coverage cases; doesn't fit in
your head reading top-to-bottom = over-specified.

## What goes into `when:` / `then:`

- `when:` — the **situation** (inputs, state, actor, trigger). One sentence. No
  assertion language.
- `then:` — the **outcome observable from outside** (return value, error code,
  event, state mutation, response shape). No "calls X with Y" leaks.

Internal-only `then:` ("the cache is warmed", "the mutex held") → flag as
too-internal. Restate in externally observable terms, or move tier down (if you
must observe internals it's a unit-tier concern — but scenarios reject unit per
§ "Scope rule").

## Output shape (excerpt)

Rendered plain-code-fenced so prettier doesn't reflow the example. The
**rendered goals.md** uses sub-bullets specifically because they're
prettier-safe.

```
## G1 — <short name> (main)

When this PR ships, the system will support <capability>.

### How the scenarios prove this

<Plain-English paragraph tying SG1.1–SG1.3 back to the goal.>

## Scenarios

- SG1.1
  - when: <situation>
  - then: <observable outcome>
  - test: `pkg/x/foo_test.go::TestFoo_HappyPath`
  - tier: component
- SG1.2
  - when: <situation>
  - then: <observable outcome>
  (no - test: / - tier: yet — /forge-tests hasn't run for this scenario)
```

The `## Scenarios` header under each goal is **load-bearing** — parsed by
`/forge-tests` and `/forge-audit`. Don't rename, don't merge into goal body.

## Next step

- `/forge-tests` — typical next phase
- `/forge-status` — chain state + drift

## Usage

```
/forge-scenarios                   # all goals, current branch
/forge-scenarios --goal G2         # only G2
/forge-scenarios --slug auth-refactor
```
