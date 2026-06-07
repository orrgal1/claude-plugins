---
name: forge-scenarios
description: "Draft when/then scenarios covering each goal."
argument-hint: '[--slug <name>] [--goal G<n>] [--iterate "<feedback>"] [--push]'
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

Sub-bullets, not bare indented `key: value` — prettier reflows bare indented
continuation lines into one wrapped paragraph, destroying the scenario;
sub-bullets are prettier-safe. `test:` path in backticks — inline code spans
never wrap, so the path stays atomic across prettier's 80-col reflow.

Before `/forge-tests`: header + `when:` + `then:` only. After: append `- test:`

- `- tier:`. **Test code carries only `when:` / `then:` comments**; the
  back-link lives in `goals.md`, not test source.

Parsers tolerate any whitespace per line. Downstream regexes accept canonical +
legacy bare-indented form:

- scenario header: `^- SG\d+\.\d+\s*$`
- when line: `^\s+(-\s+)?when:\s+.+$`
- then line: `^\s+(-\s+)?then:\s+.+$`
- test line: ``^\s+(-\s+)?test:\s+`?\S+::\S+`?\s*$``
- tier line: `^\s+(-\s+)?tier:\s+\S+\s*$`

ID = `SG<n>.<m>`: `SG2.1` is the first scenario under `G2`. Hierarchy keeps the
goal link explicit, survives goal additions, lets downstream skills enumerate by
grep (`^- SG\d+\.\d+`). Content rules in § "What goes into `when:` / `then:`".

## Coverage rule

Scenarios complete when:

- Every `Gn` has ≥1 **proof** — a scenario here, or a validation under
  `## Validations` (`/forge-validations`). A removal/structural goal may have
  **zero scenarios**, fully proven by validations — not an uncovered goal.
  Behavioral goals still want ≥1 scenario.
- No scenario orphaned (each lives under a real `Gn`).
- Each `then:` specific enough to observe. "Works correctly" doesn't count —
  name the surface.

## Scope rule — endpoint behavior only

A scenario's `then:` is exposable by hitting the actual service endpoint — HTTP
response, RPC result, queue message, persisted record, log line, metric, render
output.

NOT scenarios (internal → unit-level concern, not a scenario):

- "Returns from private method X with value Y." Internal mechanic.
- "Field `cache.lastRefresh` becomes Z." Internal state.
- "Function W is called." Impl detail.

Only-honest-`then:`-is-internal → promote the closest endpoint-visible
consequence into the `then:`, or drop the scenario.

Consequence: every scenario gets a **component-or-higher tier test**.
`/forge-tests` rejects unit-tier attachment; `/forge-proof` re-checks; this
skill establishes on first authoring.

## Process

1. Resolve slug (argument, branch, or the only
   `$FORGE_ART/branches/*/goals.md`).
2. Read `goals.md`. Enumerate `Gn` via `^## G\d+ —`. Missing file → exit "run
   /forge-goals first".
3. **Harvest** existing `when:` / `then:` from the PR diff (§ "Harvest").
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
   `### How the scenarios prove this` section: **≤2 sentences** tying SGs
   (`SG<n>.<m>` or ranges `SG1.1–SG1.5`) to the goal's end-state.
   Reviewer-facing only, not parsed downstream. Phrases over prose; no restating
   each scenario — the SG list already says it. Rewrite when scenarios change.
8. **Publish goals.md** (tracked per `[artifacts].track`) — gitignore
   bootstrap + force-add-if-ignored per `/forge-goals` §5, commit msg
   `forge-scenarios: update review artifact`.
9. **`--push`** (orchestrator entry, before `AWAIT_SCENARIOS_REVIEW`) — push
   gate per `/forge-goals` §6.

10. Recap — per-goal counts (harvested vs new), orphan resolutions, then
    `→ /forge-tests next` (or `→ AWAIT_SCENARIOS_REVIEW` when
    orchestrator-driven).

## Iterate mode — `--iterate "<feedback>"`

Triggered by `/forge` from `AWAIT_SCENARIOS_REVIEW`. Free-text feedback.

1. Read existing `goals.md` (missing → exit `BLOCKED_ITERATE_NO_FILE`).
2. Apply feedback directly — no dialogue. Stay inside Sizing rules.
3. Preserve `SG<n>.<m>` IDs across edits (Edit mode rule).
4. Re-write inline + re-commit per §6–§8.
5. `--push` (orchestrator default) per §9.
6. Recap with `iterated on: <feedback summary>` tail.

Orchestrator re-settles `AWAIT_SCENARIOS_REVIEW` after push.

## Harvest

Operators often write `when:` / `then:` on tests before formalizing — don't make
them re-state.

**Scope:** PR diff only (`gh pr diff --name-only` filtered to test paths +
non-test files where the diff added annotations to an existing test). Out: tests
that already had `when:` / `then:` before this PR opened.

**Extract:** language-aware grep for the `when:` / `then:` shape directly above
a test function. Capture `{file, function, when, then}`. Prior chain run already
linked this test (path in existing `goals.md`) → trust the link.

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
  [d] keep as orphan — TODO under ## Orphan scenarios (WARN at proof, no block)
```

Choice `[a]` halts, re-run `/forge-goals` first. Choice `[d]` is the escape
hatch.

**Promote to scenarios** — CONFIDENT + LIKELY-accepted candidates:

- Allocate next `SG<n>.<m>` under matched goal.
- Promote `when:` / `then:` verbatim.
- Cache back-link in `$FORGE_ART/branches/<slug>/.harvest.json`:

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
not every code path; branch coverage is separate.

Typical goal: **2-5 scenarios**. Wider needs justification — each scenario
encodes a distinct observable outcome. Same surface + same `then:`, different
inputs → merge.

Completeness checklist (not a quota — skip non-applicable):

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

Internal-only `then:` ("the cache is warmed", "the mutex held") → flag
too-internal. Restate in externally observable terms (observing internals is a
unit-tier concern — scenarios reject unit per § "Scope rule").

## Output shape (excerpt)

Rendered plain-code-fenced so prettier doesn't reflow the example. The
**rendered goals.md** uses sub-bullets specifically because they're
prettier-safe.

```
## G1 — <short name> (main)

When this PR ships, the system will support <capability>.

### How the scenarios prove this

<≤2 sentences tying SG1.1–SG1.3 back to the goal. No per-scenario restatement.>

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
`/forge-tests` and `/forge-proof`. Don't rename, don't merge into goal body.

## Next step

- `/forge-tests` — typical next phase
- `/forge-validations` — proofs for any removal / structural goal (no runtime
  observable)
- `/forge-status` — chain state + drift

## Usage

```
/forge-scenarios                   # all goals, current branch
/forge-scenarios --goal G2         # only G2
/forge-scenarios --slug auth-refactor
```
