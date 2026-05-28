---
name: forge-audit
description: "Aggregate the full forge attestation chain: goals → scenarios → tests → match → runs."
argument-hint: "[--slug <name>] [--embed]"
triggers:
  - "forge verify"
  - "verify forge chain"
  - "audit forge chain"
  - "audit goals to tests"
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

# /forge-audit — full-chain attestation

Aggregator. Calls each verify skill in order, adds the design layer when
`design.md` exists, emits a single PASS / FAIL + optionally embeds in the PR
body.

## Layers

| Layer | Source                        | Skill                     |
| ----- | ----------------------------- | ------------------------- |
| L1    | `goals.md` + PR body          | `/forge-verify-goals`     |
| L2    | `goals.md`                    | `/forge-verify-scenarios` |
| L3    | `goals.md`, `links.json`      | `/forge-verify-tests`     |
| L4    | `goals.md`, linked test files | `/forge-verify-match`     |
| L5    | `design.md` (optional)        | **inline** — see below    |
| L6    | `run.json`                    | `/forge-verify-runs`      |

Each per-layer skill is the canonical reference for its verdicts and fix
recommendations.

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
6. Aggregate (see "Verdict logic"). Emit report.
7. If `--embed` AND PR exists: write report between `<!-- forge-audit:begin -->`
   / `<!-- forge-audit:end -->` in PR body, wrapped in collapsed `<details>`
   with a verdict-bearing `<summary>`. Idempotent overwrite via `gh api`. No
   commit, no push, no CI trigger.

   ```
   <!-- forge-audit:begin -->
   <details>
   <summary>🔨 forge — &lt;verdict&gt; · &lt;slug&gt;</summary>

   # /forge-audit result
   …report body…

   </details>
   <!-- forge-audit:end -->
   ```

   No PR → no-op with hint "no PR yet — open one then re-run with --embed."

## Report shape

```
# /forge-audit result

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

## smallest blocking set
1. <fix that clears the most failing checks in one move>
2. <next>

## next move
<one concrete suggestion>
```

`## smallest blocking set` is parsed by `/forge-audit-green`; preserve the
section name and Layer + verdict pair per row.

## Verdict logic

- **PASS** — every layer PASS or SKIPPED.
- **FAIL** — any layer FAIL.
- L5 SKIPPED-NO-DESIGN and L6 SKIPPED-NO-RUN never fail (pre-impl / trivial-PR
  cases).
- `PARTIAL / DRIFT / WARN` surface as findings, do not fail.

## Non-goals

- **Not a fixer.** Surfaces findings + the smallest blocking set; never edits
  artifacts. The fix-loop is `/forge-audit-green`.
- **Not a runtime check.** L6 reads `run.json` statically.

## Next step

PASS → drive CI green, optionally review.

- `/forge-ci-green`
- `/forge-review` (opt-in)
- `/forge-status` — chain state + drift

FAIL → re-run the specific failing layer for tighter signal:

- `/forge-verify-goals` | `-scenarios` | `-tests` | `-match` | `-runs`
- `/forge-audit-green` — auto-fix mechanical findings via fix-loop

## Usage

```
/forge-audit                              # current branch, console report
/forge-audit --embed                      # also embed report in PR description
/forge-audit --slug auth-refactor         # explicit slug
```
