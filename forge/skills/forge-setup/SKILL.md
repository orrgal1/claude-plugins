---
name: forge-setup
description:
  "Map host-repo tooling (build, test, lint, typecheck, codegen, devenv,
  localenv) into forge home (~/.claude/forge/<repo-key>/ by default) so forge
  adopts into any repo across all worktrees."
argument-hint:
  "[--cap <name>=<command>]... [--instr <name>=<prose>]... [--list] [--yes]
  [--migrate user|repo] [--home user|repo|<path>]"
triggers:
  - "forge setup"
  - "set up forge in this repo"
  - "configure forge tooling"
  - "map forge commands"
  - "wire forge to this repo"
  - "migrate forge state"
  - "forge home"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
user-invocable: true
---

# /forge-setup — map forge to this repo's tooling

Creates a **tooling map** telling forge how to build/test/lint/codegen **here**.
Run once per repo before the first `/forge` chain; re-run to add or fix a
capability. The map is the **only** place repo-specific tooling lives — forge
resolves every operation through it. Each capability is wired as a runnable
command/script (deterministic) **or** prose instructions the agent reads and
carries out (conditional/multi-step flows). Unmapped capability → gap
(`NEEDS_SETUP`); forge never guesses.

## Setup is a hard prerequisite

**No forge skill runs until `/forge-setup` completes locally for this repo** —
final step writes `[meta].ready = true` to `$FORGE_HOME/forge.toml`, the gate
every entry point checks. `/forge` + `forge-step-runner` refuse `SETUP_REQUIRED`
when absent; `/forge-status` reports `NOT_SET_UP`. "Locally" = marker in **this
repo's** `$FORGE_HOME` (keyed by git identity); a sibling repo's setup doesn't
count. Setup also hard-requires built-in `/code-review` + `/security-review`
(always-on channels wrap them) — refuses to mark ready without them.

## Forge home — where state lives

Repo-scoped state lives at **`$FORGE_HOME`**, default
`~/.claude/forge/<repo-key>/`. User layer, so every worktree of the same repo
shares it.

```
~/.claude/forge/<repo-key>/
  forge.toml          # capability map + [meta] + every other [section]
  commands/           # per-capability scripts or instructions:
    test              #   executable script  (run directly)
    codegen.md        #   instructions doc   (agent reads + performs)
  tools/              # operator-named runbooks (see /forge-tool)
  review-channels/    # /forge-review channel overrides (see /forge-review)
  lenses/             # host-repo lens overrides (see /forge-review)
  personas/           # host-repo persona overrides (see /forge-review)
  maps/
    main/<area>.json          # ground truth, tied to default branch
    branches/<br>/<area>.json # lazy fork on divergent write; absorbed on merge
```

`<repo-key>` derived deterministically from git identity (see § "Repo
identity"). Each capability is wired one of four ways (see resolution below):
executable `commands/<cap>`, `[commands].<cap>` string, instructions
`commands/<cap>.md`, or `[instructions].<cap>` string. Command for one
line/script; instructions for conditional/multi-step ("bring up infra, wait for
health, run pytest").

Three distinct surfaces — don't confuse them:

| Surface                       | Owns                                             | Where it lives                    |
| ----------------------------- | ------------------------------------------------ | --------------------------------- |
| `$FORGE_HOME` (forge home)    | **How to run** this repo's tooling + repo state  | `~/.claude/forge/<repo-key>/`     |
| `.pr-artifacts/<slug>/forge/` | **Per-PR chain artifacts** (goals, scenarios, …) | inside the worktree               |
| Plugin bundle                 | Bundled defaults (lenses, channels, personas)    | inside the installed forge plugin |

## `$FORGE_HOME` resolver

Every forge skill resolves paths through this function.

```
forge_home():
  1. $FORGE_HOME env var (full path) — wins when set
  2. ~/.claude/forge/$(forge_repo_key)/ — default
  3. <repo-root>/.forge/ — legacy fallback (one-release migration window)
```

Env var overrides everything (CI / sandboxed). User layer is the default. Legacy
`.forge/` honored during the migration window (this release); both present →
warn, prefer user-layer, point at `--migrate user`. Fallback removed next major
version.

## Repo identity

`<repo-key>` is the canonical id for the repo at user layer. Resolved in order:

1. `forge.toml` `[meta].canonical_id` — operator override (free-form slug).
2. `git remote get-url origin` parsed to `<host>/<owner>/<repo>` (lowercase,
   strip `.git`, alphanumerics + `/` + `-`). Works for `git@host:owner/repo.git`
   and `https://host/owner/repo.git`. Forks get their own key by design.
3. SHA256 of `git rev-parse --show-toplevel` (first 12 hex) — for repos without
   a remote.

Stability properties:

- Same key across clones, worktrees, path moves (when origin matches).
- Different key for forks (different origin).
- Operator override (`[meta].canonical_id`) survives all of the above; use it
  after origin renames or for monorepo-as-subdir setups.

## Capabilities

Logical operations forge resolves through the map. All optional — wire only what
this repo has.

| Capability        | What it runs                                                                                      | Used by                                         |
| ----------------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `test`            | Run tests. Forge appends an optional selector as the last arg.                                    | `/forge-impl-green`, `/forge-tests`, audit runs |
| `build`           | Compile / build                                                                                   | `/forge-ci-green`, impl loop                    |
| `lint`            | Lint                                                                                              | `/forge-ci-green`                               |
| `typecheck`       | Static type check                                                                                 | `/forge-ci-green`, impl loop                    |
| `codegen`         | Regenerate generated code (mocks, proto, clients)                                                 | impl loop recovery, `/forge`                    |
| `devenv`          | Bring up a dev environment (optional)                                                             | manual / component-tier flows                   |
| `localenv`        | Bring up local infra for component-tier tests (optional)                                          | component-tier test runs                        |
| review automation | GitHub `gh` baseline: list unresolved / reply / resolve / re-request. External tools → draft-only | `/forge-address-review`                         |

`test` is the one capability nearly every chain needs; the rest as warranted.

**Review automation — GitHub baseline auto-driven, external tools draft-only.**
GitHub `gh` is the always-on auto-driven channel (forge operates on GitHub PRs):
list unresolved / reply / resolve / re-request all run through `gh`.

External CI / review tools (Reviewable, custom review bots, etc.) are **not**
auto-driven. They typically dump their comments **as GitHub issue / PR
comments** — so the `gh` baseline already intakes them — or somewhere else the
operator points forge at ad-hoc. For those, `/forge-address-review` **drafts**
replies; the operator posts them (manually, or by ad-hoc instructing the agent
to use whatever automation they have). Forge never auto-publishes to an external
tool.

## Capability resolution (the contract forge skills follow)

Paths resolved through `forge_home()` (§ above). To run capability `<cap>`, in
order:

1. `$FORGE_HOME/commands/<cap>` exists + executable → **run it** (args, e.g. a
   single-test selector, appended as `$@`).
2. `[commands].<cap>` non-empty string → **run that command** (selector
   appended).
3. `$FORGE_HOME/commands/<cap>.md` exists → **follow it as instructions** (agent
   performs the steps by hand).
4. `[instructions].<cap>` non-empty string → **follow that prose** the same way.
5. Else → **unwired.** Surface `NEEDS_SETUP cap=<cap>`, point at `/forge-setup`.
   Never guess.

Deterministic forms (1–2) win over instruction forms (3–4) when both present —
but a capability normally has exactly one wiring.

**Review automation** isn't a `forge.toml` slot: GitHub `gh` is the always-on
auto-driven baseline; external review tools are draft-only (see Capabilities).
Never `NEEDS_SETUP`.

## `forge.toml` shape

Lives at `$FORGE_HOME/forge.toml`. Generated by `/forge-setup`. Edit freely.

```toml
# $FORGE_HOME/forge.toml — maps forge's logical capabilities to this repo's
# tooling + holds every other forge section ([tools], [review], [maps]).

[meta]
# Forge-internal metadata about this repo's state location + identity.
canonical_id    = ""        # operator override of the auto-derived repo key (rare)
default_branch  = "main"    # ground-truth branch for maps. Auto-set on first run.
home            = "user"    # "user" (default) | "repo" — where forge state lives
migrated_from   = ""        # set by /forge-setup --migrate; audit trail
notes           = ""        # anything forge should know about layout / test strategy
ready             = true                          # set by /forge-setup step 12 — the prerequisite gate every forge skill checks
setup_at          = ""                            # ISO-8601 UTC of last completed setup
setup_version     = ""                            # forge plugin version that ran setup
builtins_verified = ["code-review", "security-review"]  # core skills confirmed present at setup

# Logical capability -> shell command (deterministic). A script at
# $FORGE_HOME/commands/<cap> takes precedence. Leave a capability empty if
# this repo has no such tooling — forge surfaces a gap instead of guessing.
[commands]
test      = ""
build     = ""
lint      = ""
typecheck = ""
codegen   = ""
devenv    = ""
localenv  = ""
# Review automation is NOT a forge.toml slot — GitHub `gh` is the auto-driven
# baseline; external review tools are draft-only (see Capabilities).

# Logical capability -> prose instructions the agent reads and carries out.
# Use for conditional / multi-step operations a single command can't capture.
# A commands/<cap>.md file is the multi-line equivalent and takes precedence.
[instructions]
# localenv = "Run `make infra-up`, wait until `curl localhost:8080/health` is 200, then component tests can run."

[test]
# Optional refinements forge reads when running tests.
# selector_usage = "how forge should pass a single-test selector"
# component_tier = "command or notes to run the component tier specifically"
# tiers          = ["unit", "component", "e2e"]

# /forge-review reads [review] to pick which review channels to run.
# Channels live in forge/review-channels/ (bundled) + $FORGE_HOME/review-channels/
# (host-repo overrides). See forge/review-channels/README.md for the channel
# concept and authoring shape.
[review]
default_channels = ["lens-fanout", "code-review-builtin", "security-review-builtin"]    # active channel set; seeded from channels with default_enabled: true
aggregation      = "interleave"        # "interleave" (sort by file:line) | "grouped" (section per channel)

# Per-channel config. The [review.channels.<id>] subtable enables / disables
# a channel and sets channel-specific knobs read from its body. Missing
# subtable = channel's frontmatter defaults apply.
[review.channels.lens-fanout]
enabled       = true
agent         = "@orrgal1/forge:forge-lens-reviewer"
lens_dir      = "lenses"
order         = "lens-mode"            # "lens-mode" | "file-by-file"
severity_cap  = ""                     # empty = no cap; values: blocker/major/minor/nit

[review.channels.code-review-builtin]
enabled       = true                   # always-on; wraps Claude Code's /code-review
effort        = "medium"               # low | medium | high | max
severity_cap  = ""                     # empty = no cap; cap to "minor" to keep advisory

[review.channels.security-review-builtin]
enabled       = true                   # always-on; wraps Claude Code's /security-review
scope         = ""                     # empty = full diff; otherwise --scope path
severity_cap  = ""                     # empty = no cap
```

Channel resolution layers like capabilities: bundled
`forge/review-channels/<id>.md`; host override
`$FORGE_HOME/review-channels/<id>.md` (same schema, wins when both exist);
config toggle in `[review.channels.<id>]`. Discovery is automatic — a file in
either dir surfaces in `--list` and at the `/forge-review` gate, but only
**active** when listed in `default_channels` (or `--add-channel` per-run).

### `[tools]` — operator-named runbooks

`/forge-tool` owns this section. Each entry is an operator-captured runbook
under `$FORGE_HOME/tools/`. Distinct from `[commands]` (canonical capabilities),
`[review]` (channel registry), `[maps]` (read-only snapshots).

```toml
[tools]
dir = "tools"             # where tool files live, relative to $FORGE_HOME

# Each tool is a subtable [tools.<name>]:
[tools.seed-test-db]
form      = "script"      # script | instructions | dir | agent
file      = "tools/seed-test-db"
purpose   = "load fixture rows into the test db"
inputs    = "[--rows N]"
captured  = "2026-05-31T08:14:00Z"
source    = "discovered during PR #432 work"

# Agent-form tools also carry the subagent slug:
[tools.audit-feature-flag-usage]
form      = "agent"
file      = "tools/audit-feature-flag-usage.md"
agent     = "caveman:cavecrew-investigator"
purpose   = "find every call site of isEnabled() for a given flag key"
captured  = "2026-05-28T13:40:00Z"
```

Tools are first-class — other skills resolve a tool by name via
`/forge-tool run <name>` or direct reference in a `commands/<cap>.md` file. See
`/forge-tool` for the registry contract.

### `[maps]` — ground truth + branch divergence

`/forge-map` owns this section. Maps reflect the repo's domain surface (db, api,
events, config, ad-hoc). Layout:

```
$FORGE_HOME/maps/
  main/<area>.json              # ground truth — tied to [meta].default_branch
  branches/<branch>/<area>.json # divergent snapshot for a feature branch
```

Ground truth in `maps/main/` (dir name follows literal default-branch, e.g.
`maps/master/`, driven by `[meta].default_branch`). Feature branches read ground
truth by default; `/forge-map` lazily forks into
`maps/branches/<branch>/<area>.json` **only when a write would diverge**. On
merge, the next default-branch `/forge-map` detects merged branch dirs and
offers to absorb their maps into ground truth (replace + delete branch dir).

```toml
[maps]
dir            = "maps"
branch_scoped  = true    # ground-truth + lazy fork (default). false = single set across branches.
default_branch = ""      # auto-discovered from origin/HEAD; copies [meta].default_branch when blank

[maps.db]
file      = "maps/main/db.json"
last_run  = "2026-05-31T08:14:00Z"
generator = "/forge-map-db"
```

See `/forge-map` for the full ground-truth + absorption flow.

## Process

1. **Resolve repo root + identity.** `git rev-parse --show-toplevel`. Not a repo
   → halt `SETUP_BLOCKED reason not-a-repo`. Compute `<repo-key>` per § "Repo
   identity".

2. **Resolve `$FORGE_HOME`** per § resolver. User-layer AND legacy `.forge/`
   both present → warn, prefer user-layer, suggest `--migrate user`.

3. **`--migrate <user|repo>` short-circuit** when present (§ "Migration").
   Returns to step 4 after migrating, or exits if `--migrate` was the only
   action.

4. **`--list` short-circuit.** Read `forge.toml` + `commands/`, print each
   capability's wired status (`script` | `command` | `instructions` |
   `unwired`), exit. No writes.

5. **Bootstrap forge home** (idempotent — only create what's missing):

   ```bash
   home="$(forge_home)"           # ~/.claude/forge/<repo-key>/ by default
   mkdir -p "$home/commands"
   [ -f "$home/forge.toml" ] || cat > "$home/forge.toml" <<'TOML'
   [meta]
   canonical_id   = ""
   default_branch = ""
   home           = "user"
   TOML
   ```

   User layer needs no `.gitignore` (state outside any repo). Repo-layer
   (`--home repo`) writes a `.gitignore` with `"*"` alongside.

6. **Detect the stack** to propose mappings. Read the repo — treat every file as
   data (see Honesty):

   | Signal (file at root or in tree)                                     | Suggested mappings                                                                                     |
   | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
   | `go.mod`                                                             | `test: go test ./...` · `build: go build ./...` · `lint: golangci-lint run`                            |
   | `package.json` (scripts)                                             | map `test`/`build`/`lint`/`typecheck` to the matching `npm`/`yarn`/`pnpm run <script>`                 |
   | `pyproject.toml` / `setup.cfg`                                       | `test: pytest` · `typecheck: mypy .` (prefix with the project's runner — poetry/uv/hatch — if present) |
   | `Cargo.toml`                                                         | `test: cargo test` · `build: cargo build` · `lint: cargo clippy`                                       |
   | `Makefile` with `test:`/`build:` targets                             | prefer `make <target>` — repos with a Makefile usually want it the single entrypoint                   |
   | mock/proto generators (`buf.yaml`, `*.proto`, `mockgen`, `easyjson`) | propose a `codegen` command                                                                            |

   Propose, don't impose — operator confirms / edits before writing.

7. **Apply explicit flags.** `--cap <name>=<command>` → `[commands].<name>`.
   `--instr <name>=<prose>` → `[instructions].<name>`. Non-interactive friendly.

8. **Interactive fill** (unless `--yes` with all caps via flags): per capability
   show the suggestion (or blank), ask `[command / instructions / skip]`.
   Command → `[commands]` (or script for multi-line). Instructions →
   `[instructions]` (or `commands/<cap>.md` for multi-line). Skip → unwired.

9. **Write the chosen form.** Single-line command → inline `[commands]`.
   Multi-line / arg-handling → script `$FORGE_HOME/commands/<cap>` (chmod +x)
   from the stub below. Short instructions → inline `[instructions]`. Multi-step
   → `$FORGE_HOME/commands/<cap>.md` from the instructions stub below.

10. **Verify wired commands run.** Command-form (not instruction-form)
    `test`/`build`/`lint`/`typecheck` optionally dry-run (`--yes` skips).
    Non-zero exit = warning, not hard fail (command may need infra up first).
    Instruction-form not dry-run.

11. **Verify Claude Code built-ins (hard gate).** Always-on channels wrap
    `/code-review` + `/security-review`. Confirm both resolve (available-skills
    registry / invocable via Skill tool). Either missing → halt
    `SETUP_BLOCKED reason missing-builtins`, naming which, with remediation
    (update Claude Code). Setup does **not** complete without them — no fallback
    for either channel.

12. **Mark setup ready.** Write to `[meta]`: `ready = true`,
    `setup_at = "<ISO-8601 UTC>"`, `setup_version = "<plugin version>"`,
    `builtins_verified = ["code-review", "security-review"]`. The gate every
    forge skill checks (§ "Setup is a hard prerequisite"). Re-running refreshes
    it.

13. **Recap.** Print the capability table with final status + next move.

## Stub templates

**Script** — `$FORGE_HOME/commands/<cap>` (chmod +x), script form:

```sh
#!/usr/bin/env sh
# $FORGE_HOME/commands/<cap> — <one-line purpose>.
# Forge invokes: $FORGE_HOME/commands/<cap> [args]
# Exit 0 = success. Replace the body with this repo's real command.
set -eu
exec <your command here> "$@"
```

Until filled, an unconfigured stub must exit non-zero so forge treats the
capability as a gap, not a silent pass:

```sh
#!/usr/bin/env sh
echo "forge: '<cap>' not configured — edit \$FORGE_HOME/commands/<cap>" >&2
exit 127
```

**Instructions** — `$FORGE_HOME/commands/<cap>.md`. Prose the agent reads and
carries out:

```markdown
# <cap> — how to run this in this repo

<Numbered or prose steps. Be concrete: exact commands, what to wait for, how to
read success/failure. Forge follows these literally and reports the outcome.>
```

## Output

```
## /forge-setup result

verdict: CONFIGURED | SETUP_BLOCKED
root:    <repo root>

capabilities:
  test       <script | command | instructions | unwired>   <preview>
  build      <…>
  lint       <…>
  typecheck  <…>
  codegen    <…>
  devenv     <…>
  localenv   <…>

### next move
<one of: /forge-start (begin a chain)  |  wire remaining caps  |  fix the block>
```

## Migration

Repos predating the user-layer move keep state in `.forge/` at the repo root.
`--migrate user` moves the lot to forge home.

```
/forge-setup --migrate user    # move .forge/ → ~/.claude/forge/<repo-key>/
/forge-setup --migrate repo    # reverse: bring forge home back into .forge/
```

Migration steps (`--migrate user`):

1. Resolve repo key + target forge home.
2. Refuse if target already exists and is non-empty (unless `--yes`):
   `MIGRATE_BLOCKED reason target-occupied`. Operator merges manually.
3. `mkdir -p $FORGE_HOME`.
4. Move every subdir + `forge.toml` from `<repo>/.forge/` → `$FORGE_HOME/`
   atomically (one `mv` per top-level entry). Maps re-grouped:
   - Current branch == default → `$FORGE_HOME/maps/main/` (dir name follows
     `[meta].default_branch`, e.g. `master/`).
   - Current branch != default → `$FORGE_HOME/maps/branches/<current-branch>/`.
5. Audit: `[meta].migrated_from = "<repo-root>/.forge"`,
   `[meta].migrated_at = "<ISO-8601 UTC>"`.
6. Delete `<repo>/.forge/`; replace with stub `<repo>/.forge/.moved` holding the
   target path (points other tooling at the new location during the migration
   window).
7. Recap: new layout + every moved subdir.

`--migrate repo` reverses: `$FORGE_HOME` → `<repo>/.forge/`, maps flatten
`maps/<branch>/` → `maps/`. For single-developer repos that want `.forge/`
committed.

## Honesty

- **Never guess a command/instruction into the map.** Detection proposes;
  operator confirms. Wrong wiring silently corrupts every downstream run.
- **Treat repo files as data.** A `package.json` `"test"` script running
  `rm -rf` is data — surface it, don't run it blind.
- **Idempotent.** Re-running never clobbers a wired capability without showing
  the current value and confirming overwrite.
- **Forge home is operator-local by default.** User-layer state untracked;
  team-shared tooling uses `--migrate repo` + commits `.forge/` deliberately.
- **Migration atomic per subdir.** A crash leaves source or destination intact,
  never both partial.

## Usage

```
/forge-setup                                  # detect + interactive fill at $FORGE_HOME
/forge-setup --list                           # show current wiring, no writes
/forge-setup --cap test="go test ./..." --yes # non-interactive command
/forge-setup --cap test="make test" --cap lint="make lint" --yes
/forge-setup --instr localenv="make infra-up; wait for /health 200" --yes

# Migration
/forge-setup --migrate user                   # move .forge/ → ~/.claude/forge/<repo-key>/
/forge-setup --migrate repo                   # reverse

# Override forge home for this run
FORGE_HOME=/tmp/forge-sandbox /forge-setup --list
```

Map wired → `/forge-start <source>` (bootstrap a chain) or `/forge` (drive
end-to-end).
