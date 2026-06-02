---
id: commentary
name: Commentary Correctness
tags: [code-quality, comments, hygiene]
requires: diff
severity-floor: minor
brief-artifacts: [commentary-surface]
introduced-by: forge-review
---

# Commentary Correctness

Every comment, docstring, and inline note added or modified in the diff is read
against the code beside it and audited for whether it earns its place. Comments
decay differently, lie at a different rate, and outlive their context unless
held to a standard. `clean-code` names the policy in the Martin tradition; this
lens is the dedicated audit.

## Principles

- **Brevity without loss.** A comment is the shortest text that still carries
  its rationale. Drop any sentence the reader loses no signal without.
  Multi-paragraph prose where one line fits is a smell.
- **"Why," not "what."** Well-named identifiers say what. Comments earn their
  place only on non-obvious rationale: a hidden constraint, a subtle invariant,
  a workaround for a specific bug, surprising behavior. Restating code is noise.
- **No drift-prone anchors.** Comments must not pin to ephemera that rots away
  from the code:
  - PR / issue / ticket numbers without a stable URL — and even those age badly.
  - Line-number references (`see foo.py:123`) — the target moves on edit.
  - Caller lists (`used by X, Y, Z`) — callers change, the comment doesn't.
  - "Recently added" / "for the new flow" / "temporary until …" with no tied
    removal condition.
  - Author / date attributions (`/* Bob, 2023 */`).

  If a reference is genuinely needed, anchor on stable surfaces: a symbol name,
  an external standard, a public spec URL, an issue body the file outlives.

- **No session context.** Comments narrating this PR/fix/rollout —
  `added for the Y flow`, `handles the case from issue #123`,
  `see the design doc on Notion` — belong in the PR description, not the source
  tree.
- **No misleading or stale comments.** A comment contradicting the code is worse
  than none. Every comment near a changed line must still be true after the
  diff.
- **Commented-out code is dead.** Delete it; git has it. Narrow exception: a
  one-line "this knob is intentionally off; see `<stable anchor>`".
- **TODO / FIXME / XXX / HACK need owner + condition or date.**
  `TODO: fix later` rots; `TODO(orgal, post-v3 migration)` carries enough to
  action or remove.
- **No signature-echo docstrings.** Keep the docstring for the contract the
  signature can't carry: invariants, side effects, ownership semantics, allowed
  concurrent callers, error modes — not a paraphrase of each param.
- **Banner / divider noise has no place.** `# ====== HELPERS ======`, ASCII
  boxes, decorative dividers — structure belongs in identifiers and file layout.
- **Tone discipline.** No "obviously," "simply," "just," apologies, hedges, or
  commentary about the author's mood.

## Pattern smells

- Comment paraphrases the function it sits above
  (`# returns true if user is active` above `def is_active_user`).
- TODO without owner or removal condition.
- Block of commented-out code near actively-edited code.
- Comment cites a PR / ticket / line with nothing pinning it to the comment.
- Docstring repeats every arg from the signature with no added invariant.
- Comment narrates the current PR's intent rather than the code's intent.

The brief carries the diff's commentary surface — every added/modified comment,
docstring, or inline note with surrounding code — plus the rules above. No forge
artifact.

## Severity

`forge-review-green` drives only blockers + majors to zero; minors survive to
merge. So the two failure modes this lens exists to stop — **drift** and
**sustained verbosity** — promote to major so they are actually forced.

| Severity    | When                                                                                                                                                                                                                                                              |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **minor**   | Isolated low-rot slip: one redundant line, a lone signature-echo param, a banner/divider, a tone word. One comment, no rot vector, reader loses nothing if it ships.                                                                                              |
| **major**   | **Drift-prone anchor** (PR/issue/ticket number, line-number ref, caller list, session/PR-narration note, author/date stamp, `temporary until …` with no removal condition); OR **sustained verbosity** (a _block_ failing brevity). One finding covers the block. |
| **blocker** | Misleading: a comment contradicts the code or claims behavior the code doesn't implement, _and_ a future reader would rely on it for a correctness decision (`this never returns null` above code that does).                                                     |

When in doubt between minor and major: does this rot or mislead, or is it merely
redundant? Rot/mislead → major. Merely redundant → minor.
