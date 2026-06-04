# forge

A repo-agnostic **PR forge chain** for
[Claude Code](https://claude.com/claude-code).

forge drives a pull request from a one-line source brief all the way to
**READY** — capturing goals, drafting behavior scenarios, writing a test per
scenario, designing the implementation, driving tests + CI green, and running a
lens-designed code review — with attestation at every step so nothing is claimed
that isn't backed by a goal, a scenario, a test, and a passing run.

It's built to run **unattended**: it recovers from external blockers on its own
(waits out a red base PR or an infra incident, then restacks and resumes), keeps
CI green **continuously until merge** rather than once, and on READY hands off
to peer review — arming a watch for incoming feedback and proposing the most
relevant reviewer — while leaving the move from draft to **ready-for-review** to
you.

forge has **no hard-coded knowledge of any repo's tooling** — you teach it how
to build/test/lint _your_ repo once, into a `$FORGE_HOME` map (default
`~/.claude/forge/<repo-key>/`, shared across worktrees); everything else is
generic. Adopt it into any project.

**Dependency:** forge requires the **`@orrgal1/devloop`** plugin — it calls
`/restack` to sync a branch onto its base (every CI iteration, and when resuming
after an external block). Install both (below). Aside from devloop + the `gh`
CLI, forge has no other plugin dependencies.

## The chain

```
/forge-start   source brief → draft PR
/forge-goals   the PR's intended end-state, as a goal list
/forge-scenarios  when:/then: scenarios covering each goal (observable behavior)
/forge-design  map each scenario to the components/symbols that satisfy it
/forge-tests   one component-tier test per scenario (the only step that writes test code)
/forge-impl-green  drive the linked tests to green
/forge-audit   attest the whole chain: goals ⇐ source · scenarios ⇒ goals · tests ⇒ scenarios · bodies ⇒ when/then · runs green
/forge-ci-green   drive PR CI to green — restacks each iteration; after the first green stays armed --until-merge
/forge-review     lens-designed, chain-aware PR review
/forge-review-green  drive the review to 0 findings (every severity)
   ── on READY ──
/forge-review-watch    stand watch for incoming peer feedback → /forge-address-review (hands-free)
/forge-find-reviewer   rank the most relevant peer reviewer; gated ready+request (your call, even in yolo)
/forge-address-review  work externally-submitted reviewer feedback to resolution
```

`/forge` runs the whole arc end-to-end. **Modes:** `auto` (pause at goals +
design + scenarios), `manual` (pause every phase), `yolo` (no contract pauses —
drive to READY, stop only at genuine blockers; `/forge-yolo` is the thin
wrapper). Resume with `/forge approve` and `/forge iterate "<feedback>"`.

### Runs unattended

- **Continuous CI until merge** — after CI first goes green, forge keeps a
  background `/forge-ci-green --until-merge` armed; it re-arms on every new HEAD
  (review fixes, restacks, base syncs) and drives CI back to green until the PR
  merges. No one-shot "final CI".
- **External-block recovery** — when a halt is something an external actor owns
  (a red/behind base PR, an infra incident), `/forge-find-blocker` identifies
  the peripheral blocker and `/forge-wait-for` watches that one condition (base
  PR CI, a Slack thread, any predicate), then restacks and resumes the chain.
  Genuine halts still stop.
- **Peer-review handoff** — on READY, forge arms the review watch and proposes a
  reviewer; **the PR is already open as a draft, so moving it to
  ready-for-review and requesting the reviewer is a gated author gesture** that
  needs your approval, even in `yolo`.

## Install

From the `orrgal1` marketplace (forge + its `devloop` dependency):

```
/plugin marketplace add orrgal1/claude-plugins
/plugin install forge@orrgal1
/plugin install devloop@orrgal1
```

Or point Claude Code at a local checkout:

```
git clone git@github.com:orrgal1/claude-plugins.git
claude --plugin-dir claude-plugins/forge --plugin-dir claude-plugins/devloop
```

## Quickstart

```
/forge-setup                         # one-time: map this repo's build/test/lint/...
/forge-start https://tracker/TICKET  # open a draft PR from a source
/forge                               # drive the chain to READY
```

## The `$FORGE_HOME` tooling map

forge runs **no** repo-specific command directly. `/forge-setup` builds a
`$FORGE_HOME` directory — default `~/.claude/forge/<repo-key>/`, a user-layer
path keyed to the repo so every worktree shares it — mapping forge's logical
capabilities to _your_ repo's tooling:

```
~/.claude/forge/<repo-key>/
  forge.toml          # capability → command (+ [meta], every other section)
  commands/           # one per capability — a script OR a `<cap>.md` instructions doc
    test
    build
    lint
    typecheck
    codegen
  review/             # optional: extra review mechanisms, stacked on the GitHub baseline
  review-channels/    # optional: /forge-review channel overrides
  tools/              # optional: /forge-tool packaged ad-hoc flows
```

Each capability is wired as **either** a runnable command/script (deterministic)
**or** prose instructions the agent follows (for conditional, multi-step flows a
fixed command can't capture). A capability that isn't mapped surfaces a
`NEEDS_SETUP` gap — forge never guesses a command. (`$FORGE_HOME` overrides the
default path; an in-repo `.forge/` is honored only as a one-release legacy
fallback.)

Review automation is **additive**: GitHub (via `gh`) is the always-on baseline;
drop one file per extra mechanism in `$FORGE_HOME/review/` to integrate other
review platforms alongside it.

## Review

`/forge-review` runs a parallel, lens-designed review: always-on chain-semantic
lenses (goal-delivery, scenario-realism, test-match) + code-quality lenses, plus
1–3 lenses designed against the diff's risk surface, fanned out to a bundled
`forge-lens-reviewer` agent. The lens pool (`lenses/`) and reviewer personas
(`personas/`) ship with the plugin and are extensible per-repo via
`$FORGE_HOME/lenses/` and `$FORGE_HOME/personas/`.

## Skills

| Skill                                                                                  | Role                                                                              |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `/forge-setup`                                                                         | Map host-repo tooling into `$FORGE_HOME`                                          |
| `/forge-start`                                                                         | Bootstrap a chain: source brief → draft PR                                        |
| `/forge`                                                                               | Orchestrate the whole chain to READY                                              |
| `/forge-goals` · `/forge-scenarios` · `/forge-design` · `/forge-tests`                 | Chain atoms                                                                       |
| `/forge-audit` + `/forge-verify-*`                                                     | Full + per-layer attestation                                                      |
| `/forge-impl-green` · `/forge-ci-green` · `/forge-audit-green` · `/forge-review-green` | Fix-loops to green (ci-green restacks each iteration; `--until-merge` continuous) |
| `/forge-review`                                                                        | Lens-designed, chain-aware PR review                                              |
| `/forge-review-watch` · `/forge-address-review`                                        | Watch for + drive submitted reviewer feedback to resolution                       |
| `/forge-find-reviewer`                                                                 | Rank the best peer reviewer; gated ready+request                                  |
| `/forge-find-blocker` · `/forge-wait-for`                                              | Identify an external blocker; wait it out, then restack + resume                  |
| `/forge-status` · `/forge-triage` · `/forge-stuck-check`                               | Status, triage, loop-health                                                       |

## State & artifacts

Two locations, by purpose:

- **Per-PR chain artifacts** live in-repo under
  `.pr-artifacts/<branch-slug>/forge/` (goals, design, links, run, decisions,
  review cycles; forge self-bootstraps a `.pr-artifacts/.gitignore`). Loop
  scratchpads and the continuous-CI monitor's status live under
  `.pr-artifacts/<slug>/forge/loop/`.
- **The tooling map + repo-scoped state** live at `$FORGE_HOME`
  (`~/.claude/forge/<repo-key>/`) — a user-layer path, never committed, shared
  by every worktree of the repo.

## License

[MIT](./LICENSE).
