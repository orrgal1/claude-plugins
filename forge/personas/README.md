# Reviewer personas

A persona is a named reviewer profile that `/forge-review` and
`/forge-review-green` can layer on top of the always-on lens baseline. It
contributes a `lenses:` list (union'd with the baseline) plus a description of
what that reviewer cares about and how they phrase findings.

Forge bundles **no** persona. The no-persona default is the tiered lens baseline
(`review-channels/lens-fanout.md` § Selection) — a persona only ever _adds_
lenses on top, so "no persona" already runs the right set. A host repo adds its
own in `$FORGE_HOME/personas/*.md` (or `.forge/personas/*.md`) when it wants
emphasis beyond the baseline.

## Schema

```markdown
---
id: backend-senior
name: Senior backend reviewer
lenses: [correctness, robustness, observability, api-design]
---

# Senior backend reviewer

<What this reviewer cares about, recurring smells they catch, tone. Free prose.>
```

| Field    | Meaning                                                                                            |
| -------- | -------------------------------------------------------------------------------------------------- |
| `id`     | Slug, matches filename. Passed via `--persona <id>`.                                               |
| `name`   | Human label shown at the consultation gate.                                                        |
| `lenses` | Pool lens ids to add to the baseline. Every id must exist in the lens pool (bundled or `.forge/`). |

## Adding a persona for a surface

`/forge-review-green` suggests a persona by diff fingerprint (dominant language
/ area). With none bundled, add personas matching the surfaces your repo reviews
most — e.g. a backend persona for service code, a frontend persona for UI work.
Until one exists (or when none matches), forge runs the baseline only — no
persona.
