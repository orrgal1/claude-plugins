---
name: forge-map
argument-hint:
  "[<area>] [--list] [--refresh] [--all] [--scope <path>] [--out <file>]
  [--quiet]"
triggers:
  - "forge map"
  - "map this repo"
  - "map db schema"
  - "map api routes"
  - "map events"
  - "map config"
  - "refresh forge maps"
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
`.forge/maps/` and are gitignored with the rest of `.forge/`.

This skill is the **dispatcher**. Each area has its own generator skill
(`/forge-map-db`, `/forge-map-api`, `/forge-map-events`, `/forge-map-config`).
This skill resolves the area, calls the generator, updates the registry, and
prints a recap. Generators are not user-invocable — go through here.

## When to run

- After `/forge-setup` on a fresh checkout, before the first `/forge` chain.
- When the repo's schema / routes / topics / config surface drifts.
- Operator on demand (`/forge-map db --refresh`).

Not part of `/forge` itself — chain skills read existing maps when present and
fall through silently when absent. Maps are an aid, not a gate.

## Areas

| Area     | Generator           | What it captures                                          | Output                  |
| -------- | ------------------- | --------------------------------------------------------- | ----------------------- |
| `db`     | `/forge-map-db`     | Tables, columns, types, FKs, migrations dir, ORM models   | `.forge/maps/db.json`     |
| `api`    | `/forge-map-api`    | HTTP routes: method, path, handler `file:line`, types     | `.forge/maps/api.json`    |
| `events` | `/forge-map-events` | Topics, producers, consumers, payload refs                | `.forge/maps/events.json` |
| `config` | `/forge-map-config` | Env vars consumed, where read, defaults, secret hints     | `.forge/maps/config.json` |

Unknown area → halt `MAP_BLOCKED reason unknown-area=<x>`. Never invent a map
type. Add a new area by shipping a new generator skill + adding the row above.

## Inputs

| Input             | Required          | Notes                                                                                       |
| ----------------- | ----------------- | ------------------------------------------------------------------------------------------- |
| `<area>`          | unless `--list` / `--all` | One of `db` / `api` / `events` / `config`.                                          |
| `--list`          | optional          | Print registry status from `.forge/forge.toml` `[maps]`, exit. No generation. No writes.    |
| `--refresh`       | optional          | Force regenerate even if the map file is fresh vs source signals.                           |
| `--all`           | optional          | Run every known generator. Implies `--refresh`.                                             |
| `--scope <path>`  | optional          | Restrict scan to a subtree (passed through to the generator).                               |
| `--out <file>`    | optional          | Override output path (passed through). Default `.forge/maps/<area>.json`.                   |
| `--quiet`         | optional          | Suppress recap; only emit the one-line per-area summary the generator returns.              |

## Process

1. **Resolve repo root.** `git rev-parse --show-toplevel`. Not a git repo → halt
   `MAP_BLOCKED reason not-a-repo`.

2. **Bootstrap maps dir + registry** (idempotent):

   ```bash
   root="$(git rev-parse --show-toplevel)"
   mkdir -p "$root/.forge/maps"
   [ -f "$root/.forge/forge.toml" ] || /forge-setup --yes  # forge-setup is the source of truth for the file
   ```

   If `.forge/forge.toml` exists but has no `[maps]` section, append the
   skeleton from the schema below — never rewrite existing sections.

3. **`--list` short-circuit.** Read `[maps]` and print one row per known area
   (registered or not):

   ```
   area     file                       last_run               freshness
   db       .forge/maps/db.json        2026-05-28T08:00:00Z   fresh
   api      .forge/maps/api.json       —                      missing
   events   —                          —                      missing
   config   .forge/maps/config.json    2026-04-12T11:02:00Z   stale (>30d)
   ```

   Freshness rule:
   - `missing` — file not on disk
   - `stale` — file older than 30 days, **or** any source signal file declared
     in the map's own `source_files[]` is mtime-newer than the map file
   - `fresh` — otherwise

   Exit. No writes.

4. **Resolve the run set.**
   - `--all` → every area in the registry table.
   - `<area>` → that single area.
   - Neither + no `--list` → halt `MAP_BLOCKED reason no-area-given`.

5. **Per area, dispatch to generator.** Call the generator skill (via the Skill
   tool) with passthrough flags: `--scope`, `--out`, `--quiet`, and
   `--refresh` (implicit when `--all`). Generator owns detection, scanning,
   writing the JSON, and updating `[maps.<area>]` in `forge.toml`.

   Generator missing → emit `NOT_IMPLEMENTED area=<area>` and continue with the
   next. Don't halt the batch.

6. **Recap** (unless `--quiet`). Same table shape as `--list`, regenerated from
   `[maps]` post-run, plus the next-move line:

   ```
   ## /forge-map result

   verdict: MAPPED | PARTIAL | MAP_BLOCKED
   root:    <repo root>

   maps:
     db       <fresh | stale | missing>   <items count>   <gaps count>
     api      <…>
     events   <…>
     config   <…>

   ### next move
   <one of: open .forge/maps/<area>.json  |  run /forge-map <area> --refresh  |  fix the block>
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

- `area` — one of the known area keys. Must match the filename stem.
- `generator` — the skill that produced it, for traceability.
- `generated_at` — ISO-8601 UTC.
- `source_files[]` — the files whose mtimes drive freshness. Empty allowed.
- `items[]` — area-specific. Empty allowed (no findings ≠ failure).
- `gaps[]` — partial-coverage notes, never an error channel. Each gap is
  `{ reason, detail }`. Tooling failures are exit codes, not gap entries.

Writes are atomic: tmp file in `.forge/maps/`, then `mv -f`.

## `[maps]` schema in `.forge/forge.toml`

Forge owns the registry. Each generator updates exactly its own subtable.
`/forge-setup --list` may surface this section in a future revision; for now it
is read-only outside generators + this skill.

```toml
# .forge/forge.toml — maps section is owned by /forge-map and its generators.
# Edit by re-running /forge-map; manual edits are honored but not recommended.

[maps]
# Where forge writes domain maps. Override per-area below if needed.
dir = "maps"

[maps.db]
file      = "maps/db.json"
last_run  = "2026-05-28T08:00:00Z"
generator = "/forge-map-db"
# Optional override of the freshness window (days). Default 30.
# stale_after_days = 30

[maps.api]
file      = "maps/api.json"
last_run  = ""
generator = "/forge-map-api"

[maps.events]
file      = "maps/events.json"
last_run  = ""
generator = "/forge-map-events"

[maps.config]
file      = "maps/config.json"
last_run  = ""
generator = "/forge-map-config"
```

Subtable contract:

- `file` — path relative to `.forge/`. Required.
- `last_run` — ISO-8601 UTC of the most recent successful generator run, or
  empty string. Required field, empty is valid.
- `generator` — the canonical skill name. Required.
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
- **Never write outside `.forge/`.** Generators read the host repo; they only
  write under `.forge/maps/` and `.forge/forge.toml`.
- **No host-repo edits.** Maps are auxiliary; never modify tracked files.
