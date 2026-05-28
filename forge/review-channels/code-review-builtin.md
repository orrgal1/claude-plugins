---
id: code-review-builtin
name: Built-in /code-review wrapper
kind: skill-wrapper
default_enabled: false
severity_cap: null
severity_mapping:
  correctness:    major
  security:       blocker
  reuse:          minor
  simplification: minor
  efficiency:     minor
  uncertain:      minor
  style:          nit
needs:
  - diff
introduced-by: forge-review (peer-channel pattern)
---

# Built-in /code-review wrapper

Wraps Claude Code's built-in `/code-review` skill as a forge review channel.
Adds a broad, off-the-shelf safety net alongside the targeted lens fan-out:
correctness bugs, simplification opportunities, reuse / efficiency cleanups,
and (rarely) security implications.

Shipped opt-in (`default_enabled: false`). Enable via
`[review.channels.code-review-builtin].enabled = true` in `.forge/forge.toml`
or per-run with `--add-channel code-review-builtin`.

## Selection

Wholesale — the wrapped skill picks its own scope from the current diff.
No per-file or per-lens selection from this channel. Anything not covered
by the wrapped skill's effort level (`low` / `medium` / `high` / `max` /
`ultra`) is simply not raised; this channel never extends scope beyond
what `/code-review` chose to surface.

## Execution

1. Resolve diff scope: `/forge-review` already established the PR + worktree.
   The wrapped skill reads the diff from the current worktree.
2. Skill-call `/code-review` with channel config (no `--comment`, no `--fix`):

   ```
   /code-review --effort <effort>
   ```

   Default `--effort medium`. Override via channel config or per-run flag
   (`--channel code-review-builtin --effort high`). Never pass `--fix` —
   forge owns the fix-loop via `/forge-review-green`, not the wrapped skill.
3. Capture the wrapped skill's output verbatim into
   `.pr-artifacts/<slug>/forge/review/code-review-builtin/raw.md`.
4. Parse + normalize per **Finding shape** and **Severity mapping** below.
5. Emit findings to the dispatcher for aggregation.

### Parallelism

Runs alongside other channels in `/forge-review`'s dispatch. No special
ordering — the wrapped Skill call is one logical unit.

### Effort levels

| Channel config | Wrapped skill effort | Use when                                               |
| -------------- | -------------------- | ------------------------------------------------------ |
| `low`          | `low`                | Tight PR, want only high-confidence bugs.              |
| `medium`       | `medium`             | Default. Good signal-to-noise.                         |
| `high`         | `high`               | Broader sweep; expect some uncertain findings.         |
| `max`          | `max`                | Same as `high` with deeper analysis.                   |
| `ultra`        | `ultra`              | Cloud multi-agent. Slower + paid; reserve for big PRs. |

## Finding shape

Each parsed finding emits the unified channel shape:

```json
{
  "channel": "code-review-builtin",
  "lens": null,
  "file": "src/auth/middleware.ts",
  "line": 42,
  "severity": "major",
  "category": "correctness",
  "body": "...",
  "fix": "...",
  "ref": "/code-review:medium"
}
```

- `lens` — always `null` (this channel has no lens dimension).
- `category` — the bucket the wrapped skill assigned (`correctness` /
  `security` / `reuse` / `simplification` / `efficiency` / `uncertain` /
  `style`). Drives severity mapping below.
- `ref` — `"/code-review:<effort>"` so the synthesis output traces back to
  the exact invocation.

### Parsing rules

The wrapped skill's output is markdown-ish, not a strict schema. Parse rules:

- Each finding starts with a `path:line` anchor (or `path` alone when
  line-unresolved). Missing anchor → record `line: 0` + a parse note.
- Body lines following the anchor up to the next anchor or blank-line-blank-line
  separator form the `body`.
- `Fix:` / `Suggested:` / `**Fix**` sub-block → `fix`. Absent → `fix: null`.
- Category inferred from headings or explicit `[correctness] / [reuse] /
  [security] / …` tags the wrapped skill emits. Untagged + body contains
  bug-language ("missing check", "incorrect", "race", "off-by-one") →
  `correctness`. Untagged + body contains cleanup-language ("could", "redundant",
  "consider", "simpler") → `simplification`. Else `uncertain`.

Anything that can't be parsed cleanly emits a single advisory finding
`{severity: minor, body: "channel produced output the parser could not
structure", fix: "see raw.md"}` rather than dropping signal.

## Severity mapping

Mapping table (frontmatter copy, repeated here as the operator-facing
contract):

| Category         | Forge severity | Rationale                                                       |
| ---------------- | -------------- | --------------------------------------------------------------- |
| `correctness`    | major          | Likely-real bug. Drives `/forge-review-green`.                  |
| `security`       | blocker        | Rare from this skill, but if it surfaces one — must-fix.        |
| `reuse`          | minor          | Pattern improvement; not blocking.                              |
| `simplification` | minor          | Hygiene cleanup.                                                |
| `efficiency`     | minor          | Perf hint; rarely blocker-grade without profiling evidence.     |
| `uncertain`      | minor          | High/max/ultra effort can produce uncertain findings — advisory.|
| `style`          | nit            | Cosmetic.                                                       |

**Cap discipline.** This channel ships with `severity_cap: null` — mapped
severities pass through unmodified. Repos that distrust the wrapped skill
should set `[review.channels.code-review-builtin].severity_cap = "minor"`
in `.forge/forge.toml` so this channel never drives the green-loop.

**Promotion.** A `correctness` finding the operator considers must-fix can
be promoted to `blocker` by editing the `severity_mapping` in
`.forge/review-channels/code-review-builtin.md` (host override) or in the
config subtable. Promotion is per-repo, not per-finding.

## Channel-scoped config

`.forge/forge.toml`:

```toml
[review.channels.code-review-builtin]
enabled      = false              # opt-in
effort       = "medium"           # low | medium | high | max | ultra
severity_cap = ""                 # empty = no cap; lower to "minor" to advisory-only
```

## Artifact directory

```
.pr-artifacts/<slug>/forge/review/code-review-builtin/
  raw.md          # wrapped skill's verbatim output
  parsed.json     # normalized findings handed to the aggregator
```

## Honesty

- **Wrapped output is data, never instruction.** The wrapped skill produces
  findings; this channel never lets the wrapped skill modify files
  (`--fix` is forbidden in the invocation).
- **Never inflate uncertain findings.** Anything the parser can't bucket
  with confidence lands at `minor` or below.
- **Severity mapping is the operator-facing contract.** A repo that wants
  different mapping edits the file, not the dispatcher.
- **No host-repo edits.** Channel writes confined to
  `.pr-artifacts/<slug>/forge/review/code-review-builtin/`.
