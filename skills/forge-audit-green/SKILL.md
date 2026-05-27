---
name: forge-audit-green
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "forge audit green"
  - "drive forge audit to green"
  - "fix audit findings"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Agent
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-audit-green — drive structural audit to PASS

Wraps `/forge-audit` in a fix-loop. Each iteration: read smallest blocking set,
apply the named one-step fix (or route to the right sub-skill), commit,
re-audit. Sister to `/forge-ci-green` + `/forge-impl-green`.

## Inputs

| Input     | Default               |
| --------- | --------------------- |
| `--slug`  | sanitized branch name |
| `max=<N>` | `10`                  |

## Chain-contract guard

Each per-iteration patch is checked before it lands. **Refuse** if it touches:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `.pr-artifacts/<slug>/forge/goals.md`   | Goals + scenarios are the spec.                              |
| `.pr-artifacts/<slug>/forge/links.json` | Linkage is the chain — don't repoint to silence Layer-4.     |
| Linked test bodies (assertions)         | `assert:` is the contract. (Comments + AAA markers OK.)      |
| `.pr-artifacts/<slug>/forge/design.md`  | Design records intent; rewriting to absorb Layer-5 is drift. |

Refusal → settle `BLOCKED_CONTRACT`. Operator addresses the contract via
`/forge-scenarios`, `/forge-tests`, `/forge-goals`, `/forge-design`.

Non-contract surfaces (impl source, test `when:` / `then:` comments, AAA
markers, tier notes, coverage map cells for SGs already in `goals.md`) are fair
game.

## Findings → fix mapping

`/forge-audit` emits `## smallest blocking set` (preserve verbatim — this loop
parses it). Per row:

| Layer + verdict                             | One-step fix                                                                                   |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Layer 1 — structural FAIL (any)             | Halt `BLOCKED_CONTRACT` — goals shape is operator-iterate via `/forge-goals`.                  |
| Layer 1 — loyalty DRIFTED / EXTRA / MISSING | Halt `BLOCKED_CONTRACT` — loyalty fix is `/forge-goals --iterate "<feedback>"`.                |
| Layer 2 — UNCOVERED                         | Spawn `/forge-scenarios --goal G<n>` once. Halt `BLOCKED_CONTRACT` if it doesn't fill.         |
| Layer 3 — UNLINKED                          | Spawn `/forge-tests --scenario SG<n>.<m>` once. Halt `BLOCKED_CONTRACT` on miss.               |
| Layer 3 — STALE                             | Spawn `/forge-tests --refresh SG<n>.<m>` once. Halt `BLOCKED_CONTRACT` on miss.                |
| Layer 3 — TIER-UNIT / TIER-UNKNOWN          | Halt `BLOCKED_CONTRACT` — re-tiering implies behavior change, operator.                        |
| Layer 4 — NO-COMMENT                        | Add `when:` / `then:` above the test, verbatim from scenario.                                  |
| Layer 4 — NO-AAA                            | Add `// --- arrange:` / `// --- act:` / `// --- assert:` markers, one short note per phase.    |
| Layer 4 — DRIFT                             | Update the stale entity name in `when:` / `then:`.                                             |
| Layer 4 — MISMATCH                          | Halt `BLOCKED_CONTRACT` — `assert:` doesn't realize the scenario; operator picks side.         |
| Layer 5 — ORPHAN-SG                         | Spawn `forge-step-runner` step=`design` once. Halt `BLOCKED_CONTRACT` if it doesn't cover.     |
| Layer 5 — ORPHAN-ELEMENT / EMPTY-PROVES     | Edit the component's `proves:` line to cite the right SG(s).                                   |
| Layer 5 — DANGLING-SG                       | Halt `BLOCKED_CONTRACT` — map cites a scenario no longer in `goals.md`.                        |
| Layer 6 — STALE                             | Spawn `/forge-impl-green --watch` once to refresh `run.json`. Halt `BLOCKED_CONTRACT` on red.  |
| Layer 6 — MISSING                           | Spawn `/forge-impl-green` once (linked SG never ran). Halt `BLOCKED_CONTRACT` if red persists. |
| Layer 6 — DANGLING                          | Spawn `/forge-tests --refresh SG<n>.<m>` once to realign cache; re-read `run.json`.            |
| Layer 6 — FAIL / ERROR                      | Halt `BLOCKED_CONTRACT` — behavior fix is `/forge-impl-green`, not annotation.                 |
| Tier sanity WARN                            | Skip (not a blocker).                                                                          |
| `tier_reason` missing on non-component      | Add the reason to the scenario's `- tier:` sub-bullet.                                         |

**Same defect 3 iters in a row** → halt `BLOCKED_RECURRENT`.

## Process

1. Resolve slug + worktree (per `/forge-status` § 1). Read `goals.md` + (if
   present) `links.json` for the contract-file allowlist. Missing goals → settle
   `NO_CHAIN`.
2. **Run `/forge-audit --slug <slug>`.** `PASS` → settle `AUDIT_GREEN`, exit.
   `FAIL` → parse `## smallest blocking set`.
3. **Statusline** —
   `/forge-line --phase-id audit-green --sub "iter <N>/<M> (<F> findings)"`.
   Heartbeat every 5 min in long subagent calls.
4. **Apply one fix per finding.** Contract-guard each diff. Sub-skill routes
   spawn one `forge-step-runner` with scoped finding — refuse multi-finding
   briefs (one attempt per boundary). Mechanical fixes edit directly.
5. **Commit + decisions log.**

   ```
   forge-audit-green: <SG or layer> <one-line fix>
   ```

   `.pr-artifacts/<slug>/forge/decisions.md` entry:

   ```
   ## <iso> — forge-audit-green cycle <N>
   - finding: <layer> <verdict> <SG or path>
   - fix:     <one-line>
   - commit:  <sha>
   ```

6. **Layer 1 signals** — track `same-finding-recurs`, `same-file-edited`,
   `diff-grew-pass-flat`, `contract-guard-refused` (hard at 1),
   `subagent-same-blocker`. On hard trip →
   `/forge-stuck-check --slug <slug> --phase audit-green --signal <name> --iter <N> --json`:
   - `confirmed` → halt loop, settle `STUCK` with the named reason.
   - `suspected` → bump threshold once, log, continue.
   - `none` → log false-alarm, continue.

7. **Loop** — re-run audit at iter N+1. Hit `max=<N>` without PASS → settle
   `BUDGET_EXHAUSTED`.

## Settle

| Verdict             | Meaning                                      |
| ------------------- | -------------------------------------------- |
| `AUDIT_GREEN`       | `/forge-audit` PASS                          |
| `NO_CHAIN`          | no `goals.md` for slug                       |
| `BLOCKED_CONTRACT`  | guard refused OR finding on contract surface |
| `BLOCKED_RECURRENT` | same finding survived 3 iters                |
| `BUDGET_EXHAUSTED`  | hit `max=<N>` without PASS                   |
| `STUCK`             | `/forge-stuck-check` confirmed               |

## Hooks

- `/forge` phase 6 — drives audit to PASS before embed. Skip phase when
  `/forge-status` says `audit.last_verdict=PASS` and no commits since.
- `/forge-status` drift (`pr.no_forge_block`, `goals.uncovered`,
  `links.test_id_missing`) recommends this skill as the fix command.

## Next step

`AUDIT_GREEN` → resume chain.

- `/forge-audit --embed` — write report to PR body
- `/forge-ci-green` — confirm CI stays green after any landed commits
- `/forge-review-green` — semantic review
- `/forge` — close the chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-audit-green                       # current branch
/forge-audit-green --slug auth-refactor  # explicit slug
/forge-audit-green max=20                # raise budget
```
