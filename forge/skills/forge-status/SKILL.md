---
name: forge-status
description: "Read forge chain state and recommend the next step."
argument-hint: "[--slug <name>] [--json]"
triggers:
  - "forge status"
  - "forge state"
  - "where am i in the forge chain"
  - "where does this pr stand"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
practices:
  - tdd
  - code-review
user-invocable: true
---

# /forge-status — read state, recommend next step

Read-only. Reports phase verdict + drift list + one recommended next command.
`/forge` calls this at entry to pick a resume phase; operators call it for "what
now".

## Inputs

| Input    | Default               |
| -------- | --------------------- |
| `--slug` | sanitized branch name |
| `--json` | off — human report    |

Slug rule per `/forge-goals`: lowercase, alphanumerics + dashes, strip leading
`feat/` / `fix/` / `chore/`.

## Process

### 0. Setup gate

Confirm `$FORGE_HOME/forge.toml` has `[meta].ready = true` for this repo. Absent
→ emit `phase: NOT_SET_UP`, next move `run /forge-setup`, stop (no chain to read
yet). Exit non-zero.

**Provider preflight.** Resolve every required registry cap (`/forge-setup` §
"Global agent capabilities"): override → its plugin; else the built-in default
provider (`@orrgal1/devloop` — forge's single companion — for the PR ops, the
`iteration_loop`, and `deslop`). Any required cap un-overridden whose default
provider is **not installed** → emit `phase: PROVIDER_MISSING`, list the missing
provider(s)

- affected caps, next move `install <provider> or override via /forge-setup`,
  stop (exit 3). Forge can't run those caps until the backing exists.

### 1. Resolve slug + worktree

Run the canonical resolver — it derives slug, `$FORGE_ART`, and chain presence
exactly as `/forge-start` created them (single source; no divergent sed):

```bash
eval "$(~/.claude/forge/bin/forge-resolve.sh --sh)"   # --json for structured
slug="$FORGE_SLUG"; art="$FORGE_CHAIN_ROOT"
```

`$FORGE_ART` is **worktree-rooted**, not `$FORGE_HOME` — even with an
`[artifacts].prefix`, that only nests it deeper inside this worktree. Never
`ls`/`find` for `branches/<slug>/`, and never look under `~/.claude/forge/`.
`FORGE_CHAIN_PRESENT=false` → no chain here (run `/forge-start`);
`FORGE_BRANCHES` lists existing chain dirs for reconciliation if a passed
`--slug` disagrees.

### 2. Read artifacts

Missing is data, not error.

| Probe                    | Used for                                                           |
| ------------------------ | ------------------------------------------------------------------ |
| `$art/goals.md`          | spec layer present + `## G\d+` + `^- SG\d+\.\d+` + `^- VG\d+\.\d+` |
| `$art/links.json`        | tests linked count + tier per SG                                   |
| `$art/design.md`         | design layer present                                               |
| `$art/run.json`          | last run pass/fail/error/skip + mtime                              |
| `$art/validations.json`  | per-VG verdict + evidence + mtime                                  |
| `$art/decisions.md`      | unattended-mode log                                                |
| `$art/approvals.json`    | per-phase sha approvals (`goals`, `design`, …)                     |
| `$art/review/cycle-*.md` | review cycle count + last B+M                                      |

For each `approvals.json` entry: sha matches artifact's last-touching commit
(`git log -1 --format=%H -- <artifact>`) → phase APPROVED. Else AWAIT.

### 3. PR + git state

```
gh pr view --json number,state,isDraft,body,statusCheckRollup,headRefName,baseRefName 2>/dev/null
```

No PR → `pr=none`. Plus: `git status --porcelain`,
`git rev-list --count origin/<base>..HEAD`, mtime of HEAD vs `run.json`.

### 4. Cross-check linkage

For each `links.json` entry: resolve test file + function/symbol. Miss → drift
`links.test_id_missing`.

### 5. Phase verdict

Earliest unsatisfied phase wins:

| Phase                    | Trigger                                                                                                                                                                                       | Next                                                                                                  |
| ------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `NO_CHAIN`               | no `$art/` AND no PR                                                                                                                                                                          | `/forge <source>`                                                                                     |
| `START_PENDING`          | branch local but no remote / draft PR                                                                                                                                                         | `/forge-start <source>` (or `/forge` to resume start)                                                 |
| `GOALS_DRAFT`            | `goals.md` exists, no `approvals.json.goals`                                                                                                                                                  | `/forge-goals --push`                                                                                 |
| `AWAIT_GOALS_REVIEW`     | goals pushed; `approvals.json.goals` absent OR sha-stale                                                                                                                                      | operator: `/forge approve` or `/forge iterate "<fbk>"`                                                |
| `GOALS_APPROVED`         | approval sha matches goals.md last commit                                                                                                                                                     | `/forge-design --push`                                                                                |
| `DESIGN_DRAFT`           | `design.md` exists, no `approvals.json.design`                                                                                                                                                | `/forge-design --push`                                                                                |
| `AWAIT_DESIGN_REVIEW`    | design pushed; approval absent or sha-stale                                                                                                                                                   | operator: same shape                                                                                  |
| `DESIGN_APPROVED`        | approval sha matches design.md                                                                                                                                                                | `/forge-scenarios --push`                                                                             |
| `SCENARIOS_DRAFT`        | scenarios written, no `approvals.json.scenarios`                                                                                                                                              | `/forge-scenarios --push`                                                                             |
| `AWAIT_SCENARIOS_REVIEW` | scenarios pushed; `approvals.json.scenarios` absent OR sha-stale                                                                                                                              | operator: `/forge approve` or `/forge iterate "<fbk>"`                                                |
| `SCENARIOS_APPROVED`     | approval sha matches goals.md scenarios block, no `links.json` (or empty)                                                                                                                     | `/forge-tests`                                                                                        |
| `TESTS_LINKED`           | links present, no `run.json` (or older than any linked test)                                                                                                                                  | `/forge-impl-green`                                                                                   |
| `RED`                    | `run.json` `fail>0` or `error>0`                                                                                                                                                              | `/forge-impl-green`                                                                                   |
| `IMPL_GREEN`             | `run.json` all pass, no proof-green PASS yet                                                                                                                                                  | per-layer attestation 5a-5e → `/forge-proof-green`                                                    |
| `PROOF_GREEN`            | last proof PASS, no embed in PR body OR no CI green for HEAD                                                                                                                                  | `/forge-proof --embed` + `/forge-ci-green`                                                            |
| `CI_GREEN`               | PR CI green on HEAD, no review cycles                                                                                                                                                         | `/forge-review-green`                                                                                 |
| `REVIEW_OPEN`            | last `cycle-N.md` B+M>0 AND no commits since                                                                                                                                                  | `/forge-review-green`                                                                                 |
| `REVIEW_STALE`           | last cycle B+M>0 AND commits since, no new cycle                                                                                                                                              | `/forge-review-green` (re-cycle)                                                                      |
| `REVIEW_GREEN`           | last cycle B+M=0, commits since last `ci.green`                                                                                                                                               | phase 9 ci-ready: read continuous monitor `loop/ci-green-continuous/status.json`; GREEN → READY-phase |
| `AWAIT_REVIEW_REQUEST`   | would-be READY, PR still `isDraft`, no `approvals.json.review_request`, not `--no-review-request`                                                                                             | operator: `/forge approve` (mark-ready+request) or `/request-review --ready`                          |
| `READY`                  | CI green post-review + proof-embed present + last B+M=0 (or `--no-review` recorded), AND ready-for-review resolved (`approvals.json.review_request` OR PR not draft OR `--no-review-request`) | mark ready / merge                                                                                    |

Manual-mode AWAIT verdicts (phases 4-9): `AWAIT_TESTS_REVIEW`,
`AWAIT_IMPL_REVIEW`, `AWAIT_PROOF_REVIEW`, `AWAIT_CI_REVIEW`,
`AWAIT_REVIEW_REVIEW`. Detect via `wip.mode_manual` in `decisions.md` +
phase-completion signal without matching `approvals.json` entry.
(`AWAIT_SCENARIOS_REVIEW` is always-on across both modes — see table above.)

### 6. Drift

Independent of phase. `block` halts autopilot; `warn` surfaces only.

| Drift                             | Severity | Detection                                                             | Fix                                                                |
| --------------------------------- | -------- | --------------------------------------------------------------------- | ------------------------------------------------------------------ |
| `links.test_id_missing`           | block    | step 4 cross-check failed                                             | `/forge-tests --refresh <SG>` or restore                           |
| `goals.uncovered`                 | block    | `## G\d+` with 0 `^- SG\d+\.\d+` AND 0 `^- VG\d+\.\d+`                | `/forge-scenarios --goal G<n>` or `/forge-validations --goal G<n>` |
| `design.orphan`                   | warn     | `design.md` exists, no `goals.md`                                     | `/forge-goals` to seed                                             |
| `run.stale`                       | warn     | `run.json` older than any linked test file OR older than HEAD         | `/forge-impl-green`                                                |
| `validations.stale`               | warn     | `validations.json` older than HEAD commit                             | `/forge-verify-validations`                                        |
| `review.unaddressed`              | block    | last cycle B+M>0, no commits since                                    | `/forge-review-green`                                              |
| `review.assumed_fixed_no_recycle` | warn     | last cycle B+M>0, commits since, no new cycle                         | `/forge-review` (re-cycle)                                         |
| `pr.no_forge_block`               | warn     | run+proof clean, PR body lacks `<!-- forge-proof -->`                 | `/forge-proof --embed`                                             |
| `pr.brief_stale`                  | warn     | `/forge-brief --check` reports STALE (brief diverged from `goals.md`) | `/forge-brief`                                                     |
| `pr.dirty_worktree`               | warn     | `git status --porcelain` non-empty                                    | commit / stash                                                     |
| `pr.ahead_unpushed`               | warn     | commits ahead of remote tracking                                      | push                                                               |
| `pr.ci_failing`                   | block    | `statusCheckRollup` has FAILURE on HEAD                               | `/forge-ci-green`                                                  |

### 7. Emit report

Human (default):

```
FORGE STATUS — <slug>
  branch:   <branch>   (clean | dirty: N files)
  pr:       #<num> <state>   ci: <pass|fail|pending|none>
  phase:    <VERDICT>

  artifacts:
    goals.md       <N goals, M scenarios>
    design.md      <present|absent>
    links.json     <K linked / M scenarios>
    run.json       <P pass · F fail · E error · S skip · age: 2h>
    review         <cycle-1: B=0 M=2 | cycle-2: B=0 M=0>

  drift:
    [block] review.unaddressed: cycle-2 has 2 majors, no commits since 10:43

  recommendation:
    verdict:  PROCEED | BLOCKED_DRIFT | ALREADY_FORGED
    next:     /forge-review-green --slug <slug>
    why:      <one line>
```

JSON (`--json`):

```json
{
  "slug": "<slug>",
  "phase": "REVIEW_OPEN",
  "pr": { "number": 12345, "state": "OPEN", "draft": false, "ci": "pass" },
  "artifacts": {
    "goals": { "exists": true, "goals": 3, "scenarios": 7 },
    "design": { "exists": true },
    "links": { "linked": 7, "missing": 0 },
    "run": { "pass": 7, "fail": 0, "error": 0, "skip": 0, "age_sec": 7200 },
    "review": { "cycles": 2, "last": { "blockers": 0, "majors": 2 } }
  },
  "drift": [
    { "severity": "block", "signal": "review.unaddressed", "detail": "..." }
  ],
  "recommendation": {
    "verdict": "BLOCKED_DRIFT",
    "next": "/forge-review-green --slug <slug>",
    "why": "<one line>"
  }
}
```

## Hooks

- `/forge` at entry → `--json`. `status.phase` drives entry phase. Any
  `severity=block` drift → halt `BLOCKED_DRIFT`. `--from` overrides.
- `/forge approve` / `/forge iterate` → `--json` to detect the awaiting phase.
  One `AWAIT_<phase>_REVIEW` → target it. Multiple AWAITs → require
  `--phase <phase>`. None → refuse "no awaiting phase".
- `approve` writes `{"<phase>": "<sha>"}` to `approvals.json`.
  `iterate "<feedback>"` re-spawns the phase skill with `--iterate --push`;
  prior sha goes stale on commit.
- **`AWAIT_REVIEW_REQUEST` is an action gate, not a sha gate.** `approve` at it
  runs `/request-review --ready` (mark ready + request the proposed reviewer)
  and records `{"review_request": "<reviewer-login>"}` in `approvals.json`;
  `iterate "<steer>"` re-runs `/request-review` with the steer to re-rank before
  marking ready. No sha pinning.

## Symbol presence check

`links.json` entries validated via language-aware grep — `def`, `func`,
`it(`/`test(`/`describe(`. Miss → drift `links.test_id_missing` (block).

## Out of scope

- Modifying any artifact. Pure read.
- Fixing drift. Recommends; never applies.

## Honesty

- Missing artifact = `absent`, not broken.
- Stale data surfaces explicitly (`run.stale`, `review.stale-vs-commits`).
- Verdict uncomputable from disk → `UNKNOWN`, no invention.

## Exit codes

| Code | Meaning                                                                                              |
| ---- | ---------------------------------------------------------------------------------------------------- |
| 0    | phase = READY                                                                                        |
| 1    | phase < READY                                                                                        |
| 2    | ≥1 `block` drift                                                                                     |
| 3    | phase = NOT_SET_UP (no `[meta].ready`) or PROVIDER_MISSING (default provider absent, not overridden) |
| 64   | unrecoverable read error                                                                             |
