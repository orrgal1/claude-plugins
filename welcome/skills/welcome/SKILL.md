---
name: welcome
argument-hint: "[step name to jump to, optional]"
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
  - Skill
---

# /welcome

Interactive, idempotent onboarding for the **orrgal1** marketplace. Walks a new
operator from a bare Claude Code install to a fully wired setup, then prints a
usage guide.

The marketplace ships seven plugins:

| Plugin             | Headline              | Reach for it when…                                        |
| ------------------ | --------------------- | --------------------------------------------------------- |
| `forge`            | `/forge`              | drive a PR from a brief to READY with attestation         |
| `devloop`          | `/restack` `/deslop`  | restack a PR stack on its base; strip AI slop from a diff |
| `diagnose`         | `/root-cause`         | find the root cause of a bug, flake, or regression        |
| `grind`            | `/grind`              | grind a bounded verifiable target to green, committing    |
| `graphify-wrapper` | `/graphify-wrapper-*` | structural knowledge-graph search across a monorepo       |
| `persona`          | `/load-persona`       | swap behavioral guidance Claude loads every session       |
| `reviewable`       | `/reviewable-*`       | drive Reviewable.io review threads                        |

## Agent contract

Run the phases **in order**. If `$ARGUMENTS` names a step, jump straight to it.
At each phase: **detect** current state → **report** it tersely → **ask** before
acting → **act or emit**. Skip anything already done — this skill is safe to
re-run.

Hard rule on `/plugin`: you **cannot** invoke `/plugin` yourself (it's an
interactive UI). For plugin installs, **emit paste-ready commands** in a code
block and let the operator run them. Everything else — file ops, the registry,
invoking other skills via the Skill tool — you do directly after confirming.

Keep output as bullets, not prose. One line per finding.

---

### Phase 1 — Prerequisites

Detect and report:

```bash
gh auth status 2>&1 | head -3 || echo "gh: NOT INSTALLED"
git config --get remote.origin.url 2>/dev/null || echo "no origin yet"
git --version
```

- `gh` un-authed/missing → `forge`, `devloop`, `reviewable` need it. Point the
  operator at `! gh auth login` (the `!` prefix runs it in this session).
- `origin` is `https://…` → flag it: persona git discipline is SSH-only; HTTPS
  bypasses the YubiKey. Suggest `git remote set-url origin git@github.com:…`.
- Anything green → say so and move on.

---

### Phase 2 — Recommended 3rd-party plugins

Read `~/.claude/plugins/installed_plugins.json` and report which of the four are
already present. For the missing ones, `AskUserQuestion` (multiSelect) which to
install, then emit a single paste-ready block for the chosen set:

```
# claude-mem — cross-session memory, smart-explore, mem-search
/plugin marketplace add thedotmack/claude-mem
/plugin install claude-mem@thedotmack

# caveman — token-compression mode + cavecrew subagents
/plugin marketplace add JuliusBrussee/caveman
/plugin install caveman@caveman

# context7 — live library/framework docs lookup
/plugin marketplace add upstash/context7
/plugin install context7-plugin@context7-marketplace

# claude-plugins-official — code-review, /simplify, pr-review-toolkit, plugin-dev
/plugin marketplace add anthropics/claude-plugins-official
/plugin install code-review@claude-plugins-official
/plugin install code-simplifier@claude-plugins-official
/plugin install pr-review-toolkit@claude-plugins-official
/plugin install plugin-dev@claude-plugins-official
```

Why each matters to orrgal1:

- **claude-mem** — session-start memory injection + `/smart-explore`; the
  graph-first habit in the shipped persona leans on structural search.
- **caveman** — compresses long `forge` / `diagnose` sessions; `cavecrew`
  subagents shrink tool-result context ~60%.
- **context7** — fresh docs for any library, beats stale training data.
- **official bundle** — `forge` and `devloop` reuse the built-in `/simplify` and
  `/code-review`; the bundle adds the review toolkit and plugin-dev tooling.

---

### Phase 3 — Persona

Check `~/.claude/persona.md` and whether `~/.claude/CLAUDE.md` `@`-imports it.

- Missing → invoke `/setup-persona` (bootstraps the file + the import).
- Then offer `/load-persona orrgal` to load the shipped persona from the builtin
  pool (`persona/personas/`). List the pool with bare `/load-persona` first so
  the operator can pick.
- Note: behavioral rules (git discipline, tone, security preamble) live
  **inline** in `~/.claude/persona.md`. Edit it directly to change behavior.

---

### Phase 4 — graphify-wrapper (optional, structural search)

One-time per machine, then per repo:

- Per machine/repo → invoke `/graphify-wrapper-setup` (installs the CLI,
  gitignores `graphify-out/`, inits the per-repo registry, picks a semantic
  backend).
- Per repo → `/graphify-wrapper-map` proposes a focused set of domains and
  registers the chosen ones; `/graphify-wrapper-sync` builds them.
- Worktrees auto-seed from `main` at session start; check freshness with
  `/graphify-wrapper-status`.
- Skip if the operator doesn't want structural search — grep still works.

---

### Phase 5 — Per host-repo setup (forge)

`forge` carries **no** hard-coded repo knowledge. For each repo you'll forge in,
from inside that repo's worktree:

- `/forge-setup` — maps the repo's build / test / lint / typecheck / codegen
  into a gitignored `.forge/` dir. One-time per repo (shared across worktrees).
- Then the chain is live: `/forge-start <source>` → `/forge`.
- Unmapped capabilities surface a `NEEDS_SETUP` gap — forge never guesses a
  command.

If the operator uses Reviewable.io: `/reviewable-login` once to wire the browser
session.

---

### Phase 6 — Usage guide

Print the plugin table at the top of this file, then the canonical entry points:

- **Ship a PR end-to-end** → `/forge-setup` (once) → `/forge-start <ticket>` →
  `/forge`.
- **Keep a PR stack current** → `/restack` (one) / `/restack-all` (stack).
- **Clean a diff before review** → `/deslop`.
- **Debug something broken** → `/root-cause` (or `/diagnose` to route).
- **Grind to green autonomously** → `/grind <verifiable target>`.
- **Orient in a domain** → `/graphify-wrapper-query <domain> "…"`.
- **Switch behavior** → `/load-persona <name>`.

Close by listing what's still unset (any phase the operator skipped) so they can
come back with `/welcome <step>`.

---

## Notes

- Idempotent: every phase detects state and skips completed work. Safe to
  re-run.
- The skill never installs plugins itself — it emits the `/plugin` commands. All
  other setup (persona, graphify, forge) it performs via the relevant skills
  after confirming.
- Jump to a phase: `/welcome persona`, `/welcome graphify`, `/welcome repo`,
  `/welcome usage`.
