---
name: trace
description: Route verbose process output to disk and grep instead of polluting agent context.
argument-hint: "command or service name"
triggers:
  - "tail the logs"
  - "watch this process"
  - "stream logs"
  - "too much output"
  - "context is blowing up"
practices:
  - log-discipline
allowed-tools:
  - Bash
  - Read
  - Grep
---

# /trace

Pattern, not a tool. When a process or service produces enough output to poison
agent context, route it to disk and extract only what you need.

**Input:** `$ARGUMENTS`

## The rule

**Never let verbose output land directly in agent context.** Every byte of log
you scroll past is a byte of cache gone. File → Grep → Read-with-offset stays
cheap.

## Pattern 1 — run a single command, keep output

```bash
./long-command > /tmp/trace-<topic>.log 2>&1
```

Then:

```
Grep pattern="ERROR|WARN" path=/tmp/trace-<topic>.log
Grep pattern="<marker>" path=/tmp/trace-<topic>.log -A 3 -B 1
Read file_path=/tmp/trace-<topic>.log offset=<N> limit=50
```

Never `cat` the whole file. If you think you need to, you don't — narrow the
`Grep`.

## Pattern 2 — background a long-running process

```bash
./service > /tmp/svc-<topic>.log 2>&1 &
```

Use `Bash(run_in_background=true)` for the command. Kill it with the shell id
when you're done. Prefer this when:

- The process takes >30s to produce its first useful log line.
- You need to trigger the repro in a separate step while the process runs.
- You plan to pepper and re-run multiple times (see `/pepper`).

## Pattern 3 — tail-while-triggering

Background a `tail -F` into a filtered file so you can Grep the filtered version
without re-scanning the whole log:

```bash
tail -F /tmp/svc.log | grep --line-buffered "\[DBG-" > /tmp/svc-filtered.log &
```

Only useful when the source log is huge and the filter is cheap.

## Pattern 4 — multi-service timeline

For a failure that spans services, merge-sort their logs by timestamp:

```bash
# Each service log must already start lines with a sortable timestamp
cat /tmp/gateway.log /tmp/signing.log /tmp/indexer.log \
  | sort -k1,1 \
  > /tmp/timeline.log
```

Then `Grep` a short time window instead of reading the merged file:

```
Grep pattern="2026-04-22T10:3[0-5]" path=/tmp/timeline.log
```

## Pattern 5 — bucket a failure window

When the failure time is known, extract a 60-second slice:

```bash
awk '/2026-04-22T10:32:/,/2026-04-22T10:33:/' /tmp/svc.log > /tmp/window.log
```

Then treat `/tmp/window.log` as the full context — it's small enough to read.

## Housekeeping

- Use a unique `<topic>` per debugging run so concurrent sessions don't clobber
  each other's files.
- `rm /tmp/trace-<topic>.log*` when the investigation is done; `/tmp` is
  session-scoped but habits matter.
- Don't commit trace files. Add `/tmp/` patterns to `.gitignore` only if you're
  genuinely putting traces inside the repo (don't).

## Anti-patterns

- `cat /tmp/huge.log` — defeats the whole point.
- Streaming stdout directly in a Bash call without redirection — context
  catastrophe.
- Reading a 50 MB file with `Read` and no offset — slow and useless.
- Grepping without `-A` / `-B` context and then re-grepping to get surrounding
  lines — set context on the first Grep.

## Tools used

`Bash` (redirect, background, sort/awk), `Grep`, `Read` (with `offset` /
`limit`).
