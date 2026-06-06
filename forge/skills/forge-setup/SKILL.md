---
name: forge-setup
description:
  "Map host-repo tooling (build, test, lint, typecheck, codegen, devenv,
  localenv) into forge home (~/.claude/forge/<repo-key>/ by default) so forge
  adopts into any repo across all worktrees."
argument-hint:
  "[--cap <name>=<command>]... [--instr <name>=<prose>]... [--playbook
  <name>=<when_output>::<then>]... [--list] [--yes] [--migrate user|repo]
  [--home user|repo|<path>]"
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
| `$FORGE_ART/branches/<slug>/` | **Per-PR chain artifacts** (goals, scenarios, …) | inside the worktree               |
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

## `$FORGE_ART` resolver — per-PR artifact root

`$FORGE_HOME` holds **how to run** the repo + cross-PR config; `$FORGE_ART` is
the **in-repo, in-worktree** root where per-PR chain metadata lives. Every skill
resolves it through this function.

```
forge_art():
  prefix = forge.toml [artifacts].prefix   # default ""
  base   = (prefix == "") ? ".forge" : "<prefix>/.forge"
  return <worktree-root>/<base>            # e.g. ".forge" or ".pr-artifacts/.forge"
```

Layout under `$FORGE_ART`:

```
$FORGE_ART/                 # .forge (default) | <prefix>/.forge
  .gitignore                # tracking policy (generated from [artifacts].track)
  branches/
    <slug-1>/               # one dir per PR — goals.md, design.md, links.json,
    <slug-2>/               #   run.json, validations.json, decisions.md, loop/,
    …                       #   review/, blocker/, wait/, …
```

High-level config (the `.gitignore`) sits at the `$FORGE_ART` root; **all per-PR
metadata is namespaced under `branches/<slug>/`** — never directly under
`$FORGE_ART`.

**`.forge/` coexistence.** The default home is out-of-repo
(`~/.claude/forge/<repo-key>/`), so in-repo `.forge/` is free for artifacts. On
a legacy host still using the in-repo `$FORGE_HOME` fallback, the two share the
`.forge/` dir harmlessly: home owns `forge.toml` + `commands/` at the root,
artifacts own `branches/`. The artifact `.gitignore` scopes every rule to
`branches/…`, so it never touches home files.

## `$FORGE_ART/.gitignore` — per-PR tracking policy

Default forge tracks **everything** under `branches/<slug>/` — the metadata is
checked in so reviewers see the proof chain in the PR. The operator narrows that
via `[artifacts].track`; `/forge-setup` (and the first per-PR writer, as a
bootstrap) regenerates `$FORGE_ART/.gitignore` from it. The file is the single
enforcement point, committed so the policy travels with the repo.

**Category → re-include globs** (relative to `$FORGE_ART`, all under
`branches/`):

| Category  | Globs                                                                                                                                                                             |
| --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `spec`    | human review surfaces: `branches/*/goals.md` `branches/*/design.md`                                                                                                               |
| `proof`   | machine chain state: `branches/*/links.json` `branches/*/run.json` `branches/*/validations.json` `branches/*/decisions.md` `branches/*/approvals.json` `branches/*/.harvest.json` |
| `loop`    | `branches/*/loop/`                                                                                                                                                                |
| `review`  | `branches/*/review/` `branches/*/reviewer/`                                                                                                                                       |
| `monitor` | `branches/*/blocker/` `branches/*/wait/`                                                                                                                                          |

`spec` is the review-facing pair (goals + design); `proof` is the machine state
the chain regenerates — `track = ["spec"]` keeps a repo's tracked surface to the
two human artifacts.

Generation is **allowlist**, not denylist: ignore everything under `branches/`,
then re-include only the tracked categories. This is deliberate — a PR's
artifact dir also accumulates uncategorized scratch (`brief.md`, `*.log`, ad-hoc
notes); a denylist would leak those into git, an allowlist never does.

```bash
art="$(forge_art)"; mkdir -p "$art/branches"
gi="$art/.gitignore"   # at $FORGE_ART root, above branches/ — always tracked
{
  echo "# Forge per-PR artifact tracking — generated from forge.toml [artifacts].track"
  echo "# Governs only branches/<slug>/ metadata. Edit [artifacts].track + re-run /forge-setup."
  case "$track" in
    all)  : ;;                          # track everything → ignore nothing
    none) echo "branches/**" ;;         # ignore all per-PR metadata
    *)    echo "branches/**"            # ignore all, then re-include tracked
          echo "!branches/*/"           #   (descend into slug dirs)
          for cat in $track; do
            for g in $(globs_for "$cat"); do
              echo "!$g"
              case "$g" in */) echo "!$g**" ;; esac   # dir glob → also re-include contents
            done
          done ;;
  esac
} > "$gi"
```

`none`/`[list]` ignore only `branches/**`, so the `.gitignore` (above
`branches/`) stays tracked without a `!` rule. Dropping `spec` is unusual — it
is the review surface. This recipe is canonical; per-PR writers (`/forge-goals`,
`/forge-design`, `/forge-start`) bootstrap it on first write and otherwise leave
it alone.

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

| Capability        | What it runs                                                                                      | Used by                                                      |
| ----------------- | ------------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `test`            | Run tests. Forge appends an optional selector as the last arg.                                    | `/forge-impl-green`, `/forge-tests`, proof runs              |
| `build`           | Compile / build                                                                                   | `/forge-ci-green`, impl loop                                 |
| `lint`            | Lint                                                                                              | `/forge-ci-green`                                            |
| `typecheck`       | Static type check                                                                                 | `/forge-ci-green`, impl loop                                 |
| `codegen`         | Regenerate generated code (mocks, proto, clients)                                                 | impl loop recovery, `/forge`                                 |
| `devenv`          | Bring up a dev environment (optional)                                                             | manual / component-tier flows                                |
| `localenv`        | Bring up local infra for component-tier tests (optional)                                          | component-tier test runs                                     |
| `restack`         | Sync the branch's base into the branch (base from upstream first)                                 | `/forge-ci-green` (each iteration), `/forge-wait-for` resume |
| review automation | GitHub `gh` baseline: list unresolved / reply / resolve / re-request. External tools → draft-only | `/forge-address-review`                                      |

`test` is the one capability nearly every chain needs; the rest as warranted.

**`restack` — no hard plugin dependency.** Forge needs to bring a branch's base
into the branch (every CI iteration; on external-block resume). It resolves this
through the map like any capability — additionally accepting a **skill** wiring
(`[restack].skill`, e.g. `@orrgal1/devloop`'s `/restack`). When nothing is
wired, forge falls back to a **built-in** plain-git restack
(`git fetch <remote> <base>` → merge `<remote>/<base>` into the branch; conflict
→ `BLOCKED_RESTACK_CONFLICT`). So `/restack` is the recommended wiring when
devloop is installed, but **not required** — forge runs standalone.

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

**Skill wiring (restack).** `restack` accepts one extra form, checked **first**:
a `[restack].skill` string naming an installed slash-command skill (e.g.
`/restack`) — forge invokes that skill instead of a shell command. Resolution
for `restack`: `[restack].skill` → forms 1–4 above → **built-in git fallback**
(`git fetch <remote> <base>`, then merge `<remote>/<base>` into the branch;
conflict → `BLOCKED_RESTACK_CONFLICT`). `restack` therefore never surfaces
`NEEDS_SETUP` — the built-in fallback always applies. No other capability has a
built-in fallback.

**Review automation** isn't a `forge.toml` slot: GitHub `gh` is the always-on
auto-driven baseline; external review tools are draft-only (see Capabilities).
Never `NEEDS_SETUP`.

## Failure recovery — playbooks (consulted on capability failure)

A wired capability that exits non-zero is not always a hard stop. Repos have
**known recoveries for known failures** — expired cloud creds, a daemon that
must be started, stale codegen. `[playbooks.<name>]` rules encode these so forge
recovers **itself** instead of blocking and asking the operator to "go auth."
Distinct from `[tools]`: a tool is **pulled** (invoked by name on demand); a
playbook is **triggered** — matched against a failure signature, it fires on its
own.

Every forge skill that runs a capability follows this contract. When a
forge-invoked capability `<cap>` exits non-zero, **before** surfacing the
failure / blocking / asking the operator:

1. `[playbooks].enabled = false` → skip; existing behavior. Else capture the
   run's combined stdout+stderr.
2. Match the **first** `[playbooks.<name>]` where **both**:
   - `when_capability` is empty/absent **or** contains `<cap>`, **and**
   - `when_output` (regex) matches the captured output. No match → existing
     behavior (block / `NEEDS_SETUP` / ask). **Unchanged** — playbooks only ever
     _add_ a recovery path, never suppress a genuine block.
3. Match **and** attempts remain (this `(rule, op)` has fired
   `< [playbooks].max_attempts` times): **attempt the recovery** — `then`
   command, or `skill` if set (resolved like a `restack` skill). Forge attempts
   it in **every** mode (best-effort); it is never a pre-emptive block.
   - `interactive = true` flags that the recovery may need a human to **complete
     it** (e.g. `aws sso login` opens a browser). In an attended session (manual
     / default), surface it as `! <then>` so the operator's own terminal owns
     the prompt. In **yolo / auto / unattended**, run it directly anyway —
     best-effort: those modes are best-effort by design, and an operator may
     well be watching a `yolo` run and catch the browser approval. If no human
     completes it, the command simply fails → step 4 turns it into a genuine
     block _then_, organically. Forge never refuses to try.
   - `interactive = false` → forge just runs it; no human needed.

   After the recovery, if `retry = true`, re-run `<cap>` once and re-evaluate
   from the top (counting against `max_attempts`).

4. Recovery command itself fails (including an `interactive` recovery that no
   human completed), **or** retry still fails after `max_attempts` → block with
   the **original** failure, noting the playbook was attempted (rule name +
   action taken). Never loop a playbook past `max_attempts`; a playbook never
   re-matches on its own recovery output.

`/forge-triage` consults the same table: an `INFRA_FAILURE` whose output matches
a playbook routes to that recovery instead of dead-ending at `BLOCKED_INFRA`.

### Emergent playbooks — capture on the fly

The map is never complete up front. When forge hits a capability failure that
**no playbook matched** and that failure is then **resolved** — the operator ran
a command to clear it (often via `! …`), or an ad-hoc step forge took on the
operator's instruction made the retry pass — forge has just observed a
failure→recovery pair worth remembering. Recognize it and **offer to capture a
new `[playbooks.<name>]`**:

1. **Recognize.** A capability exited non-zero, no rule matched, and a
   subsequent action (operator command or one-off step) led to the same op
   passing. That `(failure signature, recovery action)` is a candidate.
2. **Distill the signature.** Reduce the failure output to a stable regex — the
   stable error phrase (`ExpiredToken`, `connection refused`,
   `mockgen: command not found`), not run-specific paths / timestamps / pids.
3. **Offer.** Show the proposed rule (`when_capability`, `when_output`, `then`,
   `interactive` inferred from whether the recovery needed a human) and ask
   `[capture / edit / skip]`. Accepted → append the `[playbooks.<name>]`
   subtable to `$FORGE_HOME/forge.toml`; it applies to every later run and every
   worktree. Honesty gate (§ "Honesty"): forge **proposes**, never silently
   writes a recovery command it inferred.
4. **Unattended.** In yolo / unattended, do **not** write config without
   approval — record the candidate rule (commented, with its observed signature
   - recovery) in the chain's `decisions.md` and surface it in the final recap
     so the operator can confirm it into the map later.

This is the playbook analogue of `/forge-tool`'s ad-hoc capture: a recurring
manual recovery graduates into a wired, automatic one.

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

# Per-PR artifact layout + git-tracking policy. Governs ONLY the in-repo per-PR
# metadata under $FORGE_ART/branches/<slug>/. Does NOT govern maps / tools /
# commands (those live in $FORGE_HOME; gitignore them separately if in-repo).
[artifacts]
prefix = ""        # "" -> .forge at repo root ; "<prefix>" -> <prefix>/.forge
track  = "all"     # what of per-PR metadata git tracks. Default tracks everything.
                   #   "all"  -> nothing ignored
                   #   "none" -> ignore every branches/<slug>/ artifact
                   #   [list] -> track only these categories, ignore the rest
                   # Categories:
                   #   spec     goals.md design.md       (human review surfaces)
                   #   proof    links.json run.json validations.json
                   #            decisions.md approvals.json .harvest.json
                   #   loop     loop/**     (green-loop scratchpads)
                   #   review   review/**   (cycles, synthesis, watch)
                   #   monitor  blocker/** wait/**
                   # e.g. track = ["spec"]  tracks only goals.md + design.md
                   # /forge-setup regenerates $FORGE_ART/.gitignore from this.

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

# How forge restacks a branch onto its base (every CI iteration + on
# external-block resume). No hard plugin dependency — wire ONE form, or leave
# all blank for the built-in git fallback (fetch base, merge into branch).
# Resolution: skill → commands/restack(.md) / [commands].restack /
# [instructions].restack → built-in fallback.
[restack]
skill = ""    # an installed slash-command skill, e.g. "/restack" (devloop). Recommended when installed.
# Or wire it as a command/instructions like any capability:
#   [commands].restack    = "git fetch origin main && git merge origin/main"
#   [instructions].restack = "Run `/restack` if present, else fetch + merge the base."

# Repo-scoped recovery playbooks. Forge consults these AUTOMATICALLY when a
# wired capability run exits non-zero — BEFORE blocking on the operator — so a
# known failure with a known recovery (expired cloud creds, a daemon to start,
# stale codegen) self-heals instead of stalling the chain. Distinct from
# [tools]: a tool is PULLED (invoked by name on demand); a playbook is TRIGGERED
# (matched against the failure signature, it fires on its own). See § "Failure
# recovery — playbooks".
[playbooks]
enabled      = true
max_attempts = 1     # recovery+retry rounds per (rule, op) before a genuine block

# Each playbook is a subtable [playbooks.<name>] — one failure→recovery rule.
# ILLUSTRATIVE EXAMPLE — forge ships NO playbooks; the recovery is repo-specific
# and supplied by the operator (forge never guesses a command). Shown to convey
# the schema, not as a default.
[playbooks.ecr-auth]
when_capability = ["localenv", "build"]   # capabilities this applies to; omit or [] = any
when_output     = "no basic auth credentials|denied: .*ecr|ExpiredToken|ecr.*not authorized"  # regex over captured stdout+stderr
then            = "aws sso login"          # THIS repo's recovery (another repo: gcloud auth login / docker login / …)
skill           = ""                       # alternative to `then`: an installed slash-command skill to invoke
interactive     = true                     # hint that completing it may need a human (browser). Attended → suggest `! aws sso login`; yolo/auto/unattended → forge runs it best-effort (fails → genuine block then). Never a pre-emptive block.
retry           = true                     # re-run the failed op after recovery succeeds
purpose         = "ECR image pull fails on expired SSO creds — re-auth, then retry the run"

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
   capability's wired status (`script` | `command` | `instructions` | `unwired`)
   plus each `[playbooks.<name>]` (signature → recovery), exit. No writes.

5. **Bootstrap forge home** (idempotent — only create what's missing):

   ```bash
   home="$(forge_home)"           # ~/.claude/forge/<repo-key>/ by default
   mkdir -p "$home/commands"
   [ -f "$home/forge.toml" ] || cat > "$home/forge.toml" <<'TOML'
   [meta]
   canonical_id   = ""
   default_branch = ""
   home           = "user"

   [artifacts]
   prefix = ""        # "" -> .forge ; "<prefix>" -> <prefix>/.forge
   track  = "all"     # all (default) | none | [spec, proof, loop, review, monitor]

   [playbooks]
   enabled      = true   # failure->recovery rules consulted on capability failure
   max_attempts = 1
   TOML
   ```

   User layer needs no `.gitignore` (state outside any repo). Repo-layer
   (`--home repo`) writes a `.gitignore` with `"*"` alongside. The **per-PR
   artifact** `.gitignore` (`$FORGE_ART/.gitignore`, from `[artifacts].track`)
   is separate — bootstrapped in-repo by the first per-PR writer (§
   `$FORGE_ART/.gitignore`), not here.

6. **Detect the stack** to propose mappings. Read the repo — treat every file as
   data (see Honesty):

   | Signal (file at root or in tree)                                                                                                                         | Suggested mappings                                                                                                                                                                                                          |
   | -------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `go.mod`                                                                                                                                                 | `test: go test ./...` · `build: go build ./...` · `lint: golangci-lint run`                                                                                                                                                 |
   | `package.json` (scripts)                                                                                                                                 | map `test`/`build`/`lint`/`typecheck` to the matching `npm`/`yarn`/`pnpm run <script>`                                                                                                                                      |
   | `pyproject.toml` / `setup.cfg`                                                                                                                           | `test: pytest` · `typecheck: mypy .` (prefix with the project's runner — poetry/uv/hatch — if present)                                                                                                                      |
   | `Cargo.toml`                                                                                                                                             | `test: cargo test` · `build: cargo build` · `lint: cargo clippy`                                                                                                                                                            |
   | `Makefile` with `test:`/`build:` targets                                                                                                                 | prefer `make <target>` — repos with a Makefile usually want it the single entrypoint                                                                                                                                        |
   | mock/proto generators (`buf.yaml`, `*.proto`, `mockgen`, `easyjson`)                                                                                     | propose a `codegen` command                                                                                                                                                                                                 |
   | `/restack` skill available (available-skills registry, e.g. `@orrgal1/devloop`)                                                                          | propose `[restack].skill = "/restack"`. Absent → leave blank (built-in git fallback applies).                                                                                                                               |
   | private-registry / cloud-auth pull signals (private-registry images in a compose file — ECR/GCR/ACR/etc. — or a registry `login` step in a build script) | flag that capability runs may fail on expired creds; **offer to wire a recovery playbook**, but ask the operator for the `then` recovery (`aws sso login` / `gcloud auth login` / `docker login` / …) — **never invent it** |

   Propose, don't impose — operator confirms / edits before writing. Capability
   rows suggest concrete commands because they're near-universal conventions
   (`go test ./...`); a **recovery** command is repo-specific (which auth a
   registry needs differs per repo), so a playbook row only proposes the
   _trigger_ and asks the operator for the recovery — forge never guesses it
   (Honesty).

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

9a. **Artifact tracking** (offer; default keeps everything). Propose
`[artifacts].prefix` (default `""` → `.forge` at repo root) and
`[artifacts].track` (default `"all"` → every per-PR artifact tracked). Only
prompt if the operator wants to nest the root or exclude noisy categories
(`loop`, `monitor`); otherwise write the defaults silently. Governs only
`$FORGE_ART/branches/<slug>/` — not maps/tools.

9b. **Recovery playbooks** (offer; § "Failure recovery — playbooks"). For each
auth/recovery _signal_ detection flagged (step 6), describe the likely failure
and the proposed `when_capability` + `when_output` **trigger**, then **ask the
operator for the recovery** (`then` command / `skill`) — forge never fills it
in. Operator supplies it → write the `[playbooks.<name>]` subtable; declines →
skip. None flagged → write the empty `[playbooks]` header with `enabled = true`
so the table exists for later capture. `--playbook <name>=<when_output>::<then>`
adds one non-interactively (interactive defaults true, retry true). Same
propose-don't-impose gate as capability detection — forge never invents a
recovery command into the map unconfirmed.

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

13. **Recap.** Print the capability table with final status + next move, plus
    the `[playbooks.<name>]` rules (signature → recovery), and any emergent
    playbook candidates recorded this run awaiting confirmation.

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
  restack    <skill | command | instructions | built-in fallback>   <preview>

playbooks:
  <name>     <when_capability> · /<when_output>/ → <then>   (interactive|auto, retry)
  …          (none → "no recovery playbooks wired")

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
/forge-setup --playbook ecr-auth="ExpiredToken|denied: .*ecr::aws sso login" --yes  # failure→recovery rule

# Migration
/forge-setup --migrate user                   # move .forge/ → ~/.claude/forge/<repo-key>/
/forge-setup --migrate repo                   # reverse

# Override forge home for this run
FORGE_HOME=/tmp/forge-sandbox /forge-setup --list
```

Map wired → `/forge-start <source>` (bootstrap a chain) or `/forge` (drive
end-to-end).
