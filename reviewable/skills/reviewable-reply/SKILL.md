---
name: reviewable-reply
argument-hint: "<follow_up_ref> <reply-text>"
triggers:
  - "reply to reviewable"
  - "reviewable reply"
  - "draft reviewable reply"
allowed-tools:
  - Bash
  - Read
---

# /reviewable-reply — Type a reply draft into a specific discussion

Fills the per-discussion Follow-up textbox identified by `<follow_up_ref>`
(captured by `/reviewable-read`). The text **auto-saves as a draft** inside the
active `--session-name reviewable` session — nothing is published. Use
`/reviewable-publish` once all replies are drafted and the code change is
pushed + verified.

## Preflight

1. **Binary + auth.** `command -v agent-browser`; if missing or session not
   authenticated, run `/reviewable-login` first.
2. **Session live.** The page must be loaded from a prior `/reviewable-read` on
   the target PR. If not, tell the operator to run `/reviewable-read <PR>`
   first. (Snapshot refs are per-snapshot; replying with a stale ref will fail
   or hit the wrong element.)
3. **Args present.** `<follow_up_ref>` must be `@eNNN` form. `<reply-text>` may
   be multi-line — quote appropriately for shell passing.

## Fill

```
agent-browser --session-name reviewable fill '<follow_up_ref>' '<reply-text>'
```

`fill` clears the textbox before typing, so re-running the skill against the
same ref replaces the draft rather than appending.

### Reply→Draft DOM swap gotcha

Reviewable's "Follow up…" textbox starts as a placeholder "Reply" textarea. The
first character typed promotes it from "Reply" to "Draft": Reviewable destroys
the placeholder element and renders a fresh textarea with a different snapshot
ref. The first `fill` writes into the now-detached node, then the page swaps in
the new textarea — empty. The draft counter still increments (Reviewable's
Firebase listener fires on the promotion, not on the text), so a counter-only
verify returns a false positive.

Mitigation: after the first `fill`, **re-snapshot to capture the new ref**, then
`fill` again into the fresh ref. The second fill lands on the persistent Draft
textarea.

## Verify Draft Saved

Counter-only checks false-positive on the Reply→Draft swap above. Assert
**textarea value length** alongside the draft counter. Re-snapshot first to pick
up the post-promotion ref, then:

```
agent-browser --session-name reviewable eval \
  "JSON.stringify((() => {
    const drafts = document.body.innerText.match(/(\d+)\s+draft/i)?.[1] ?? '0';
    const filled = Array.from(document.querySelectorAll('textarea'))
      .map(t => ({ph: t.placeholder, len: t.value.length}))
      .filter(t => t.len > 0);
    return {drafts, filled};
  })())"
```

Success requires **both** `drafts >= 1` AND at least one `filled` entry whose
`len` matches the expected reply length. If `drafts` incremented but `filled` is
empty → Reply→Draft swap ate the text; re-snapshot and re-fill into the new ref.
If `drafts` did not increment at all, the fill went to the wrong textbox — most
likely the Review Summary box at the page bottom (which also has a `Follow up…`
placeholder when prior summary text exists). Re-run `/reviewable-read` to get
fresh refs and verify the snapshot anchors the follow-up textbox under the right
discussion.

## Notes

- One reply per discussion per cycle — Reviewable's reply box accumulates a
  single draft per thread until publish.
- Multi-line replies: pass with `$'line1\nline2'` in bash, or use a HEREDOC
  piped into `agent-browser fill` via stdin (check `agent-browser fill --help`
  for stdin support).
- Markdown allowed; renders on publish via Reviewable's GitHub mirror.

## Usage

```
/reviewable-reply @e1971 "Done in r19 — moved the recover() to wrap each call."
/reviewable-reply @e2034 "Good catch, will fix."
```
