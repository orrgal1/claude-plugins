---
name: restack
description:
  Restack a PR on its base — sync the base with upstream, then bring it into the
  PR branch.
argument-hint: "[pr number, url, or branch — defaults to current branch]"
allowed-tools:
  - Bash
---

# /restack

Bring a PR's base branch into the PR branch, after syncing the base with
upstream.

## Resolve the PR

Default: infer from GitHub.

```bash
gh pr view ${1:-} --json number,headRefName,baseRefName,state
```

If `gh` fails or no PR exists, fall back to raw git: base is the branch's
tracked upstream or the repo default branch
(`git symbolic-ref refs/remotes/origin/HEAD`); head is the current branch.

## Restack

1. `git fetch origin` — sync. Update local base to `origin/<base>`.
2. Bring base into head. **Use the operator's standing merge-vs-rebase
   preference** (persona / git discipline). No stated preference → merge.
   - merge: `git merge origin/<base>` on the head branch.
   - rebase: `git rebase origin/<base>` (only if prefs say so, or `--rebase` is
     passed).
3. Conflicts → stop, surface them.
4. Push once at the end: plain push for merge, `--force-with-lease` for rebase.
   Never force-push the base/default branch.
