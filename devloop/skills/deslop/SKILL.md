---
name: deslop
description:
  Scan a PR diff and strip AI slop — verbose obvious comments and over-complex
  local code.
argument-hint: "[pr number, url, or branch — defaults to current branch]"
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

## Fix

1. **Comments** — delete comments that restate the code, narrate the obvious, or
   were clearly auto-generated. Keep only ones that earn their place
   (non-obvious why, gotcha, invariant). Terse.
2. **Over-complex local code** — collapse needless indirection, dead
   abstraction, and verbose constructs that have a simpler equivalent. Run the
   built-in `/simplify` skill on the changed files for this pass.

Behavior must not change. Show the diff. Commit; don't push unless asked.
