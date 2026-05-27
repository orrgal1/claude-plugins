---
name: forge-review
argument-hint:
  "[PR# or branch] [--slug <name>] [--persona <id> | --personas <a,b,c> |
  --no-persona] [--embed]"
triggers:
  - "forge review"
  - "review the forge chain"
  - "lens review with forge"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
  - Agent
practices:
  - code-review
user-invocable: true
---

# /forge-review — forge-chain-aware lens-designed PR review

A parallel, lens-designed PR review whose ground truth comes from the forge
chain (`goals.md`, `links.json`, linked tests) instead of guessing from the PR
body. Seven always-on lenses (3 chain-semantic, 4 code-quality) +
persona-derived lenses + 1-3 per-PR designed lenses against the diff's risk
surface. Target 7-9 total.

If the PR has no forge chain → forge-review still runs, dropping the
chain-semantic lenses (L0-L2) and reviewing the diff with code-quality +
designed lenses only. If the chain is broken → run `/forge` first (or at minimum
`/forge-goals`, `/forge-scenarios`, `/forge-tests`, `/forge-audit`) to restore
L0-L2 ground truth.

## Pipeline

1. Resolve slug + worktree + PR (per `/forge` rules).
2. Load `.pr-artifacts/<slug>/forge/{goals.md,links.json}`. Missing either →
   exit, point at `/forge`.
3. Run `/forge-audit` (cached if recent). FAIL → refuse to review; point at the
   report. Lens budget is too expensive for noise.
4. Scope intake: PR metadata, file list, +A/-D, base ref, stack position.
5. Risk hot-spots — 3-5 anchored to concrete paths, from the diff.
6. **Lens design.** Baseline L0-L6 (see below). Persona-derived: union+dedup of
   selected personas' `lenses:` lists. Designed: 1-3 against the diff's risk
   surface per `lenses/README.md` § "Designing per-PR lenses". Target 7-9.
7. **Consultation gate** (mandatory). Persona picker + lens approval (see §
   "Gate output").
8. Order: lens-mode (default) | file-by-file.
9. **Fan-out.** One `@orrgal1/forge:forge-lens-reviewer` Agent per lens, all in
   a single message (true parallelism). L0/L1/L2 briefs carry the relevant slice
   of `goals.md` / `links.json` verbatim.
10. Main thread synthesis, dedup, rank.
11. Verdict + ask (per § "Verdict").

## Always-on lenses

Definitions live in `lenses/<id>.md` (a host repo may override or add via
`.forge/lenses/<id>.md`). The lens body (markdown after frontmatter) is inlined
verbatim in each subagent brief.

| L#  | Pool id            | Group          | Brief artifacts                   |
| --- | ------------------ | -------------- | --------------------------------- |
| L0  | `goal-delivery`    | chain-semantic | `goals.md`, PR description        |
| L1  | `scenario-realism` | chain-semantic | `goals.md`                        |
| L2  | `test-match`       | chain-semantic | `links.json`, linked test files   |
| L3  | `clean-code`       | code-quality   | —                                 |
| L4  | `elegance`         | code-quality   | —                                 |
| L5  | `robustness`       | code-quality   | —                                 |
| L6  | `commentary`       | code-quality   | commentary surface (diff-derived) |

L0-L2 (chain-semantic) carry the forge chain's ground truth — present whenever a
chain exists. On a PR with no chain they're skipped automatically (the diff has
no `goals.md`/`links.json` to check against). L3-L6 can be edited at the gate;
defaults on.

## Persona selection

- `--persona <id>` / `--personas <a,b,c>` — comma-separated union+dedup. Unknown
  id → abort with valid-id list.
- `--no-persona` — skip picker, baseline only.
- Default — interactive picker at the gate (numbered list; `none` is the safe
  explicit default). No personas in pool → silent skip.

Persona's `lenses:` union with baseline. Missing lens id in persona → hard
error.

## Per-PR designed lenses (L7+)

Designed against the diff's risk surface per `lenses/README.md` § "Designing
per-PR lenses" — wire contract, schema fidelity, mapping/dispatch invariants,
coupling, naming, wire-up symmetry. 1-3 to land in the 7-9 sweet spot.

## Gate output

```
PR #<num> — "<title>"
Diff: N files · +A/-D · base <ref> · stack pos: <pos>
Forge: <slug> · G<n> goals · SG<n> scenarios · L<n> tests linked
Audit: PASS (<timestamp>)

Personas: <selected slugs | "none — baseline only">

Risk hot-spots:
  - <hot-spot>  → <path or area>

Proposed lenses (M total, target 7-9):
  L0  goal-delivery       (baseline; cannot drop)
  L1  scenario-realism    (baseline; cannot drop)
  L2  test-match          (baseline; cannot drop)
  L3-L6 …                 (baseline; code-quality)
  L7+ <pool id | name>    (persona | design)

Order: lens-mode (default) | file-by-file
Agent: @orrgal1/forge:forge-lens-reviewer

Approve? [y / edit / abort]
  edit:  --add <pool-id-or-name:scope> | --drop <Lx>
         --rename <Lx>:<name> | --merge <Lx>+<Ly> | --split <Lx>
         --order file-by-file
         --persona <id> | --personas <a,b,c> | --no-persona
```

## Subagent brief

Each lens gets its own brief — the prompt passed to a `forge-lens-reviewer`
Agent. The agent bakes severity tiers, line format, scope guard, and
read-full-files rule, so the brief only supplies context. For always-on lenses,
brief assembled mechanically from the pool entry:

- **Lens focus** — pool file body (after frontmatter), inlined verbatim.
- **Brief artifacts** per pool's `brief-artifacts:` list:
  - `goals.md` — full contents in `## Goals` block.
  - `pr-description` — PR body verbatim in `## PR description` block.
  - `links.json` — full contents + linked test paths (agent reads tests directly
    from the worktree).
  - `commentary-surface` — every added/modified comment, docstring, or note in
    the diff with surrounding code context.
  - `full-diff` / `linked-test-files` per the `brief-artifacts` schema in
    `lenses/README.md`.
- **Worktree path + file scope** — always included.

L7+ briefs carry only file scope + lens focus.

## Severity

Four tiers, baked into the `forge-lens-reviewer` agent: blocker / major / minor
/ nit. Each pool lens declares its `severity-floor:` in frontmatter; body
documents promotion rules.

## Verdict

Extends `/forge`'s wrap-verdict ladder:

| Verdict            | Meaning                                                                  |
| ------------------ | ------------------------------------------------------------------------ |
| `READY`            | audit PASS, linked tests pass/skip, review clean (no blockers).          |
| `RED_BAR`          | audit PASS but ≥1 linked test `fail` / `error`, or review-clean pending. |
| `INCOMPLETE`       | audit FAIL — wrap skipped, review not run.                               |
| `REVIEWED_BLOCKED` | audit PASS, tests pass, but lens review found ≥1 blocker.                |

`REVIEWED_BLOCKED` → fix blockers, re-run `/forge-review`, re-wrap.

## Embed

`--embed` appends a `## Review` section **inside** the existing `<details>`
wrapper of the `<!-- forge-audit:begin -->` / `<!-- forge-audit:end -->` block,
then rewrites `<summary>` to reflect joint state:

```
<summary>🔨 forge — audit: <verdict> · review: <findings> · <slug></summary>
```

`<findings>` is short count (`1 blocker · 2 majors` or `clean`). Idempotent
overwrite — preserves the audit block above. No `open` attribute. No embed-block
yet → refuse with "run `/forge-audit --embed` first".

## Artifact directory

```
.pr-artifacts/<slug>/forge/review/
  proposal.md       # lens-design proposal echoed at the gate
  lens-LN.md        # per-lens finding log (local; not tracked)
  synthesis.md      # final synthesis (local; not tracked)
```

## Synthesis output

Main thread merges per-lens findings: one section per lens, findings sorted
blocker > major > minor > nit, cross-lens duplicates collapsed (cite all lenses
that flagged it), then a verdict block leading with the smallest blocking set +
a numbered action set + one action-choice question. Verdict block names the
extended tier.

## Out-of-PR proposals

Any fix that would touch a file outside this PR's scope (follow-up PR, unrelated
refactor, sibling-module backfill, ticket) goes in a separate
`## Out-of-PR proposals` section, one bullet each, framed as a yes/no question —
never buried in the numbered fix list. The operator owns those scope decisions.

## Next step

- `REVIEWED_CLEAN` → `/forge` (or autopilot continues).
- `REVIEWED_BLOCKED` (B+M > 0) → `/forge-review-green` to drive to green.
- `/forge-status` — chain state + drift.

## Usage

```
/forge-review                                   # current branch's PR + chain
/forge-review 21228                             # PR by number
/forge-review --slug auth-refactor              # explicit slug override
/forge-review --embed                           # also embed in PR body
/forge-review --persona backend-senior          # one persona
/forge-review --personas backend-senior,security-paranoid
/forge-review --no-persona                      # baseline only
```
