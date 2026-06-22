---
id: self-evident
name: Self-Evident Change
tags: [hygiene, legibility, intent, review-friction]
requires: diff
severity-floor: minor
brief-artifacts: [pr-description]
introduced-by: lens-review
---

# Self-Evident Change

Every change in the diff must be legible on its own terms. A reviewer reading a
hunk should be able to tell **why** it was made — from the hunk plus the PR's
stated intent, without asking the author. A change that draws a "why is this
here / why was this removed / why did this become X?" is a defect of
**legibility**, separate from correctness: the diff is the artifact reviewers
reason about, and an unexplained change is unreviewable. When a reviewer has to
ask, that question is the signal — and the answer is usually that a more
self-evident alternative existed and wasn't taken.

**The test, per change:** would a competent reviewer, seeing only this hunk +
the PR's stated intent, understand why it was made? If not, it is a mystery
change — flag it.

## Mystery patterns

- **Incidental deletion forced by a primary change.** A type/signature/API
  change breaks an unrelated call site or test datum, and the author _drops_ the
  broken thing instead of adapting it. The deletion then reads as an unrelated
  removal. The self-evident move is to adapt it — keep the data/call, show it is
  a mechanical consequence — even at a small cost (one import, a cast).
  _Canonical example:_ a field's type changes `int64 → BigInt`; two untouched
  test files had struct literals using the old `int` constant, and they are
  deleted rather than converted. Dropping is self-evident **only** when the
  thing was already dead and the diff makes that deadness obvious.
- **Unexplained semantic shift.** A literal, flag, constant, or default quietly
  changes value; a condition flips; an order changes — with nothing in the hunk
  or the PR's intent saying why.
- **Mystery move / rename** — a symbol relocated or renamed where the motivation
  isn't derivable from the change.
- **Silent behavior trade** — an error path swallowed, a branch removed, a guard
  dropped — that looks incidental but a reviewer can't confirm is safe.
- **Orphaned consequence** — only half of a paired change is present (a field
  removed but its writer left; a param dropped but a caller still passes it), so
  the reader can't reconstruct the intent.

## Remedy ladder (prefer the earliest)

1. **Choose the self-evident change.** Adapt instead of delete; keep the shape
   that shows the change is mechanical. The reviewer's "why?" disappears because
   the change explains itself. Almost always right, and worth a one-line cost.
2. **Make the intent visible** — a minimal, earned one-line rationale where the
   code genuinely can't speak (held to the `commentary` standard), or fold the
   incidental consequence into the PR description so it is expected, not
   surprising.
3. Only if neither fits does the change stand, and the finding records the
   residual friction.

## Boundary — what this lens is not

- **Not `scope`.** An in-scope change (a true consequence of the PR's goal) can
  still be a mystery; an out-of-scope change is `scope`'s call. This lens asks
  "is the _why_ legible?", not "does it belong?".
- **Not `pr-description-fidelity`.** That checks the diff against described
  claims; this checks a change against its own intelligibility, described or
  not.
- **Not `commentary`.** That audits comments that exist; this fires with zero
  comments present, and its first remedy is to change the code, not add a note.

## Severity

The review fix-loop drives only blockers + majors to zero; minors survive to
merge. The failure mode this lens exists to stop — a mystery change shipping
unexamined — is forced by promoting the genuine-mystery tier to major.

| Severity    | When                                                                                                                                                                                                                                                  |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **minor**   | Mildly non-obvious: a reviewer could infer the why with modest effort; low friction, nothing risky hidden. A small adaptation whose motivation is one step removed.                                                                                   |
| **major**   | A genuine mystery — a deletion, value/semantic shift, move, or orphaned consequence whose rationale a reviewer cannot derive from the hunk + PR intent, **and** a more self-evident alternative plainly exists. Take that path or surface the intent. |
| **blocker** | A mystery change that also **hides a possible behavior/correctness impact** a reviewer can't evaluate — an incidental-looking deletion or guard-drop that might be removing real coverage or logic. Unreviewable _and_ risky.                         |

**Heuristic:** if you catch yourself drafting "why did they …?" in a review
comment, that change failed this lens. Don't ask the author — record the
finding; the fix is to make the change not need the question.

The brief carries the PR description verbatim (the primary intent) plus the
diff. Read each hunk against "would this draw a _why?_".
