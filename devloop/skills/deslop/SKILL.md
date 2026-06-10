---
name: deslop
description:
  Scan a PR diff and strip AI slop — verbose obvious comments and over-complex
  local code.
argument-hint:
  "[pr number, url, or branch — defaults to current branch] [--protect <globs>]"
allowed-tools:
  - Bash
  - Read
  - Edit
  - Skill
---

# /deslop

Remove AI slop from a PR's changed code.

## Scope

Only the PR's diff. Resolve base/head from GitHub (`gh pr view`), fall back to
`git diff <base>...HEAD`. Touch only changed hunks — don't reformat the repo.

Honor `--protect <comma-separated globs>` (same convention as `/ci-green`):
never edit a changed file matching one — skip it silently. Callers pass paths
whose exact bytes are load-bearing (e.g. a forge chain's linked test bodies +
contract artifacts), so a slop pass must leave them untouched.

## Fix

1. **Comments** — delete comments that restate the code, narrate the obvious, or
   were clearly auto-generated. Keep only the rare ones that earn their place
   (non-obvious why, gotcha, invariant). Hard-cap every survivor at one line —
   collapse anything longer to one line or drop it; two lines only in the rare
   case one can't carry the rationale, and only with the operator's sign-off.
   Strip drift-prone PR-artifacts from any comment kept: forge goal/scenario/
   validation IDs, PR/branch/commit refs, review-thread numbers — keep the
   rationale, drop the artifact that carried it.
2. **Over-complex local code** — collapse needless indirection, dead
   abstraction, and verbose constructs that have a simpler equivalent. Run the
   built-in `/simplify` skill on the changed files for this pass.

Behavior must not change. Show the diff. Commit; don't push unless asked.
