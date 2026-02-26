---
name: redteam
description: Active exploit verification — writes and runs throwaway exploit tests to confirm or disprove security findings
---

**Created:** 2026-02-25-00-00
**Last Updated:** 2026-02-25-00-00

# Red Team

Active exploit verification for security findings. Instead of pattern-matching (like `/security-review`), this skill writes and executes throwaway exploit tests to confirm or disprove vulnerabilities.

Use after `/security-review` to verify Critical/High findings, or standalone for targeted exploit testing.

## Usage

```bash
/redteam                    # Full verification (all 8 categories)
/redteam --quick            # Categories 1-2 only (injection + auth bypass). ~5 min.
/redteam --focus injection  # Single category deep-dive
```

---

## Exploit Categories

---

### Category 1: Injection Verification

**Technique:** Import target module, pass SQL/command/path traversal payloads, check if processed unsafely.

**Exploits:**
1. SQL injection: Pass `' OR 1=1--`, `'; DROP TABLE users--`, `1 UNION SELECT * FROM credentials` to database-facing functions
2. Command injection: Pass `; cat /etc/passwd`, `$(whoami)`, `` `id` `` to functions that build shell commands
3. Path traversal: Pass `../../../etc/passwd`, `....//....//etc/passwd`, `%2e%2e%2f` to file-serving functions
4. Template injection: Pass `{{7*7}}`, `${7*7}`, `<%= 7*7 %>` to template-rendering functions
5. Header injection: Pass `\r\nX-Injected: true` to functions that set HTTP headers

**Verification:** If the payload is processed without sanitization (query executes, file is read, command runs), the finding is CONFIRMED.

---

### Category 2: Auth Bypass

**Technique:** Call authenticated handlers without auth, with expired auth, or with another user's credentials.

**Exploits:**
1. Missing auth: Call endpoint handler directly without auth middleware/context
2. Expired token: Forge a JWT with `exp` in the past, verify it's still accepted
3. Wrong user: Use User A's token to access User B's resources (IDOR)
4. Role escalation: Use a `viewer` role token on an `admin` endpoint
5. CSRF: Submit state-changing request without CSRF token

**Verification:** If the handler returns success (200/201) or modifies data without valid auth, the finding is CONFIRMED.

---

### Category 3: Secret Confirmation

**Technique:** Verify that detected secret patterns are real credentials, not test fixtures or examples.

**Checks:**
1. Entropy analysis: Real secrets have high entropy (>3.5 bits/char). Test strings like `sk-test-12345` are low entropy.
2. Format validation: Match exact provider format (e.g., GitHub PAT is exactly `ghp_` + 36 alphanumeric chars)
3. Context analysis: Is the string in a test fixture, example config, or documentation? If so, likely not real.
4. Prefix check: `sk-test-`, `pk-test-`, `fake-`, `example-` prefixes indicate test values
5. Git blame: Was it added in a "test" or "example" commit?

**Verification:** If the secret matches provider format, has high entropy, and is not in a test context, it is CONFIRMED as a real credential.

---

### Category 4: SSRF/Redirect

**Technique:** Pass internal URLs and metadata endpoints to fetch/request functions.

**Exploits:**
1. Localhost: Pass `http://127.0.0.1`, `http://localhost`, `http://[::1]` to URL-accepting functions
2. Cloud metadata: Pass `http://169.254.169.254/latest/meta-data/` (AWS), `http://metadata.google.internal/` (GCP)
3. Internal network: Pass `http://10.0.0.1`, `http://192.168.1.1` to verify internal network access
4. DNS rebinding: Pass a domain that resolves to `127.0.0.1`
5. Protocol smuggling: Pass `file:///etc/passwd`, `gopher://`, `dict://` to URL handlers

**Verification:** If the function makes the request without URL validation/allowlisting, the finding is CONFIRMED.

---

### Category 5: Deserialization

**Technique:** Pass crafted payloads to deserialization functions.

**Exploits:**
1. Python pickle: Pass `pickle.loads()` a crafted payload that would execute `os.system()` (verify the function accepts arbitrary bytes, don't actually execute)
2. YAML unsafe load: Pass `!!python/object/apply:os.system ['echo pwned']` to `yaml.load()` (without SafeLoader)
3. JSON prototype pollution: Pass `{"__proto__": {"isAdmin": true}}` to JSON merge/assign functions
4. XML external entities: Pass `<!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>` to XML parsers
5. Java ObjectInputStream: Verify untrusted data flows into `ObjectInputStream.readObject()`

**Verification:** If the deserializer processes the payload without safe loading/validation, the finding is CONFIRMED.

---

### Category 6: Crypto Weakness

**Technique:** Verify weak algorithm constants, key lengths, and IV reuse.

**Checks:**
1. Algorithm verification: Confirm use of MD5/SHA1 for security purposes (not just checksums)
2. Key length: Verify RSA keys < 2048 bits, AES keys < 128 bits
3. IV reuse: Check if the same initialization vector is used across multiple encryptions
4. ECB mode: Verify block cipher is using ECB (patterns preserved)
5. Hardcoded keys: Verify encryption key is a constant, not derived from secure source
6. `Math.random()`/`random.random()`: Verify used for security-sensitive values (tokens, session IDs)

**Verification:** Write a test that instantiates the crypto function and asserts the weak parameter. If the assertion passes, the finding is CONFIRMED.

---

### Category 7: Race Condition

**Technique:** Fire N parallel calls and check for data corruption or double-processing.

**Exploits:**
1. Counter increment: Call increment function 100 times concurrently, verify final count equals 100
2. Balance deduction: Submit 10 concurrent withdrawals of $10 from a $50 balance, verify balance doesn't go negative
3. Unique constraint: Create 100 concurrent records with the same unique key, verify only 1 succeeds
4. File write: Write to the same file from 10 concurrent calls, verify no data corruption
5. Cache stampede: Invalidate cache and send 100 concurrent requests, verify only 1 cache rebuild

**Verification:** Use `Promise.all` (JS), `asyncio.gather` (Python), or `sync.WaitGroup` (Go) to fire concurrent calls. If the result is inconsistent across runs, the finding is CONFIRMED.

---

### Category 8: Config Exposure

**Technique:** Check for debug endpoints, admin panels, and verbose errors accessible without auth.

**Checks:**
1. Debug endpoints: Check if `/debug`, `/_debug`, `/debug/pprof` are accessible
2. Admin panels: Check if `/admin`, `/dashboard`, `/internal` respond without auth
3. API docs in prod: Check if `/swagger`, `/docs`, `/graphql` (with introspection) are accessible
4. Verbose errors: Send a malformed request and check if stack traces are returned
5. Environment leaks: Check if `/health`, `/status`, `/info` expose environment variables or versions

**Verification:** If the endpoint returns sensitive information without authentication, the finding is CONFIRMED.

---

## Execution Flow

1. **Detect language/framework** (package.json, pyproject.toml, go.mod, etc.)
2. **Accept input:** Parse `/security-review` findings OR do quick standalone scan
3. **Filter** to Critical/High findings only
4. For each finding:
   a. Write throwaway exploit test: `__redteam_exploit_<N>.test.{ts,py,go}`
   b. Run with project's test runner
   c. Record: **CONFIRMED** / **DISPROVED** / **INCONCLUSIVE**
5. **Cleanup:** Delete ALL `__redteam_exploit_*` files
6. **Verify cleanup:** Run `git status` to confirm no artifacts remain
7. **Generate report**

---

## Modes

- `--quick`: Categories 1-2 only (injection + auth bypass). ~5 min.
- `--focus <cat>`: Single category. Options: `injection`, `auth`, `secrets`, `ssrf`, `deserialization`, `crypto`, `race`, `config`.
- Full (no flags): All 8 categories. 15-30 min.

---

## Rules

1. **NEVER commit exploit code.** Write -> run -> report -> delete.
2. **NEVER test against production or external systems.** Local code and modules only.
3. **NEVER exfiltrate data.** Verify vulnerability exists, don't extract real data.
4. **Delete all `__redteam_*` artifacts on completion.** Verify with `git status`.
5. **If CONFIRMED, escalate to Critical** regardless of original severity.
6. **Include exploit evidence in report** (what was tested, what happened, why it confirms the finding).

---

## Report Format

```markdown
## Red Team Report - [date]

**Scope:** Full / Quick / Focus: [category]
**Input:** /security-review findings / standalone scan
**Findings tested:** N Critical/High

### Summary

| # | Finding | Category | Original Severity | Result | New Severity |
|---|---------|----------|------------------|--------|-------------|
| 1 | SQL injection in user query | Injection | High | CONFIRMED | Critical |
| 2 | Missing auth on /admin | Auth | High | DISPROVED | Low |

### Confirmed Vulnerabilities

**[CRITICAL] SQL injection in user query**
- File: `src/db/users.ts:42`
- Exploit: Passed `' OR 1=1--` to `findUser()`, query returned all users
- Impact: Full database read access via user input
- Fix: Use parameterized queries

### Disproved Findings

**[DOWNGRADED: High -> Low] Missing auth on /admin**
- Original finding: `/admin` endpoint has no auth middleware
- Test result: Endpoint returns 404 in production config (only registered in dev)
- New assessment: Low risk (dev-only route)

### Inconclusive

- [Findings that couldn't be verified with available context]

### Cleanup Verification

- `__redteam_exploit_*` files: 0 remaining
- `git status`: clean (no untracked exploit artifacts)
```

---

## Related

- `/security-review` -- Pattern-matching security audit (run first, then `/redteam` to verify)
- `/bug-review --reproduce` -- Bug reproduction (similar approach for correctness bugs)
- `/fuzz` -- Property-based testing (complements red teaming with random inputs)
