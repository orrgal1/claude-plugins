---
name: pepper
description: Scatter uniquely-marked trace logs through suspect code, run repro, grep, iterate, clean up.
argument-hint: "bug description + suspected file(s) or function(s)"
triggers:
  - "add debug logs"
  - "can't see what's happening"
  - "need more visibility"
  - "trace this"
  - "log peppering"
practices:
  - hypothesis-iteration
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
---

# /pepper

Agent-optimized log peppering. Scatter trace logs with a unique marker through
suspected code paths, run the repro, `Grep` the marker to see the runtime trace
without polluting context, narrow, iterate, clean up.

**Input:** `$ARGUMENTS`

## 1. Pick a marker

Choose a prefix that won't collide with anything in the codebase:

```
[DBG-<topic>-<session>]    e.g. [DBG-swap-42]
```

`Grep` the codebase for the literal prefix first and confirm zero hits. Unique
markers make cleanup safe and `Grep` cheap. Two-digit session number lets you
pepper twice in one debugging run without confusion.

## 2. Pick placement points

Start sparse. Typical high-value spots:

- **Entry and exit** of each suspected function — include args (entry) and
  return value (exit).
- **Before and after each state mutation** — "was X / now X".
- **Inside each branch** of conditionals you suspect — include the branch
  condition's evaluated value.
- **Before each await / goroutine / channel send** — these are the usual sites
  of concurrency bugs.

Avoid hot loops unless you're investigating the loop itself — use a counter gate
(`if i < 5 { log(...) }`) to bound output.

## 3. Format the trace lines

Every marker line includes:

- The marker prefix
- A unique location tag (`fn-name:step`)
- The relevant values

Example (language varies):

```go
log.Printf("[DBG-swap-42] refresh:pre tx=%s version=%d", txID, tx.Version)
// ...
log.Printf("[DBG-swap-42] refresh:post tx=%s version=%d err=%v", txID, tx.Version, err)
```

Keep each line single-line — multi-line output breaks `Grep` correlation.

## 4. Run the repro

Run the failing command. If output is noisy, redirect to a file and use `Grep`
instead of reading the full log (see `/trace` for the pattern):

```bash
./run-repro 2>&1 | tee /tmp/pepper-42.log
# or
./run-repro > /tmp/pepper-42.log 2>&1
```

## 5. Extract the trace

```bash
grep "\[DBG-swap-42\]" /tmp/pepper-42.log
```

Read the trace as a story: what values did each step see? Where did the actual
path diverge from the expected path?

## 6. Narrow

Based on what the trace revealed:

- **Trace stopped early** — something panicked or returned early; add more logs
  on error paths.
- **Trace shows wrong value** — move the marker upstream to find where the value
  was set.
- **Trace looks right but bug persists** — the suspected path isn't the actual
  path; widen the net.

Add / move markers, bump the session number if desired, re-run.

## 7. Cleanup (mandatory)

When the bug is diagnosed, remove every marker. The unique prefix makes this
safe:

```bash
grep -rn "\[DBG-swap-42\]" <repo>   # review what you added
```

Then Edit or `sed -i` every file listed, confirm with another `grep` that
returns zero hits, and commit the fix separately from the diagnosis trace so the
repo history stays clean.

## Anti-patterns

- Generic markers like `[DEBUG]` or `fmt.Println("here")` — collide with
  existing logs, uncleanable.
- Peppering in hot loops without a counter gate — floods output, obscures
  signal.
- Leaving markers in because "they might be useful later" — that's what real
  logging is for; debug markers rot.
- Peppering before forming a hypothesis — you'll add logs everywhere and learn
  nothing. Pair this with `/hypothesize`.

## Tools used

`Edit` (add/remove markers), `Bash` (run repro), `Grep` (extract trace, confirm
cleanup).
