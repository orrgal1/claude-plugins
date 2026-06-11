# @orrgal1/forge

A repo-agnostic **PR forge chain** for
[Claude Code](https://claude.com/claude-code).

forge drives a pull request from a one-line source brief all the way to
**READY** — capturing goals, drafting behavior scenarios, designing the
implementation, writing a test per scenario, driving tests + CI green, and
running a lens-designed code review. What sets it apart is the **proof chain**:
nothing reaches READY that isn't backed by a goal, a scenario, a test, and a
passing run — and forge mechanically attests every link.

**Works best with:** the `gh` CLI is the one hard external requirement. For its
agent capabilities forge **works best with a single companion plugin**, which it
uses by default — **`@orrgal1/devloop`** backs every capability forge consumes:
the chain-blind PR ops (`/forge-review` fan-out, `request_review`,
`find_blocker`, `ci_green`, …), the `iteration_loop` behind every `*-green`
loop, and the optional diagnostic toolkit. It's the default backing, so the
chain needs it installed (or the capability repointed) to run — an un-overridden
capability whose default provider is missing halts that step
(`PROVIDER_MISSING`) until you install it. Every capability is **repointable**
to another plugin via `/forge-setup`, so the coupling is tight by default yet
never hardwired. The one capability that needs no companion at all is
**`restack`**: it has a **built-in plain-git fallback** (fetch the base, merge
it into the branch); `/forge-setup` can still point it at an installed skill
(e.g. `@orrgal1/devloop`'s `/restack`, richer for stacked PRs) or a
command/instructions.

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

Because the chain is mechanical, "done" means _proven_, not _asserted_ — and the
attestation can be embedded straight into the PR description (`--embed`) so
reviewers see the proof, not a promise.

The PR body stays disciplined: a tight, non-collapsible **brief** on top (owned
by `/forge-brief`, kept current as intent evolves — never left to stale), and
every embedded chain artifact below it as its own **idempotent collapsible
block** (`/forge-proof`, `/forge-review`, …). Each writer touches only its own
region, so the description never drifts into a wall of stale machine output.

## The chain

```
/forge-start   source brief → scaffold worktree → draft PR → hand off
/forge-ground  conditional: verify a bug claim against observed behavior before goals (not reproduced / expectation suspect → ticket pushback, not a PR)
/forge-goals   the PR's intended end-state, as a goal list (loyal to source; symptom-only bug sources halt until the expected behavior is stated)
/forge-scenarios  when:/then: scenarios covering each goal (observable behavior)
/forge-validations  checkable predicates for removal/structural goals (no runtime observable)
/forge-design  map each scenario to the components/symbols that satisfy it
/forge-tests   one component-tier test per scenario (the only step that writes test code)
/forge-impl-green  drive the linked tests to green
/forge-proof   attest the whole chain (the 7 layers above)
/forge-review     lens-designed, chain-aware PR review
/forge-review-green  drive the review to 0 findings (every severity)
/forge-ci-green   drive PR CI to green over the review-clean diff — restacks each iteration; after first green stays armed --until-merge
   ── on READY ──
/forge-review-watch    stand watch for incoming peer feedback → /forge-address-review (hands-free)
author-review gate     /forge-author-review aids your self-review (goals-framed walkthrough + manual verify); gated (your call, even in yolo) → ingests forge:self-review comments
request_review cap     rank the most relevant peer reviewer; gated ready+request (your call, even in yolo)
/forge-address-review  work externally-submitted reviewer feedback to resolution
```

`/forge` runs the whole arc end-to-end. **Modes:** `auto` (pause at goals +
design + scenarios), `manual` (pause every phase), `yolo` (no contract pauses —
drive to READY, stop only at genuine blockers; `/forge-yolo` is the thin
wrapper). At any pause, resume with a plain reply — "approved" advances,
"pushback: …" (or any feedback) iterates. `/forge approve` and
`/forge iterate "<feedback>"` are the explicit forms.

### Runs unattended

- **Continuous CI until merge** — after CI first goes green, forge keeps a
  background `/forge-ci-green --until-merge` armed; it re-arms on every new HEAD
  (peer-review fixes, restacks, base syncs) and drives CI back to green until
  the PR merges. No one-shot "final CI".
- **External-block recovery** — when a halt is something an external actor owns
  (a red/behind base PR, an infra incident), the `find_blocker` capability
  identifies the peripheral blocker and `/forge-wait-for` watches that one
  condition (base PR CI, a Slack thread, any predicate), then restacks and
  resumes the chain. Genuine halts still stop.
- **Self-healing on known failures** — repo-scoped **recovery playbooks**
  (`[playbooks.<name>]`) let forge recover a known capability failure itself
  instead of blocking to ask. A failure matching a playbook's signature triggers
  its recovery, then retries — e.g. an ECR pull failing on an expired SSO token
  runs `aws sso login` and re-runs. Forge also offers to capture a new playbook
  on the fly when a recurring failure is cleared manually. Recoveries run
  best-effort in every mode — an interactive one (browser auth) is attempted
  even in `yolo`/unattended; if no one completes it, it falls through to a
  genuine block then. See **The `$FORGE_HOME` tooling map** below.
- **Peer-review handoff** — on READY, forge arms the review watch and proposes a
  reviewer; **the PR is already open as a draft, so moving it to
  ready-for-review and requesting the reviewer is a gated author gesture** that
  needs your approval, even in `yolo`.

## Install

From the `orrgal1` marketplace. forge bundles only its own chain logic + chain
lenses; it **works best with two companion plugins** it uses by default for its
agent capabilities, so install them alongside (see **Works best with** and
**Review** above):

```
/plugin marketplace add orrgal1/claude-plugins
/plugin install forge@orrgal1
/plugin install devloop@orrgal1   # default provider for the PR ops — /forge-review,
                                  # request-review, find-blocker, ci-green, /restack
/plugin install grind@orrgal1     # default provider for iteration_loop (the *-green loops)
```

Because they're the default backing, the chain needs both installed (or the
capability repointed) to run — forge halts a step (`PROVIDER_MISSING`,
preflighted at `/forge` + `/forge-status`) when an un-overridden capability's
default provider is missing; install both, or repoint individual capabilities
via `/forge-setup`. The pieces that need no companion at all: the plain-git
`restack` fallback and the always-on `/code-review` + `/security-review` review
channels.

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

**Machine-global agent capabilities.** Above the per-repo dirs, at the forge
root, `/forge-setup` also maintains `~/.claude/forge/capabilities.toml` — a
single machine-scoped map from generic agent functions to the installed plugin
that provides each — all defaulting to forge's single companion
`@orrgal1/devloop`. Two classes: **optional enhancements** (`root_cause`,
`hypothesize`, `trace_logging`) degrade gracefully when their provider is
absent; **required** capabilities — the chain-blind PR ops (`ci_green`,
`review`, `review_watch`, `address_review`, `pr_brief`, `request_review`,
`find_blocker`), the `iteration_loop` the `*-green` wrappers drive, and
`deslop`. Every capability carries a **built-in default provider**
(`@orrgal1/devloop`): forge falls back to it automatically, so the registry is
an **override surface**, not required wiring. Forge **works best with** this
companion and uses it by default — it's the default backing for the required
caps, so an un-overridden required capability whose default provider isn't
installed makes forge **refuse** (`PROVIDER_MISSING`; install the provider, or
repoint the cap via `/forge-setup`), preflighted at `/forge` and `/forge-status`
entry. Forge honors any override, so the coupling is the deliberate
forge↔devloop/grind kind: tight by default, fully repointable; no hardcoded
slash command. (Supersedes the retired `@fordefi/setup` +
`~/.claude/.fordefi/tools.yml`.)

**Recovery playbooks.** A repo also has known recoveries for known failures —
expired cloud creds, a daemon to start, stale codegen. `[playbooks.<name>]`
rules (`when_output` regex → `then` recovery command, with `interactive` +
`retry`) let forge recover **itself** when a capability fails, instead of
blocking to ask you to "go auth." E.g. an ECR pull failing on an expired SSO
token matches a playbook whose recovery is `aws sso login`, then retries the
run. `/forge-setup` proposes playbooks from repo signals and wires them; when
forge hits an unmapped failure that a manual step then clears, it recognizes the
pattern and **offers to capture a new playbook on the fly**. Recoveries run
best-effort in every mode — an interactive one (e.g. a browser SSO login) is
attempted even under `yolo`/unattended (an operator may be watching and catch
the approval); only if no one completes it does it fall through to a genuine
block.

## Review

`/forge-review` is a thin chain wrapper over the `review` capability (default
`/review`, `@orrgal1/devloop`), which fans out review channels in parallel to
one ranked verdict:

- **Lens fan-out** — code-quality + correctness lenses, diff-fingerprint
  specialists, plus 1–3 lenses designed against the diff's risk surface, each
  dispatched to the `lens-reviewer` agent. forge adds its chain-semantic lenses
  (goal-delivery, scenario-realism, test-match) as context lenses when a chain
  exists.
- **Built-in `/code-review`** and **`/security-review`** — always on.

The review engine, lens pool, reviewer personas, and channels ship with the
capability provider (`@orrgal1/devloop`); forge bundles only the three chain
lenses. All are extensible per-repo via `$FORGE_HOME/lenses/`,
`$FORGE_HOME/personas/`, `$FORGE_HOME/review-channels/`; external CI/review
tools are drafted, never auto-posted.

## Skills

| Skill                                                                                         | Role                                                                              |
| --------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| `/forge-setup`                                                                                | Map host-repo tooling into `$FORGE_HOME`                                          |
| `/forge-start`                                                                                | Bootstrap a chain: source brief → scaffold worktree → draft PR → hand off         |
| `/forge-brief`                                                                                | Own the tight, non-collapsible PR brief; refresh it as intent evolves             |
| `/forge`                                                                                      | Orchestrate the whole chain to READY                                              |
| `/forge-goals` · `/forge-scenarios` · `/forge-validations` · `/forge-design` · `/forge-tests` | Chain atoms                                                                       |
| `/forge-proof` + `/forge-verify-*`                                                            | Full + per-layer attestation (the proof chain)                                    |
| `/forge-impl-green` · `/forge-ci-green` · `/forge-proof-green` · `/forge-review-green`        | Fix-loops to green (ci-green restacks each iteration; `--until-merge` continuous) |
| `/forge-review`                                                                               | Lens-designed, chain-aware PR review                                              |
| `/forge-review-watch` · `/forge-address-review`                                               | Watch for + drive submitted reviewer feedback to resolution                       |
| `request_review` capability (`/request-review`, `@orrgal1/devloop`)                           | Rank the best peer reviewer; gated ready+request (consumed via capability map)    |
| `find_blocker` capability (`@orrgal1/devloop`) · `/forge-wait-for`                            | Identify an external blocker; wait it out, then restack + resume                  |
| `/forge-map` (+ `-db` · `-api` · `-events` · `-config`)                                       | Build JSON domain snapshots under `$FORGE_HOME/maps/`                             |
| `/forge-tool`                                                                                 | Package an ad-hoc flow as a reusable tool                                         |
| `/forge-status`                                                                               | Read chain state + drift, recommend next step                                     |

## State & artifacts

Two locations, by purpose:

- **Per-PR chain artifacts** live in-repo under `$FORGE_ART/branches/<slug>/` —
  `goals.md`, `links.json`, `run.json`, `validations.json`, `design.md`,
  decisions, review cycles, loop scratchpads, the continuous-CI monitor's
  status. `$FORGE_ART` is `.forge` by default, or `<prefix>/.forge` when
  `[artifacts].prefix` is set. **What of this metadata git tracks is
  configurable** via `[artifacts].track` (default: everything), enforced by a
  generated `$FORGE_ART/.gitignore` scoped to `branches/…`. Categories: `spec`
  (goals + design), `proof` (machine chain state), `loop`, `review`, `monitor` —
  e.g. `track = ["spec"]` tracks only `goals.md` + `design.md`.
- **The tooling map + repo-scoped state** live at `$FORGE_HOME`
  (`~/.claude/forge/<repo-key>/`) — a user-layer path, never committed, shared
  by every worktree of the repo. Maps, tools, and commands live here,
  **outside** the `[artifacts].track` policy.

## License

[MIT](../LICENSE).
