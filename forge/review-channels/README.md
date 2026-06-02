# Review channels

A **channel** is one review mechanism `/forge-review` runs. The default
mechanism — the parallel lens fan-out — is one channel (`lens-fanout`). Other
channels wrap external review skills, run shell commands, or fan out to
different agent shapes. Channels coexist: a single `/forge-review` invocation
can run several, and findings are normalized to forge's 4-tier severity
(`blocker` / `major` / `minor` / `nit`), tagged with their source, deduped, and
aggregated.

This dir ships **inside the forge plugin** — no dependency on any other plugin.
A host repo extends or overrides by dropping channel files into
`.forge/review-channels/` (same schema); forge prefers
`.forge/review-channels/<id>.md` over the bundled one when both exist.

## File layout

One channel per file. Filename = channel id (slug, lowercase, hyphen-separated):

```
review-channels/
  README.md                    # this file
  lens-fanout.md               # id: lens-fanout   (always-shipped default)
  code-review-builtin.md       # id: code-review-builtin
  security-review-builtin.md   # id: security-review-builtin
```

Adding a channel never renumbers anything — channels are identified by id across
all surfaces (config, CLI flags, finding tags).

## File schema

YAML frontmatter + markdown body. The body is the channel's contract — what
`/forge-review` reads and follows when running this channel.

```markdown
---
id: lens-fanout
name: Lens fan-out
kind: agent-fanout
default_enabled: true
severity_cap: null
severity_mapping:
  blocker: blocker
  major: major
  minor: minor
  nit: nit
needs:
  - diff
  - forge-chain
introduced-by: forge-review
---

# Lens fan-out

<channel body — instructions /forge-review follows literally. Includes:
selection (lenses, agents, briefs), execution, finding normalization.>
```

### Frontmatter fields

| Field              | Type   | Meaning                                                                                                                                                                                      |
| ------------------ | ------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `id`               | slug   | Stable identifier. Must match filename (`<id>.md`). Referenced by config + CLI flags + finding tags.                                                                                         |
| `name`             | string | Human-readable label used in the consultation gate.                                                                                                                                          |
| `kind`             | enum   | `agent-fanout` (parallel agent calls), `skill-wrapper` (Skill-invoke + normalize), `command-wrapper` (shell command + parse).                                                                |
| `default_enabled`  | bool   | When `true` the channel is seeded into `default_channels` at setup, so it runs without explicit opt-in. Bundled defaults: `lens-fanout` + `code-review-builtin` + `security-review-builtin`. |
| `severity_cap`     | enum   | Optional ceiling: `blocker` / `major` / `minor` / `nit` / `null`. Findings from this channel never exceed the cap. `null` = no cap.                                                          |
| `severity_mapping` | map    | Required when the channel emits non-forge-native severities (skill-wrapper, command-wrapper). Maps native → forge severity.                                                                  |
| `needs`            | list   | Pre-conditions the channel needs: `diff`, `forge-chain` (`goals.md` / `links.json`), `pr-metadata`. `/forge-review` enforces.                                                                |
| `introduced-by`    | string | Provenance — which skill / use case introduced it. Free text.                                                                                                                                |

### Body

Markdown after the frontmatter. Required sections (use these headings so
`/forge-review` can locate them):

- `## Selection` — what this channel picks to review (lenses, files, scope).
  Empty when the channel is wholesale (e.g. wraps a Skill that decides for
  itself).
- `## Execution` — how to actually run. For `agent-fanout`: agent name, brief
  shape, parallelism rules. For `skill-wrapper`: Skill name, args, expected
  output format. For `command-wrapper`: command, arg format, expected output
  parser.
- `## Finding shape` — the channel's native finding fields and how they map into
  the unified shape: `{ channel, file, line, severity, body, fix, ref }`.
- `## Severity mapping` — how to translate this channel's native severities into
  forge's 4-tier. Must match `severity_mapping` in frontmatter.

## Channel kinds

### `agent-fanout`

Channel fans out N subagents in parallel, one per work item (lens, file, risk
area). Each subagent gets a brief — instructions + relevant artifacts — and
returns structured findings. `lens-fanout` is the canonical example.

Use when the review needs **many narrow viewpoints** assembled in parallel.

### `skill-wrapper`

Channel Skill-calls another review skill (`/code-review`, `/security-review`, a
custom org skill), ingests its output, and normalizes to the unified finding
shape. Channel body provides the severity mapping and any output parsing
instructions.

Use when an off-the-shelf review skill already covers the territory and you want
its signal inside the forge review pipeline.

### `command-wrapper`

Channel runs a shell command (lint tool, SAST scanner, custom CI hook), parses
its output, and normalizes. Useful for repo-local tools that aren't exposed as
skills.

Use when the signal comes from a binary the repo already runs.

## Configuration

Per-repo defaults live in `.forge/forge.toml` `[review]` and
`[review.channels.<id>]`:

```toml
[review]
default_channels = ["lens-fanout", "code-review-builtin", "security-review-builtin"]
aggregation      = "interleave"     # or "grouped"

[review.channels.lens-fanout]
enabled = true

[review.channels.code-review-builtin]
enabled      = true
effort       = "medium"
severity_cap = "major"
```

`enabled` is the master switch. `severity_cap` overrides the channel
frontmatter's default cap. Other fields are channel-specific — see each
channel's body for what it reads.

Per-run overrides via `/forge-review` CLI: `--channels <ids>` replaces the set,
`--add-channel <id>` / `--drop-channel <id>` mutates. Channel-scoped flags use
`--channel <id> --<flag> <value>`.

## Finding aggregation

After every selected channel runs, `/forge-review` aggregates findings:

1. **Cap** each finding's severity against the channel's `severity_cap`
   (frontmatter + config-override).
2. **Tag** each finding with `channel: <id>` (and `lens: <id>` when the channel
   surfaces lens identity).
3. **Dedupe** by `(file, line, content-hash)` — same finding reported by
   multiple channels collapses to one with multiple sources listed.
4. **Sort** per the aggregation mode:
   - `interleave` (default) — by `(file, line)`. Channel shown as tag.
   - `grouped` — section per channel, file/line within.
5. **Verdict** — `/forge-review-green` chases **every** open finding regardless
   of source channel or severity (blocker through nit). Severity sets fix order,
   not whether a finding is fixed; minors + nits are drained too, never left
   informational.

## Authoring a new channel

1. Copy a bundled channel as a starting template (`lens-fanout.md` for
   agent-fanout, `code-review-builtin.md` for skill-wrapper).
2. Pick an id (lowercase slug). Add `<id>.md` to either this dir (to ship inside
   a fork of the plugin) or `.forge/review-channels/` (host-repo only).
3. Fill the required frontmatter + the four body sections.
4. Add the matching `[review.channels.<id>]` subtable to `.forge/forge.toml` if
   the channel needs config (or rely on its frontmatter defaults).
5. Test via `/forge-review --add-channel <id>` on a small PR before adding to
   `default_channels`.

## Authoring discipline

- **One concern per channel.** Don't bundle "lint + SAST + style" into one
  channel — each is its own channel, with its own severity cap, that the
  operator can toggle independently.
- **Severity mapping is mandatory for non-native channels.** Never default a
  skill-wrapper or command-wrapper to "minor for everything" — make the mapping
  explicit so the operator sees the contract.
- **Channels are advisory by default for wrappers.** Set `severity_cap` if the
  wrapped tool tends to produce noise; the operator can promote in
  `.forge/forge.toml` when they trust it.
- **Channels run in parallel when possible.** A channel that needs serial
  ordering relative to others should say so in its body — `/forge-review`
  defaults to parallel execution.
