---
name: hypothesize
description:
  Diagnose a local bug via 2–4 candidates and one cheap experiment per round.
argument-hint: "bug description or error message"
triggers:
  - "I think it might be"
  - "what could cause"
  - "not sure why"
  - "let's think through"
  - "debug this locally"
practices:
  - hypothesis-iteration
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
  - Edit
---

# /hypothesize

Disciplined thinking for local bugs that aren't worth a full `/root-cause`
fan-out. Single context, no subagents — just 2–4 candidates, one cheap
experiment at a time, belief updates between rounds.

**Input:** `$ARGUMENTS`

## 1. Ground the symptom

One sentence. Observable behavior, reproducible? what you've already ruled out.
If the input is vague, ask once: "What exactly are you seeing, and what were you
expecting?"

## 2. List 2–4 candidates

Keep it to the handful you actually believe. Each:

```
H<N>: <one-line claim>
  prior: high | medium | low — why
  predicts: if true, we'd see <X>
  cheapest test: <one concrete check>
```

Order by `prior × (1/cost of test)` — cheap tests on medium-prior hypotheses
beat expensive tests on high-prior ones.

## 3. Run the cheapest test on the top candidate

One experiment per round. Don't batch. Options:

- Read the relevant file(s) with Grep/Read.
- Run the failing command with more output (`-v`, `--debug`, `LOG_LEVEL=debug`).
- Add a single trace log (if you need more than a couple, switch to `/pepper`).
- Run a small isolated repro.

## 4. Update beliefs

After the test:

```
H<N>: confirmed | contradicted | inconclusive
  evidence: <what you saw>
  updated prior: <new>
```

Contradicted → cross out. Confirmed high-prior → skip to step 6.

## 5. Pick the next test

Usually the next-highest-prior candidate's cheapest test. If a test surfaced a
new observation, consider whether it seeds a new hypothesis — add it to the list
with a prior.

Loop: step 3 → step 4 → step 5.

## 6. Land the diagnosis

When one candidate is confirmed:

```
Root cause: <one sentence>
Mechanism: <how cause → symptom>
Evidence: <the specific observations>
Fix: <smallest change that resolves it>
```

Then stop.

## Escalation

Switch to `/root-cause` if:

- Three rounds with no candidate confirmed and no new observations worth a
  sub-hypothesis.
- The bug spans services and you need parallel investigation.
- The symptom points at infra (Datadog, K8s, RabbitMQ, MongoDB).

## Anti-patterns

- "It might be a race condition" with no falsifier — that's not a hypothesis,
  that's a shrug.
