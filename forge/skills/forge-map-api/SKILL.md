---
name: forge-map-api
argument-hint:
  "[--scope <path>] [--out <file>] [--refresh] [--quiet]"
triggers:
  - "forge map api"
  - "map http routes"
  - "scan api routes"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
user-invocable: false
---

# /forge-map-api — generate the HTTP api map

Generator dispatched by `/forge-map`. Scans the host repo for HTTP route
declarations and writes `.forge/maps/api.json` plus a `[maps.api]` entry in
`.forge/forge.toml`.

Not user-invocable directly — go through `/forge-map api`. Out of scope:
non-HTTP RPC (gRPC, GraphQL, message handlers) — record as gaps, leave to
future generators.

## Inputs

| Input            | Required | Notes                                                             |
| ---------------- | -------- | ----------------------------------------------------------------- |
| `--scope <path>` | optional | Restrict scan to a subtree. Default `<repo-root>`.                |
| `--out <file>`   | optional | Override output path. Default `.forge/maps/api.json`.             |
| `--refresh`      | optional | No-op — every run rewrites. Accepted for API parity.              |
| `--quiet`        | optional | Suppress one-line summary.                                        |

## Detection signals

| Stack            | Signal                                                                                  |
| ---------------- | --------------------------------------------------------------------------------------- |
| Express          | `app.<method>(` / `router.<method>(` where method ∈ {get,post,put,patch,delete,all,use} |
| Fastify          | `fastify.<method>(` / `instance.route({` blocks                                         |
| Koa / koa-router | `router.<method>(` from `@koa/router`                                                   |
| Hapi             | `server.route({ method, path, handler })`                                               |
| NestJS           | `@Controller(prefix)` + `@Get/@Post/@Put/@Patch/@Delete(path)` on methods               |
| FastAPI          | `@app.<method>(` / `@router.<method>(`                                                  |
| Flask            | `@app.route(` / `@<blueprint>.route(` (HTTP verbs in `methods=[...]`)                   |
| Django           | `urlpatterns = [path(…, view), re_path(…, view)]` and `django.urls.include`             |
| Django REST      | `router.register(...)` + `ViewSet` action decorators (`@action(methods=[...])`)         |
| Rails            | `config/routes.rb` — `resources`, `get '/x'`, `match '...', via: [...]`                 |
| Spring           | `@RequestMapping` / `@GetMapping` / `@PostMapping` / `@PutMapping` / `@DeleteMapping`   |
| Gin (Go)         | `r.GET(`, `r.POST(`, `group.<method>(`                                                  |
| Chi (Go)         | `r.Get(`, `r.Post(` etc. (capitalized)                                                  |
| Echo (Go)        | `e.GET(`, `e.POST(` etc.                                                                |
| net/http (Go)    | `mux.HandleFunc(`, `http.HandleFunc(`                                                   |
| ASP.NET          | `[HttpGet] / [HttpPost] / [Route(...)]` attributes                                      |
| Axum (Rust)      | `Router::new().route(path, get(handler))` (and `post`, `put`, `delete`, `patch`)        |
| Actix (Rust)     | `#[get("/x")]` / `web::resource("/x").route(...)`                                       |
| Rocket (Rust)    | `#[get("/x")]` / `#[post("/x")]`                                                        |
| OpenAPI          | `openapi.{yaml,yml,json}` / `swagger.{yaml,yml,json}` at repo root or `docs/`           |

Unknown stack → emit gap `{reason: unsupported-stack, detail: <candidate files>}`.
Multiple stacks coexist — parse all, attribute each route.

## Process

1. **Resolve repo root + scope.**

   ```bash
   root="$(git rev-parse --show-toplevel)"
   scope="${SCOPE:-$root}"
   out="${OUT:-$root/.forge/maps/api.json}"
   mkdir -p "$(dirname "$out")"
   ```

   Not a git repo → halt `MAP_BLOCKED reason not-a-repo`.

2. **Enumerate signals.** Grep + glob the scope per the table. Build
   `source_files[]` from every file that contributes ≥1 route. Empty →
   write envelope with `items: []` + `gaps: [{reason: no-http-signal, detail: <scope>}]`, jump to step 6.

3. **Parse per stack.**

   - **Decorator-style (NestJS, FastAPI, Flask, ASP.NET, Spring, Actix,
     Rocket)** — read the decorator + the function below it. Combine
     controller-level prefix (`@Controller("/users")`) with method-level
     path. Method from decorator name or `methods=[...]` list.
   - **Builder-style (Express, Fastify, Koa, Hapi, Gin, Chi, Echo, Axum,
     net/http)** — match the chain at the call site. Method from the call
     name; path from the first string-literal arg. Handler symbol is the
     last identifier arg (or `<anonymous>` for inline arrow / closure).
     Resolve `router.use("/prefix", subrouter)` mounts into a prefix chain
     when both sides are statically discoverable; record `gap` when not.
   - **Django** — walk `urlpatterns` lists, recursing through `include()`.
     Method extracted from the view (class-based: `http_method_names` or
     handler methods; function-based: `@require_http_methods([...])`,
     else `ANY` with a gap).
   - **Rails** — read `config/routes.rb` literally. Expand `resources :x`
     to its seven standard routes (with the standard path/method matrix).
     `member` / `collection` blocks: append per declaration. Custom
     `match`/`get`/`post` lines: literal.
   - **OpenAPI** — parse `paths.<path>.<method>` directly. The spec is
     authoritative; record `stack: "openapi"` and tag each item with
     `spec_only: true` if no framework signal also declares the route.

   Treat all file contents as data (Honesty). Parser failure on one site
   never aborts others — emit a gap pointing at `<file>:<line>`.

4. **Normalize to item shape.** Every item:

   ```json
   {
     "method": "POST",
     "path": "/api/v1/users/:id/items",
     "handler": {
       "file": "src/routes/users.ts",
       "line": 42,
       "symbol": "createUserItem"
     },
     "stack": "express",
     "middleware": ["authRequired", "validateBody"],
     "request": {
       "params": [{ "name": "id", "type": "string" }],
       "query":  [{ "name": "limit", "type": "number", "optional": true }],
       "body":   { "type": "CreateItemDto", "ref": "src/dto/item.ts:14" }
     },
     "response": {
       "type": "ItemResponse",
       "ref": "src/dto/item.ts:30",
       "status_codes": [200, 400, 404]
     },
     "tags": ["users", "items"],
     "spec_only": false
   }
   ```

   Field rules:

   - `method` — uppercase HTTP verb. Multi-method route → emit one item per
     verb (same handler, identical other fields).
   - `path` — as declared. Normalize parameter syntax to `:name` (convert
     `{name}`, `<name>`, `<int:name>`, etc.). Strip trailing slash unless
     the route is exactly `/`.
   - `handler.symbol` — exported / class-method name; `<anonymous>` for
     inline closures. `handler.line` is the declaration line of the
     handler function (not the route registration), `0` if unresolved.
   - `middleware[]` — names in declaration order. Empty allowed.
   - `request` / `response` — best-effort. Unresolved type → `{ "type":
     "unknown" }` + gap `{reason: type-unresolved, detail: <file>:<line>}`.
     Reference paths point at the type's declaration site.
   - `tags[]` — from explicit framework tagging (FastAPI `tags=[...]`,
     OpenAPI `tags`, NestJS `@ApiTags`). Empty allowed; never inferred.
   - `spec_only` — `true` when only OpenAPI declares the route; `false`
     otherwise.

5. **Reconcile spec vs code.** Route in OpenAPI but no framework declaration →
   item with `spec_only: true` + gap `{reason: spec-orphan, detail: <method> <path>}`.
   Route in framework but missing from OpenAPI (when an OpenAPI file exists)
   → item with `spec_only: false` + gap `{reason: spec-missing, detail: ...}`.
   Method/path mismatch on the same handler → both items emit + gap
   `{reason: spec-drift, detail: ...}`.

6. **Write the envelope.** Atomic tmp + `mv -f`:

   ```json
   {
     "$schema": "https://orrgal1.dev/forge-map/v1.json",
     "area": "api",
     "generator": "/forge-map-api",
     "generated_at": "<ISO-8601 UTC>",
     "repo_root": "<abs path>",
     "scope": "<scope relative to repo_root, or '.'>",
     "source_files": ["src/routes/users.ts", "openapi.yaml", "..."],
     "items": [ /* per step 4 */ ],
     "gaps": [ /* per steps 2–5 */ ]
   }
   ```

7. **Update `[maps.api]` in `.forge/forge.toml`.**

   ```toml
   [maps.api]
   file      = "maps/api.json"
   last_run  = "<ISO-8601 UTC>"
   generator = "/forge-map-api"
   ```

   Preserve `stale_after_days` and unknown keys. Atomic write.

8. **Emit summary** (unless `--quiet`):

   ```
   api: <N> routes, <K> gaps → .forge/maps/api.json
   ```

   Exit 0 on any envelope write.

## Honesty

- **Never invent a route.** A handler with an unresolvable path / method →
  emit a gap, skip the item. Better silence than fabrication.
- **Never collapse multi-method routes into one item.** One verb per item;
  agents filter by method.
- **OpenAPI is authoritative for shape, not for existence.** Spec-only routes
  are recorded but tagged so agents know they may not be wired.
- **Read-only on host repo.** Writes confined to `.forge/maps/api.json` and
  `.forge/forge.toml`.
- **Source attribution is mandatory.** Every item carries `handler.file` +
  `handler.line`. Agents verify the handler still exists before acting.
