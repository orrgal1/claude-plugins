---
name: forge-goals
description: "Capture the PR's intended end-state as a goal list, loyal to its source."
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

First link in the chain. **Most interactive skill** — goals are the spine,
getting them wrong cascades. Operator drives; sources are reference.

A **goal** = future end-state the PR commits to. Not tasks, not file lists —
what the system **will support** or **will be**. If it doesn't fit, it's
implementation detail.

## Goal shape

Pick one phrasing:

- **Capability** — "When this PR ships, the system will support `<X>`."
- **End-state** — "After this PR, `<Y>` will be the new state of `<subsystem>`."
- **Invariant** — "After this PR, `<Z>` will always hold for `<entity>`."
- **Removal** — "After this PR, `<deprecated thing>` will no longer be
  reachable."

Wrong: "Refactor X" (task), "Add tests" (means), "Fix the bug" (no specificity).

## Count — hard cap 3, floor 1

- **G1** = main (the one sentence reviewers should remember).
- **G2**, **G3** = secondary outcomes the PR also commits to.
- Right-size, don't pad slots. A 1-goal tight PR > 3-goal padded one.
- **>3 → halt + recommend splitting into focused PRs.** No `--force` escape
  hatch.

Out-of-scope items live under `## Out of scope` — don't count toward cap.

## Process

1. **Resolve slug + worktree.** Branch name sanitized (lowercase,
   alphanumerics + dashes, strip `feat/` / `fix/` / `chore/`). `--slug`
   overrides.
2. **Open dialogue first.** Before fetching anything:

   > How do you see this PR? Main thing it delivers? Anything else on the side?

   Operator's framing is the seed; sources corroborate. If operator points at
   Jira / PR body → fetch, then ask "Source says X — match your view, or source
   stale?"

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

5. **Write `.pr-artifacts/<slug>/forge/goals.md`** per Output shape below.
   Bootstrap the artifact dir + root forge gitignore:

   ```bash
   mkdir -p ".pr-artifacts/${slug}/forge"
   gi=".pr-artifacts/.gitignore"
   if [ ! -f "$gi" ]; then
     cat > "$gi" <<'EOF'
   # Forge: ignore everything under <slug>/forge/ except shared review surfaces.
   */forge/*
   !*/forge/goals.md
   !*/forge/design.md
   EOF
   fi
   ```

   On legacy hosts whose root `.gitignore` blanket-ignores `.pr-artifacts/`,
   force-add:

   ```bash
   gm=".pr-artifacts/${slug}/forge/goals.md"
   if git check-ignore -q "$gm"; then
     git add -f "$gi" "$gm"
     git commit -m "forge-goals: publish artifact (ignored path)"
   fi
   ```

6. **`--push`** (orchestrator entry): push when local commits ahead
   (`git rev-list --count @{u}..HEAD > 0`); else no-op. SSH-only. `--push`
   without upstream → `git push -u origin HEAD`.

7. **Recap:**

   ```
   ✓ goals.md written: .pr-artifacts/<slug>/forge/goals.md
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

`.pr-artifacts/<slug>/forge/goals.md`:

```markdown
# Goals — <PR title or feature name>

> ⚠️ **Scheduled for cleanup.** Forge artifact — checked in temporarily for
> inline review. Removal / re-gitignore timing TBD. Don't depend on it from
> runtime code.

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
`/forge-audit` grep `^## G\d+`. The `(main)` / `(secondary)` tag is
informational — both downstream skills ignore it. Omit absent goal blocks
entirely.

## Non-goals

- Not a PRD. The goal IS the acceptance bar.
- Not a task plan. No file lists / test plans.
- Never reads code. Source + operator only.

## Next step

- `/forge-scenarios` — typical next phase
- `/forge-status` — chain state + drift

## Usage

```
/forge-goals                              # current branch, dialogue-led
/forge-goals https://jira/FOO-123         # explicit Jira; still asks
/forge-goals --slug auth-refactor         # override slug
/forge-goals docs/feature-x.md            # markdown reference
```
