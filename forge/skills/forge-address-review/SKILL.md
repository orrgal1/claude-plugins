---
name: forge-address-review
description:
  "Process reviewer feedback on a forge PR — thin chain wrapper over the
  address_review capability."
argument-hint:
  "[PR# or branch] [--slug <name>] [--auto] [--source github|self|all]"
triggers:
  - "forge address review"
  - "address forge review"
  - "address reviewer feedback on forge PR"
  - "reviewer comments came in on the forge chain"
  - "work the review on the forge PR"
practices:
  - code-review
  - commit-per-iteration
allowed-tools:
  - Skill
  - Bash
  - Read
  - Write
  - Grep
  - Glob
user-invocable: true
---

# /forge-address-review — chain wrapper around the `address_review` capability

A **thin** chain layer over the chain-blind `address_review` capability (default
`/address-review`, `@orrgal1/devloop`). The capability owns intake, triage, the
fix walk, replies/resolve, and re-request. This wrapper adds only what's
**forge-chain**: the chain prereq, the contract-protect set, chain-located cycle
state, the self-review marker, and CHAIN-IMPACTING escalation routing.

## Resolve

1. Resolve slug + worktree + PR per `/forge` rules. Load `goals.md` +
   `links.json`. Missing → exit (no chain to guard).
2. Resolve the `address_review` capability (`~/.claude/forge/capabilities.toml`;
   unconfigured → `NEEDS_SETUP cap=address_review`).

## Invoke the capability

```
/address-review [PR# or branch] [--auto] [--source <github|self|all>] \
  --protect '$FORGE_ART/branches/<slug>/{goals.md,design.md,links.json}',<linked test paths> \
  --self-marker forge:self-review \
  --state $FORGE_ART/branches/<slug>/review/
```

- `--protect` carries the chain-contract surfaces (goals/design/links + every
  test in `links.json`). A capability `PROTECTED`-escalated item ⇒
  **CHAIN-IMPACTING**: route to the operator for a chain edit + `/forge`
  re-verify — never satisfied inline. Mirrors `/forge-review-green`'s guard.
- `--state` lands `external-<cycle>.md` + reply scratch where `/forge-status`
  and the watch expect them.
- After the capability returns, validate linked tests via the `test` capability
  and refresh `run.json` (automatic, never offered — per `/forge` § "Bias to
  progress").

## On return (chain verdict)

- All blocking GitHub feedback resolved + proof still PASS → suggest
  `/forge-proof --embed`, `/forge-review --embed`, `/forge-status`. Post a
  `<!-- forge:feedback-addressed -->` proof comment.
- CHAIN-IMPACTING (capability `PROTECTED` escalation) still open → route to
  `/forge` to edit the artifact + re-verify, then re-run this skill.

## Guardrails

- **Never modify `goals.md`, `links.json`, linked tests, or `design.md`** to
  satisfy a reviewer — escalate as CHAIN-IMPACTING (enforced via `--protect`).
- Capability guarantees (untrusted-input, narrow fixes, push-only-at-gate,
  external-tool draft-don't-post) hold — see the `address_review` capability.

## Usage

```
/forge-address-review                       # current branch's forge PR, interactive
/forge-address-review 21228                 # PR by number
/forge-address-review --auto                # batch (what /forge-review-watch dispatches)
/forge-address-review --source github       # GitHub threads only
```

## Next step

- Converged + proof PASS → `/forge-proof --embed` → `/forge-review --embed`.
- CHAIN-IMPACTING open → `/forge` (edit artifact + re-verify), then re-run.
- `/forge-review-watch` — keep armed to auto-dispatch this on every new review.
- `/forge-status` — chain state + drift.
