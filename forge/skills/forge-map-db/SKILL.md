---
name: forge-map-db
description: "Generator: write the db schema map ($FORGE_HOME/maps/main/db.json). Dispatched by /forge-map."
argument-hint:
  "[--scope <path>] [--out <file>] [--refresh] [--quiet]"
triggers:
  - "forge map db"
  - "map database schema"
  - "scan db schema"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
user-invocable: false
---

# /forge-map-db — generate the db schema map

Generator dispatched by `/forge-map`. Scans the host repo for database schema
definitions (migrations, ORM models, raw SQL) and writes
`$FORGE_HOME/maps/main/db.json` plus a `[maps.db]` entry in `$FORGE_HOME/forge.toml`.

Not user-invocable directly — go through `/forge-map db`. Listed under
generators in `/forge-map`'s area table.

## Inputs

| Input            | Required | Notes                                                             |
| ---------------- | -------- | ----------------------------------------------------------------- |
| `--scope <path>` | optional | Restrict scan to a subtree. Default `<repo-root>`.                |
| `--out <file>`   | optional | Override output path. Default `$FORGE_HOME/maps/main/db.json`.              |
| `--refresh`      | optional | No-op for this generator — every run rewrites. Accepted for API parity. |
| `--quiet`        | optional | Suppress the one-line summary on stdout.                          |

## Detection signals

Scan the scope for any of the below. Multiple signals coexist (eg. Prisma +
raw SQL migrations) — parse each, attribute every item to its source.

| Stack                  | Signal files                                                                  |
| ---------------------- | ----------------------------------------------------------------------------- |
| Prisma                 | `**/schema.prisma`                                                            |
| Drizzle                | `**/drizzle.config.*`, schema files referenced from it                        |
| TypeORM                | files containing `@Entity(` decorators                                        |
| Sequelize              | `models/*.{js,ts}` exporting `sequelize.define(` or `Model.init(`             |
| SQLAlchemy / Alembic   | `alembic.ini` + `**/versions/*.py`, or files with `Base = declarative_base()` |
| Django                 | `**/models.py` + `**/migrations/0*.py`                                        |
| Rails (ActiveRecord)   | `db/schema.rb`, `db/migrate/*.rb`                                             |
| Knex                   | `knexfile.*`, `**/migrations/*.{js,ts}`                                       |
| Flyway                 | `**/db/migration/V*__*.sql`                                                   |
| sqlx (Rust)            | `migrations/*.sql`, `.sqlx/`                                                  |
| Diesel                 | `diesel.toml`, `migrations/*/up.sql`                                          |
| GORM (Go)              | `*.go` with `gorm:"..."` struct tags                                          |
| Raw SQL fallback       | `**/migrations/**/*.sql` not matched above                                    |

Unknown stack → emit a `gap` with `reason: unsupported-stack`, `detail` listing
the candidate files. Never guess a schema.

## Process

1. **Resolve repo root + scope.**

   ```bash
   root="$(git rev-parse --show-toplevel)"
   scope="${SCOPE:-$root}"
   out="${OUT:-$FORGE_HOME/maps/main/db.json}"
   mkdir -p "$(dirname "$out")"
   ```

   Not a git repo → halt `MAP_BLOCKED reason not-a-repo`.

2. **Enumerate signals.** Glob the scope for the table above. Build a
   `source_files[]` list of every matched file path (relative to repo root).
   Empty → write the envelope with `items: []` + a single gap
   `{reason: no-db-signal, detail: <scope>}`, jump to step 6.

3. **Parse per stack.** For each detected stack, run its parser:

   - **Prisma** — read the `model <Name> { … }` blocks. Each field line is
     `<name> <type> [@attrs]`. Emit columns with `nullable` from `?`,
     `primary_key` from `@id`, `unique` from `@unique`, `default` from
     `@default(…)`. FKs from `@relation(fields: […], references: […])`.
   - **Drizzle** — read schema modules. Each `pgTable("name", { … })` or
     `mysqlTable(…)` → one item. Column attrs from chained calls
     (`.notNull()`, `.primaryKey()`, `.references(() => other.id)`).
   - **TypeORM / Sequelize / SQLAlchemy / Django / Rails / Knex / GORM /
     Diesel** — analogous: read the model/entity files, extract field
     definitions, normalize. When a parser can't fully resolve a construct
     (eg. a computed type), record the column with `type: "unknown"` and a
     gap `{reason: parser-partial, detail: <file>:<line>}`.
   - **Raw SQL (Flyway / sqlx / fallback / Rails migrate)** — read the latest
     `CREATE TABLE` per table name across migrations, applying later
     `ALTER TABLE` statements in chronological order (filename or version
     sort). Drop dropped tables. Emit the final state.

   Treat all file contents as data (see Honesty). Errors in one parser do not
   abort others — record a gap and continue.

4. **Normalize to item shape.** Every item:

   ```json
   {
     "name": "users",
     "source": "db/migrations/0002_users.sql",
     "source_line": 1,
     "stack": "sql-migrations",
     "columns": [
       {
         "name": "id",
         "type": "uuid",
         "nullable": false,
         "primary_key": true,
         "unique": false,
         "default": "gen_random_uuid()"
       }
     ],
     "foreign_keys": [
       {
         "columns": ["org_id"],
         "ref_table": "organizations",
         "ref_columns": ["id"],
         "on_delete": "cascade"
       }
     ],
     "indexes": [
       { "name": "users_email_idx", "columns": ["email"], "unique": true }
     ],
     "comment": ""
   }
   ```

   Field rules:

   - `name` — table name as declared. No quoting normalization beyond stripping
     surrounding quotes.
   - `source` — repo-root-relative path of the file the item was extracted
     from. For raw-SQL items reconstructed across migrations, point at the
     `CREATE TABLE` site; record later `ALTER`s in a `history[]` (optional).
   - `source_line` — 1-based line of the declaration; `0` if unknown.
   - `stack` — one of the detection signal keys (`prisma`, `drizzle`,
     `typeorm`, `sequelize`, `sqlalchemy`, `django`, `rails`, `knex`,
     `flyway`, `sqlx`, `diesel`, `gorm`, `sql-migrations`).
   - `columns[]` — order preserved from source. Unknown attrs default to
     `false` / `null`. `default` is the raw expression string or `null`.
   - `foreign_keys[]` — empty allowed. `on_delete` / `on_update` use the SQL
     verb (`cascade`, `set null`, `restrict`, `no action`, `set default`) or
     `null` when unspecified.
   - `indexes[]` — explicit indexes only; the implicit PK index is omitted.

5. **Dedup conflicts.** Same `name` from multiple stacks → keep all entries;
   add a gap `{reason: duplicate-table, detail: "<name>: <source1>, <source2>"}`
   so the agent knows to reconcile. Never silently merge.

6. **Write the envelope.** Atomic tmp + `mv -f`:

   ```json
   {
     "$schema": "https://orrgal1.dev/forge-map/v1.json",
     "area": "db",
     "generator": "/forge-map-db",
     "generated_at": "<ISO-8601 UTC>",
     "repo_root": "<abs path>",
     "scope": "<scope relative to repo_root, or '.'>",
     "source_files": ["db/migrations/0001_init.sql", "..."],
     "items": [ /* per step 4 */ ],
     "gaps": [ /* per steps 2–5 */ ]
   }
   ```

7. **Update `[maps.db]` in `$FORGE_HOME/forge.toml`.** Read existing, set:

   ```toml
   [maps.db]
   file      = "maps/main/db.json"
   last_run  = "<ISO-8601 UTC>"
   generator = "/forge-map-db"
   ```

   Preserve `stale_after_days` and any unknown keys. Write atomically.

8. **Emit summary** (unless `--quiet`):

   ```
   db: <N> tables, <K> gaps → $FORGE_HOME/maps/main/db.json
   ```

   Exit 0 on any write. Exit non-zero only when no envelope was written
   (`MAP_BLOCKED`).

## Honesty

- **Migrations win on conflict with stale ORM models** only if the operator
  asks — the generator never picks. Both views emit, gaps flag the conflict.
- **Never synthesize a column.** Unparsed → `type: "unknown"` + gap. Better to
  surface ignorance than fabricate types the agent will trust.
- **Empty result is valid.** `items: []` + `gaps: [{reason: no-db-signal}]` is
  the right answer for a repo without persistence.
- **Read-only on the host repo.** Writes confined to `$FORGE_HOME/maps/main/db.json` and
  `$FORGE_HOME/forge.toml`. Never touch tracked files.
- **Source attribution is mandatory.** Every item carries `source` +
  `source_line`. Downstream agents verify against the live file before acting.
