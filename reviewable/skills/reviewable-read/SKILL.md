---
name: reviewable-read
argument-hint: "[PR# or Reviewable URL]"
triggers:
  - "read reviewable"
  - "list reviewable comments"
  - "show reviewable discussions"
  - "reviewable review"
allowed-tools:
  - Bash
  - Read
---

# /reviewable-read — List unresolved Reviewable discussions

Open a Reviewable PR via `agent-browser`, extract the unresolved discussion
threads, and return them as a structured list the agent can act on (read
context, then draft replies via `/reviewable-reply`, then batch via
`/reviewable-publish`).

## Argument Resolution

- Bare integer → `https://reviewable.io/reviews/<owner>/<repo>/<N>`, where
  `<owner>/<repo>` is the current git repo's GitHub origin
  (`gh repo view --json nameWithOwner --jq .nameWithOwner`).
- Full `reviewable.io/reviews/...` URL → use as-is.
- Empty → derive from the current branch's PR via
  `gh pr view --json number,url --jq '.number'`.

## Preflight

1. **Binary present.** `command -v agent-browser`. If missing, offer to install
   (one-prompt confirm; ≈170MB Chrome-for-Testing download on first run):

   ```
   brew install agent-browser && agent-browser install
   ```

   Do not run silently — one-prompt confirm, then run.

2. **Session authenticated.** All ops use `--session-name reviewable`. First run
   (or after session expiry) requires a one-time interactive GitHub OAuth tap;
   delegate to `/reviewable-login` for that flow.

   Quick probe:

   ```
   agent-browser --session-name reviewable eval \
     "JSON.stringify({title: document.title, hasLogin: !!document.querySelector('a[href*=\"github.com/login\"]')})"
   ```

   If `title` is empty or contains `Sign in to GitHub`, or `hasLogin` is `true`
   after navigating to a Reviewable URL, stop and instruct the operator to run
   `/reviewable-login`, then re-run this skill.

## Navigate + Snapshot

```
agent-browser --session-name reviewable open <reviewable-url>
agent-browser --session-name reviewable snapshot > /tmp/reviewable-snap.txt
```

The snapshot can be large (several thousand lines on PRs with many revisions).

## Extract Discussions

Two surfaces matter:

1. **Discussion summary rows.** Look for `LayoutTableRow` entries inside the
   right-rail panel. Each row encodes `<count><preview-text>` — e.g.
   `"3 review thread comment"` or `"1 Test comment"`. Filter the unresolved
   bucket under `LayoutTableCell " Unresolved (N discussions)"`.

2. **Expanded thread bodies.** Click each discussion row's ref, re-snapshot, and
   capture the contiguous block containing:
   - reviewer login (`StaticText "<handle>"`)
   - per-comment paragraph text
   - the per-thread reply input — `textbox "Follow up…" [ref=eNNN]` — keep this
     ref for `/reviewable-reply`.

Snapshot refs are **per-snapshot**, not stable across navigations. Capture the
follow-up ref in the same snapshot the operator will act from.

## Output Shape

Return a JSON-shaped list (rendered as a code block in chat):

```json
[
  {
    "discussion_index": 1,
    "file": "<path>",
    "line": "<n>",
    "revision": "r<n>",
    "reviewer": "<handle>",
    "comments": [{ "author": "<handle>", "body": "<markdown text>" }],
    "follow_up_ref": "@eNNN"
  }
]
```

`follow_up_ref` is the input to `/reviewable-reply`. Discussions without a
follow-up textbox (e.g. operator-authored unanswered) still appear but mark
`follow_up_ref` as `null`.

## Out of Scope

- Disposition state (resolved / acknowledged / LGTM) — not exposed by GH
  mirroring, requires Firebase. Future work.
- Closed/resolved discussions — only `Unresolved` bucket is read.
- Posting comments / publishing drafts — see `/reviewable-reply` and
  `/reviewable-publish`.

## Usage

```
/reviewable-read 21531              # resolves owner/repo from git origin
/reviewable-read https://reviewable.io/reviews/<owner>/<repo>/21531
/reviewable-read                    # current branch's PR
```
