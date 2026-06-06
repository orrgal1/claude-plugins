# @orrgal1/reviewable

[Reviewable.io](https://reviewable.io) automation for
[Claude Code](https://claude.com/claude-code), driven through `agent-browser`.
It reads unresolved discussions, drafts replies, and batch-publishes them —
letting Claude work a Reviewable review cycle the way it works GitHub threads.

Repo-agnostic: resolves owner/repo from the git origin. No dependency on other
plugins.

## Skills

| Skill                 | Purpose                                                                                                                                                                                                              |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/reviewable-login`   | One-time interactive auth — stand up an authenticated `--session-name reviewable` profile in `agent-browser`. The session persists across restarts, so this runs once on first use (and again only when it expires). |
| `/reviewable-read`    | List the unresolved discussion threads on a Reviewable PR as a structured list to act on.                                                                                                                            |
| `/reviewable-reply`   | Type a reply into a specific discussion — **auto-saves as a draft** (not yet published).                                                                                                                             |
| `/reviewable-publish` | Click-and-hold the top-right publish button to **batch-publish all drafts** at once, notifying the reviewer to re-review.                                                                                            |

## Typical flow

```
/reviewable-login                 # once: authenticate the browser session
/reviewable-read 1234             # list unresolved threads (PR# or Reviewable URL)
/reviewable-reply …               # draft a reply per thread
/reviewable-publish               # publish all drafts in one batch
```

Requires `agent-browser` and `git`. Sessions live in
`~/.agent-browser/sessions/reviewable/`.

## License

[MIT](../LICENSE).
