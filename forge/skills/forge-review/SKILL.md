---
name: forge-review
description:
  "Forge-chain-aware multi-channel PR review — fans out parallel review
  mechanisms — lens fan-out + built-in /code-review + built-in /security-review,
  all on by default) and aggregates findings."
argument-hint:
  "[PR# or branch] [--slug <name>] [--channels <ids>] [--add-channel <id>]...
  [--drop-channel <id>]... [--channel <id> --<flag> <val>]... [--persona <id> |
  --personas <a,b,c> | --no-persona] [--embed]"
triggers:
  - "forge review"
  - "review the forge chain"
  - "lens review with forge"
  - "channel review"
  - "review with channels"
  - "multi-channel pr review"
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

# /forge-review — forge-chain-aware multi-channel PR review

Runs N **review channels** in parallel and aggregates their findings into a
single ranked verdict. Ground truth comes from the forge chain (`goals.md`,
`links.json`, linked tests) rather than guesses from the PR body.

The forge plugin ships three channels (`forge/review-channels/`):

| Channel                   | Kind          | Default     | Wraps                                                           |
| ------------------------- | ------------- | ----------- | --------------------------------------------------------------- |
| `lens-fanout`             | agent-fanout  | **enabled** | parallel lens fan-out (`forge-lens-reviewer` agent + lens pool) |
| `code-review-builtin`     | skill-wrapper | **enabled** | Claude Code's built-in `/code-review`                           |
| `security-review-builtin` | skill-wrapper | **enabled** | Claude Code's built-in `/security-review`                       |

A host repo extends or overrides by dropping channel files into
`$FORGE_HOME/review-channels/` (same shape as `forge/review-channels/<id>.md` —
see `forge/review-channels/README.md`).

If the PR has no forge chain → `/forge-review` still runs, but channels that
declare `needs: forge-chain` are skipped. If the chain is broken → run `/forge`
first (or at minimum `/forge-goals`, `/forge-scenarios`, `/forge-tests`,
`/forge-audit`) to restore chain-semantic coverage.

## Pipeline

1. Resolve slug + worktree + PR (per `/forge` rules).
2. Load `.pr-artifacts/<slug>/forge/{goals.md,links.json}`. Missing either →
   continue in **no-chain mode**: channels needing `forge-chain` are dropped
   with a one-line note.
3. Run `/forge-audit` (cached if recent). FAIL → refuse to review; point at the
   report. Review budget too expensive for noise.
4. Scope intake: PR metadata, file list, +A/-D, base ref, stack position.
5. Risk hot-spots — 3-5 anchored to concrete paths, from the diff. Available to
   channels that ask for them.
6. **Channel selection.** Read enabled channels from `$FORGE_HOME/forge.toml`
   `[review]` `default_channels`, intersected with discovered channel files
   (`forge/review-channels/` + override `$FORGE_HOME/review-channels/`). Apply
   CLI overrides: `--channels` replaces the set, `--add-channel <id>` /
   `--drop-channel <id>` mutate. Each channel's `needs` checked against context
   — unmet need → channel dropped with a one-line note (`needs: forge-chain` on
   a no-chain PR).
7. **Per-channel design.** For each selected channel, run its body's
   `## Selection` step to build its work plan (e.g. `lens-fanout` runs
   lens-design baseline + persona + designed; `code-review-builtin` is
   wholesale).
8. **Consultation gate** (mandatory). Operator approves the channel set + each
   channel's per-run config (see § "Gate output").
9. **Dispatch.** Per channel, follow its body's `## Execution` section.
   `agent-fanout` channels send all subagent calls in **a single message** for
   true parallelism. `skill-wrapper` channels Skill-call and ingest output.
   `command-wrapper` channels run + parse. Channels run in parallel when
   possible; a channel's body declares serial constraints when needed.
10. **Normalize.** For each channel, apply its body's `## Severity mapping`
    - `## Finding shape` to produce the unified finding shape.
11. **Aggregate.** Cap each finding against `severity_cap` (frontmatter + config
    override). Tag with `channel: <id>` (and `lens: <id>` where applicable).
    Dedupe by `(file, line, content-hash)` — collapsed findings list all source
    channels.
12. **Synthesize, rank, emit verdict + ask** (per § "Synthesis output" + §
    "Verdict").

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

Top-level convenience flags, implicitly scoped to the `lens-fanout` channel
(backward compat with pre-channel `/forge-review`):

- `--persona <id>` / `--personas <a,b,c>` — comma-separated union+dedup. Unknown
  id → abort with valid-id list.
- `--no-persona` — skip picker, baseline only.
- Default — interactive picker at the gate (numbered list; `none` is the safe
  explicit default). No personas in pool → silent skip.

A persona's `lenses:` union with the lens-fanout baseline. Missing lens id in
persona → hard error. This flag has no effect when `lens-fanout` is dropped from
the channel set.

## Gate output

```
PR #<num> — "<title>"
Diff: N files · +A/-D · base <ref> · stack pos: <pos>
Forge: <slug> · G<n> goals · SG<n> scenarios · L<n> tests linked
Audit: PASS (<timestamp>)
Mode: chain | no-chain

Risk hot-spots:
  - <hot-spot>  → <path or area>

Channels (M active):
  ✓ lens-fanout
      Personas:  <selected slugs | "none — baseline only">
      Lenses (K total):
        tier-1 core   <10 always-on; cannot drop>
        tier-2 chain  goal-delivery, scenario-realism, test-match (if chain)
        tier-3 auto   <pool ids matched by diff fingerprint>
        persona/design <pool id | name>
      Order: lens-mode (default) | file-by-file
      Agent: @orrgal1/forge:forge-lens-reviewer
  ✓ code-review-builtin
      Effort:       medium
      Severity cap: <value | "none">
  ✓ security-review-builtin
      Scope:        <path | "full diff">
      Severity cap: <value | "none">

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
`✗ <id> (skipped — needs forge-chain)`. Operator can override with
`--add-channel <id>` only if the channel body permits forced execution;
otherwise the channel stays skipped.

## Severity

Forge-native 4-tier: `blocker` / `major` / `minor` / `nit`. Every channel
declares a `severity_mapping` in its frontmatter + body — that's the contract
translating native severities into forge's tiers. `severity_cap` optionally
ceilings a channel; the operator overrides in config or at the gate.

`/forge-review-green` (the fix-loop) chases `blocker` + `major` regardless of
source channel.

## Verdict

Extends `/forge`'s wrap-verdict ladder:

| Verdict            | Meaning                                                                           |
| ------------------ | --------------------------------------------------------------------------------- |
| `READY`            | audit PASS, linked tests pass/skip, every channel clean (no blockers, no majors). |
| `RED_BAR`          | audit PASS but ≥1 linked test `fail` / `error`, or review-clean pending.          |
| `INCOMPLETE`       | audit FAIL — wrap skipped, review not run.                                        |
| `REVIEWED_BLOCKED` | audit PASS, tests pass, but aggregated review found ≥1 blocker (any channel).     |

`REVIEWED_BLOCKED` → fix blockers, re-run `/forge-review`, re-wrap.

## Embed

`--embed` appends a `## Review` section **inside** the existing `<details>`
wrapper of the `<!-- forge-audit:begin -->` / `<!-- forge-audit:end -->` block,
then rewrites `<summary>` to reflect joint state:

```
<summary>🔨 forge — audit: <verdict> · review: <findings> · <slug></summary>
```

`<findings>` is short count (`1 blocker · 2 majors` or `clean`), aggregated
across all channels. Idempotent overwrite — preserves the audit block above. No
`open` attribute. No embed-block yet → refuse with "run `/forge-audit --embed`
first".

## Artifact directory

```
.pr-artifacts/<slug>/forge/review/
  proposal.md                       # channel + per-channel design echoed at the gate
  synthesis.md                      # final aggregated synthesis (local; not tracked)
  <channel-id>/                     # one per active channel
    proposal.md                     # this channel's per-run plan
    raw.md                          # wrapper output (skill-wrapper / command-wrapper)
    parsed.json                     # normalized findings handed to the aggregator
    lens-LN.md                      # per-lens log (lens-fanout only)
    synthesis.md                    # this channel's local synthesis
```

## Synthesis output

Main thread merges normalized findings from every channel. Aggregation mode from
`$FORGE_HOME/forge.toml` `[review].aggregation` (`interleave` default, `grouped`
alternative):

- **interleave** (default) — findings sorted by `(file, line)`. Each line
  carries a `[<channel-id>]` tag (and `<lens-id>` when present). Cross- channel
  duplicates collapsed; all source channels cited.
- **grouped** — one section per channel, findings within sorted blocker >
  major > minor > nit. Cross-channel duplicates surface once in their primary
  channel with a `(also: <other-channels>)` note.

Both modes close with a verdict block leading with the smallest blocking set + a
numbered action set + one action-choice question.

## Out-of-PR proposals

Any fix that would touch a file outside this PR's scope (follow-up PR, unrelated
refactor, sibling-module backfill, ticket) goes in a separate
`## Out-of-PR proposals` section, one bullet each, framed as a yes/no question —
never buried in the numbered fix list. Operator owns those scope decisions.

## Next step

- `READY` (all channels clean) → `/forge` (or autopilot continues).
- `REVIEWED_BLOCKED` (B+M > 0, any channel) → `/forge-review-green` to drive to
  green.
- `/forge-status` — chain state + drift.

## Usage

```
/forge-review                                   # current branch's PR + chain
/forge-review 21228                             # PR by number
/forge-review --slug auth-refactor              # explicit slug override
/forge-review --embed                           # also embed in PR body

# Channel control
/forge-review --add-channel code-review-builtin
/forge-review --add-channel security-review-builtin --channel security-review-builtin --scope src/auth
/forge-review --channels lens-fanout,security-review-builtin
/forge-review --drop-channel lens-fanout                     # unusual; runs wrappers only

# Lens-fanout-scoped (backward compat)
/forge-review --persona backend-senior
/forge-review --personas backend-senior,security-paranoid
/forge-review --no-persona
```
