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
introduced-by: forge-review
---

# Lens fan-out — forge's default review channel

Parallel, lens-designed PR review. Ground truth comes from the forge chain
(`goals.md`, `links.json`, linked tests) when available. Seven always-on
lenses (3 chain-semantic, 4 code-quality) + persona-derived lenses + 1–3
per-PR designed lenses against the diff's risk surface. Target 7–9 total.

This channel is the forge plugin's bundled default — shipped enabled, always
present unless explicitly dropped. Other channels coexist as peers
(`code-review-builtin`, `security-review-builtin`, custom). Their findings
aggregate alongside this channel's at `/forge-review` synthesis time.

## Selection

### Always-on lenses

Definitions live in `lenses/<id>.md` (a host repo may override or add via
`.forge/lenses/<id>.md`). The lens body is inlined verbatim in each subagent
brief.

| L#  | Pool id            | Group          | Brief artifacts                   |
| --- | ------------------ | -------------- | --------------------------------- |
| L0  | `goal-delivery`    | chain-semantic | `goals.md`, PR description        |
| L1  | `scenario-realism` | chain-semantic | `goals.md`                        |
| L2  | `test-match`       | chain-semantic | `links.json`, linked test files   |
| L3  | `clean-code`       | code-quality   | —                                 |
| L4  | `elegance`         | code-quality   | —                                 |
| L5  | `robustness`       | code-quality   | —                                 |
| L6  | `commentary`       | code-quality   | commentary surface (diff-derived) |

L0–L2 (chain-semantic) require `goals.md` + `links.json`. On a PR with no
chain they're skipped automatically — channel still runs with L3–L6 +
persona + designed lenses only. L3–L6 can be edited at the gate.

### Persona-derived lenses

`--persona <id>` / `--personas <a,b,c>` (top-level flags, scoped to this
channel) — comma-separated union+dedup. Unknown id → abort with valid-id
list. `--no-persona` skips picker.

Default: interactive picker at the gate (numbered list; `none` is the safe
explicit default). Persona's `lenses:` union with baseline. Missing lens id
in persona → hard error.

### Per-PR designed lenses (L7+)

Designed against the diff's risk surface per `lenses/README.md` §
"Designing per-PR lenses" — wire contract, schema fidelity, mapping /
dispatch invariants, coupling, naming, wire-up symmetry. 1–3 to land in the
7–9 sweet spot.

## Execution

Agent: `@orrgal1/forge:forge-lens-reviewer`.

One Agent call per selected lens, all sent in **a single message** for true
parallelism. Each agent gets its own brief — instructions + lens-specific
artifacts — and returns structured findings.

### Subagent brief

The `forge-lens-reviewer` agent bakes severity tiers, line format, scope
guard, and read-full-files rule. The brief only supplies context.

For always-on lenses, brief is assembled mechanically from the pool entry:

- **Lens focus** — pool file body (after frontmatter), inlined verbatim.
- **Brief artifacts** per pool's `brief-artifacts:` list:
  - `goals.md` — full contents in `## Goals` block.
  - `pr-description` — PR body verbatim in `## PR description` block.
  - `links.json` — full contents + linked test paths (agent reads tests
    directly from the worktree).
  - `commentary-surface` — every added/modified comment, docstring, or note
    in the diff with surrounding code context.
  - `full-diff` / `linked-test-files` per the `brief-artifacts` schema in
    `lenses/README.md`.
- **Worktree path + file scope** — always included.

L7+ briefs carry only file scope + lens focus.

### Order

Two modes:

- `lens-mode` (default) — one agent per lens, full file scope per agent.
- `file-by-file` — one agent per file, every lens applied within. Opt in
  via `--order file-by-file` at the gate.

## Finding shape

Each agent returns findings in the forge-native shape — no normalization
needed for this channel:

```json
{
  "channel": "lens-fanout",
  "lens": "clean-code",
  "file": "src/auth/middleware.ts",
  "line": 42,
  "severity": "major",
  "body": "...",
  "fix": "...",
  "ref": null
}
```

`channel` is filled by the dispatcher (always `lens-fanout` for this
channel). `lens` is the pool id that produced the finding.

## Severity mapping

Native severities are already forge's 4-tier — identity mapping:

| Lens output | Forge | Notes                                                            |
| ----------- | ----- | ---------------------------------------------------------------- |
| `blocker`   | blocker | Must-fix before merge. Drives `/forge-review-green`.            |
| `major`     | major   | Should-fix; drives the green-loop.                              |
| `minor`     | minor   | Hygiene; informational unless promoted.                         |
| `nit`       | nit     | Cosmetic.                                                       |

Each pool lens declares its `severity-floor:` in frontmatter; body documents
promotion rules. The agent honors floors per-lens.

`severity_cap` in this channel's config is `null` (no cap) — lens findings
keep their native severity all the way through.

## Channel-scoped config

`.forge/forge.toml`:

```toml
[review.channels.lens-fanout]
enabled       = true            # master switch
agent         = "@orrgal1/forge:forge-lens-reviewer"
lens_dir      = "lenses"        # relative to plugin root; .forge/lenses/ overrides per file
persona       = ""              # default persona id; CLI --persona overrides
order         = "lens-mode"     # or "file-by-file"
severity_cap  = ""              # empty = no cap; values: blocker/major/minor/nit
```

## Artifact directory

Per-channel artifacts under the channel id:

```
.pr-artifacts/<slug>/forge/review/lens-fanout/
  proposal.md       # lens-design proposal echoed at the gate
  lens-LN.md        # per-lens finding log (local; not tracked)
  synthesis.md      # this channel's synthesis (local; not tracked)
```

Aggregated synthesis across all channels lives one level up at
`.pr-artifacts/<slug>/forge/review/synthesis.md`.

## Notes for /forge-review

- This channel **always exists**. Operator dropping it (`--drop-channel
  lens-fanout`) is honored but flagged at the gate as unusual.
- Consultation gate for this channel covers: lens edits (add/drop/rename/
  merge/split), persona selection, order. Other channels have their own
  gate sections.
- `/forge-review-green` drives this channel's blockers + majors the same
  way it always has — no change in fix-loop behavior.
