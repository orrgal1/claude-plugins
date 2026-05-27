# forge

A self-contained, repo-agnostic **PR forge chain** for
[Claude Code](https://claude.com/claude-code).

forge drives a pull request from a one-line source brief all the way to
**READY** — capturing goals, drafting behavior scenarios, writing a test per
scenario, designing the implementation, driving tests + CI green, and running a
lens-designed code review — with attestation at every step so nothing is claimed
that isn't backed by a goal, a scenario, a test, and a passing run.

It has **no dependency on any other plugin** and **no hard-coded knowledge of
any repo's tooling**. You teach it how to build/test/lint _your_ repo once, via
a gitignored `.forge/` map; everything else is generic. Adopt it into any
project.

## The chain

```
/forge-start   source brief → draft PR
/forge-goals   the PR's intended end-state, as a goal list
/forge-scenarios  when:/then: scenarios covering each goal (observable behavior)
/forge-design  map each scenario to the components/symbols that satisfy it
/forge-tests   one component-tier test per scenario (the only step that writes test code)
/forge-impl-green  drive the linked tests to green
/forge-audit   attest the whole chain: goals ⇐ source · scenarios ⇒ goals · tests ⇒ scenarios · bodies ⇒ when/then · runs green
/forge-ci-green   drive PR CI to green
/forge-review     lens-designed, chain-aware PR review
/forge-review-green  drive the review to 0 blockers + 0 majors
/forge-address-review  work externally-submitted reviewer feedback to resolution
```

`/forge` runs the whole arc end-to-end with two pause points (goals + design) in
**auto** mode, or a pause after every phase in **manual** mode. Resume with
`/forge approve` and `/forge iterate "<feedback>"`.

## Install

As a Claude Code marketplace plugin:

```
/plugin marketplace add orrgal1/forge
/plugin install forge@orrgal1
```

Or point Claude Code at a local checkout:

```
git clone git@github.com:orrgal1/forge.git
claude --plugin-dir forge/forge
```

## Quickstart

```
/forge-setup                         # one-time: map this repo's build/test/lint/...
/forge-start https://tracker/TICKET  # open a draft PR from a source
/forge                               # drive the chain to READY
```

## The `.forge/` tooling map

forge runs **no** repo-specific command directly. `/forge-setup` creates a
gitignored `.forge/` directory mapping forge's logical capabilities to _your_
repo's tooling:

```
.forge/
  forge.toml          # capability → command (+ notes)
  commands/           # one per capability — a script OR a `<cap>.md` instructions doc
    test
    build
    lint
    typecheck
    codegen
  review/             # optional: additional review mechanisms, on top of GitHub
```

Each capability is wired as **either** a runnable command/script (deterministic)
**or** prose instructions the agent follows (for conditional, multi-step flows a
fixed command can't capture). A capability that isn't mapped surfaces a
`NEEDS_SETUP` gap — forge never guesses a command.

Review automation is **additive**: GitHub (via `gh`) is the always-on baseline;
drop one file per extra mechanism in `.forge/review/` to integrate other review
platforms alongside it.

## Review

`/forge-review` runs a parallel, lens-designed review: always-on chain-semantic
lenses (goal-delivery, scenario-realism, test-match) + code-quality lenses, plus
1–3 lenses designed against the diff's risk surface, fanned out to a bundled
`forge-lens-reviewer` agent. The lens pool (`lenses/`) and reviewer personas
(`personas/`) ship with the plugin and are extensible per-repo via
`.forge/lenses/` and `.forge/personas/`.

## Skills

| Skill                                                                                  | Role                                            |
| -------------------------------------------------------------------------------------- | ----------------------------------------------- |
| `/forge-setup`                                                                         | Map host-repo tooling into `.forge/`            |
| `/forge-start`                                                                         | Bootstrap a chain: source brief → draft PR      |
| `/forge`                                                                               | Orchestrate the whole chain to READY            |
| `/forge-goals` · `/forge-scenarios` · `/forge-design` · `/forge-tests`                 | Chain atoms                                     |
| `/forge-audit` + `/forge-verify-*`                                                     | Full + per-layer attestation                    |
| `/forge-impl-green` · `/forge-ci-green` · `/forge-audit-green` · `/forge-review-green` | Fix-loops to green                              |
| `/forge-review`                                                                        | Lens-designed, chain-aware PR review            |
| `/forge-address-review`                                                                | Drive submitted reviewer feedback to resolution |
| `/forge-status` · `/forge-line` · `/forge-triage` · `/forge-stuck-check`               | Status, statusline, triage, loop-health         |

## State & artifacts

Per-PR chain artifacts live under `.pr-artifacts/<branch-slug>/forge/` (forge
self-bootstraps a `.pr-artifacts/.gitignore`). The `.forge/` tooling map is
separate and gitignored by default. Loop scratchpads live under
`.pr-artifacts/<slug>/forge/loop/`.

## License

[MIT](./LICENSE).
