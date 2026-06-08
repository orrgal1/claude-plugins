---
name: reviewable-login
description:
  "One-time interactive Reviewable.io auth — stand up an authenticated
  agent-browser session."
argument-hint: ""
triggers:
  - "reviewable login"
  - "login to reviewable"
  - "reviewable auth"
  - "re-auth reviewable"
allowed-tools:
  - Bash
  - Read
---

# /reviewable-login — One-time interactive Reviewable.io auth

Stand up an authenticated `--session-name reviewable` profile in
`agent-browser`. Session persists in `~/.agent-browser/sessions/reviewable/`
across restarts, so this typically runs **once on first use** and again only
when the session expires (GH OAuth drop, Chrome-for-Testing version bump, or
manual profile wipe).

Reuse this skill any time `/reviewable-read` reports a GitHub login wall where
Reviewable UI should be.

## Preflight — agent-browser binary

```
command -v agent-browser
```

If missing, surface the install command and ask the operator to approve running
it (≈170MB Chrome download on first run):

```
brew install agent-browser && agent-browser install
```

One-prompt confirm, then run — never silently.

## Open Reviewable Landing — Headed

```
agent-browser --session-name reviewable --headed open https://reviewable.io
```

The headed window pops; ask the operator to complete the GitHub OAuth flow
(login + YubiKey tap if required). Reviewable lands on its dashboard once auth
succeeds.

## Verify Auth Persisted

After the operator confirms login is done, probe the session for authenticated
state without re-popping the window:

```
agent-browser --session-name reviewable eval \
  "JSON.stringify({title: document.title, hasLogin: !!document.querySelector('a[href*=\"github.com/login\"]'), bodyHead: document.body.innerText.slice(0, 80)})"
```

Success indicators:

- `title` contains `Reviewable` (not `Sign in to GitHub`).
- `hasLogin` is `false` (no top-level login CTA).
- `bodyHead` shows dashboard text, not OAuth prompts.

If verification fails, re-pop the headed window and have the operator finish the
flow before proceeding.

## Notes

- The session cookie lives in agent-browser's profile dir; no token is passed to
  skills, eval contexts, or model context.
- `--headed` is required for the OAuth tap. Subsequent `/reviewable-*` skills
  run the same session **headless** by default.

## Usage

```
/reviewable-login
```

No arguments.
