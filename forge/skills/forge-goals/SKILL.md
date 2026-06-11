---
name: forge-goals
description: "Capture the PR's intended end-state as goals, loyal to source."
argument-hint: '[<source>] [--slug <name>] [--iterate "<feedback>"] [--push]'
triggers:
  - "forge goals"
  - "capture pr goals"
  - "start forge chain"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebFetch
practices:
  - tdd
user-invocable: true
---

# /forge-goals — capture PR goals (operator-led)

First link. Operator drives; sources are reference.

A **goal** = future end-state the PR commits to. Not tasks, not file lists —
what the system **will support** or **will be**. Else it's impl detail.

## Goal shape

Pick one phrasing:

- **Capability** — "When this PR ships, the system will support `<X>`."
- **End-state** — "After this PR, `<Y>` will be the new state of `<subsystem>`."
- **Invariant** — "After this PR, `<Z>` will always hold for `<entity>`."
- **Removal** — "After this PR, `<deprecated thing>` will no longer be
  reachable."

Wrong: "Refactor X" (task), "Add tests" (means), "Fix the bug" (no specificity).

**Proof depends on shape.** Behavioral goals (capability / end-state / invariant
with a runtime observable) → **scenarios** (`/forge-scenarios` → component
tests). **Removal** + structural goals (source-level fact, no runtime
observable: "the field is gone") → **validations** (`/forge-validations` →
`git grep` / build predicate, or agent attestation). A goal may carry both.
Every goal needs ≥1 proof, not ≥1 of each.

## Symptom-only sources — demand the expected behavior

A bug report that names only a deviation — "X is wrong / broken / missing" —
defines no end-state. Downstream proof only ever checks loyalty to goals, so an
expected behavior invented here poisons the whole chain (and may "fix" a
non-bug). Close two questions before writing goals:

1. **What is the correct behavior, concretely?** Source states it → cite it. It
   doesn't → demand it in dialogue; the operator may know, or must take it back
   to the reporter. Never derive it from the symptom by guessing.
2. **Is the claim verified?** An unreproduced report (QA claim, drive-by ticket)
   may describe behavior that is already correct — flag it, so the answer to 1
   can turn out to be "current behavior; close the ticket, no PR".

Neither source nor operator can state the expected behavior → **halt**:

```
Source claims wrong behavior but never states the right one.

  symptom: <quoted claim from source>

Options:
  [a] State the expected behavior now — it becomes the goal's end-state.
  [b] Point me at where it's specified (spec / doc / prior ticket).
  [c] Take it back to the reporter — goals stay unwritten.

Which?
```

No `--force`. Genuine blocker in every mode — yolo does not auto-approve past
it.

## Count — hard cap 3, floor 1

- **G1** = main (the one sentence reviewers should remember).
- **G2**, **G3** = secondary outcomes the PR also commits to.
- **>3 → halt + recommend splitting into focused PRs.** No `--force` escape
  hatch.

Out-of-scope items live under `## Out of scope` — don't count toward cap.

## Process

1. **Resolve slug + worktree.** Branch name sanitized (lowercase,
   alphanumerics + dashes, strip `feat/` / `fix/` / `chore/`). `--slug`
   overrides.
2. **Open dialogue first**, before fetching:

   > How do you see this PR? Main thing it delivers? Anything else on the side?

   Operator's framing is the seed; sources corroborate. Operator points at Jira
   / PR body → fetch, then ask "Source says X — match your view, or stale?"

3. **Pull reference in parallel:**

   | Source                     | How                                               |
   | -------------------------- | ------------------------------------------------- |
   | Jira ticket                | `mcp__claude_ai_Atlassian__getJiraIssue`          |
   | Current PR body            | `gh pr view --json title,body`                    |
   | GitHub PR / issue URL      | `gh pr view <url>` / `gh issue view <url>`        |
   | Notion / Confluence        | `mcp__notion__notion-fetch` / `getConfluencePage` |
   | Markdown in repo           | Read directly                                     |
   | Public web                 | `WebFetch` (auth-walled won't work)               |
   | Pasted text / conversation | Use as-is                                         |

   Don't invent goals the source doesn't claim AND the operator doesn't endorse.
   Bug-fix source → close the § "Symptom-only sources" gate before proposing.

4. **Propose, iterate, converge.** Present inline (not yet written):

   ```
   G1 (main) — <short name>
     <one-sentence end-state>

   G2 (secondary) — <short name>
     <one-sentence end-state>

   Out of scope:
     - <item>
   ```

   Ask: `[y / edit]` with options `--rewrite G<n>` `--add` (cap-checked)
   `--drop G<n>` `--promote G<n>` `--out-of-scope` `--remove-from-scope`. Loop
   until `y`. Re-present current state each loop.

5. **Write `$FORGE_ART/branches/<slug>/goals.md`** per Output shape. Bootstrap
   the artifact dir + the tracking `.gitignore` (generated from
   `[artifacts].track`, per `/forge-setup` § `$FORGE_ART/.gitignore`):

   ```bash
   mkdir -p "$FORGE_ART/branches/${slug}"
   [ -f "$FORGE_ART/.gitignore" ] || forge_write_artifact_gitignore   # from [artifacts].track; default "all"
   ```

   `track="all"` (default) tracks everything — `goals.md` is committed for
   inline review. If the operator set a host `.gitignore` that blanket-ignores
   `$FORGE_ART`'s parent and a tracked artifact ends up ignored, force-add it:

   ```bash
   gm="$FORGE_ART/branches/${slug}/goals.md"
   if git check-ignore -q "$gm"; then
     git add -f "$FORGE_ART/.gitignore" "$gm"
     git commit -m "forge-goals: publish artifact (ignored path)"
   fi
   ```

6. **`--push`** (orchestrator entry): push when local commits ahead
   (`git rev-list --count @{u}..HEAD > 0`); else no-op. SSH-only. `--push`
   without upstream → `git push -u origin HEAD`.

7. **Recap:**

   ```
   ✓ goals.md written: $FORGE_ART/branches/<slug>/goals.md
     G1 (main): <short name>     G2 (secondary): <short name>   …
     out of scope: <count>
   → /forge-scenarios next.
   ```

## Edit mode

If `goals.md` exists + was authored by this skill: read it → present current
state → ask "what changed?" → run iteration loop with existing as starting point
→ diff before overwrite → ask confirm. **Preserve `Gn` IDs across edits.**
Dropping G2 → new G2 replaces it; never renumber G3→G2. Append G4 when adding.

## Iterate mode — `--iterate "<feedback>"`

Triggered by `/forge` from `AWAIT_GOALS_REVIEW`. Free-text feedback string.

1. Read existing `goals.md` (missing → exit `BLOCKED_ITERATE_NO_FILE`).
2. Apply feedback directly — no dialogue. Stay inside right-sized rules.
3. Preserve `Gn` IDs (Edit mode rule).
4. Re-write + re-publish + re-commit per §5.
5. `--push` (orchestrator default) per §6.
6. Recap with `iterated on: <feedback summary>` tail for decisions log.

No goal gate — operator's feedback IS the gate signal. Orchestrator re-settles
`AWAIT_GOALS_REVIEW` after push.

## Over-cap

```
4+ goals proposed. Normal PR: 1 main + ≤2 secondary.

  G1: <name>   G2: <name>   G3: <name>   G4: <name> ← over

Options:
  [a] Drop to fit the cap.
  [b] Promote one as main; absorb rest as secondaries (max 3).
  [c] Split into focused PRs — file not written; this stays draft.

Which?
```

Don't write until cap respected. No `--force`.

## Output shape

`$FORGE_ART/branches/<slug>/goals.md`:

```markdown
# Goals — <PR title or feature name>

> 🔨 **Forge artifact** — the PR's goal contract, tracked per
> `[artifacts].track` (default: tracked, for inline review). Not runtime code;
> don't import it.

- Source: <Jira key | PR# | doc path | "conversation">
- Branch: <branch>
- Captured: <ISO date>

## G1 — <short name> (main)

When this PR ships, the system will support <one-sentence capability>.

## G2 — <short name> (secondary)

After this PR, <one-sentence end-state>.

## Out of scope

- <thing the source mentions that this PR will not deliver>
```

The `## Gn — <name>` header shape is **load-bearing**: `/forge-scenarios` and
`/forge-proof` grep `^## G\d+`. The `(main)` / `(secondary)` tag is
informational — both downstream skills ignore it. Omit absent goal blocks
entirely.

## Non-goals

- Not a PRD. The goal IS the acceptance bar.
- Not a task plan. No file lists / test plans.
- Never reads code. Source + operator only.

## Next step

- `/forge-scenarios` — typical next phase (behavioral goals)
- `/forge-validations` — proofs for removal / structural goals
- `/forge-status` — chain state + drift

## Usage

```
/forge-goals                              # current branch, dialogue-led
/forge-goals https://jira/FOO-123         # explicit Jira; still asks
/forge-goals --slug auth-refactor         # override slug
/forge-goals docs/feature-x.md            # markdown reference
```
