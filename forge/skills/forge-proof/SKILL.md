---
name: forge-proof
description:
  "Aggregate the full forge attestation chain: goals → scenarios/validations →
  tests → match → runs → validations-hold."
argument-hint: "[--slug <name>] [--embed]"
triggers:
  - "forge verify"
  - "verify forge chain"
  - "prove forge chain"
  - "prove goals to tests"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
  - WebFetch
practices:
  - code-review
  - tdd
user-invocable: true
---

# /forge-proof — full-chain attestation

Calls each verify skill in order, adds the design layer when `design.md` exists,
emits a single PASS / FAIL + optionally embeds in the PR body.

## Layers

| Layer | Source                         | Skill                       |
| ----- | ------------------------------ | --------------------------- |
| L1    | `goals.md` + PR body           | `/forge-verify-goals`       |
| L2    | `goals.md`                     | `/forge-verify-scenarios`   |
| L3    | `goals.md`, `links.json`       | `/forge-verify-tests`       |
| L4    | `goals.md`, linked test files  | `/forge-verify-match`       |
| L5    | `design.md` (optional)         | **inline** — see below      |
| L6    | `run.json`                     | `/forge-verify-runs`        |
| L7    | `goals.md`, `validations.json` | `/forge-verify-validations` |

Each per-layer skill is canonical for its verdicts and fix recommendations.

**Proof types.** A goal is satisfied by ≥1 proof — a **scenario** (L3/L4/L6:
linked test that runs green) or a **validation** (L7: a command/attestation
predicate that holds). L2 coverage accepts either. Removal/structural goal may
be all-validation (no linked test); behavioral all-scenario; mixed carry both.
L6 and L7 each `SKIPPED` cleanly when their proof type is unused.

## Layer 5 — design coverage (inline)

Runs only when `.pr-artifacts/<slug>/forge/design.md` exists; absent →
`SKIPPED-NO-DESIGN`, no fail. Parse the `## Coverage map` table and each
`### <Component>` block's `- proves: SG<n>.<m>, …` line.

Forward match (per SG):

| Verdict       | Meaning                                            |
| ------------- | -------------------------------------------------- |
| **MAPPED**    | SG appears in coverage map with ≥1 design element. |
| **ORPHAN-SG** | SG in `goals.md` but no row in the coverage map.   |

Back match (per design element):

| Verdict            | Meaning                                                                     |
| ------------------ | --------------------------------------------------------------------------- |
| **CITED**          | Element in `proves:` AND in coverage map for the cited SGs.                 |
| **ORPHAN-ELEMENT** | Component's `proves:` cites SG(s) but element absent from map (or reverse). |
| **DANGLING-SG**    | Coverage map cites an SG no longer in `goals.md`.                           |
| **EMPTY-PROVES**   | Component block has no `proves:` or empty `proves:`.                        |

Structural:

| Verdict             | Meaning                                                      |
| ------------------- | ------------------------------------------------------------ |
| **NO-COVERAGE-MAP** | `design.md` lacks `## Coverage map`. Re-run `/forge-design`. |
| **NO-COMPONENTS**   | `design.md` lacks `### <Component>` blocks. Re-run.          |

L5 PASS = zero ORPHAN-SG / ORPHAN-ELEMENT / DANGLING-SG / EMPTY-PROVES /
NO-COVERAGE-MAP / NO-COMPONENTS.

## Process

1. Resolve slug (argument or branch-derived).
2. Invoke `/forge-verify-goals --slug <slug> --json` → L1 verdict + findings.
   Exit 2 from sub-skill → halt `BLOCKED_NO_GOALS`.
3. Invoke `/forge-verify-scenarios --json`, `/forge-verify-tests --json`,
   `/forge-verify-match --json` in order → L2, L3, L4 verdicts.
4. L5 inline check (skip if no `design.md`).
5. Invoke `/forge-verify-runs --json` → L6 verdict; absent `run.json` →
   `SKIPPED-NO-RUN`, no fail (pre-impl attestation allowed).
6. Invoke `/forge-verify-validations --json` → L7 verdict; no `## Validations`
   anywhere → `SKIPPED-NO-VALIDATIONS`, no fail (scenario-only PRs are normal).
7. Aggregate (see "Verdict logic"). Emit report.
8. If `--embed` AND PR exists: write report between `<!-- forge-proof:begin -->`
   / `<!-- forge-proof:end -->` in PR body, wrapped in collapsed `<details>`
   with a verdict-bearing `<summary>`. Idempotent overwrite via `gh api`. No
   commit, no push, no CI trigger.

   ```
   <!-- forge-proof:begin -->
   <details>
   <summary>🔨 forge — proof: &lt;verdict&gt; · &lt;slug&gt;</summary>

   # /forge-proof result
   …report body…

   </details>
   <!-- forge-proof:end -->
   ```

   This is **one** collapsible block among siblings — review embeds in its own
   `<!-- forge-review -->` block, never inside this one (see /forge-brief §
   Body-layout contract). Touch only between the proof markers; preserve the
   brief and every other block verbatim. No PR → no-op, hint "no PR yet — open
   one then re-run with --embed."

## Report shape

```
# /forge-proof result

verdict: PASS | FAIL
PR: #<num> — <title>
slug: <branch-slug>

## Layer 1 — goals shape + loyalty
structural: PASS | FAIL    loyalty: PASS | FAIL | SKIPPED-NO-PR
<per-Gn loyalty table from /forge-verify-goals>
missing from goals: <list>

## Layer 2 — goal coverage
<per-Gn table from /forge-verify-scenarios>

## Layer 3 — scenario linkage
<per-SG table from /forge-verify-tests + tier sanity>

## Layer 4 — match
<per-SG match table from /forge-verify-match>

## Layer 5 — design coverage   (omit when design.md absent)
<per-SG MAPPED/ORPHAN-SG + per-element CITED/ORPHAN-ELEMENT/DANGLING-SG tables>

## Layer 6 — linked tests pass   (omit when run.json absent)
<per-SG result table from /forge-verify-runs>

## Layer 7 — validations hold   (omit when no validations)
<per-VG result table from /forge-verify-validations>

## smallest blocking set
1. <fix that clears the most failing checks in one move>
2. <next>

## next move
<one concrete suggestion>
```

`## smallest blocking set` is parsed by `/forge-proof-green`; preserve the
section name and Layer + verdict pair per row.

## Verdict logic

- **PASS** — every layer PASS or SKIPPED.
- **FAIL** — any layer FAIL.
- L5 SKIPPED-NO-DESIGN, L6 SKIPPED-NO-RUN, and L7 SKIPPED-NO-VALIDATIONS never
  fail (pre-impl / trivial-PR / proof-type-unused cases).
- A goal must reach ≥1 of its proofs — if a `Gn` has neither a green linked test
  (L6) nor a holding validation (L7), L2 surfaces it as uncovered.
- `PARTIAL / DRIFT / WARN` surface as findings, do not fail.

## Non-goals

- **Not a fixer.** Surfaces findings + the smallest blocking set; never edits
  artifacts. Fix-loop is `/forge-proof-green`.
- **Not a runtime check.** L6 reads `run.json` statically.

## Next step

PASS → `/forge-ci-green`, `/forge-review` (opt-in), `/forge-status`.

FAIL → re-run the failing layer (`/forge-verify-goals` | `-scenarios` | `-tests`
| `-match` | `-runs` | `-validations`) for tighter signal, or
`/forge-proof-green` to auto-fix mechanical findings via fix-loop.

## Usage

```
/forge-proof                              # current branch, console report
/forge-proof --embed                      # also embed report in PR description
/forge-proof --slug auth-refactor         # explicit slug
```
