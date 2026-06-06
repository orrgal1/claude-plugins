# @orrgal1/diagnose

A portable, repo-agnostic **diagnostic toolkit** for
[Claude Code](https://claude.com/claude-code). Four skills covering the spectrum
from a heavyweight parallel root-cause investigation down to a one-process trace
capture — no project coupling, usable in any repo. No dependency on other
plugins.

## Skills

| Skill          | Reach for it when…                                      | What it does                                                                                                                                                                      |
| -------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/root-cause`  | An incident, flaky test, or regression needs a real RCA | Hypothesis-driven root-cause analysis with **parallel investigation fan-out** — multiple candidate causes investigated concurrently, converging on the one the evidence supports. |
| `/hypothesize` | A local bug, and you want to think it through           | Lightweight loop: 2–4 candidate hypotheses, **one cheap experiment per round**, narrow down.                                                                                      |
| `/pepper`      | You can't see what the code is doing                    | Scatters **uniquely-tagged trace logs** through suspect code, runs the repro, greps for the tags, iterates, then **cleans up** after itself.                                      |
| `/trace`       | A process floods the agent's context                    | A pattern, not a tool — route verbose process output **to disk**, then grep out only what you need instead of poisoning context.                                                  |

## Usage

```
/root-cause "checkout 500s spiking since deploy abc123"   # or an alert URL / log snippet
/hypothesize "form submits twice on slow networks"
/pepper "auth token sometimes null" src/auth/session.ts
/trace "yarn dev"
```

`/root-cause` is also wired for headless CI use (read-only investigate action).
Requires `git`; the rest is generic shell + read tools.

## License

[MIT](../LICENSE).
