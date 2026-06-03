---
id: ai-slop
name: AI Slop
tags: [ai-slop, hygiene, code-quality]
requires: diff
severity-floor: blocker
brief-artifacts: []
introduced-by: deep-review
---

# AI Slop Lens

Detect unreviewed AI-generated patterns: narration comments, defensive
over-engineering, type escapes. They waste reviewer time and signal the author
didn't evaluate the output.

## Process

1. **Comments that narrate the code:**
   - `// check if valid` above `if isValid`
   - `// return the result` above `return result`
   - `// create a new instance` above a constructor call
   - `// handle error` above an error handler
   - Any comment restating the next line without adding why
   - Any comment spanning multiple lines where one line (or none) suffices

   **Exception — meaningful comments are NOT slop.** Skip any comment that (a)
   explains genuine _why_ / non-obvious _how_ / a hidden constraint or
   invariant, (b) starts with `when:` or `then:` (test scenario/outcome tags),
   or (c) is an AAA phase marker `// --- arrange` / `// --- act` /
   `// --- assert`. Only flag free-floating narration restating the code. Even a
   meaningful comment stays one line — the `commentary` lens owns the cap (one
   line; two only with sign-off) and its severity.

2. **Redundant defensive checks:**
   - Nil check after a function guaranteeing non-nil on success
   - Type assertion after a type switch already narrowed the type
   - Length check after a function documented to return non-empty
   - Duplicate validation across layers without justification
   - Error wrapping adding "failed to X" without new context

3. **Type escapes without justification:**
   - `any` / `interface{}` where a concrete type/interface exists
   - `map[string]any` where a struct should be used
   - Unsafe type assertions without checking ok
   - `Mapping[str, Any]` in Python where a Pydantic model fits

4. **Over-engineering:**
   - Abstractions for a single use case (helper called once)
   - Config for values that never change
   - Factory patterns where a constructor suffices
   - Backwards-compat shims for unreleased code

5. **Test slop:**
   - Tests asserting only "no error" without checking the result
   - Getter/setter tests verifying nothing meaningful
   - Test names that don't describe the scenario
   - Parametrized tests where a single case covers the logic

6. **Structural slop:**
   - `map[T]bool` instead of `mapset.Set`
   - Manual mocks where generated mocks/interfaces exist
   - `assert` instead of `require` in Go tests (continues after failure)
   - Empty catch/except blocks

## Output Format

```
ISSUE: [description of slop pattern]
FILE: path/to/file.go:42
PATTERN: NARRATION | REDUNDANT_CHECK | TYPE_ESCAPE | OVER_ENGINEERING | TEST_SLOP | STRUCTURAL
DETAIL: [what's wrong, what it should be instead]
```

All AI slop findings are BLOCKER. If the repo has an automated slop/lint pass,
run it first — this lens catches what such tools miss.
