---
name: reviewable-publish
argument-hint: ""
triggers:
  - "publish reviewable"
  - "reviewable publish"
  - "send reviewable replies"
allowed-tools:
  - Bash
  - Read
---

# /reviewable-publish — Batch-publish all draft replies

Click-and-holds the top-right Publish button in Reviewable. This commits every
draft reply typed in the current session to Reviewable's Firebase backend and
mirrors them to the GitHub PR as a synthesized review (`addPullRequestReview`
GraphQL mutation), **notifying every requested reviewer to re-review**. Treat it
as the final step of a review-response cycle.

## Preflight — Binary + auth

`command -v agent-browser`; if missing or session not authenticated, run
`/reviewable-login` first.

## Preflight — CONSULT operator before publishing

Publish is observable to reviewers and triggers re-review notifications. **Do
not run unattended.** Before invoking, confirm with the operator:

1. **All replies drafted.** No remaining unresolved discussions need a response.
2. **Code pushed.** The branch tip the reviewer will see contains every change
   the replies refer to.
3. **Verification done.** Tests / typechecks pass on the pushed tip.

If any of the above is unclear, stop and ask.

## Locate Button

The top-right publish button is matched by:

```
.ui.button.flex.publish.main:not(.auxiliary)
```

Do **not** select on `.green` — that class only attaches in the "ready to
publish" state. The button's state machine cycles through several mutually
exclusive class sets, and a `.green`-only selector returns `null` for half of
them, silently no-opping the publish gesture and TypeErroring on the next
`.className` read.

### Button state machine (observed)

| State            | Classes (in addition to `publish main`) | Meaning                                   |
| ---------------- | --------------------------------------- | ----------------------------------------- |
| Ready to publish | `green`                                 | Drafts present, click-and-hold to publish |
| Waiting for push | `pending`                               | Drafts present but upstream not yet ready |
| No drafts (idle) | `disabled` (no `.green`)                | Nothing to publish                        |
| Post-publish     | `pending` then drops to no-drafts state | Mutation in flight                        |

Probe the current state before holding:

```
agent-browser --session-name reviewable eval \
  "JSON.stringify((() => {
    const btn = document.querySelector('.ui.button.flex.publish.main:not(.auxiliary)');
    if (!btn) return {present: false};
    const r = btn.getBoundingClientRect();
    return {
      present: true,
      cls: btn.className,
      disabled: btn.className.includes('disabled'),
      pending: btn.className.includes('pending'),
      green: btn.className.includes('green'),
      txt: btn.innerText,
      cx: Math.round(r.left + r.width/2),
      cy: Math.round(r.top + r.height/2)
    };
  })())"
```

Hold only when `green: true`. Stop if `disabled: true` — there is nothing to
publish; check with the operator whether `/reviewable-reply` ran successfully.
Stop if `pending: true` — drafts are queued but Reviewable is waiting for the
push or a prior publish to settle; surface the state to the operator before
retrying.

Quick probe of all matching buttons (multi-button pages, debugging the state
machine):

```
agent-browser --session-name reviewable eval \
  "JSON.stringify(Array.from(document.querySelectorAll('.publish.main')).map(b => ({cls: b.className, txt: b.innerText})))"
```

## Click-and-Hold

Reviewable requires a press-and-hold gesture on the publish button as deliberate
friction against accidental publishing
(`Click and hold to arm, release to activate`). Use the mouse primitives:

```
agent-browser --session-name reviewable mouse move <cx> <cy>
agent-browser --session-name reviewable mouse down
sleep 2
agent-browser --session-name reviewable mouse up
```

Hold for 2 seconds.

## Verify Published

Confirm the publish landed. Use the broader selector so the probe survives the
post-publish class change (`.green` drops off):

```
agent-browser --session-name reviewable eval \
  "JSON.stringify((() => {
    const btn = document.querySelector('.ui.button.flex.publish.main:not(.auxiliary)');
    return {
      drafts: document.body.innerText.match(/(\d+)\s+draft/i)?.[1] ?? '0',
      btnPresent: !!btn,
      btnCls: btn?.className ?? null,
      btnDisabled: btn?.className.includes('disabled') ?? null,
      btnGreen: btn?.className.includes('green') ?? null
    };
  })())"
```

Success = `drafts: "0"` AND `btnDisabled: true` AND `btnGreen: false`. If the
counter is unchanged AND the button is still `green`, the hold did not fire —
increase the sleep, retry, or have the operator publish manually in the headed
window. If the button is `pending` post-hold, the mutation is in flight; wait
and re-probe before declaring failure.

## Out of Scope

- File-review status (marking files reviewed) — separate gesture, future work.
- LGTM / Acknowledge / Resolve dispositions on individual discussions — separate
  UI, future work.

## Usage

```
/reviewable-publish
```

No arguments — acts on the currently loaded Reviewable session.
