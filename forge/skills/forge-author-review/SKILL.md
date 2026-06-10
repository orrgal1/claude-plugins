---
name: forge-author-review
description:
  "Aid the author's self-review at the gate — thin chain wrapper over the
  author_review capability (walkthrough + manual verification)."
argument-hint:
  "[PR# or branch] [--slug <name>] [--walkthrough | --verify | --all] [--embed]
  [--json]"
triggers:
  - "forge author review"
  - "walk me through my forge pr"
  - "self-review the forge pr"
  - "forge walkthrough"
  - "manually verify the forge pr"
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Skill
user-invocable: true
---

# /forge-author-review — the author's self-review aid

A **thin** chain layer over the chain-blind `author_review` capability (default
`/author-review`, `@orrgal1/devloop`). The capability owns the self-review
mechanics — the diff walkthrough, the manual-verification drive, note intake,
the idempotent body embeds. This wrapper adds only what's **forge-chain**:
framing the walkthrough against the approved chain artifacts, resolving the
repo's manual-verification how-to from the tooling map, the chain's self-review
marker, and the body-layout placement.

Dispatched by `/forge` when the chain reaches the author-review gate (§ 9.6),
before settling `AWAIT_AUTHOR_REVIEW`. Also runs standalone any time at or past
`READY` — the aid is useful whenever the author wants a tour or a manual pass.

Most flags (`--walkthrough`/`--verify`/`--all`, `--embed`, `--json`, a
PR#/branch) pass straight through.

## Resolve

1. Resolve the chain — `~/.claude/forge/bin/forge-resolve.sh --json`
   (worktree-rooted `forge_art`/`slug`; never look under `~/.claude/forge/` for
   the chain). Setup gate: `ready != true` → `SETUP_REQUIRED`. Resolve the PR
   per `/forge` rules; no PR → no-op, hint "no PR yet — `/forge-start` opens
   one."
2. Resolve the `author_review` capability (`~/.claude/forge/capabilities.toml`):
   override → use it; else fall back to the default `/author-review`
   (`@orrgal1/devloop`). Default provider absent & no override → refuse
   `PROVIDER_MISSING cap=author_review provider=@orrgal1/devloop`. No built-in
   substitute.

## Chain context passed to the capability

- **Walkthrough framing** — pass `goals.md` (and `design.md` when present) via
  `--context`. The tour narrates the diff against the **approved goals**: a unit
  serving no goal, or a goal no unit serves, surfaces as a scrutiny callout —
  exactly the divergence the author should catch before a peer does. No goals
  yet (pre-contract ad-hoc run) → omit; the capability narrates from commits/PR
  body alone.
- **Manual-verification how-to** — resolve the repo's `manual_verify` capability
  from `$FORGE_HOME` (standard four-form resolution: `commands/manual_verify` →
  `[commands]` → `commands/manual_verify.md` → `[instructions]`;
  instructions-form is typical — e.g. "bring up the devenv, run flow X, expect
  Y"). Wired → pass as `--howto`. Unwired → let the capability degrade to its
  diff-derived plan; surface the gap once: "`manual_verify` unwired —
  `/forge-setup` to capture this repo's how-to." Never guess infrastructure.
- **Self-review notes** — pass `--self-marker forge:self-review`, so author
  notes land in the body section `/forge-address-review --source self` ingests
  when the gate is approved.

## Invoke the capability

```
/author-review [PR# or branch] [--walkthrough | --verify | --all] \
  --context <goals.md>[ --context <design.md>] \
  [--howto <resolved manual_verify>] \
  --self-marker forge:self-review \
  [--embed | per-section offer] [--json]
```

## Body layout

The capability's `walkthrough` and `manual-verification` blocks join the PR
body's collapsible stack as **siblings** under the body-layout contract
(`/forge-brief`): brief on top, then proof, review, walkthrough,
manual-verification — each writer touching only its own marker-bounded region.
Embedding stays an **offer** (per section, or pre-approved via `--embed`) —
publishing the tour to peers is the author's gesture.

## Gate coupling (§ 9.6)

The wrapper **prepares and assists**; the gate **decides**. `/forge` dispatches
it on reaching the author-review gate, then settles `AWAIT_AUTHOR_REVIEW` — the
approve/iterate resolution (ingest `forge:self-review` notes, record
`{author_review: <sha>}`) stays in `/forge`. A `fail` recorded during manual
verification is a finding for the gate's iterate path, not something this
wrapper fixes.

## Usage

```
/forge-author-review                    # both offerings on the chain's PR
/forge-author-review --walkthrough      # goals-framed tour only
/forge-author-review --verify           # manual pass via the repo's manual_verify how-to
/forge-author-review --all --embed      # both, embed both body sections
/forge-author-review --json             # machine receipt
```
