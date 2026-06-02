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
are a second language shipped next to the code; they decay differently, lie at a
different rate, and outlive their context unless held to a standard. The
`clean-code` lens names the policy in the Martin tradition; this lens is the
dedicated audit.

## Principles

- **Brevity without loss.** A comment should be the shortest text that still
  carries its rationale. If a sentence can drop without the reader losing
  signal, drop it. Multi-paragraph prose where one line fits is a smell.
- **"Why," not "what."** Well-named identifiers already say what the code does.
  Comments earn their place only when they carry a non-obvious rationale: a
  hidden constraint, a subtle invariant, a workaround for a specific bug,
  behavior that would surprise the reader. Restating the code is noise.
- **No drift-prone anchors.** Comments must not pin themselves to ephemera that
  rots away from the code:
  - PR / issue / ticket numbers without a stable URL — and even those age badly
    inside source.
  - Line-number references (`see foo.py:123`) — the target moves the moment
    someone edits the file.
  - Caller lists (`used by X, Y, Z`) — callers change, the comment doesn't.
  - "Recently added" / "for the new flow" / "temporary until …" without a tied
    removal condition.
  - Author / date attributions (`/* Bob, 2023 */`).

  If the rationale genuinely needs a reference, anchor on stable surfaces: a
  symbol name, an external standard, a public spec URL, an issue body the file
  outlives.

- **No session context.** Comments that narrate this PR, this fix, this rollout
  — `added for the Y flow`, `handles the case from issue #123`,
  `see the design doc on Notion` — belong in the PR description, not the source
  tree. They become noise the moment the PR merges.
- **No misleading or stale comments.** A comment that contradicts the code is
  worse than no comment. Every comment near a changed line must still be true
  after the diff; stale comments next to edited code → flag.
- **Commented-out code is dead.** Delete it. If it might come back, git has it.
  Narrow exception: a one-line "this knob is intentionally off; see
  `<stable anchor>`".
- **TODO / FIXME / XXX / HACK need owner + condition or date.** A bare
  `TODO: fix later` rots; `TODO(orgal, post-v3 migration)` carries enough
  context to either action or remove.
- **No signature-echo docstrings.** A docstring that lists each parameter with
  the type already in the signature, then a sentence per param paraphrasing the
  name, is noise. Keep the docstring for the contract the signature can't carry:
  invariants, side effects, ownership semantics, allowed concurrent callers,
  error modes.
- **Banner / divider noise has no place.** `# ====== HELPERS ======` blocks,
  ASCII boxes, decorative dividers — section structure belongs in identifiers
  and file layout, not in cosmetic comments.
- **Tone discipline.** No "obviously," "simply," "just," apologies, hedges, or
  commentary about the author's mood. A comment is a contract with the next
  reader; commentary about the author's process is not their problem.

## Pattern smells

- Comment paraphrases the function it sits above
  (`# returns true if user is active` above `def is_active_user`).
- TODO without owner or removal condition.
- Block of commented-out code near actively-edited code.
- Comment cites a PR / ticket / line that has nothing pinning it to the comment.
- Docstring repeats every argument from the signature with no added invariant.
- Comment narrates the current PR's intent ("this changes X so Y works") rather
  than the code's intent.

The brief carries the diff's commentary surface — every added or modified
comment, docstring, or inline note with surrounding code context — plus the rule
set above. No forge artifact.

**Severity.** The fix loop (`forge-review-green`) drives only blockers + majors
to zero; minors are noted and survive to merge. So the floor is deliberately not
"everything is minor" — the two failure modes this lens exists to stop,
**drift** and **sustained verbosity**, promote to major so they are actually
forced.

- **Minor** — an isolated, low-rot slip: one redundant line, a lone
  signature-echo param, a banner/divider, a tone word (`just`, `obviously`). One
  comment, no rot vector, reader loses nothing if it ships.
- **Major** — promote when either holds:
  - **Drift-prone anchor.** The comment pins itself to ephemera that rots away
    from the code: a PR/issue/ticket number, a line-number reference
    (`see foo.py:123`), a caller list (`used by X, Y, Z`), a
    session/PR-narration note (`added for the Y flow`,
    `handles the case from #123`), an author/date stamp, or a
    `temporary until …` with no tied removal condition. These mislead the moment
    the surface moves — minor undersells them, and minor means they ship.
  - **Sustained verbosity.** Not one stray line but a _block_ that fails
    brevity: multi-paragraph prose where one line carries the rationale, a
    docstring that paraphrases every signature param with no added invariant, or
    a comment that restates the function it sits above. Volume is the defect;
    one finding covers the block.
- **Blocker** — reserved for the misleading case: a comment that contradicts the
  code beside it or claims behavior the code does not implement, _and_ a future
  reader would rely on it for a correctness decision (e.g.
  `this never returns null` above code that does).

When in doubt between minor and major, ask: _does this rot or mislead, or is it
merely redundant?_ Rot/mislead → major. Merely redundant → minor.
