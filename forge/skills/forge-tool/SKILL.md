---
name: forge-tool
description: "Capture an ad-hoc flow as a repeatable tool under .forge/tools/ and register it in .forge/forge.toml [tools.<name>]."
argument-hint:
  "[package <name> | list | run <name> [args] | show <name> | delete <name>]
  [--purpose <text>] [--form script|instructions|dir|agent]
  [--from-session] [--from-prompt <text>] [--yes] [--dry-run]"
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

A **tool** is an operator-named, user-defined runbook living under
`.forge/tools/`. Use it when a flow you just figured out (seed a test db,
rotate staging secrets, backfill a column with care) is one you want
repeatable without rediscovery next time. Other forge skills can resolve
tools by name when wired into a capability — tools are first-class.

Tools are distinct from the other `.forge/` surfaces:

| Surface              | What lives there                            | Who names it           |
| -------------------- | ------------------------------------------- | ---------------------- |
| `.forge/commands/`   | canonical capabilities (`test`, `build`, …) | forge (finite set)     |
| `.forge/review/`     | additive review-mechanism integrations      | forge (one per mechanism) |
| `.forge/review-channels/` | `/forge-review` channels             | forge (per channel)    |
| `.forge/maps/`       | read-only domain snapshots                  | `/forge-map` (per area)|
| `.forge/tools/`      | **open-ended, operator-named runbooks**     | **the operator**       |

## Subcommands

| Subcommand            | Default? | Purpose                                                       |
| --------------------- | -------- | ------------------------------------------------------------- |
| `package <name>`      | yes      | Capture a flow as a new tool. Three capture modes (see below).|
| `list`                |          | Print every registered tool: name, form, purpose, freshness.  |
| `run <name> [args]`   |          | Resolve + execute the tool. Script form → run; instructions → agent reads + performs; dir form → run `<dir>/run`; agent form → spawn the registered subagent. |
| `show <name>`         |          | Print the tool file(s) + registry entry.                      |
| `delete <name>`       |          | Remove tool file(s) + registry entry. Asks before deleting.   |

Absent subcommand + a name → `package <name>` (the common case).

## Inputs

| Input                  | Subcommand     | Notes                                                                                  |
| ---------------------- | -------------- | -------------------------------------------------------------------------------------- |
| `<name>`               | most           | Tool id (lowercase slug, hyphens). Reserved: any `.forge/commands/<cap>` capability.   |
| `--purpose <text>`     | `package`      | One-line summary stored in `[tools.<name>].purpose`. Asked interactively if absent.    |
| `--form <form>`        | `package`      | Force form: `script` / `instructions` / `dir` / `agent`. Auto-detect when absent.      |
| `--from-session`       | `package`      | Capture from the current Claude session (recent observations / transcript / git log + edits). Operator confirms before save. |
| `--from-prompt <text>` | `package`      | One-shot capture: operator provides the full recipe inline; skill packages without further interactive prompts. |
| `--yes`                | `package`, `delete` | Skip confirmation prompts.                                                        |
| `--dry-run`            | `run`          | Show what would run; don't execute.                                                    |

`package` runs in **interactive Q&A** when neither `--from-session` nor
`--from-prompt` is passed. That's the default and the highest-fidelity capture
path — operator describes the steps; agent drafts; operator confirms.

## Tool forms

Auto-detected from the captured content; `--form` overrides.

### `script`

Single executable file at `.forge/tools/<name>`. Deterministic shell; args
passed via `$@`. Auto-detected when the captured flow is a sequence of
shell commands with no conditional logic.

```sh
#!/usr/bin/env sh
# .forge/tools/seed-test-db — load fixture rows into the test db.
# Forge invokes: .forge/tools/seed-test-db [--rows N]
set -eu
rows="${1:-100}"
exec psql "$DATABASE_URL_TEST" -c "INSERT INTO ..."
```

### `instructions`

Markdown doc at `.forge/tools/<name>.md` the agent reads and performs.
Auto-detected when the captured flow has conditionals, judgment calls,
multi-step health checks, or other content a fixed command can't capture.

```markdown
# rotate-staging-secrets — how to do it here

1. List current secrets: `vault kv list secret/staging`.
2. For each secret with `rotate=true` metadata: …
3. Wait for the canary pod to report ready before promoting …
```

### `dir`

Tool dir at `.forge/tools/<name>/` with `run` as the entrypoint and any
helper files (`lib/...`, `templates/...`). Auto-detected when the captured
flow includes file fixtures the script reads, or grows past ~50 lines.

```
.forge/tools/backfill-org-ids/
  run               # entrypoint script
  lib/migrate.sql
  lib/verify.sql
```

### `agent`

Tool that spawns a subagent with a baked prompt. The tool file is markdown
at `.forge/tools/<name>.md` with frontmatter:

```markdown
---
form: agent
agent: caveman:cavecrew-investigator
inputs:
  - name: query
    required: true
---

# audit-feature-flag-usage — agent recipe

When invoked: spawn the `caveman:cavecrew-investigator` agent with this
prompt template (substitutes `${query}`):

> Find every call site of `isEnabled(...)` for flag key `${query}`. Report
> file:line, call style, and whether it's behind a feature-flag service or
> a plain env-var check.
```

Use when the captured flow is "I ran this subagent with this kind of
prompt and want to do it again."

## Layout

```
.forge/
  tools/
    seed-test-db                    # form: script
    rotate-staging-secrets.md       # form: instructions
    audit-feature-flag-usage.md     # form: agent (frontmatter declares it)
    backfill-org-ids/               # form: dir
      run
      lib/migrate.sql
```

Filename rules:

- `script`: `.forge/tools/<name>` (no extension, executable bit set).
- `instructions` + `agent`: `.forge/tools/<name>.md` (same extension; the
  frontmatter's `form:` field distinguishes them).
- `dir`: `.forge/tools/<name>/run` is the entrypoint; helpers free-form.

Resolution order when running a tool (same spirit as `.forge/commands/`):

1. `.forge/tools/<name>` executable → run as script.
2. `.forge/tools/<name>/run` executable → run as dir-form (cwd = the dir).
3. `.forge/tools/<name>.md` with frontmatter `form: instructions` → agent
   reads + performs the body.
4. `.forge/tools/<name>.md` with frontmatter `form: agent` → spawn the
   declared subagent with the rendered prompt.
5. None → halt `TOOL_NOT_FOUND name=<name>`.

## `[tools]` schema in `.forge/forge.toml`

Forge owns the registry. Each tool gets its own subtable. Entries are
written by `/forge-tool package`; manual edits honored but not recommended.

```toml
# .forge/forge.toml — tools section is owned by /forge-tool.

[tools]
# Where tool files live, relative to .forge/. Override if you must.
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
- `file` — path relative to `.forge/`. For `dir` form: the dir, not `run`.
  Required.
- `purpose` — one-line summary. Required (asked at capture time).
- `inputs` — short usage string shown in `/forge-tool list`. Optional.
- `captured` — ISO-8601 UTC of the most recent `/forge-tool package` run.
  Required, set automatically.
- `source` — free-text provenance hint: "discovered during PR #X",
  "from session 2026-05-28". Optional.
- `agent` — subagent slug (e.g. `caveman:cavecrew-investigator`). Required
  for `agent` form, omitted otherwise.

Unknown keys are tolerated (forward-compat) but ignored by `list`.

## Cross-skill lookup contract

Other forge skills resolve a tool by name through this surface:

1. Read `.forge/forge.toml` `[tools.<name>]`. Missing → tool not registered,
   no fallback discovery.
2. Resolve the file per the **Resolution order** above.
3. Invoke per form:
   - `script` / `dir` → run directly, exit code is success.
   - `instructions` / `agent` → the calling skill is the one that follows
     the body. `/forge-tool run` does this on the operator's behalf.

Recommended use sites (advisory, not enforced):

- `.forge/commands/<cap>.md` instruction files can say "before this,
  invoke `tool: <name>` to set up state" — forge skills honor that hint.
- `/forge-impl-green` may resolve `tool: seed-test-db` when an
  `.forge/commands/test.md` references it.
- `/forge-review-green` may resolve `tool: <name>` from a fix-plan note.

Tools never auto-run from the canonical chain. The chain references them
only when an instruction file the operator wrote asks for it.

## Process

### `package <name>` — interactive Q&A (default)

1. **Resolve repo root.** `git rev-parse --show-toplevel`. Not a git repo →
   halt `TOOL_BLOCKED reason not-a-repo`.

2. **Validate name.** Lowercase, alphanumerics + hyphens, ≤40 chars. Not a
   reserved capability key. Not already registered (re-run with `--yes`
   overwrites). Else halt `TOOL_BLOCKED reason <invalid|reserved|exists>`.

3. **Bootstrap dir** (idempotent):

   ```bash
   root="$(git rev-parse --show-toplevel)"
   mkdir -p "$root/.forge/tools"
   [ -f "$root/.forge/.gitignore" ] || printf '*\n' > "$root/.forge/.gitignore"
   [ -f "$root/.forge/forge.toml" ] || /forge-setup --yes
   ```

4. **Ask: purpose.** "One line — what does this tool do?" Skip if
   `--purpose <text>` was passed.

5. **Ask: steps.** "Describe the steps. Paste commands, or talk through
   them — pseudo-shell is fine." Operator may include shell history,
   pasted runs, or narrative.

6. **Pick form** (operator may override with `--form`):
   - Captured content is pure shell, no conditionals, no narrative → `script`.
   - Conditional / multi-step / health-check / judgment → `instructions`.
   - Mentions reading helper files / templates → `dir`.
   - Operator says "I ran subagent X with this prompt" → `agent`.
   - Ambiguous → propose `instructions`; let operator override.

7. **Draft the file content** per form (see § "Tool forms" templates). For
   `script` form, wrap in the standard stub
   (`#!/usr/bin/env sh / set -eu / exec ... "$@"`). For `agent` form,
   require the operator to confirm the subagent slug + render the prompt
   template with explicit `${var}` placeholders.

8. **Show preview.** Print the proposed file + the proposed `[tools.<name>]`
   subtable. Ask: `[y / edit / abort]`.
   - `edit` → drop the operator into an inline editor loop until accept.

9. **Write atomically.**
   - File: tmp + `mv -f`. Script + dir-form `run`: `chmod +x` after move.
   - `forge.toml`: read full file, splice / replace `[tools.<name>]`,
     atomic tmp + `mv -f`. Preserve every other section + unknown keys.

10. **Optional dry-run.** When form is `script` / `dir` and operator didn't
    pass `--yes`, ask "dry-run now? [y/N]". Yes → run the tool with `--help`
    if it accepts one, else with no args. Non-zero exit → warn, don't roll
    back (operator may need to fix the captured content).

11. **Recap.** Print:

    ```
    ## /forge-tool package result

    verdict: TOOL_REGISTERED | TOOL_BLOCKED
    tool:    <name>
    form:    <form>
    file:    .forge/tools/<...>
    purpose: <one line>

    ### next move
    /forge-tool run <name>   |   /forge-tool show <name>   |   /forge-tool list
    ```

### `package <name> --from-session`

Same flow as interactive Q&A, but step 5's content is auto-proposed:

1. Read the recent session signal (whichever is available, in order):
   - `mcp__plugin_claude-mem_mcp-search__search` / `timeline` observations
     from the last 1 hour.
   - Recent shell commands from this conversation's Bash tool calls.
   - Recent file edits from `git diff` + `git log --since="1 hour ago"`.
2. Propose a steps draft to the operator: "Here's what I think this flow
   did — edit anything wrong." Operator reviews + edits before save.
3. Continue from step 6 (form picking).

If no session signal is available → fall back to interactive Q&A with a
note ("session capture found no signal; falling back to manual").

### `package <name> --from-prompt <text>`

Skip steps 4–5: take `<text>` as the steps description verbatim. Continue
from step 6. Useful for one-shot recipe paste:

```
/forge-tool package seed-test-db --purpose "load fixtures" \
  --from-prompt "psql \$DATABASE_URL_TEST -c 'INSERT ...'"
```

### `list`

1. Read `.forge/forge.toml` `[tools.*]`.
2. For each tool, compute freshness:
   - `missing` — `file` not on disk.
   - `stale` — file mtime older than the registered `captured` (operator
     edited file outside the skill); flag without judgment.
   - `fresh` — otherwise.
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
2. Resolve file via the resolution order. File missing → halt
   `TOOL_BROKEN reason file-missing`.
3. `--dry-run` → print the resolved command / instructions body / agent
   prompt and exit.
4. Execute per form:
   - `script` → `exec "$file" "$@"`.
   - `dir` → `cd "$dir" && exec ./run "$@"`.
   - `instructions` → read file, perform the steps. Args available as
     `$1..$N` for substitution into the instructions when they declare
     `inputs:` in optional frontmatter.
   - `agent` → render the prompt template with `${var}` substitutions
     from args, spawn the registered subagent via the Agent tool.
5. Surface stdout/stderr + final exit status.

### `show <name>`

Print the resolved file(s) + the registry subtable. No writes.

### `delete <name>`

1. Read `[tools.<name>]`. Missing → halt `TOOL_NOT_FOUND`.
2. Show file(s) + subtable, ask "delete? [y/N]" unless `--yes`.
3. Remove the file(s); remove the subtable from `forge.toml` (atomic
   rewrite). Print recap.

## Honesty

- **Never invent steps the operator didn't describe.** Interactive Q&A is
  the source of truth; `--from-session` proposes, operator confirms.
- **Script form requires determinism.** Anything conditional → instructions
  form. Better to surface a multi-step flow honestly than fake a one-liner.
- **Tools never auto-run during `package`.** Dry-run is opt-in.
- **`.forge/tools/` is gitignored by default** along with the rest of
  `.forge/`. Operators choose to track tools when they want them shared.
- **Operator-named, operator-owned.** This skill registers + resolves;
  it never imposes structure on what the tool does.
- **No host-repo edits during `package`.** Writes confined to
  `.forge/tools/` + `.forge/forge.toml`.
- **Source attribution on capture.** `source` field records when + how the
  tool was captured. Edits over time should refresh `captured`, never
  rewrite history.

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
