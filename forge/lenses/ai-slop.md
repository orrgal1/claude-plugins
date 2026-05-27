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

Narration comments, defensive over-engineering, type escapes.

## What This Agent Does

Detect patterns that indicate AI-generated code that wasn't reviewed. These
patterns waste reviewer time, add noise, and signal that the author didn't
critically evaluate the generated output.

## Process

1. **Comments that narrate the code:**
   - `// check if valid` above an `if isValid` check
   - `// return the result` above a `return result`
   - `// create a new instance` above a constructor call
   - `// handle error` above an error handler
   - Any comment that restates what the next line does without adding why

   **Exception — meaningful comments are NOT slop.** Skip any comment that (a)
   explains genuine _why_ / non-obvious _how_ / a hidden constraint or
   invariant, (b) starts with `when:` or `then:` (test scenario/outcome tags),
   or (c) is an AAA phase marker `// --- arrange` / `// --- act` /
   `// --- assert`. These are intentional review aids. Only flag free-floating
   narration that restates the code without adding information.

2. **Redundant defensive checks:**
   - Nil check after a function that guarantees non-nil return on success
   - Type assertion after a type switch that already narrowed the type
   - Length check after a function documented to return non-empty
   - Duplicate validation at multiple layers without justification
   - Error wrapping that just adds "failed to X" without new context

3. **Type escapes without justification:**
   - `any` / `interface{}` where a concrete type or interface exists
   - `map[string]any` where a struct should be used
   - Unsafe type assertions without checking the ok value
   - `Mapping[str, Any]` in Python where a Pydantic model should be used

4. **Over-engineering:**
   - Abstractions for a single use case (helper function called once)
   - Configuration for values that will never change
   - Factory patterns where a constructor suffices
   - Backwards-compatibility shims for code not yet released

5. **Test slop:**
   - Tests that assert only "no error" without checking the result
   - Getter/setter tests that verify nothing meaningful
   - Test names that don't describe the scenario
   - Parametrized tests where a single case covers the logic

6. **Structural slop:**
   - `map[T]bool` instead of `mapset.Set`
   - Manual mocks where generated mocks or interfaces exist
   - `assert` instead of `require` in Go tests (test continues after failure)
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
