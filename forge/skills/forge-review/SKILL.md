---
name: forge-review
description: "Multi-channel PR review — lens fan-out + code-review + security-review."
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

Runs N **review channels** in parallel, aggregates findings into one ranked
verdict; ground truth is the forge chain (`goals.md`, `links.json`, linked
tests), not the PR body.

Ships three channels (`forge/review-channels/`):

| Channel                   | Kind          | Default     | Wraps                                                           |
| ------------------------- | ------------- | ----------- | --------------------------------------------------------------- |
| `lens-fanout`             | agent-fanout  | **enabled** | parallel lens fan-out (`forge-lens-reviewer` agent + lens pool) |
| `code-review-builtin`     | skill-wrapper | **enabled** | Claude Code's built-in `/code-review`                           |
| `security-review-builtin` | skill-wrapper | **enabled** | Claude Code's built-in `/security-review`                       |

Host repo extends/overrides by dropping channel files into
`$FORGE_HOME/review-channels/` (same shape as `forge/review-channels/<id>.md` —
see `forge/review-channels/README.md`).

No forge chain → still runs, channels declaring `needs: forge-chain` skipped.
Broken chain → run `/forge` first (or `/forge-goals`, `/forge-scenarios`,
`/forge-tests`, `/forge-proof`) to restore chain-semantic coverage.

## Pipeline

1. Resolve slug + worktree + PR (per `/forge` rules).
2. Load `$FORGE_ART/branches/<slug>/{goals.md,links.json}`. Missing either →
   **no-chain mode**: channels needing `forge-chain` dropped with a one-line
   note.
3. Run `/forge-proof` (cached if recent). FAIL → refuse, point at report.
4. Scope intake: PR metadata, file list, +A/-D, base ref, stack position.
5. Risk hot-spots — 3-5 anchored to concrete diff paths. Available to channels
   that ask.
6. **Channel selection.** Enabled channels from `$FORGE_HOME/forge.toml`
   `[review].default_channels`, intersected with discovered channel files
   (`forge/review-channels/` + override `$FORGE_HOME/review-channels/`). CLI
   overrides: `--channels` replaces, `--add-channel <id>` /
   `--drop-channel <id>` mutate. Each channel's `needs` checked — unmet →
   dropped with one-line note.
7. **Per-channel design.** Run each selected channel's `## Selection` to build
   its work plan (`lens-fanout`: lens-design baseline + persona + designed;
   `code-review-builtin`: wholesale).
8. **Consultation gate** (mandatory). Operator approves channel set + each
   channel's per-run config (§ "Gate output").
9. **Dispatch.** Per channel, follow its `## Execution`. `agent-fanout`: all
   subagent calls in **a single message** for parallelism — pass `subagent_type`
   as the **exact** string the channel body names. For `lens-fanout` that is
   `@orrgal1/forge:forge-lens-reviewer` — **`/` before `forge`, `:` before the
   agent name**; the all-colons form `@orrgal1:forge:…` fails with "Agent type
   not found". `skill-wrapper`: Skill-call + ingest. `command-wrapper`: run +
   parse. Parallel when possible; channel body declares serial constraints.
10. **Normalize.** Apply each channel's `## Severity mapping` +
    `## Finding shape` to produce the unified shape.
11. **Aggregate.** Cap each finding against `severity_cap` (frontmatter + config
    override). Tag `channel: <id>` (and `lens: <id>` where applicable). Dedupe
    by `(file, line, content-hash)` — collapsed findings list all source
    channels.
12. **Synthesize, rank, emit verdict + ask** (§ "Synthesis output" + §
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

Top-level flags, implicitly scoped to `lens-fanout` (backward compat with
pre-channel `/forge-review`):

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
Forge: <slug> · G<n> goals · SG<n> scenarios · L<n> tests linked
Proof: PASS (<timestamp>)
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
`✗ <id> (skipped — needs forge-chain)`. Operator override via
`--add-channel <id>` only if the channel body permits forced execution; else
stays skipped.

## Severity

Forge-native 4-tier: `blocker` / `major` / `minor` / `nit`. Every channel
declares a `severity_mapping` (frontmatter + body) — the contract translating
native severities into forge tiers. `severity_cap` optionally ceilings a
channel; operator overrides in config or at the gate.

`/forge-review-green` (fix-loop) chases `blocker` + `major` regardless of source
channel.

## Verdict

Extends `/forge`'s wrap-verdict ladder:

| Verdict            | Meaning                                                                           |
| ------------------ | --------------------------------------------------------------------------------- |
| `READY`            | proof PASS, linked tests pass/skip, every channel clean (no blockers, no majors). |
| `RED_BAR`          | proof PASS but ≥1 linked test `fail` / `error`, or review-clean pending.          |
| `INCOMPLETE`       | proof FAIL — wrap skipped, review not run.                                        |
| `REVIEWED_BLOCKED` | proof PASS, tests pass, but aggregated review found ≥1 blocker (any channel).     |

`REVIEWED_BLOCKED` → fix blockers, re-run `/forge-review`, re-wrap.

## Embed

`--embed` writes the synthesis into its **own** collapsible block between
`<!-- forge-review:begin -->` / `<!-- forge-review:end -->`, wrapped in a
collapsed `<details>` (no `open` attribute) with a findings-bearing summary:

```
<!-- forge-review:begin -->
<details>
<summary>🔨 forge — review: <findings> · <slug></summary>

# /forge-review synthesis
…aggregated findings…

</details>
<!-- forge-review:end -->
```

`<findings>` is a short count (`1 blocker · 2 majors`, or `clean`), aggregated
across channels. This is a **sibling** of the proof block, never nested inside
it — see /forge-brief § Body-layout contract. Idempotent overwrite between the
review markers via `gh api`; preserves the brief and the proof block verbatim.
Appends after the proof block when present, else directly under the brief. No
proof block is **not** an error — review embeds independently. No PR → no-op,
hint "no PR yet — open one then re-run with --embed." No commit, no push, no CI
trigger.

## Artifact directory

```
$FORGE_ART/branches/<slug>/review/
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
`$FORGE_HOME/forge.toml` `[review].aggregation` (`interleave` default,
`grouped`):

- **interleave** (default) — sorted by `(file, line)`. Each line carries a
  `[<channel-id>]` tag (and `<lens-id>` when present). Cross-channel duplicates
  collapsed; all source channels cited.
- **grouped** — one section per channel, findings within sorted blocker >
  major > minor > nit. Cross-channel duplicates surface once in their primary
  channel with `(also: <other-channels>)`.

Both close with a verdict block leading with the smallest blocking set +
numbered action set + one action-choice question.

## Out-of-PR proposals

Any fix touching a file outside this PR's scope (follow-up PR, unrelated
refactor, sibling-module backfill, ticket) goes in a separate
`## Out-of-PR proposals` section, one bullet each, framed as yes/no — never
buried in the numbered fix list. Operator owns scope decisions.

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
