---
name: forge-tool
description:
  "Capture an ad-hoc flow as a repeatable tool under $FORGE_HOME/tools/ and
  register it in $FORGE_HOME/forge.toml [tools.<name>]."
argument-hint:
  "[package <name> | list | run <name> [args] | show <name> | delete <name>]
  [--purpose <text>] [--form script|instructions|dir|agent] [--from-session]
  [--from-prompt <text>] [--yes] [--dry-run]"
triggers:
  - "forge tool"
  - "package this flow"
  - "save this as a tool"
  - "make this repeatable"
  - "capture this workflow"
  - "i want this as a one-liner next time"
  - "turn this into a tool"
  - "list forge tools"
  - "run forge tool"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Skill
  - Agent
user-invocable: true
---

# /forge-tool — package an ad-hoc flow into a reusable tool

A **tool** is an operator-named runbook under `$FORGE_HOME/tools/` — a flow you
want repeatable without rediscovery (seed a test db, rotate staging secrets,
backfill a column). First-class: other forge skills resolve tools by name when
wired into a capability.

Tools are distinct from the other `$FORGE_HOME/` surfaces:

| Surface                        | What lives there                            | Who names it              |
| ------------------------------ | ------------------------------------------- | ------------------------- |
| `$FORGE_HOME/commands/`        | canonical capabilities (`test`, `build`, …) | forge (finite set)        |
| `$FORGE_HOME/review-channels/` | `/forge-review` channels                    | forge (per channel)       |
| `$FORGE_HOME/maps/`            | read-only domain snapshots                  | `/forge-map` (per area)   |
| `[playbooks.<name>]`           | failure→recovery rules (`/forge-setup`)     | forge/operator (per rule) |
| `$FORGE_HOME/tools/`           | **open-ended, operator-named runbooks**     | **the operator**          |

A tool and a playbook are duals: a tool is **pulled** (you invoke it by name); a
playbook is **triggered** (forge fires it on a matching capability failure). See
`/forge-setup` § "Failure recovery — playbooks".

## Subcommands

| Subcommand          | Default? | Purpose                                                                                                                                                       |
| ------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `package <name>`    | yes      | Capture a flow as a new tool. Three capture modes (see below).                                                                                                |
| `list`              |          | Print every registered tool: name, form, purpose, freshness.                                                                                                  |
| `run <name> [args]` |          | Resolve + execute the tool. Script form → run; instructions → agent reads + performs; dir form → run `<dir>/run`; agent form → spawn the registered subagent. |
| `show <name>`       |          | Print the tool file(s) + registry entry.                                                                                                                      |
| `delete <name>`     |          | Remove tool file(s) + registry entry. Asks before deleting.                                                                                                   |

No subcommand + a name → `package <name>` (common case).

## Inputs

| Input                  | Subcommand          | Notes                                                                                                                        |
| ---------------------- | ------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `<name>`               | most                | Tool id (lowercase slug, hyphens). Reserved: any `$FORGE_HOME/commands/<cap>` capability.                                    |
| `--purpose <text>`     | `package`           | One-line summary stored in `[tools.<name>].purpose`. Asked interactively if absent.                                          |
| `--form <form>`        | `package`           | Force form: `script` / `instructions` / `dir` / `agent`. Auto-detect when absent.                                            |
| `--from-session`       | `package`           | Capture from the current Claude session (recent observations / transcript / git log + edits). Operator confirms before save. |
| `--from-prompt <text>` | `package`           | One-shot capture: operator provides the full recipe inline; skill packages without further interactive prompts.              |
| `--yes`                | `package`, `delete` | Skip confirmation prompts.                                                                                                   |
| `--dry-run`            | `run`               | Show what would run; don't execute.                                                                                          |

`package` runs **interactive Q&A** when neither `--from-session` nor
`--from-prompt` is passed — the default, highest-fidelity path (operator
describes; agent drafts; operator confirms).

## Tool forms

Auto-detected from captured content; `--form` overrides.

### `script`

Executable `$FORGE_HOME/tools/<name>`, deterministic shell, args via `$@`.
Auto-detected for pure shell, no conditional logic.

```sh
#!/usr/bin/env sh
# $FORGE_HOME/tools/seed-test-db — load fixture rows into the test db.
# Forge invokes: $FORGE_HOME/tools/seed-test-db [--rows N]
set -eu
rows="${1:-100}"
exec psql "$DATABASE_URL_TEST" -c "INSERT INTO ..."
```

### `instructions`

Markdown `$FORGE_HOME/tools/<name>.md` the agent reads and performs.
Auto-detected for conditionals, judgment calls, multi-step health checks —
anything a fixed command can't capture.

```markdown
# rotate-staging-secrets — how to do it here

1. List current secrets: `vault kv list secret/staging`.
2. For each secret with `rotate=true` metadata: …
3. Wait for the canary pod to report ready before promoting …
```

### `dir`

`$FORGE_HOME/tools/<name>/` with `run` entrypoint + helper files (`lib/...`,
`templates/...`). Auto-detected when the flow includes file fixtures the script
reads, or grows past ~50 lines.

```
$FORGE_HOME/tools/backfill-org-ids/
  run               # entrypoint script
  lib/migrate.sql
  lib/verify.sql
```

### `agent`

Spawns a subagent with a baked prompt. Markdown `$FORGE_HOME/tools/<name>.md`
with frontmatter:

```markdown
---
form: agent
agent: caveman:cavecrew-investigator
inputs:
  - name: query
    required: true
---

# audit-feature-flag-usage — agent recipe

When invoked: spawn the `caveman:cavecrew-investigator` agent with this prompt
template (substitutes `${query}`):

> Find every call site of `isEnabled(...)` for flag key `${query}`. Report
> file:line, call style, and whether it's behind a feature-flag service or a
> plain env-var check.
```

Use when the flow is "I ran this subagent with this prompt and want to repeat
it."

## Layout

```
$FORGE_HOME/
  tools/
    seed-test-db                    # form: script
    rotate-staging-secrets.md       # form: instructions
    audit-feature-flag-usage.md     # form: agent (frontmatter declares it)
    backfill-org-ids/               # form: dir
      run
      lib/migrate.sql
```

Filename rules:

- `script`: `$FORGE_HOME/tools/<name>` (no extension, executable bit set).
- `instructions` + `agent`: `$FORGE_HOME/tools/<name>.md` (same extension; the
  frontmatter's `form:` field distinguishes them).
- `dir`: `$FORGE_HOME/tools/<name>/run` is the entrypoint; helpers free-form.

Resolution order when running a tool (same spirit as `$FORGE_HOME/commands/`):

1. `$FORGE_HOME/tools/<name>` executable → run as script.
2. `$FORGE_HOME/tools/<name>/run` executable → run as dir-form (cwd = the dir).
3. `$FORGE_HOME/tools/<name>.md` with frontmatter `form: instructions` → agent
   reads + performs the body.
4. `$FORGE_HOME/tools/<name>.md` with frontmatter `form: agent` → spawn the
   declared subagent with the rendered prompt.
5. None → halt `TOOL_NOT_FOUND name=<name>`.

## `[tools]` schema in `$FORGE_HOME/forge.toml`

Forge owns the registry; one subtable per tool. Written by
`/forge-tool package`; manual edits honored, not recommended.

```toml
# $FORGE_HOME/forge.toml — tools section is owned by /forge-tool.

[tools]
# Where tool files live, relative to $FORGE_HOME/. Override if you must.
dir = "tools"

[tools.seed-test-db]
form      = "script"
file      = "tools/seed-test-db"
purpose   = "load fixture rows into the test db"
inputs    = "[--rows N]"
captured  = "2026-05-31T08:14:00Z"
source    = "discovered during PR #432 work"

[tools.rotate-staging-secrets]
form      = "instructions"
file      = "tools/rotate-staging-secrets.md"
purpose   = "rotate staging vault secrets without breaking running services"
captured  = "2026-05-12T17:02:00Z"

[tools.audit-feature-flag-usage]
form      = "agent"
file      = "tools/audit-feature-flag-usage.md"
agent     = "caveman:cavecrew-investigator"
purpose   = "find every call site of isEnabled() for a given flag key"
captured  = "2026-05-28T13:40:00Z"
```

Subtable contract:

- `form` — one of `script` / `instructions` / `dir` / `agent`. Required.
- `file` — path relative to `$FORGE_HOME/`. For `dir` form: the dir, not `run`.
  Required.
- `purpose` — one-line summary. Required (asked at capture time).
- `inputs` — short usage string shown in `/forge-tool list`. Optional.
- `captured` — ISO-8601 UTC of the most recent `/forge-tool package` run.
  Required, set automatically.
- `source` — free-text provenance hint: "discovered during PR #X", "from session
  2026-05-28". Optional.
- `agent` — subagent slug (e.g. `caveman:cavecrew-investigator`). Required for
  `agent` form, omitted otherwise.

Unknown keys are tolerated (forward-compat) but ignored by `list`.

## Cross-skill lookup contract

Other forge skills resolve a tool by name:

1. Read `[tools.<name>]`. Missing → not registered, no fallback discovery.
2. Resolve the file per **Resolution order** above.
3. Invoke per form: `script` / `dir` → run directly, exit code is success;
   `instructions` / `agent` → the calling skill follows the body
   (`/forge-tool run` does this for the operator).

Recommended use sites (advisory, not enforced):

- `$FORGE_HOME/commands/<cap>.md` instruction files can say "before this, invoke
  `tool: <name>` to set up state" — forge skills honor that hint.
- `/forge-impl-green` may resolve `tool: seed-test-db` when an
  `$FORGE_HOME/commands/test.md` references it.
- `/forge-review-green` may resolve `tool: <name>` from a fix-plan note.

Tools never auto-run from the canonical chain. The chain references them only
when an instruction file the operator wrote asks for it.

## Process

### `package <name>` — interactive Q&A (default)

1. **Resolve repo root.** `git rev-parse --show-toplevel`. Not a repo → halt
   `TOOL_BLOCKED reason not-a-repo`.

2. **Validate name.** Lowercase, alphanumerics + hyphens, ≤40 chars; not a
   reserved capability key; not already registered (`--yes` overwrites). Else
   halt `TOOL_BLOCKED reason <invalid|reserved|exists>`.

3. **Bootstrap dir** (idempotent):

   ```bash
   home="$(forge_home)"           # ~/.claude/forge/<repo-key>/ by default
   mkdir -p "$home/tools"
   [ -f "$home/forge.toml" ] || /forge-setup --yes
   ```

   `/forge-setup` owns `.gitignore` handling; don't duplicate here.

4. **Ask: purpose.** "One line — what does this do?" Skip if `--purpose` passed.

5. **Ask: steps.** "Describe the steps — paste commands or talk through;
   pseudo-shell fine." Operator may include shell history, pasted runs,
   narrative.

6. **Pick form** (`--form` overrides):
   - Pure shell, no conditionals/narrative → `script`.
   - Conditional / multi-step / health-check / judgment → `instructions`.
   - Reads helper files / templates → `dir`.
   - "I ran subagent X with this prompt" → `agent`.
   - Ambiguous → propose `instructions`.

7. **Draft content** per form (§ "Tool forms"). `script` → wrap in standard stub
   (`#!/usr/bin/env sh / set -eu / exec ... "$@"`). `agent` → confirm subagent
   slug + render prompt with explicit `${var}` placeholders.

8. **Show preview.** Proposed file + `[tools.<name>]` subtable. Ask
   `[y / edit / abort]`; `edit` → inline editor loop until accept.

9. **Write atomically.**
   - File: tmp + `mv -f`. Script + dir-form `run`: `chmod +x` after move.
   - `forge.toml`: read full, splice / replace `[tools.<name>]`, tmp + `mv -f`.
     Preserve every other section + unknown keys.

10. **Optional dry-run.** `script` / `dir` + no `--yes` → ask "dry-run now?
    [y/N]". Yes → run with `--help` if accepted, else no args. Non-zero → warn,
    don't roll back.

11. **Recap.** Print:

    ```
    ## /forge-tool package result

    verdict: TOOL_REGISTERED | TOOL_BLOCKED
    tool:    <name>
    form:    <form>
    file:    $FORGE_HOME/tools/<...>
    purpose: <one line>

    ### next move
    /forge-tool run <name>   |   /forge-tool show <name>   |   /forge-tool list
    ```

### `package <name> --from-session`

Like interactive Q&A, but step 5 content auto-proposed:

1. Read recent session signal (first available, in order):
   `mcp__plugin_claude-mem_mcp-search__search` / `timeline` observations (last
   1h); recent Bash tool calls; recent edits via `git diff` +
   `git log --since="1 hour ago"`.
2. Propose a steps draft: "Here's what I think this flow did — edit anything
   wrong." Operator reviews + edits before save.
3. Continue from step 6.

No session signal → fall back to interactive Q&A with a note.

### `package <name> --from-prompt <text>`

Skip steps 4–5: take `<text>` as the steps verbatim, continue from step 6.
One-shot recipe paste:

```
/forge-tool package seed-test-db --purpose "load fixtures" \
  --from-prompt "psql \$DATABASE_URL_TEST -c 'INSERT ...'"
```

### `list`

1. Read `[tools.*]`.
2. Per tool, freshness: `missing` (file not on disk); `stale` (file mtime older
   than `captured` — edited outside the skill; flag without judgment); `fresh`
   (otherwise).
3. Print one row per tool:

   ```
   name                       form          purpose                                 captured              freshness
   seed-test-db               script        load fixture rows                       2026-05-31T08:14:00Z  fresh
   rotate-staging-secrets     instructions  rotate vault secrets safely             2026-05-12T17:02:00Z  fresh
   audit-feature-flag-usage   agent         find isEnabled() call sites             2026-05-28T13:40:00Z  fresh
   ```

   Exit. No writes.

### `run <name> [args]`

1. Read `[tools.<name>]`. Missing → halt `TOOL_NOT_FOUND`.
2. Resolve file via resolution order. Missing → halt
   `TOOL_BROKEN reason file-missing`.
3. `--dry-run` → print resolved command / instructions body / agent prompt,
   exit.
4. Execute per form:
   - `script` → `exec "$file" "$@"`.
   - `dir` → `cd "$dir" && exec ./run "$@"`.
   - `instructions` → read file, perform steps. Args as `$1..$N` for
     substitution when frontmatter declares `inputs:`.
   - `agent` → render prompt with `${var}` substitutions from args, spawn the
     registered subagent via Agent tool.
5. Surface stdout/stderr + final exit status.

### `show <name>`

Print the resolved file(s) + the registry subtable. No writes.

### `delete <name>`

1. Read `[tools.<name>]`. Missing → halt `TOOL_NOT_FOUND`.
2. Show file(s) + subtable, ask "delete? [y/N]" unless `--yes`.
3. Remove the file(s); remove the subtable from `forge.toml` (atomic rewrite).
   Print recap.

## Honesty

- **Never invent steps the operator didn't describe.** Q&A is source of truth;
  `--from-session` proposes, operator confirms.
- **Script form requires determinism.** Anything conditional → instructions
  form. Surface a multi-step flow honestly, don't fake a one-liner.
- **Tools never auto-run during `package`.** Dry-run is opt-in.
- **`$FORGE_HOME/tools/` is user-layer by default** (see `/forge-setup` § "Forge
  home"). Operator-local, untracked. Team-shared →
  `/forge-setup --migrate repo` + commit `.forge/tools/`.
- **Operator-named, operator-owned.** Registers + resolves; never imposes
  structure on what the tool does.
- **No host-repo edits during `package`.** Writes confined to
  `$FORGE_HOME/tools/` + `$FORGE_HOME/forge.toml`.
- **Source attribution on capture.** `source` records when + how. Edits refresh
  `captured`, never rewrite history.

## Usage

```
# Interactive capture (most common)
/forge-tool package seed-test-db

# One-shot from a paste
/forge-tool package seed-test-db --purpose "load fixtures" \
  --from-prompt "psql \$DATABASE_URL_TEST -c 'INSERT ...'"

# From the current session
/forge-tool package backfill-org-ids --from-session

# Run / list / show / delete
/forge-tool run seed-test-db --rows 500
/forge-tool list
/forge-tool show rotate-staging-secrets
/forge-tool delete deprecated-flow
```
