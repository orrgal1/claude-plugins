# @orrgal1/forge

A repo-agnostic **PR forge chain** for
[Claude Code](https://claude.com/claude-code).

forge drives a pull request from a one-line source brief all the way to
**READY** — capturing goals, drafting behavior scenarios, designing the
implementation, writing a test per scenario, driving tests + CI green, and
running a lens-designed code review. What sets it apart is the **proof chain**:
nothing reaches READY that isn't backed by a goal, a scenario, a test, and a
passing run — and forge mechanically attests every link.

**Dependency:** forge has **no hard plugin dependency** — the `gh` CLI is the
only external requirement. Forge needs to restack a branch onto its base (every
CI iteration, and when resuming after an external block); the **`restack`
capability** is configured via `/forge-setup` and can point to an installed
skill (e.g. **`@orrgal1/devloop`**'s `/restack` — recommended when present), a
command/instructions, or fall back to forge's **built-in plain-git restack**
(fetch the base, merge it into the branch). Install devloop for the richer
stacked-PR restack, or run forge standalone on the built-in fallback.

## The proof chain — forge's core idea

Most "AI wrote a PR" workflows let the model assert that the work is done. forge
refuses to take its own word for it. Every claim is reduced to an artifact, and
every artifact is checked against the one before it. The result is an
**attestation chain** that runs source → goals → proofs → tests → runs, where a
break anywhere fails the proof.

The unit of truth is a **goal**, and a goal is satisfied only by a **proof**.
There are exactly two kinds of proof:

- **Scenario** — a `when:`/`then:` behavior, attached to a real component-tier
  test, whose body matches the scenario and which **runs green**. This is how
  behavioral goals are proven.
- **Validation** — a checkable predicate bound to a shell command (or, where no
  command can express it, an adversarially-confirmed agent attestation) that
  **holds**. This is how removal / negative / structural goals are proven — the
  ones with no runtime behavior to observe.

A goal needs **≥1 proof**. Behavioral goals carry scenarios, structural goals
carry validations, and a goal can carry both. A goal with no reachable proof is
surfaced as uncovered — it cannot pass.

`/forge-proof` aggregates the whole chain into a single **PASS / FAIL** across
seven layers, each owned by a dedicated verify skill:

| Layer  | Question it answers                                                 | Skill                            |
| ------ | ------------------------------------------------------------------- | -------------------------------- |
| **L1** | Are the goals well-formed, and **loyal to the PR source**?          | `/forge-verify-goals`            |
| **L2** | Is every goal covered by **≥1 proof** (scenario or validation)?     | `/forge-verify-scenarios`        |
| **L3** | Is every scenario **attached to a real component-tier test**?       | `/forge-verify-tests`            |
| **L4** | Does each **test body match** its scenario's `when`/`then` + AAA?   | `/forge-verify-match`            |
| **L5** | Does the design **cover every scenario** (component ⇒ proves SG)?   | inline (when `design.md` exists) |
| **L6** | Do the **linked tests pass**?                                       | `/forge-verify-runs`             |
| **L7** | Do the **validations hold** (command runs / attestation confirmed)? | `/forge-verify-validations`      |

PASS = every layer PASS or cleanly SKIPPED. Layers skip honestly: L5 skips with
no design, L6 skips before impl (pre-impl attestation is allowed), L7 skips when
a PR has no validations. `/forge-proof` is a **reader, not a fixer** — it emits
the smallest blocking set of findings; `/forge-proof-green` is the loop that
clears them.

Because the chain is mechanical, "done" means _proven_, not _asserted_ — and
the attestation can be embedded straight into the PR description (`--embed`) so
reviewers see the proof, not a promise.

## The chain

```
/forge-start   source brief → scaffold worktree → draft PR → hand off
/forge-goals   the PR's intended end-state, as a goal list (loyal to source)
/forge-scenarios  when:/then: scenarios covering each goal (observable behavior)
/forge-validations  checkable predicates for removal/structural goals (no runtime observable)
/forge-design  map each scenario to the components/symbols that satisfy it
/forge-tests   one component-tier test per scenario (the only step that writes test code)
/forge-impl-green  drive the linked tests to green
/forge-proof   attest the whole chain (the 7 layers above)
/forge-ci-green   drive PR CI to green — restacks each iteration; after first green stays armed --until-merge
/forge-review     lens-designed, chain-aware PR review
/forge-review-green  drive the review to 0 findings (every severity)
   ── on READY ──
/forge-review-watch    stand watch for incoming peer feedback → /forge-address-review (hands-free)
/forge-request-review   rank the most relevant peer reviewer; gated ready+request (your call, even in yolo)
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

From the `orrgal1` marketplace (forge runs standalone; `devloop` is optional —
it provides the recommended `/restack`, see **Dependency** above):

```
/plugin marketplace add orrgal1/claude-plugins
/plugin install forge@orrgal1
/plugin install devloop@orrgal1   # optional: richer stacked-PR /restack
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

forge has **no hard-coded knowledge of any repo's tooling** — you teach it how
to build/test/lint _your_ repo once. forge runs **no** repo-specific command
directly; `/forge-setup` builds a `$FORGE_HOME` directory — default
`~/.claude/forge/<repo-key>/`, a user-layer path keyed to the repo so every
worktree shares it — mapping forge's logical capabilities to your repo's
tooling:

```
~/.claude/forge/<repo-key>/
  forge.toml          # capability → command (+ [meta], every other section)
  commands/           # one per capability — a script OR a `<cap>.md` instructions doc
    test
    build
    lint
    typecheck
    codegen
  review-channels/    # optional: /forge-review channel overrides
  lenses/             # optional: extra review lenses (stacked on the bundled pool)
  personas/           # optional: extra reviewer personas
  maps/               # /forge-map JSON domain snapshots
  tools/              # optional: /forge-tool packaged ad-hoc flows
```

Each capability is wired as **either** a runnable command/script (deterministic)
**or** prose instructions the agent follows (for conditional, multi-step flows a
fixed command can't capture). A capability that isn't mapped surfaces a
`NEEDS_SETUP` gap — forge never guesses a command. (`$FORGE_HOME` overrides the
default path; an in-repo `.forge/` is honored only as a one-release legacy
fallback.)

## Review

`/forge-review` fans out review channels in parallel to one ranked verdict:

- **Lens fan-out** — always-on chain-semantic lenses (goal-delivery,
  scenario-realism, test-match) + code-quality lenses, plus 1–3 lenses designed
  against the diff's risk surface, each dispatched to the bundled
  `forge-lens-reviewer` agent.
- **Built-in `/code-review`** and **`/security-review`** — always on.

The lens pool (`lenses/`) and reviewer personas (`personas/`) ship with the
plugin and are extensible per-repo via `$FORGE_HOME/lenses/` and
`$FORGE_HOME/personas/`. Extra channels are added per-repo via
`$FORGE_HOME/review-channels/`; external CI/review tools are drafted, never
auto-posted.

## Skills

| Skill                                                                                         | Role                                                                              |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `/forge-setup`                                                                                | Map host-repo tooling into `$FORGE_HOME`                                          |
| `/forge-start`                                                                                | Bootstrap a chain: source brief → scaffold worktree → draft PR → hand off         |
| `/forge`                                                                                      | Orchestrate the whole chain to READY                                              |
| `/forge-goals` · `/forge-scenarios` · `/forge-validations` · `/forge-design` · `/forge-tests` | Chain atoms                                                                       |
| `/forge-proof` + `/forge-verify-*`                                                            | Full + per-layer attestation (the proof chain)                                    |
| `/forge-impl-green` · `/forge-ci-green` · `/forge-proof-green` · `/forge-review-green`        | Fix-loops to green (ci-green restacks each iteration; `--until-merge` continuous) |
| `/forge-review`                                                                               | Lens-designed, chain-aware PR review                                              |
| `/forge-review-watch` · `/forge-address-review`                                               | Watch for + drive submitted reviewer feedback to resolution                       |
| `/forge-request-review`                                                                       | Rank the best peer reviewer; gated ready+request                                  |
| `/forge-find-blocker` · `/forge-wait-for`                                                     | Identify an external blocker; wait it out, then restack + resume                  |
| `/forge-map` (+ `-db` · `-api` · `-events` · `-config`)                                       | Build JSON domain snapshots under `$FORGE_HOME/maps/`                             |
| `/forge-tool`                                                                                 | Package an ad-hoc flow as a reusable tool                                         |
| `/forge-status` · `/forge-triage` · `/forge-stuck-check`                                      | Status, triage, loop-health                                                       |

## State & artifacts

Two locations, by purpose:

- **Per-PR chain artifacts** live in-repo under
  `.pr-artifacts/<branch-slug>/forge/` — `goals.md`, `links.json`, `run.json`,
  `validations.json`, `design.md`, decisions, review cycles (forge
  self-bootstraps a `.pr-artifacts/.gitignore`). Loop scratchpads and the
  continuous-CI monitor's status live under `.pr-artifacts/<slug>/forge/loop/`.
- **The tooling map + repo-scoped state** live at `$FORGE_HOME`
  (`~/.claude/forge/<repo-key>/`) — a user-layer path, never committed, shared
  by every worktree of the repo.

## License

[MIT](../LICENSE).
