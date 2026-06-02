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
(`goals.md`, `links.json`, linked tests) when available. The selected lens set
is composed in three tiers — an **always-on core**, **chain-conditional** lenses
that fire only when a chain exists, and **diff-fingerprint auto-selected**
specialists that fire only when the diff touches their surface — plus
persona-derived and (rarely) per-PR designed lenses on top.

This channel is the forge plugin's bundled default — shipped enabled, always
present unless explicitly dropped. Other channels coexist as peers
(`code-review-builtin`, `security-review-builtin`, custom). Their findings
aggregate alongside this channel's at `/forge-review` synthesis time.

## Selection

Definitions live in `lenses/<id>.md` (a host repo may override or add via
`.forge/lenses/<id>.md`). The lens body is inlined verbatim in each subagent
brief. The dispatcher composes the set at review time from three tiers, then
dedups against persona + designed lenses (if a designed lens would duplicate a
selected pool lens, drop the designed one).

### Tier 1 — always-on core

Runs on **every** review, chain or not. Cheap + universal hygiene/correctness.

| Pool id                   | Group        | Brief artifacts                   |
| ------------------------- | ------------ | --------------------------------- |
| `clean-code`              | code-quality | —                                 |
| `elegance`                | code-quality | —                                 |
| `robustness`              | code-quality | —                                 |
| `commentary`              | code-quality | commentary surface (diff-derived) |
| `codebase-idiom`          | code-quality | —                                 |
| `ai-slop`                 | hygiene      | —                                 |
| `scope`                   | hygiene      | PR description                    |
| `pr-description-fidelity` | hygiene      | PR description                    |
| `correctness`             | correctness  | —                                 |
| `completeness`            | correctness  | —                                 |

### Tier 2 — chain-conditional

Require the forge chain (`goals.md` / `links.json`). On a PR with **no chain**
they're skipped automatically; the review still runs Tier 1 + Tier 3 + persona +
designed. When a chain exists, `pr-description-fidelity` (Tier 1) and
`goal-delivery` (Tier 2) overlap on fidelity — the chain lens is authoritative,
the description lens still covers file-list / claim drift.

| Pool id            | Group          | Brief artifacts                 |
| ------------------ | -------------- | ------------------------------- |
| `goal-delivery`    | chain-semantic | `goals.md`, PR description      |
| `scenario-realism` | chain-semantic | `goals.md`                      |
| `test-match`       | chain-semantic | `links.json`, linked test files |

### Tier 3 — diff-fingerprint auto-select

The dispatcher fingerprints the diff and fires each specialist **only when its
surface is touched** — keeps each review focused and the all-severity fix loop
bounded. A lens fires if ANY of its triggers match.

| Pool id             | Fires when the diff touches …                                                                      |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| `security`          | auth / authz / crypto / secrets / IAM / signatures / input validation / request handlers           |
| `production-wiring` | a new interface+impl, constructor, registered endpoint, background job, feature flag, or migration |
| `paired-tier-types` | cross-tier type defs (proto, pydantic, ORM schema, OpenAPI, TS API types)                          |
| `api-design`        | public API surface — routes, request/response shapes, exported client                              |
| `observability`     | service code with failure paths, async work, or external calls (oncall-relevant)                   |
| `test-quality`      | new / changed test files                                                                           |

Fingerprint heuristics live in `lenses/README.md` § "Diff fingerprint → lens".
Tier 1 + selected Tier 2/3 lenses can be edited at the gate (add/drop).

### Persona-derived lenses

`--persona <id>` / `--personas <a,b,c>` (top-level flags, scoped to this
channel) — comma-separated union+dedup. Unknown id → abort with valid-id list.
`--no-persona` skips picker.

Default: interactive picker at the gate (numbered list; `none` is the safe
explicit default). Persona's `lenses:` union with baseline. Missing lens id in
persona → hard error.

### Per-PR designed lenses (L7+)

Designed against the diff's risk surface per `lenses/README.md` § "Designing
per-PR lenses" — wire contract, schema fidelity, mapping / dispatch invariants,
coupling, naming, wire-up symmetry. With Tier 1–3 now covering most recurring
surfaces, designed lenses are the **exception** (0–2): reach for one only when
the diff has a risk no pool lens captures. If a designed lens would duplicate a
selected pool lens, drop it.

## Execution

Agent: `@orrgal1/forge:forge-lens-reviewer`.

One Agent call per selected lens, all sent in **a single message** for true
parallelism. Each agent gets its own brief — instructions + lens-specific
artifacts — and returns structured findings.

### Subagent brief

The `forge-lens-reviewer` agent bakes severity tiers, line format, scope guard,
and read-full-files rule. The brief only supplies context.

For always-on lenses, brief is assembled mechanically from the pool entry:

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

### Order

Two modes:

- `lens-mode` (default) — one agent per lens, full file scope per agent.
- `file-by-file` — one agent per file, every lens applied within. Opt in via
  `--order file-by-file` at the gate.

## Finding shape

Each agent returns findings in the forge-native shape — no normalization needed
for this channel:

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

`channel` is filled by the dispatcher (always `lens-fanout` for this channel).
`lens` is the pool id that produced the finding.

## Severity mapping

Native severities are already forge's 4-tier — identity mapping:

| Lens output | Forge   | Notes                                                |
| ----------- | ------- | ---------------------------------------------------- |
| `blocker`   | blocker | Must-fix before merge. Drives `/forge-review-green`. |
| `major`     | major   | Should-fix; drives the green-loop.                   |
| `minor`     | minor   | Hygiene; informational unless promoted.              |
| `nit`       | nit     | Cosmetic.                                            |

Each pool lens declares its `severity-floor:` in frontmatter; body documents
promotion rules. The agent honors floors per-lens.

`severity_cap` in this channel's config is `null` (no cap) — lens findings keep
their native severity all the way through.

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

- This channel **always exists**. Operator dropping it
  (`--drop-channel lens-fanout`) is honored but flagged at the gate as unusual.
- Consultation gate for this channel covers: lens edits (add/drop/rename/
  merge/split), persona selection, order. Other channels have their own gate
  sections.
- `/forge-review-green` drives this channel's findings at **every** severity
  (blocker through nit) to zero — no severity-tier skipping.
