---
name: forge-proof-green
description:
  "Drive the forge proof to PASS — thin wrapper over the iteration_loop
  capability (grind); the proof check is the chain coupling."
argument-hint: "[--slug <name>] [max=<N>]"
triggers:
  - "forge proof green"
  - "drive forge proof to green"
  - "fix proof findings"
  - "make proof pass"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-proof-green — drive structural proof to PASS

Thin forge wrapper over the `iteration_loop` capability. The loop is **grind's**
— this skill only resolves the chain context, seeds finding-routing guidance,
and maps grind's verdict back to the chain. The proof check (`/forge-proof`) IS
grind's verify command — that coupling is what makes this a forge skill.

## Inputs

| Input     | Default               |
| --------- | --------------------- |
| `--slug`  | sanitized branch name |
| `max=<N>` | `10`                  |

## Steps

1. **Resolve** slug + worktree. Verify prereqs:
   `$FORGE_ART/branches/<slug>/goals.md` and `links.json` exist. Missing →
   `NO_CHAIN`. `/forge-proof` is the prereq _check_ (and the loop's verify).
2. **Resolve** the `iteration_loop` capability from
   `~/.claude/forge/capabilities.toml`: override → use it; else fall back to the
   default `/grind` (`@orrgal1/devloop`). Default provider absent & no override
   → refuse `PROVIDER_MISSING cap=iteration_loop provider=@orrgal1/devloop`
   (install it or override via `/forge-setup`).
3. **Invoke** the loop — its verify command is `/forge-proof`:

   ```
   <iteration_loop> "drive the forge proof to PASS — verify: /forge-proof exits 0 (all layers PASS)" \
     protect='$FORGE_ART/branches/<slug>/{goals.md,links.json,design.md},<linked test paths>' \
     slot=proof-green-<slug> max=<N>
   ```

   Pass the finding-routing guidance below into the loop's brief. grind loops:
   re-prove → fix the smallest blocking set → re-prove, committing each step,
   until `/forge-proof` PASSes or it stops on budget/stuck/protected edit.

4. **On SUCCESS** → settle `PROOF_GREEN`, then run `/forge-proof --embed` once
   (one-shot, no push) to write the proof block into the PR body.

## Chain-contract guard (enforced via `protect=`)

`protect=` makes the chain spec untouchable by the loop. A fix that can only
pass by editing a protected path → grind stops `BLOCKED` → wrapper settles
`BLOCKED_CONTRACT`. Protected surfaces:

| Surface                                 | Reason                                                       |
| --------------------------------------- | ------------------------------------------------------------ |
| `$FORGE_ART/branches/<slug>/goals.md`   | Goals + scenarios are the spec.                              |
| `$FORGE_ART/branches/<slug>/links.json` | Linkage is the chain — don't repoint to silence Layer-4.     |
| `$FORGE_ART/branches/<slug>/design.md`  | Design records intent; rewriting to absorb Layer-5 is drift. |
| Linked test bodies (assertions)         | `assert:` is the contract. (Comments + AAA markers OK.)      |

Non-contract surfaces (impl source, test `when:` / `then:` comments, AAA
markers, tier notes, coverage-map `proves:` cells for SGs already in `goals.md`,
the scenario `- tier:` reason sub-bullet) are fair game for the loop.

## Findings → loop-fixable vs routed (seeded into the loop brief)

`/forge-proof` emits `## smallest blocking set`. Split it:

- **Loop-fixable** (grind applies the mechanical delta in-loop): Layer-4
  NO-COMMENT / NO-AAA / DRIFT (add `when:`/`then:`, AAA markers, fix a stale
  entity name); Layer-5 ORPHAN-ELEMENT / EMPTY-PROVES (cite the right SG in a
  component's `proves:`); missing `tier_reason` on a non-component scenario.
- **Routed** (the fix lives in another chain skill — these touch protected spec,
  so grind stops `BLOCKED`; wrapper surfaces `BLOCKED_CONTRACT` for the operator
  to route): Layer-1 structural / loyalty → `/forge-goals`; Layer-2 UNCOVERED →
  `/forge-scenarios`; Layer-3 UNLINKED / STALE / TIER-\* → `/forge-tests`;
  Layer-4 MISMATCH (`assert:` ≠ scenario) → operator picks side; Layer-5
  ORPHAN-SG / DANGLING-SG → `/forge-design` or `/forge-goals`; Layer-6 FAIL /
  ERROR (red tests) → `/forge-impl-green` (its own loop, behavior change).

## Settle (grind verdict → chain verdict)

| grind verdict       | chain verdict       | Meaning                                             |
| ------------------- | ------------------- | --------------------------------------------------- |
| `SUCCESS`           | `PROOF_GREEN`       | `/forge-proof` PASS → embed once                    |
| `BLOCKED` (protect) | `BLOCKED_CONTRACT`  | fix needs a protected spec surface → route to skill |
| `BLOCKED` (stuck)   | `BLOCKED_RECURRENT` | same finding survived grind's stuck threshold       |
| `BUDGET_EXHAUSTED`  | `BUDGET_EXHAUSTED`  | hit `max=<N>` without PASS                          |
| (no `goals.md`)     | `NO_CHAIN`          | no chain for slug                                   |
| (provider missing)  | `PROVIDER_MISSING`  | `cap=iteration_loop provider=@orrgal1/devloop`      |

## Hooks

- `/forge` phase 6 — drives proof to PASS before embed. Skip when
  `/forge-status` says `proof.last_verdict=PASS` and no commits since.
- `/forge-status` drift (`pr.no_forge_block`, `goals.uncovered`,
  `links.test_id_missing`) recommends this skill as the fix command.

## Next step

`PROOF_GREEN` → resume chain.

- `/forge-proof --embed` — write report to PR body
- `/forge-review-green` — semantic review (next in the chain after proof)
- `/forge-ci-green` — drive CI green over the review-clean diff
- `/forge` — close the chain
- `/forge-status` — chain state + drift

## Usage

```
/forge-proof-green                       # current branch
/forge-proof-green --slug auth-refactor  # explicit slug
/forge-proof-green max=20                # raise budget
```
