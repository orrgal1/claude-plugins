# @orrgal1/ralph

A general **bounded-autonomy iteration loop** for
[Claude Code](https://claude.com/claude-code). Give `/ralph` a target plus a way
to verify it, and it grinds: pick the next step, do it, verify, write down what
it learned, commit, repeat — stopping at success or budget exhaustion.

Inspired by Geoffrey Huntley's "Ralph Wiggum as a software engineer," adapted
for a single Claude session. Repo-agnostic and self-contained — designed to be
wrapped by more specific fix-loops, but depends on no other plugin.

## When to use it

- The target is **bounded and verifiable** — a command exiting 0 means done.
- The work is **mechanical or narrow**: codemod, test repair, lint sweep, dep
  bump, migration, narrow-scope feature with a spec.
- You're willing to let the agent grind unattended **inside the budget**.

Not for "looks good" targets — only mechanical checks survive a loop.

## How it works

- **Commit per iteration** — each verified step is committed, giving you a clean
  undo history and a record of what changed when.
- **Bounded** — caps the number of iterations (`max=<N>`); stops at the cap even
  if not yet green, so it never runs away.
- **Verify-driven** — the loop is only as good as the verify command; it reruns
  it every step and stops the moment it passes.

## Usage

```
/ralph "make `npm test` pass" max=20
/ralph "fix all `eslint .` errors"
/ralph "migrate callers off deprecated fooBar() until `rg fooBar` is empty"
```

Requires `git` and whatever your verify command needs.

## License

[MIT](../LICENSE).
