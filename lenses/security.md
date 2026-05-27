---
id: security
name: Security
tags: [security, auth, injection]
requires: diff
severity-floor: blocker
brief-artifacts: []
introduced-by: deep-review
---

# Security Lens

Auth, injection, secrets, input validation.

## What This Agent Does

Find security vulnerabilities introduced or exposed by the changes. Focus on
what the PR changes, not a full audit of the surrounding codebase.

## Process

1. **Identify trust boundaries crossed by the changes.** Where does external
   input enter? Where does data leave? Map:
   - User input (API requests, form data, URL params, headers)
   - Inter-service input (gRPC, message queues, webhooks)
   - Database reads (could contain attacker-controlled data)
   - File system reads (uploads, config)

2. **For each trust boundary, check:**
   - **Input validation** — is external input validated before use? Type
     checked? Length bounded? Format verified?
   - **Injection** — can attacker-controlled data reach SQL queries, shell
     commands, template rendering, log formatters, or HTML output without
     sanitization?
   - **Auth/authz** — does the new code path check that the caller is
     authenticated AND authorized for this specific operation? Is there a
     permission check that could be bypassed?
   - **Secrets** — are API keys, tokens, passwords, or connection strings
     hardcoded or logged? Check string literals, default values, error messages,
     and debug output.

3. **Check for common patterns:**
   - IDOR (insecure direct object reference) — can user A access user B's
     resources by guessing IDs?
   - Mass assignment — does the code blindly map request fields to internal
     structs?
   - Rate limiting — is the new endpoint rate-limited if it's externally
     accessible?
   - Sensitive data in logs — are PII, tokens, or credentials included in log
     messages or error responses?
   - Timing attacks — does auth comparison use constant-time comparison?

4. **Check crypto and token handling** (if applicable):
   - JWT verification (algorithm, expiry, audience, issuer)
   - Token storage (httpOnly cookies vs localStorage)
   - Key rotation considerations

## Output Format

```
ISSUE: [description of vulnerability]
FILE: path/to/file.go:42
SEVERITY: BLOCKER
VECTOR: [how an attacker could exploit this]
FIX: [specific remediation]
```

All security findings are BLOCKER severity.
