---
name: root-cause
description:
  Find the root cause of an incident, flaky test, or regression via parallel
  hypothesis fan-out.
argument-hint: "symptom description, error, alert URL, or log snippet"
triggers:
  - "root cause"
  - "why is this happening"
  - "what's causing"
  - "find the cause"
  - "debug this"
  - "why does this fail"
  - "investigate why"
  - "flaky test"
  - "what changed"
practices:
  - pd-investigation
allowed-tools:
  - Skill
  - Bash
  - Read
  - Grep
  - Glob
---

> For PagerDuty data (incident details, on-call), invoke the `/pd` skill rather
> than calling any raw API — `/pd` owns the CLI wrapper and the API keys.

# /root-cause

> **CRITICAL: Run on main context.** Spawns 3–5 parallel investigation subagents
> per round. Subagents can't spawn their own. Delegating this skill to an Agent
> collapses the fan-out to a single pass.

Find the root cause of anything — incidents, flaky tests, performance
regressions, unexpected behavior. Doesn't stop until it lands a
hypothesis-backed-by-hard-evidence, or exhausts sources and tells you what's
left.

## Usage

```
/root-cause "gateway 500s spiking since 14:00"
/root-cause "test_swap_routing is flaky on CI"
/root-cause https://company.pagerduty.com/incidents/P123
/root-cause "latency p99 doubled after last deploy"
/root-cause "works locally, fails in staging"
```

## 1. Intake — normalize the symptom

- **PD incident/URL** → delegate to `/pd incidents get Pxxx`
- **Sentry URL** → Sentry MCP
- **Description** → use directly
- **Slack URL** → read the thread
- **Log snippet** → extract patterns + timestamps

Produce a **symptom statement**: one sentence — observable problem, when it
started (if known), what's affected.

## 2. Breadth-first context

Pull initial context in parallel, scoped to symptom type:

- **Infra:** Datadog (logs, metrics, traces around timeframe); K8s (pod health,
  events, restarts); Sentry (related errors, frequency deltas); Git (deploys +
  merged PRs in window); known patterns.
- **Code / tests:** git log + blame on affected files; recent test failure/flake
  history; read the affected paths; dependency version changes.
- **Behavioral ("works here, fails there"):** env diff (config, versions,
  flags); data diff (input/state); network (DNS, TLS, connectivity).

Announce: "Gathered initial context: [brief observations]."

## 3. Known patterns — fast path

Check playbooks first. Use the classifier to match the symptom to a playbook;
read its `known_causes` and `phases` sections. Match? Call it out:

> "This matches a known pattern: [description]. Verifying now."

Verify with targeted evidence. Confirmed → skip to step 8 (Prove). Not confirmed
→ continue to hypothesis generation, noting the near-miss.

`phases` lists composable debug skills — use them as investigation primitives.

Also search Notion postmortems for similar signatures — prior incidents are
strong seeds.

## 4. Hypothesize

3–5 theories ranked by prior probability. Each:

```
## Hypothesis N: [name]
**Claim:** what happened and why.
**Prior:** High/Medium/Low — why this is likely given context.
**Predictions:** if true, we'd see:
  - [observable 1]
  - [observable 2]
**Evidence needed:** where to look, what to check.
**Falsified by:** what would definitively rule it out.
```

Announce before investigating: "Generated N hypotheses. Investigating in
parallel."

## 5. Fan-out investigate

Launch one subagent per hypothesis. Each:

1. Reads hypothesis (claim, predictions, evidence needed)
2. Gathers evidence for/against
3. Checks each prediction (confirmed / contradicted / inconclusive)
4. Returns:

```
Hypothesis: [name]
Verdict: SUPPORTED / CONTRADICTED / INCONCLUSIVE
Evidence:
  - [prediction 1]: CONFIRMED — [what was found]
  - [prediction 2]: CONTRADICTED — [what was found instead]
Confidence: high/medium/low
New observations: [anything unexpected]
```

Each subagent gets domain-appropriate MCP tools (Datadog for metrics, K8s for
pods, Sentry for errors, code tools for source, etc.).

## 6. Triage — score and narrow

- SUPPORTED high-confidence → deep dive.
- SUPPORTED low-confidence → keep, needs more evidence.
- INCONCLUSIVE → keep if no better alternatives.
- CONTRADICTED → kill explicitly with reason.

Surface **new observations** — they may seed new sub-hypotheses.

Announce:

```
Round 1:
  H1 (deploy regression): SUPPORTED — high confidence
  H2 (provider outage):   CONTRADICTED — status healthy
  H3 (data volume spike): INCONCLUSIVE — need metric check
Pursuing: H1, H3. Killed: H2.
New lead: unusual error pattern in [service].
```

## 7. User checkpoint (interactive pivot)

After each triage round:

- **Reproduce:** "Can you trigger this with [steps]? Confirms/rules out H1."
- **Access:** "I can't reach [system]. Can you check [specific thing]?"
- **Redirect:** accept user input: "Actually, this started after we changed X" →
  incorporate as strong signal.
- **Confirm:** "Does this match what you're seeing? [describe expected from
  leading H]"

Re-score with new evidence. Need refinement → sub-hypotheses → back to step 5.
User has nothing → auto-proceed to the next round.

## 8. Prove — evidence chain

When a hypothesis reaches high confidence:

```
## Root Cause
**What:** [one sentence]
**Why:** [mechanism — how the cause produced the symptom]

## Evidence Chain
1. Observed [symptom] at [time]
2. Checked [source] → found [evidence A]
3. [Evidence A] indicates [intermediate conclusion]
4. Verified by [source] → [evidence B] confirms
5. Reproduced by [steps] (if applicable)

## Ruled Out
- [Alt 1]: [evidence]
- [Alt 2]: [evidence]

## Confidence: HIGH / MEDIUM

## Remaining Uncertainty
[what's still unclear, what would resolve it]
```

## Termination

| Outcome      | When                                                     | Output                                        |
| ------------ | -------------------------------------------------------- | --------------------------------------------- |
| **Proven**   | One hypothesis with strong chain, alternatives ruled out | Full evidence chain, high confidence          |
| **Narrowed** | 1–2 candidates, can't close without manual steps         | What's known, what's not, specific next steps |
| **Stuck**    | Exhausted sources after 3+ rounds                        | Everything checked, what's left               |

**Narrowed** and **Stuck** always return concrete next steps (exactly what
manual check would help and what to look for).

**Cap: 5 rounds.** If not converged, terminate and present all accumulated
evidence. User can say "keep going" to override.

## When invoked by `/pd`

- Input pre-parsed (symptom + PD/alert context).
- Known patterns checked against incident playbooks.
- Output goes back to `/pd` for response coordination.
- Skip user checkpoint — `/pd` manages the interaction.

## Tools used

Domain-dependent:

- Infrastructure: Datadog, Kubernetes, Sentry; delegate PagerDuty to `/pd`
- Code: Read, Grep, Glob, git log/blame/diff via Bash
- History: Notion MCP for postmortems
