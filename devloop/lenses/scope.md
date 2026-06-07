---
id: scope
name: Scope
tags: [scope, hygiene]
requires: diff
severity-floor: blocker
brief-artifacts: [pr-description]
introduced-by: deep-review
---

# Scope Lens

Every change in the PR must belong there. The PR description is the spec —
anything not required by it is a finding. Scope creep, unrelated changes,
drive-by refactors.

## Process

1. **Read the PR description and title.** This is your contract — the diff must
   deliver this and nothing else.

2. **Check every changed file against the goal:**
   - Necessary for the stated purpose?
   - If tangential, a clear reason it had to change (callers updated because a
     signature changed)?
   - Flag files that don't belong.

3. **Within each file, check every hunk:**
   - **Drive-by refactors** — renamed vars, reformatting, restructured logic not
     required by the goal. Even an improvement doesn't belong here.
   - **Feature creep** — extra params, validation, API fields, functionality
     beyond the description.
   - **Unnecessary abstractions** — helpers, interfaces, wrappers not needed for
     the stated goal.
   - **"While I'm here" fixes** — bug/style fixes or cleanups in adjacent code.

4. **Check commit history.** Multiple unrelated concerns in separate commits is
   still scope creep — separate PRs.

5. **Check test scope.** New tests not testing the PR's changes are scope creep.

## Output Format

```
ISSUE: [description of out-of-scope change]
FILE: path/to/file.go:42
TYPE: DRIVE_BY | FEATURE_CREEP | UNNECESSARY_ABSTRACTION | UNRELATED_FILE
DETAIL: [why this doesn't belong — reference the PR description]
```

Every scope finding is a BLOCKER. Unrelated changes must be reverted or moved to
a separate PR.
