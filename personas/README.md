# Reviewer personas

A persona is a named reviewer profile that `/forge-review` and
`/forge-review-green` can layer on top of the always-on lens baseline. It
contributes a `lenses:` list (union'd with the baseline) plus a description of
what that reviewer cares about and how they phrase findings.

Forge ships one generic persona (`default.md`). A host repo can add its own —
either here (if forking the plugin) or, without touching the plugin, in
`.forge/personas/*.md`. Forge reads both locations; `.forge/` wins on id clash.

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
/ area). The bundled pool only ships `default`; add personas matching the
surfaces your repo reviews most — e.g. a backend persona for service code, a
security persona for trust-boundary changes, a frontend persona for UI work.
Until one exists, forge falls back to `default`.
