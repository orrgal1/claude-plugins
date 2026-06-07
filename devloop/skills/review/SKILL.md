---
name: review
description:
  "Multi-channel PR review — parallel lens fan-out + code-review +
  security-review, aggregated into one ranked verdict."
argument-hint:
  "[PR# or branch] [--channels <ids>] [--add-channel <id>]... [--drop-channel
  <id>]... [--channel <id> --<flag> <val>]... [--persona <id> | --personas
  <a,b,c> | --no-persona] [--context-lens-dir <dir>] [--context
  <name>=<path>]... [--state <dir>] [--embed]"
triggers:
  - "review this pr"
  - "multi-channel pr review"
  - "lens review"
  - "channel review"
  - "review with channels"
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

# /review — multi-channel PR review

Runs N **review channels** in parallel and aggregates their findings into one
ranked verdict. Repo-agnostic and standalone — no dependency on any other plugin
or on a forge chain. A caller (e.g. forge) layers its own context on top via
`--context` / `--context-lens-dir` without re-implementing the engine.

Ships three channels (`review-channels/`):

| Channel                   | Kind          | Default     | Wraps                                                |
| ------------------------- | ------------- | ----------- | ---------------------------------------------------- |
| `lens-fanout`             | agent-fanout  | **enabled** | parallel lens fan-out (`lens-reviewer` agent + pool) |
| `code-review-builtin`     | skill-wrapper | **enabled** | Claude Code's built-in `/code-review`                |
| `security-review-builtin` | skill-wrapper | **enabled** | Claude Code's built-in `/security-review`            |

A caller extends/overrides by pointing at an override channel dir (and an
override lens dir for context lenses) — same file shape as
`review-channels/<id>.md` (see `review-channels/README.md`).

## Inputs

| Input                                        | Default                                                          |
| -------------------------------------------- | ---------------------------------------------------------------- |
| `[PR# or branch]`                            | the current branch's PR                                          |
| `--channels`                                 | replace the active channel set                                   |
| `--add-channel <id>` / `--drop-channel <id>` | mutate the active set                                            |
| `--channel <id> --<flag> <val>`              | channel-scoped flag                                              |
| `--persona` / `--personas` / `--no-persona`  | lens-fanout persona selection (§ below)                          |
| `--context-lens-dir`                         | extra lens dir for context-conditional (Tier 2) lenses           |
| `--context <name>=<path>`                    | named context artifacts inlined into briefs (repeatable)         |
| `--state <dir>`                              | artifact dir for proposals / synthesis (default a neutral cache) |
| `--embed`                                    | also embed the synthesis into the PR body (§ Embed)              |

## Pipeline

1. Resolve PR + worktree (`[PR# or branch]`, else the current branch's PR).
2. **Context intake** — load any `--context <name>=<path>` artifacts (the caller
   supplies them; the engine treats them as opaque inlined data). No context →
   channels declaring `needs:` an unmet context are dropped with a one-line
   note.
3. Scope intake: PR metadata, file list, +A/-D, base ref, stack position.
4. Risk hot-spots — 3-5 anchored to concrete diff paths. Available to channels
   that ask.
5. **Channel selection.** Enabled channels (config `default_channels`),
   intersected with discovered channel files (`review-channels/` + override
   dir). CLI overrides: `--channels` replaces, `--add-channel`/`--drop-channel`
   mutate. Each channel's `needs` checked — unmet → dropped with a one-line
   note.
6. **Per-channel design.** Run each selected channel's `## Selection` to build
   its work plan (`lens-fanout`: lens-design baseline + persona + context lenses
   from `--context-lens-dir` + designed; `code-review-builtin`: wholesale).
7. **Consultation gate** (mandatory). Operator approves the channel set + each
   channel's per-run config (§ "Gate output").
8. **Dispatch.** Per channel, follow its `## Execution`. `agent-fanout`: all
   subagent calls in **a single message** for parallelism — pass `subagent_type`
   as the **exact** string the channel body names. For `lens-fanout` that is
   `@orrgal1/devloop:lens-reviewer` — **`/` before `devloop`, `:` before the
   agent name**; the all-colons form `@orrgal1:devloop:…` fails with "Agent type
   not found". `skill-wrapper`: Skill-call + ingest. `command-wrapper`: run +
   parse. Parallel when possible; channel body declares serial constraints.
9. **Normalize.** Apply each channel's `## Severity mapping` +
   `## Finding shape` to produce the unified shape.
10. **Aggregate.** Cap each finding against `severity_cap` (frontmatter + config
    override). Tag `channel: <id>` (and `lens: <id>` where applicable). Dedupe
    by `(file, line, content-hash)` — collapsed findings list all source
    channels.
11. **Synthesize, rank, emit verdict + ask** (§ "Synthesis output" + § Verdict).

## Channel selection on the CLI

```
--channels lens-fanout,code-review-builtin       # replace the active set
--add-channel security-review-builtin            # add to the active set
--drop-channel lens-fanout                       # remove from the active set
--channel code-review-builtin --effort high      # channel-scoped flag
--channel security-review-builtin --scope src/auth
```

Multiple `--add-channel` / `--drop-channel` / `--channel <id> --<flag>` flags
allowed per invocation. Unknown channel id → abort with the valid-id list.

## Persona selection (lens-fanout channel)

Top-level flags, implicitly scoped to `lens-fanout`:

- `--persona <id>` / `--personas <a,b,c>` — comma-separated union+dedup. Unknown
  id → abort with valid-id list.
- `--no-persona` — skip picker, baseline only.
- Default — interactive picker at the gate (numbered list; `none` is the safe
  default). No personas in pool → silent skip.

A persona's `lenses:` union with the lens-fanout baseline. Missing lens id →
hard error. No effect when `lens-fanout` is dropped.

## Gate output

```
PR #<num> — "<title>"
Diff: N files · +A/-D · base <ref> · stack pos: <pos>
Context: <names supplied via --context, or "none">

Risk hot-spots:
  - <hot-spot>  → <path or area>

Channels (M active):
  ✓ lens-fanout
      Personas:  <selected slugs | "none — baseline only">
      Lenses (K total):
        tier-1 core    <10 always-on; cannot drop>
        tier-2 context <lenses from --context-lens-dir matched to supplied context>
        tier-3 auto    <pool ids matched by diff fingerprint>
        persona/designed <pool id | name>
      Order: lens-mode (default) | file-by-file
      Agent: @orrgal1/devloop:lens-reviewer
  ✓ code-review-builtin
      Effort:       medium
      Severity cap: <value | "none">
  ✓ security-review-builtin
      Scope:        <path | "full diff">

Approve? [y / edit / abort]
  edit:  --channels <ids> | --add-channel <id> | --drop-channel <id>
         --channel <id> --<flag> <val>
         (lens-fanout shortcuts:)
         --add <pool-id-or-name:scope> | --drop <Lx>
         --rename <Lx>:<name> | --merge <Lx>+<Ly> | --split <Lx>
         --order file-by-file
         --persona <id> | --personas <a,b,c> | --no-persona
```

`needs:` failures show inline beside the dropped channel:
`✗ <id> (skipped — needs <context>)`.

## Severity

4-tier: `blocker` / `major` / `minor` / `nit`. Every channel declares a
`severity_mapping` (frontmatter + body) — the contract translating native
severities into these tiers. `severity_cap` optionally ceilings a channel;
operator overrides in config or at the gate.

A caller's fix-loop typically chases `blocker` + `major` regardless of source
channel.

## Verdict

| Verdict          | Meaning                                                    |
| ---------------- | ---------------------------------------------------------- |
| `CLEAN`          | every channel clean (no blockers, no majors).              |
| `REVIEW_BLOCKED` | aggregated review found ≥1 blocker or major (any channel). |

`REVIEW_BLOCKED` → fix the blocking set, re-run `/review`. (A caller may map
these to its own richer verdict ladder.)

## Embed

`--embed` writes the synthesis into its **own** collapsible block between
`<!-- review:begin -->` / `<!-- review:end -->`, wrapped in a collapsed
`<details>` with a findings-bearing summary:

```
<!-- review:begin -->
<details>
<summary>🔍 review: <findings></summary>

# /review synthesis
…aggregated findings…

</details>
<!-- review:end -->
```

`<findings>` is a short count (`1 blocker · 2 majors`, or `clean`). Idempotent
overwrite between the review markers via `gh api`; preserves everything else in
the body verbatim. No PR → no-op, hint "no PR yet — open one then re-run with
--embed." No commit, no push, no CI trigger.

## Artifact directory (`--state <dir>`)

```
<state>/review/
  proposal.md                       # channel + per-channel design echoed at the gate
  synthesis.md                      # final aggregated synthesis
  <channel-id>/                     # one per active channel
    proposal.md · raw.md · parsed.json · lens-LN.md · synthesis.md
```

## Synthesis output

Main thread merges normalized findings from every channel. Aggregation mode
(config `aggregation`, `interleave` default, `grouped`):

- **interleave** (default) — sorted by `(file, line)`. Each line carries a
  `[<channel-id>]` tag (and `<lens-id>` when present). Cross-channel duplicates
  collapsed; all source channels cited.
- **grouped** — one section per channel, findings within sorted blocker > major
  > minor > nit. Cross-channel duplicates surface once in their primary channel
  > with `(also: <other-channels>)`.

Both close with a verdict block leading with the smallest blocking set +
numbered action set + one action-choice question.

## Out-of-PR proposals

Any fix touching a file outside this PR's scope (follow-up PR, unrelated
refactor, sibling-module backfill, ticket) goes in a separate
`## Out-of-PR proposals` section, one bullet each, framed as yes/no — never
buried in the numbered fix list. Operator owns scope decisions.

## Usage

```
/review                                   # current branch's PR
/review 21228                             # PR by number
/review --embed                           # also embed in PR body
/review --add-channel security-review-builtin --channel security-review-builtin --scope src/auth
/review --channels lens-fanout,security-review-builtin
/review --persona backend-senior
/review --context-lens-dir ~/.../chain-lenses --context goals=goals.md --context links=links.json
```
