---
name: forge-map-config
description: "Generator: write the config / env-var map ($FORGE_HOME/maps/main/config.json). Dispatched by /forge-map."
argument-hint:
  "[--scope <path>] [--out <file>] [--refresh] [--quiet]"
triggers:
  - "forge map config"
  - "map env vars"
  - "scan config surface"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
user-invocable: false
---

# /forge-map-config — generate the config / env-var map

Generator dispatched by `/forge-map`. Scans the host repo for environment
variables consumed by code, joins them to declarations in `.env.example` /
deployment manifests, infers defaults + required-ness, and writes
`$FORGE_HOME/maps/main/config.json` plus a `[maps.config]` entry in `$FORGE_HOME/forge.toml`.

Not user-invocable directly — go through `/forge-map config`.

## Inputs

| Input            | Required | Notes                                                             |
| ---------------- | -------- | ----------------------------------------------------------------- |
| `--scope <path>` | optional | Restrict scan to a subtree. Default `<repo-root>`.                |
| `--out <file>`   | optional | Override output path. Default `$FORGE_HOME/maps/main/config.json`.          |
| `--refresh`      | optional | No-op — every run rewrites. Accepted for API parity.              |
| `--quiet`        | optional | Suppress one-line summary.                                        |

## Detection signals

**Reads** (every place code consumes an env var or config key):

| Language / framework  | Signal                                                                                            |
| --------------------- | ------------------------------------------------------------------------------------------------- |
| Node / TS             | `process.env.X`, `process.env["X"]`. Defaults from `process.env.X ?? "..."` / `\|\| "..."`.       |
| Zod env validators    | `z.object({ X: z.string()… })` patterns; field types + transforms.                                |
| Python (stdlib)       | `os.getenv("X")`, `os.environ["X"]`, `os.environ.get("X", default)`.                              |
| Pydantic Settings     | `class … (BaseSettings)` fields; defaults + `Field(default=…, env="X")`.                          |
| Go                    | `os.Getenv("X")`, `viper.GetString("x")`, `envconfig` struct tags (`env:"X" default:"…"`).        |
| Java / Spring         | `@Value("${X:-default}")`, `System.getenv("X")`, `Environment.getProperty(...)`.                  |
| Ruby                  | `ENV["X"]`, `ENV.fetch("X", default)`.                                                            |
| Rust                  | `std::env::var("X")`, `envy::from_env::<Cfg>()`, `figment`, `config` crate.                       |
| C# / .NET             | `Environment.GetEnvironmentVariable("X")`, `IConfiguration["X"]`, `builder.Configuration[...]`.   |
| PHP                   | `getenv("X")`, `$_ENV["X"]`.                                                                      |

**Declarations** (where env vars are documented / set, not read):

| Source                  | Signal                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------- |
| Dotenv templates        | `.env.example`, `.env.template`, `.env.sample`, `.env.defaults`.                        |
| Dotenv runtime          | `.env`, `.env.local`, `.env.development`, `.env.production` (values redacted, see Honesty). |
| docker-compose          | `services.*.environment:` lists / maps, `env_file:` references.                         |
| Kubernetes              | `env:` and `envFrom:` in `Deployment` / `StatefulSet` / `Job` manifests; ConfigMap keys. |
| Helm                    | `values.yaml` keys consumed by templates that produce `env:` blocks.                    |
| GitHub Actions / CI     | `env:` blocks in `.github/workflows/*.yml`, `gitlab-ci.yml`, `buildkite/*.yml`.         |
| Heroku / Render / Fly   | `app.json`, `render.yaml`, `fly.toml` env sections.                                     |

Unknown stack → emit gap `{reason: unsupported-stack, detail: <files>}`.
Multiple stacks coexist — parse each.

## Process

1. **Resolve repo root + scope.**

   ```bash
   root="$(git rev-parse --show-toplevel)"
   scope="${SCOPE:-$root}"
   out="${OUT:-$FORGE_HOME/maps/main/config.json}"
   mkdir -p "$(dirname "$out")"
   ```

   Not a git repo → halt `MAP_BLOCKED reason not-a-repo`.

2. **Enumerate signals.** Grep + glob the scope per the tables above. Build
   `source_files[]` from every contributing file (reads + declarations). Empty
   → write envelope `items: []` + gap `{reason: no-config-signal, detail: <scope>}`,
   jump to step 7.

3. **Collect reads.** For each read site:

   - record `name` (the env-var key as it appears in source)
   - record `file` + `line`
   - extract a `default` when the call has one (`os.getenv("X", "v")`,
     `process.env.X ?? "v"`, `envconfig` `default:"v"` tag, etc.). Else
     `default: null`.
   - extract `required` flag when the framework expresses it (Zod
     `.optional()` → false, Pydantic field without default → true,
     `os.environ["X"]` indexing → true, `os.getenv` → false unless wrapped in
     an explicit check).

   Computed / dynamic key names (`process.env[\`API_\${region}\`]`) → record
   `name` as the literal template + gap `{reason: dynamic-key, detail: <file>:<line>}`.

4. **Collect declarations.** For each declaration site:

   - record `name`, `file`, `line`
   - record `value` if present in a tracked template file (`.env.example`
     etc.). For runtime dotenv files (`.env`, `.env.local`, …) read the line
     but **redact** the value (see Honesty); record `value: "<redacted>"` +
     gap `{reason: runtime-dotenv, detail: <file>}`.
   - record adjacent `comment` text on the preceding line or trailing `#`,
     when present.

5. **Join reads + declarations by name.** One item per unique env-var name.
   Same name in different cases is **not** the same item — record both + gap
   `{reason: case-collision, detail: "<X> vs <x>"}`.

6. **Normalize to item shape.**

   ```json
   {
     "name": "DATABASE_URL",
     "reads": [
       {
         "file": "src/db.ts",
         "line": 12,
         "default": null
       }
     ],
     "declarations": [
       {
         "file": ".env.example",
         "line": 3,
         "value": "postgres://localhost:5432/app",
         "comment": "primary database connection"
       }
     ],
     "required": true,
     "secret": true,
     "type": "string",
     "validation": {
       "source": "src/env.ts:5",
       "schema": "z.string().url()"
     }
   }
   ```

   Field rules:

   - `name` — verbatim from source. No case normalization.
   - `reads[]` — every consumption site, ordered by `file:line`. Empty → the
     var is declared but never read (orphan declaration).
   - `declarations[]` — every declaration site, ordered. Empty → the var is
     read but never declared (undocumented requirement) + gap
     `{reason: undeclared-read, detail: <name>}`.
   - `required` — `true` when **any** read site treats absence as fatal
     (indexing, Pydantic no-default, Zod required, `MustGetenv`, etc.). Else
     `false`.
   - `secret` — `true` only when explicit (validator tagged as secret,
     `SecretStr` in Pydantic, Kubernetes `valueFrom.secretKeyRef`, etc.).
     Name-based heuristic (`*_TOKEN`, `*_SECRET`, `*_PASSWORD`, `*_KEY`,
     `*_CREDENTIALS`, `*_PRIVATE_*`) → still `true` **but** emit gap
     `{reason: secret-by-name, detail: <name>}` so the agent knows it was
     inferred, not declared.
   - `type` — best-effort: `"string"` (default) / `"number"` / `"bool"` /
     `"url"` / `"json"` / `"unknown"`. Pull from validator schema when
     present.
   - `validation` — pointer to the validator declaration (`source` =
     `<file>:<line>`, `schema` = the literal validator expression). `null`
     when no validator is found.

7. **Write the envelope.** Atomic tmp + `mv -f`:

   ```json
   {
     "$schema": "https://orrgal1.dev/forge-map/v1.json",
     "area": "config",
     "generator": "/forge-map-config",
     "generated_at": "<ISO-8601 UTC>",
     "repo_root": "<abs path>",
     "scope": "<scope relative to repo_root, or '.'>",
     "source_files": ["src/env.ts", ".env.example", "k8s/deploy.yaml", "..."],
     "items": [ /* per step 6 */ ],
     "gaps": [ /* per steps 2–6 */ ]
   }
   ```

8. **Update `[maps.config]` in `$FORGE_HOME/forge.toml`.**

   ```toml
   [maps.config]
   file      = "maps/main/config.json"
   last_run  = "<ISO-8601 UTC>"
   generator = "/forge-map-config"
   ```

   Preserve `stale_after_days` and unknown keys. Atomic write.

9. **Emit summary** (unless `--quiet`):

   ```
   config: <N> vars, <K> gaps → $FORGE_HOME/maps/main/config.json
   ```

   Exit 0 on any envelope write.

## Honesty

- **Never write secret values into the map.** Runtime dotenv files (`.env`,
  `.env.local`, `.env.production`) get `value: "<redacted>"` + gap. Template
  files (`.env.example`) are treated as safe-to-record because they ship in
  the repo by design — but still redact any line that looks like a real
  credential (long random strings, JWTs, base64 blobs over 32 chars).
- **`secret: true` requires evidence.** Name-based inference is allowed but
  always paired with a `secret-by-name` gap. Explicit validators / k8s
  `secretKeyRef` are accepted without a gap.
- **Read sites are authoritative for required-ness, not declarations.** A var
  declared in `.env.example` but never read → orphan declaration, not
  required. A var read with no default → required, even if absent from
  every template.
- **Never collapse case variants.** `DATABASE_URL` and `database_url` are
  separate items with a gap.
- **Read-only on host repo.** Writes confined to `$FORGE_HOME/maps/main/config.json`
  and `$FORGE_HOME/forge.toml`. Never modify `.env*` or manifests.
- **Source attribution is mandatory.** Every read + declaration carries
  `file` + `line`. Agents verify against the live file before acting.
