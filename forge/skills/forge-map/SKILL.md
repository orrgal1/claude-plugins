---
name: forge-map
description: "Domain maps of the host repo (db, api, events, config, ad-hoc) — pre-flight aid that builds JSON snapshots downstream agents cheap-load."
argument-hint:
  "[<area> | adhoc <name> --prompt <text>] [--list] [--refresh] [--all]
  [--scope <path>] [--out <file>] [--quiet]"
triggers:
  - "forge map"
  - "map this repo"
  - "map db schema"
  - "map api routes"
  - "map events"
  - "map config"
  - "refresh forge maps"
  - "map this for me"
  - "build me a map of"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Skill
user-invocable: true
---

# /forge-map — domain maps of the host repo

Pre-flight aid, not a chain phase. Builds structured JSON snapshots of areas
agents revisit constantly (db schema, api routes, events, config) so downstream
skills load a single file instead of re-discovering. Maps live under
`$FORGE_HOME/maps/` (per `/forge-setup` § "`$FORGE_HOME` resolver").

This skill is the **dispatcher**. Each canonical area has its own generator
skill (`/forge-map-db`, `/forge-map-api`, `/forge-map-events`,
`/forge-map-config`). This skill resolves the area, picks the right
ground-truth-or-branch path, calls the generator, updates the registry, and
prints a recap. Generators are not user-invocable — go through here.

It also runs **ad-hoc maps**: operator describes an area in prose
(`/forge-map adhoc <name> --prompt "<description>"`) and the dispatcher
performs the scan inline, writing the same JSON envelope. Ad-hoc lets the
operator spin up new map types on demand without authoring a new generator
skill — useful when the area is one-off or still being shaped. Promote to
a real generator once the shape stabilizes.

## Ground truth + branch divergence + absorption

Maps reflect repo state — which differs across branches. Forge handles
this with a git-shaped model:

- **Ground truth** lives under `$FORGE_HOME/maps/main/<area>.json` (the
  literal dir name follows `[meta].default_branch` — `master/` for older
  repos). Tied to the repo's default branch.
- **Reads** on any branch fall back to ground truth when no branch-specific
  map exists. Reads on the default branch always hit ground truth.
- **Writes** on a feature branch produce ground-truth content by default.
  Only when the generator's output **differs** from the ground-truth file
  does the dispatcher lazily fork into
  `$FORGE_HOME/maps/branches/<branch>/<area>.json`. Identical output → keep
  reading ground truth, don't fork. Saves disk + cognitive load.
- **Absorption** on merge: when the dispatcher runs on the default branch,
  it scans `$FORGE_HOME/maps/branches/*/` for branches that have merged
  (per `git branch --merged <default>` + remote-deletion check). For each
  merged branch with divergent maps, it offers: "absorb <branch>'s maps
  into ground truth? [y/N/diff]". Yes → replace `maps/main/<area>.json`
  with the branch's, delete `maps/branches/<branch>/`. Diff → side-by-side
  view, then prompt.
- **`branch_scoped = false`** in `[maps]` flattens to a single
  `$FORGE_HOME/maps/<area>.json` for repos that don't want this dance.

This means maps stay accurate on the default branch (the operator's main
context), feature branches get correct local snapshots when their changes
diverge, and merged work flows back into ground truth without manual
bookkeeping.

## When to run

- After `/forge-setup` on a fresh checkout, before the first `/forge` chain.
- When the repo's schema / routes / topics / config surface drifts.
- Operator on demand (`/forge-map db --refresh`).

Not part of `/forge` itself — chain skills read existing maps when present and
fall through silently when absent. Maps are an aid, not a gate.

## Areas

Output column shows the ground-truth path. Branch-divergent writes land at
`$FORGE_HOME/maps/branches/<branch>/<area>.json` (see § "Ground truth").

| Area     | Generator           | What it captures                                          | Output (ground truth)              |
| -------- | ------------------- | --------------------------------------------------------- | ---------------------------------- |
| `db`     | `/forge-map-db`     | Tables, columns, types, FKs, migrations dir, ORM models   | `$FORGE_HOME/maps/main/db.json`     |
| `api`    | `/forge-map-api`    | HTTP routes: method, path, handler `file:line`, types     | `$FORGE_HOME/maps/main/api.json`    |
| `events` | `/forge-map-events` | Topics, producers, consumers, payload refs                | `$FORGE_HOME/maps/main/events.json` |
| `config` | `/forge-map-config` | Env vars consumed, where read, defaults, secret hints     | `$FORGE_HOME/maps/main/config.json` |
| `adhoc <name>` | dispatcher (inline) | Operator-described area, agent-driven scan          | `$FORGE_HOME/maps/main/<name>.json` |

Unknown area name that isn't `adhoc` → halt `MAP_BLOCKED reason
unknown-area=<x>`. Never invent a canonical map type — to add a stable one,
ship a new generator skill and add the row above. Use `adhoc` for one-offs or
exploratory scans that haven't earned a generator yet.

## Inputs

| Input              | Required          | Notes                                                                                                       |
| ------------------ | ----------------- | ----------------------------------------------------------------------------------------------------------- |
| `<area>`           | unless `--list` / `--all` / `adhoc` | One of `db` / `api` / `events` / `config`.                                          |
| `adhoc <name>`     | with `--prompt`   | Ad-hoc map. `<name>` is the registry key (lowercase, alphanumerics + dashes). Reserved: any canonical area. |
| `--prompt <text>`  | with `adhoc`      | Operator's free-form description of what to map. Drives the inline scan.                                    |
| `--list`           | optional          | Print registry status from `$FORGE_HOME/forge.toml` `[maps]`, exit. No generation. No writes.                    |
| `--refresh`        | optional          | Force regenerate even if the map file is fresh vs source signals.                                           |
| `--all`            | optional          | Run every canonical generator. Does **not** re-run ad-hoc maps. Implies `--refresh`.                        |
| `--scope <path>`   | optional          | Restrict scan to a subtree (passed through to the generator).                                               |
| `--out <file>`     | optional          | Override output path (passed through). Default `$FORGE_HOME/maps/<area>.json`.                                   |
| `--quiet`          | optional          | Suppress recap; only emit the one-line per-area summary the generator returns.                              |

## Process

1. **Resolve repo root.** `git rev-parse --show-toplevel`. Not a git repo → halt
   `MAP_BLOCKED reason not-a-repo`.

2. **Bootstrap maps dir + registry** (idempotent):

   ```bash
   root="$(git rev-parse --show-toplevel)"
   mkdir -p "$root/$FORGE_HOME/maps"
   [ -f "$root/$FORGE_HOME/forge.toml" ] || /forge-setup --yes  # forge-setup is the source of truth for the file
   ```

   If `$FORGE_HOME/forge.toml` exists but has no `[maps]` section, append the
   skeleton from the schema below — never rewrite existing sections.

3. **`--list` short-circuit.** Read `[maps]` and print one row per known area
   (registered or not):

   ```
   area     file                       last_run               freshness
   area     file                                  last_run               freshness
   db       maps/main/db.json                     2026-05-31T08:14:00Z   fresh
   api      maps/main/api.json                    —                      missing
   events   —                                     —                      missing
   config   maps/main/config.json                 2026-04-12T11:02:00Z   stale (>30d)
   db       maps/branches/feat-new-orgs/db.json   2026-05-30T17:08:00Z   fresh (branch)
   ```

   Freshness rule:
   - `missing` — file not on disk
   - `stale` — file older than 30 days, **or** any source signal file declared
     in the map's own `source_files[]` is mtime-newer than the map file
   - `fresh` — otherwise

   Exit. No writes.

4. **Resolve the run set.**
   - `--all` → every canonical area in the registry table (`db` / `api` /
     `events` / `config`). Ad-hoc maps are intentionally excluded.
   - `<area>` → that single canonical area.
   - `adhoc <name>` → one ad-hoc run, inline (step 6).
   - Neither + no `--list` → halt `MAP_BLOCKED reason no-area-given`.
   - `adhoc <name>` with `<name>` matching a canonical area key → halt
     `MAP_BLOCKED reason adhoc-name-reserved=<name>`. Never shadow a generator.
   - `adhoc <name>` without `--prompt` → halt
     `MAP_BLOCKED reason adhoc-missing-prompt`.

5. **Per canonical area, dispatch to generator.** Call the generator skill (via
   the Skill tool) with passthrough flags: `--scope`, `--out`, `--quiet`, and
   `--refresh` (implicit when `--all`). Generator owns detection, scanning,
   writing the JSON, and updating `[maps.<area>]` in `forge.toml`.

   Generator missing → emit `NOT_IMPLEMENTED area=<area>` and continue with the
   next. Don't halt the batch.

6. **Ad-hoc run** (when `adhoc <name>` was given). The dispatcher runs the
   scan itself — no sub-skill. Steps:

   1. Read `--prompt` literally; treat it as the contract for what to find.
   2. Pick detection heuristics (grep patterns, file globs, parsers) that fit
      the prompt. Read host files via Read / Grep / Glob only. Never write
      outside `$FORGE_HOME/`.
   3. Normalize findings into items. Choose a stable item schema for this run
      and record it under the envelope's optional `item_schema` field (object
      describing field names + types). Without `item_schema` the agent
      reading the map can't trust the shape.
   4. Write the envelope to `--out` (default `$FORGE_HOME/maps/<name>.json`) with:
      - `area: "<name>"`
      - `generator: "/forge-map (adhoc)"`
      - `prompt: "<verbatim --prompt text>"` (extra optional field, persists
        the operator intent so re-runs preserve scope)
      - `item_schema: { … }`
      - everything else per the shared envelope below.
   5. Update `[maps.<name>]` in `$FORGE_HOME/forge.toml` with
      `generator = "/forge-map (adhoc)"` + `prompt = "<text>"`. Preserve
      `stale_after_days` and unknown keys.
   6. Emit the same one-line summary generators emit:
      `<name>: <N> items, <K> gaps → $FORGE_HOME/maps/<name>.json`.

   Ad-hoc never auto-runs under `--all`. Re-run by invoking
   `/forge-map adhoc <name> --prompt "<same or refined text>"` — the prompt is
   intentionally re-stated so drift stays visible.

7. **Recap** (unless `--quiet`). Same table shape as `--list`, regenerated from
   `[maps]` post-run, plus the next-move line. Ad-hoc maps appear after the
   canonical rows, sorted by name:

   ```
   ## /forge-map result

   verdict: MAPPED | PARTIAL | MAP_BLOCKED
   root:    <repo root>

   maps:
     db          <fresh | stale | missing>   <items count>   <gaps count>
     api         <…>
     events      <…>
     config      <…>
     <adhoc>     <…>                          (kind: adhoc)

   ### next move
   <one of: open $FORGE_HOME/maps/<area>.json  |  run /forge-map <area> --refresh  |  fix the block>
   ```

   `PARTIAL` when at least one generator returned `NOT_IMPLEMENTED` or wrote a
   non-empty `gaps[]`. `MAPPED` only when every requested area landed clean.

## Shared JSON envelope

Every generator writes the same outer shape. The `items[]` schema is
area-specific (defined in each generator's SKILL.md). This envelope is the
agent-facing contract — downstream skills can load any map and read counts,
freshness, and gaps without knowing the area.

```json
{
  "$schema": "https://orrgal1.dev/forge-map/v1.json",
  "area": "db",
  "generator": "/forge-map-db",
  "generated_at": "2026-05-28T08:00:00Z",
  "repo_root": "/abs/path/to/repo",
  "scope": ".",
  "source_files": [
    "db/migrations/0001_init.sql",
    "db/migrations/0002_users.sql"
  ],
  "items": [],
  "gaps": [
    { "reason": "unsupported-orm", "detail": "found prisma + drizzle; only prisma parsed" }
  ]
}
```

Field rules:

- `area` — one of the canonical area keys, or the ad-hoc `<name>`. Must match
  the filename stem.
- `generator` — the skill that produced it (`/forge-map-<area>`), or
  `"/forge-map (adhoc)"` for ad-hoc runs.
- `generated_at` — ISO-8601 UTC.
- `source_files[]` — the files whose mtimes drive freshness. Empty allowed.
- `items[]` — area-specific. Empty allowed (no findings ≠ failure).
- `gaps[]` — partial-coverage notes, never an error channel. Each gap is
  `{ reason, detail }`. Tooling failures are exit codes, not gap entries.

Optional fields written only by ad-hoc runs:

- `prompt` — the verbatim `--prompt` text the operator passed. Persists intent
  across re-runs.
- `item_schema` — a JSON object describing the `items[]` shape this run
  chose. Required for ad-hoc, omitted for canonical generators (their shape
  is defined in their SKILL.md).

Writes are atomic: tmp file in `$FORGE_HOME/maps/`, then `mv -f`.

## `[maps]` schema in `$FORGE_HOME/forge.toml`

Forge owns the registry. Each generator updates exactly its own subtable.
`/forge-setup --list` may surface this section in a future revision; for now it
is read-only outside generators + this skill.

```toml
# $FORGE_HOME/forge.toml — maps section is owned by /forge-map and its generators.
# Edit by re-running /forge-map; manual edits are honored but not recommended.

[maps]
# Where forge writes domain maps. Override per-area below if needed.
dir = "maps"

[maps.db]
file      = "maps/main/db.json"
last_run  = "2026-05-28T08:00:00Z"
generator = "/forge-map-db"
# Optional override of the freshness window (days). Default 30.
# stale_after_days = 30

[maps.api]
file      = "maps/main/api.json"
last_run  = ""
generator = "/forge-map-api"

[maps.events]
file      = "maps/main/events.json"
last_run  = ""
generator = "/forge-map-events"

[maps.config]
file      = "maps/main/config.json"
last_run  = ""
generator = "/forge-map-config"

# Example ad-hoc map — written by /forge-map adhoc <name> --prompt "..."
[maps.feature-flags]
file      = "maps/main/feature-flags.json"
last_run  = "2026-05-28T09:14:00Z"
generator = "/forge-map (adhoc)"
prompt    = "every call to isEnabled() and its flag key"
```

Subtable contract:

- `file` — path relative to `$FORGE_HOME/`. Required.
- `last_run` — ISO-8601 UTC of the most recent successful generator run, or
  empty string. Required field, empty is valid.
- `generator` — the canonical skill name, or `"/forge-map (adhoc)"`. Required.
- `prompt` — required when `generator = "/forge-map (adhoc)"`, omitted
  otherwise.
- `stale_after_days` — optional integer; falls back to the dispatcher's
  default (30) when absent.

Unknown subtables are tolerated (forward-compat) but ignored by `--list`.

## Honesty

- **Maps are snapshots, not source of truth.** Anything an agent reads here it
  must verify against live source before acting on it. Freshness signals are
  hints, not guarantees.
- **Never invent items.** A generator that can't parse a construct emits a
  `gap`, not a guessed entry. Empty `items[]` is a valid result.
- **Never partial-write.** Atomic mv only. A crashed generator leaves the
  previous map intact.
- **Never write outside `$FORGE_HOME/`.** Generators read the host repo; they only
  write under `$FORGE_HOME/maps/` and `$FORGE_HOME/forge.toml`.
- **No host-repo edits.** Maps are auxiliary; never modify tracked files.
- **Ad-hoc is bounded the same way.** The free-form `--prompt` does not
  loosen the contract — same envelope, same atomic write, same `$FORGE_HOME/`-only
  write surface, same `gap` discipline. The prompt directs *what* to scan, not
  *how* the output is shaped.
- **Promote ad-hoc when it stabilizes.** Once an ad-hoc map name re-runs with
  a steady shape, ship a real generator skill and drop the `adhoc` form.
  Keeping ad-hoc forever lets the shape silently drift.
