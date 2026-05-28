---
name: forge-line
description: "Write the forge statusline state file (~/.claude/forge/state.json)."
argument-hint:
  "--phase-id <id> --sub <one-line> [--slug <name>] [--recap <text>] [--verdict
  <in-progress|READY|...>]"
triggers:
  - "forge line"
  - "update forge statusline"
allowed-tools:
  - Bash
  - Read
practices: []
user-invocable: false
---

# /forge-line — write the forge statusline state file

Tiny write skill. Keeps `~/.claude/forge/state.json` fresh.
`bin/forge-statusline.sh` reads it and renders one line.

## When to write

- Phase transitions in `/forge`.
- Patch-loop iteration boundaries (impl / audit / ci / review).
- Triage / status entries + verdict emits.
- Subagent step start + end.
- Heartbeat at minimum every 5 min — long-thinking steps must keep state alive
  so the renderer doesn't flag `(stale Nmin)`.

## Inputs

| Input        | Required    | Notes                                                                                                                      |
| ------------ | ----------- | -------------------------------------------------------------------------------------------------------------------------- |
| `--phase-id` | yes         | `start` `goals` `design` `scenarios` `tests` `impl-green` `audit-green` `ci-green` `review-green` `triage` `await-<phase>` |
| `--sub`      | yes         | one-line current sub-step, e.g. `SG1.4 iter 3/15`                                                                          |
| `--slug`     | auto-detect | per `/forge-status` § 1 rule                                                                                               |
| `--recap`    | optional    | past-tense one-liner                                                                                                       |
| `--verdict`  | optional    | `in-progress` (default), `READY`, `BLOCKED_*`, `NEEDS_OPERATOR`, `STUCK`, `await`                                          |

## Process

1. Resolve slug (per `/forge-status` § 1).
2. Compose state:
   ```json
   {
     "ts": "<ISO-8601 UTC>",
     "slug": "<slug>",
     "branch": "<current branch>",
     "phase_id": "<--phase-id>",
     "sub": "<--sub>",
     "verdict": "<--verdict, default in-progress>",
     "recap": "<--recap or empty>",
     "started_at": "<preserved when slug+phase_id unchanged, else now>"
   }
   ```
3. Atomic write:
   ```bash
   mkdir -p ~/.claude/forge
   tmp=$(mktemp ~/.claude/forge/state.json.XXXXXX)
   cat > "$tmp" <<EOF
   { "ts": "...", ... }
   EOF
   mv -f "$tmp" ~/.claude/forge/state.json
   ```
   `mv -f` is atomic same-filesystem → reader never sees partial JSON.
4. **No-op if unchanged** (ignoring `ts`) — prevents churn in tight loops.

## Call sites (canonical)

| Caller                 | When                                                             |
| ---------------------- | ---------------------------------------------------------------- |
| `/forge`               | every phase transition + every `AWAIT_*_REVIEW` settle + verdict |
| `/forge-triage`        | entry + verdict                                                  |
| `/forge-status`        | entry + emit                                                     |
| `/forge-*-green` loops | pre-flight + every iteration + verdict                           |
| `/forge-stuck-check`   | invocation + verdict                                             |
| `forge-step-runner`    | step start + tool calls during long steps + receipt return       |

Verdict tokens settle on terminal state. AWAIT pauses use `verdict=await` with
the phase name in `sub`.

## Honesty

- `sub` reflects actual current work. Loop just started → `bootstrapping`.
- `recap` is past-tense.
- `verdict` stays `in-progress` until settlement.
- State is presentation-only — never read it in business logic; skills that need
  chain state read the artifact files directly.

## Setup — wire to Claude Code statusline

`~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "${CLAUDE_PLUGIN_ROOT}/bin/forge-statusline.sh"
  }
}
```

`${CLAUDE_PLUGIN_ROOT}` resolves to this plugin's install dir, so the path
survives version bumps and however the plugin was installed.

## Usage

```
/forge-line --phase-id impl-green --sub "SG1.4 iter 3/15" --recap "drove SG1.1-1.3 green"
/forge-line --phase-id ci-green --sub "watching go-unittests"
/forge-line --phase-id forge --sub "READY" --verdict READY --recap "11 scenarios, 0 blockers"
```

## Exit codes

| Code | Meaning                                     |
| ---- | ------------------------------------------- |
| 0    | state written (or no-op)                    |
| 64   | unrecoverable error (cannot write home dir) |
