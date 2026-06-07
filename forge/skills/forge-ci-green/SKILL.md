---
name: forge-ci-green
description:
  "Drive a forge PR's CI to green — thin chain wrapper over the ci_green
  capability."
argument-hint:
  "[--slug <name>] [--watch] [--until-merge] [max=<N>] [<check>] [stop]"
triggers:
  - "forge ci green"
  - "drive ci to forge green"
  - "make pr ci green"
  - "keep ci green until merge"
allowed-tools:
  - Skill
  - Bash
  - Read
  - Write
  - Grep
  - Glob
user-invocable: true
---

# /forge-ci-green — chain wrapper around the `ci_green` capability

A **thin** chain layer over the chain-blind `ci_green` capability (default
`/ci-green`, `@orrgal1/devloop`). The capability owns the entire fix-to-green
loop, the three-probe `ci-check`, `ci-fix`, continuous `--until-merge` mode, and
stuck detection. This wrapper adds only what touches the **forge chain**: the
triage gate, the contract-protect set, chain-located loop state, the
external-block recognizer, and `decisions.md` / `run.json` bookkeeping.

`stop`, `--watch`, `--until-merge`, `max=<N>`, and a positional `<check>` pass
straight through to the capability.

## Resolve

1. Resolve slug + worktree + PR per `/forge` rules.
2. Resolve the `ci_green` capability (`~/.claude/forge/capabilities.toml`;
   unconfigured → `NEEDS_SETUP cap=ci_green`, point at `/forge-setup`). No
   built-in substitute.

## Triage gate (chain — skip if `--watch` or a single trivial check)

```
gh pr checks <num> --json name,conclusion | failing list
/forge-triage --failing <list> --json
```

Branch on `recommendation`:

- `PROCEED` → continue.
- `PROCEED_WITH_SKIPS` → for each `OUT_OF_PR_SCOPE` / `STACK_DEFERRED_<ref>`:
  refuse if the test path is in `links.json` → halt `BLOCKED_CONTRACT`; else
  apply the language-appropriate skip (Go `t.Skip`, py `@pytest.mark.skip` /
  `xfail`, TS `.skip(...)`) with verdict comment + sibling PR ref, commit
  `forge-ci-green: defer <test> per /forge-triage (<verdict>)`, and narrow the
  loop to the `REAL_BUG` subset.
- `HALT_TRIAGE` → verdict-named halt: `FLAKE_SUSPECT` → `BLOCKED_FLAKY`;
  `INFRA_FAILURE` → `BLOCKED_INFRA` unless triage returned a matched
  `recovery=<name>` playbook (run it best-effort per `/forge-setup` § playbooks;
  halt only if the recovery itself fails); `AMBIGUOUS` → `NEEDS_OPERATOR` reason
  `triage-ambiguous`.

## Invoke the capability

Build the chain-contract protect set from `links.json` + spec files, point loop
state at the chain, and wire the post-green refresh:

```
/ci-green \
  --protect '$FORGE_ART/branches/<slug>/{goals.md,design.md,links.json}',<linked test paths> \
  --state   $FORGE_ART/branches/<slug>/loop/ci-green-continuous/ \
  --on-green '<refresh run.json: re-run linked tests via the test capability, no fix>' \
  [--watch | --until-merge | max=<N> | <check> | stop]
```

- `--protect` carries the chain-contract surfaces — goals/design/links + every
  test named in `links.json`. A capability `BLOCKED_PROTECTED` settle ⇒
  `BLOCKED_CONTRACT` (operator revises via `/forge-tests` / `/forge-scenarios`).
- `--state` lands the capability's `status.json` exactly where `/forge-status`
  and `/forge` phase 9 read it.
- `--on-green` keeps `run.json` fresh (automatic, never offered — per `/forge` §
  "Bias to progress").

## On capability settle (chain mapping)

| Capability verdict                    | Chain action                                                                            |
| ------------------------------------- | --------------------------------------------------------------------------------------- |
| `CI_GREEN`                            | settle `CI_GREEN`; `--on-green` already refreshed `run.json`                            |
| `BLOCKED_REBASE`                      | **external** — run the `find_blocker` recognizer (§ below), mode-gate `/forge-wait-for` |
| `BLOCKED_PROTECTED`                   | settle `BLOCKED_CONTRACT`, name the contract file                                       |
| `BLOCKED_REBASE_CONFLICT`             | genuine — settle `BLOCKED_RESTACK_CONFLICT` (operator resolves; never waitable)         |
| `RED_PERSISTENT` / `BUDGET_EXHAUSTED` | settle verbatim; log to `decisions.md`                                                  |
| `MERGED`                              | continuous monitor ended; settle `MERGED`                                               |

Append one `decisions.md` line per fix-to-green episode (cycle count + terminal
verdict).

### External-block recognizer (waitable settles)

`BLOCKED_REBASE` (base behind / red) and a triage `INFRA_FAILURE` are external —
resolved by a base PR going green or an incident clearing, not by a fix here.
Per `/forge` § "External-block recognizer": run the `find_blocker` capability
(`/find-blocker --hint <verdict> --json --out $FORGE_ART/branches/<slug>/blocker/last.json`);
on a confirmed peripheral blocker, mode-gate the dispatch of
`/forge-wait-for --condition <spec> --from ci` (`yolo`/unattended → auto
restack+resume; `auto`/`manual` → surface the command, settle as-is).
`BLOCKED_FLAKY` is diagnosis-only — **never** waitable; `BLOCKED_CONTRACT` /
`BLOCKED_RESTACK_CONFLICT` are genuine — never waitable.

## Hooks

- `/forge` phase 5.5 — post-impl CI before proof-green (one-shot).
- `/forge` phase 6.5 — post-proof-embed CI re-confirm (one-shot).
- `/forge` phase 7.5 — on the first `CI_GREEN`, forge arms this skill
  `--until-merge` in the background; the capability's continuous monitor keeps
  CI green through review and beyond, re-arming on every new HEAD until merge.
  **There is no separate final CI phase.**
- `/forge-status` reads the continuous monitor's `status.json` (under
  `--state`); drift `pr.ci_failing` recommends this skill.

One-shot phases skip when `/forge-status` reports `pr.ci=pass` and no commits
since last green.

## Next step

- `/forge-proof --embed` — post-impl path
- `/forge-review` — post-proof path
- `/forge` — close chain · `/forge-status` — chain state + drift

## Usage

```
/forge-ci-green                              # current branch's PR
/forge-ci-green --slug auth-refactor         # explicit slug
/forge-ci-green --watch                      # poll-only, no fixes
/forge-ci-green --until-merge                # continuous: keep CI green until merge
/forge-ci-green --until-merge stop           # stop the continuous monitor
/forge-ci-green max=20                       # raise budget
/forge-ci-green "go unittests"               # narrow to one check
```
