---
name: restack-all
description:
  Restack an entire PR stack bottom-up — each PR onto its updated base.
argument-hint: "[any branch/PR in the stack — defaults to current]"
allowed-tools:
  - Bash
  - Skill
---

# /restack-all

`/restack` across a whole stack, bottom-up.

## Build the chain

Default: infer from GitHub. List open PRs and link each `headRefName` to its
`baseRefName` to form the chain containing the target branch:

```bash
gh pr list --state open --json number,headRefName,baseRefName
```

If `gh` fails, fall back to raw git analysis (tracked upstreams / merge-bases).

## Restack

Order the chain bottom-up (closest to trunk first). For each PR in order, run
`/restack` on it. Each restack picks up the parent's just-updated head, so
changes propagate up the stack.

Stop on the first conflict and surface it — do not continue past a broken layer.
