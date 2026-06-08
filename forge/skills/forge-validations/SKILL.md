---
name: forge-validations
description: "Draft checkable validations for removal/structural goals."
argument-hint: '[--slug <name>] [--goal G<n>] [--iterate "<feedback>"] [--push]'
triggers:
  - "forge validations"
  - "draft validations for goals"
  - "prove a removal goal"
  - "validate a structural goal"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
practices:
  - tdd
user-invocable: true
---

# /forge-validations — validations per goal

Sibling to `/forge-scenarios`. A scenario proves a **behavioral** goal by a
runtime-observable `when:/then:` test; a **validation** proves a **removal /
negative / structural** goal — no runtime observable — by a **checkable
predicate**.

Two proof kinds; a goal may carry either or **both**:

- **scenario** — `when:/then:` → component test → run → pass.
  (`/forge-scenarios`)
- **validation** — `assert:` predicate bound to a `check:` (shell command or
  `attest`) → executed/attested → evidence recorded. (this skill)

Use validations when the only honest `then:` would be internal or non-existent:
"the field no longer exists", "the abstraction is gone, not renamed", "the
package no longer imports X", "the build still compiles after the removal". You
can't runtime-test that a symbol is _absent_; you grep and assert zero hits.

## When a goal wants validations, not scenarios

Validation-shaped signals:

- **Removal** phrasing ("… will no longer be reachable / will no longer exist").
- End-state is a **compile-time / source-level fact** (symbol gone, import
  dropped, field deleted, proto field removed), not endpoint behavior.
- The only imaginable test asserts an internal mechanic or "still compiles".

A goal can be **mixed**: validations (the removal) + one behavioral guard
scenario (surviving surface still works). Guard via `/forge-scenarios`,
structural facts here.

## Validation shape

```
- VG<n>.<m>
  - assert: <one-sentence checkable predicate / end-state>
  - check: `<shell command; exit 0 = satisfied>`
  - kind: command
```

Attestation form, when no command can express the predicate:

```
- VG<n>.<m>
  - assert: <one-sentence predicate a human/agent can confirm by reading code>
  - check: attest
  - kind: attest
```

Sub-bullets, not bare indented `key: value` — prettier reflows bare continuation
lines into one paragraph; sub-bullets are prettier-safe. `check:` command in
backticks — inline code spans never wrap, so it stays atomic across prettier's
80-col reflow.

ID = `VG<n>.<m>`: `VG2.1` is the first validation under `G2`. `VG` prefix is
distinct from scenarios' `SG` so enumeration never collides (`^- VG\d+\.\d+` vs
`^- SG\d+\.\d+`).

Downstream regexes (canonical + legacy bare-indented tolerated):

- validation header: `^- VG\d+\.\d+\s*$`
- assert line: `^\s+(-\s+)?assert:\s+.+$`
- check line: ``^\s+(-\s+)?check:\s+(`.+`|attest)\s*$``
- kind line: `^\s+(-\s+)?kind:\s+(command|attest)\s*$`

## Prefer command over attest — mechanical first

A validation is only as trustworthy as its check. **Default to
`kind: command`.** An agent "reading the code and signing off" is a self-graded
test — confirmation bias. A command is deterministic and re-runnable by anyone.

Reach for `kind: attest` **only** when no command can express the predicate
(e.g. "this abstraction is gone, not renamed to something semantically
equivalent" — grep proves the old name absent, not that the _concept_ didn't
migrate). Even then, write the tightest command as a **first** validation;
reserve attest for the residual judgment.

### Writing good `check:` commands

- **Exit 0 = satisfied.** Phrase so success means the goal holds. For absence,
  negate a grep: `! git grep -nI '<symbol>' -- <paths>` (exit 0 = no matches).
- **Scope the paths** to directories the removal touches, so an unrelated match
  elsewhere doesn't fail the check.
- **Build / codegen / lint resolve through the tooling map**, never hardcoded:
  cite the capability by name; the runner resolves per `$FORGE_HOME/`. E.g.
  "backend still compiles after removal" → `check: build`.
- **No side effects.** Validations are read-only predicates; never mutate state.

## Coverage rule

Validations are complete for a goal when:

- Every removal/structural claim the goal makes maps to ≥1 validation.
- Every `assert:` is specific enough to be checked — "cleaned up" doesn't count;
  name the symbol / path / surface.
- Each `kind: command` check is phrased so exit 0 means the assert holds.

A goal needs **≥1 proof total** (scenario or validation), not ≥1 of each.

## Process

1. Resolve slug (argument, branch, or the only
   `$FORGE_ART/branches/*/goals.md`).
2. Read `goals.md`. Enumerate `Gn` via `^## G\d+ —`. Missing file → exit "run
   /forge-goals first".
3. **For each goal** (or `--goal G<n>` only) that is validation-shaped (or
   mixed):
   - Read existing `## Validations` block if present (edit mode).
   - Draft validations per § "Validation shape" + "Sizing".
   - Renumber within-goal: `VG<n>.1`, `VG<n>.2`, …; existing IDs stable, new
     ones append.
   - For each `kind: command`, **dry-run the check now** against the current
     tree to confirm it's well-formed and resolves (likely FAILs pre-impl —
     expected; you're linting the command _shape_, not the result). Capture
     nothing.
4. **Write validations inline** in canonical sub-bullet shape. Insert a
   `## Validations` block immediately under each goal — after its `## Scenarios`
   block if one exists, else directly under the goal body / narration.
5. **Forge narration** — add or extend a `### How the proofs prove this` section
   (shared with scenarios when both exist) tying VGs (and SGs) to the goal's
   end-state. Reviewer-facing; not parsed downstream.
6. **Publish goals.md** (tracked per `[artifacts].track`) — gitignore
   bootstrap + force-add-if-ignored per `/forge-goals` §5, commit msg
   `forge-validations: update review artifact`.
7. **`--push`** (orchestrator entry) — push gate per `/forge-goals` §6.
8. Recap — per-goal validation counts (command vs attest), then
   `→ /forge-tests next` (for any behavioral guards) or
   `→ /forge-verify-validations` once impl has landed the removal.

## Iterate mode — `--iterate "<feedback>"`

Triggered by `/forge` from `AWAIT_SCENARIOS_REVIEW` (validations share the
scenarios review gate). Free-text feedback.

1. Read existing `goals.md` (missing → exit `BLOCKED_ITERATE_NO_FILE`).
2. Apply feedback directly — no dialogue. Stay inside Sizing rules.
3. Preserve `VG<n>.<m>` IDs across edits.
4. Re-write inline + re-commit per §6.
5. `--push` (orchestrator default) per §7.
6. Recap with `iterated on: <feedback summary>` tail.

## Sizing — right-size, not maximize

Target the **smallest set that proves the removal/structural goal**. Typical:
**1–4 validations**. One per distinct surface the goal claims is gone or changed
(the Go symbol, the proto field, the build still green). Don't add a validation
that another already subsumes (a single grep over the whole subsystem may cover
several named symbols).

Self-check per candidate:

1. Does this assert a distinct fact the goal claims?
2. Is the `check:` phrased so exit 0 = the fact holds?
3. Could a command replace this `attest`? If yes, rewrite as command.

## What goes into `assert:` / `check:`

- `assert:` — the **predicate** stated as the end-state, specific enough to
  check. Name the symbol, file/path, or surface.
- `check:` — either a backticked **shell command** (exit 0 = satisfied) or the
  literal `attest`. Commands resolve build/codegen/lint through the tooling map
  by capability name.
- `kind:` — `command` or `attest`. Must agree with `check:`.

## Output shape (excerpt)

Rendered plain-code-fenced so prettier doesn't reflow the example.

```
## G2 — <short name> (secondary)

After this PR, <removed thing> will no longer exist.

### How the proofs prove this

<Plain-English paragraph tying VG2.1–VG2.3 (and any SG) back to the goal.>

## Validations

- VG2.1
  - assert: `Settings.SafeDecodingEnabled` field + bson tag absent from the org model + handler
  - check: `! git grep -nI 'SafeDecodingEnabled' -- services/organization/service`
  - kind: command
- VG2.2
  - assert: backend still compiles after the removal
  - check: build
  - kind: command
- VG2.3
  - assert: the per-org toggle concept is gone, not relocated to another field
  - check: attest
  - kind: attest
```

The `## Validations` header under each goal is **load-bearing** — parsed by
`/forge-verify-validations` and `/forge-proof`. Don't rename, don't merge into
the goal body or the `## Scenarios` block.

## Non-goals

- **Not a fixer.** Drafts predicates; `/forge-impl-green` makes them true,
  `/forge-verify-validations` checks them.
- **Not a runtime test.** If the honest proof is a `when:/then:` observable,
  it's a scenario — use `/forge-scenarios`.

## Next step

- `/forge-verify-validations` — run/attest the predicates (after impl)
- `/forge-tests` — bind any behavioral guard scenarios
- `/forge-status` — chain state + drift

## Usage

```
/forge-validations                   # all validation-shaped goals, current branch
/forge-validations --goal G2         # only G2
/forge-validations --slug auth-refactor
```
