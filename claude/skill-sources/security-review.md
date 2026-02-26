---
name: security-review
description: Comprehensive security audit covering 10 threat categories
---

**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-25-00-00

# Security Review

Systematic security audit of the repository. Covers the full taxonomy of how repos develop bad security -- from dependency CVEs to AI-agent-specific threats.

Triggered automatically every 3 PRs as part of the assessment waterfall (alongside `/repo-assessment`) or on demand.

## Usage

```bash
/security-review                # Full audit (all 10 categories)
/security-review --quick        # Categories 1-2 only (deps + secrets)
/security-review --focus auth   # Single category deep-dive
```

---

## Threat Taxonomy

The audit covers 10 categories. Each has specific scan steps and patterns.

---

### Category 1: Supply Chain & Dependencies

**How it goes wrong:** A dependency gets a CVE. A transitive dependency you've never heard of is compromised. A typosquatted package slips in. CI actions are pinned to `@main` instead of a SHA.

**Scan:**

1. **Known CVEs in direct + transitive dependencies**
   - Node.js: `npm audit --audit-level=moderate`
   - Python: `pip-audit` (install via `pip install pip-audit`)
   - Go: `govulncheck ./...`
   - Ruby: `bundle-audit check --update`
   - Rust: `cargo audit`

2. **Outdated dependencies** (not yet vulnerable, but risk increases with age)
   - `npm outdated` / `pip list --outdated`
   - Flag anything >6 months behind latest

3. **Lock file integrity**
   - Verify lock files exist (`package-lock.json`, `poetry.lock`, `go.sum`, `Cargo.lock`)
   - Verify lock files are committed (not gitignored)
   - Check for `package-lock.json` vs `yarn.lock` conflicts

4. **Dependency source verification**
   - Check `.npmrc` / `pip.conf` for non-default registries
   - Verify no `--index-url` pointing to untrusted sources
   - Check for `git+` dependencies pointing to arbitrary repos

5. **CI action pinning**
   - Scan `.github/workflows/*.yml` for unpinned actions
   - Flag: `uses: actions/checkout@main` (should be `@v4` or SHA)
   - Flag: `uses: third-party/action@latest`

6. **Dependabot / Renovate configured?**
   - Check for `.github/dependabot.yml` or `renovate.json`
   - Verify it covers all ecosystems in use

**Critical finding:** Known critical CVE in a direct dependency. Stop and alert.

---

### Category 2: Secrets & Credentials

**How it goes wrong:** An API key gets hardcoded "just for testing" and never removed. A `.env` file gets committed. A secret lives in git history even after deletion. AI agents paste tokens into source files.

**Scan:**

1. **Hardcoded secrets in source** (scan all tracked files)

   **Provider-specific patterns (high confidence -- these are never false positives):**

   | Provider | Pattern | Example |
   |----------|---------|---------|
   | **OpenAI** | `sk-proj-[A-Za-z0-9]{20,}` | `sk-proj-abc123...` |
   | **Anthropic** | `sk-ant-[A-Za-z0-9]{20,}` | `sk-ant-api03-...` |
   | **Google/Gemini** | `AIza[A-Za-z0-9_-]{35}` | `AIzaSyC...` |
   | **AWS Access Key** | `AKIA[A-Z0-9]{16}` | `AKIA...` |
   | **AWS Secret Key** | 40-char base64 after `aws_secret` | `wJalrXUtnFEMI/K7MDENG/...` |
   | **GitHub PAT** | `ghp_[A-Za-z0-9]{36}` | `ghp_xxxx...` |
   | **GitHub OAuth** | `gho_[A-Za-z0-9]{36}` | `gho_xxxx...` |
   | **GitHub App** | `ghu_[A-Za-z0-9]{36}` or `ghs_` | `ghu_xxxx...` |
   | **Stripe Live** | `sk_live_[A-Za-z0-9]{24,}` | `sk_live_...` |
   | **Stripe Publishable** | `pk_live_[A-Za-z0-9]{24,}` | `pk_live_...` |
   | **Slack Bot** | `xoxb-[0-9]{10,}-[A-Za-z0-9]{24}` | `xoxb-...` |
   | **Slack User** | `xoxp-[0-9]{10,}-[0-9]{10,}-` | `xoxp-...` |
   | **Twilio** | `SK[a-f0-9]{32}` | `SK...` |
   | **SendGrid** | `SG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}` | `SG.xxx.yyy` |
   | **Mailgun** | `key-[a-f0-9]{32}` | `key-...` |
   | **Firebase** | `AAAA[A-Za-z0-9_-]{7}:[A-Za-z0-9_-]{140}` | `AAAA...` |
   | **Supabase** | `sbp_[a-f0-9]{40}` | `sbp_...` |
   | **Vercel** | `vercel_[A-Za-z0-9]{24}` | `vercel_...` |

   **Generic patterns:**
   - `(api_key|secret|token|password|credential)\s*[=:]\s*["'][^"']{10,}`
   - Private keys: `-----BEGIN (RSA|EC|OPENSSH|PGP) PRIVATE KEY-----`
   - Connection strings: `(mongodb|postgres|mysql|redis)://[^@]+:[^@]+@`
   - Base64-encoded secrets: long base64 strings in config files
   - JWT tokens: `eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}`

2. **Secrets in git history** (even if removed from HEAD)
   - Use `git log --all -p -S 'sk-' --diff-filter=D` to find deleted secrets
   - Check for `.env` files ever committed: `git log --all --diff-filter=A -- '*.env' '.env.*'`
   - Check for key files: `git log --all --diff-filter=A -- '*.pem' '*.key' 'id_rsa'`

3. **Tracked files that shouldn't be**
   - `.env`, `.env.local`, `.env.production`
   - `*.pem`, `*.key`, `id_rsa`, `*.p12`, `*.pfx`
   - `credentials.json`, `service-account.json`
   - `*.sqlite`, `*.db` (may contain user data)

4. **Secrets in CI/CD configs**
   - Scan `.github/workflows/*.yml` for inline secrets (not using `${{ secrets.X }}`)
   - Check for secrets exposed via `echo` or logging in CI scripts
   - Verify `GITHUB_TOKEN` permissions are minimal

5. **Secrets in Docker**
   - `ARG` or `ENV` with secret values in Dockerfiles
   - Secrets copied into images (check COPY/ADD of sensitive files)
   - Multi-stage builds leaking secrets from build stage

6. **Secrets in comments, TODOs, or docs**
   - Grep for patterns like `// placeholder: replace with real key`, `# temp password:`
   - Check README, docs/ for example credentials that are actually real

7. **Secrets in AI agent logs (CRITICAL -- often overlooked)**

   Users paste secrets into Claude/Codex conversations. Agents read `.env` files into context. These get persisted in plaintext log files on disk.

   **Claude conversation logs:**
   ```bash
   # Claude stores full conversation history as JSONL
   # Location: ~/.claude/projects/<project-hash>/*.jsonl
   # Also: ~/.claude/projects/<project-hash>/subagents/*.jsonl

   # Scan for provider-specific patterns in all conversation logs
   grep -rn 'sk-proj-\|sk-ant-\|AKIA\|ghp_\|sk_live_\|AIza' \
     ~/.claude/projects/ 2>/dev/null | head -20

   # Scan for generic secret patterns
   grep -rn 'api_key.*=\|password.*=\|secret.*=\|token.*=' \
     ~/.claude/projects/ 2>/dev/null | grep -v '"type"' | head -20
   ```

   **Claude review logs:**
   ```bash
   # Claude review history
   grep -n 'sk-proj-\|sk-ant-\|AKIA\|ghp_\|sk_live_' \
     ~/.claude/claude-commit-reviews.log 2>/dev/null
   ```

   **Claude file-based debugging:**
   ```bash
   # Temporary files from Claude debugging pattern
   grep -n 'sk-proj-\|sk-ant-\|AKIA\|ghp_\|sk_live_' \
     /tmp/question.txt /tmp/reply.txt 2>/dev/null
   ```

   **If secrets found in logs:**
   - **STOP immediately.** This is Critical severity.
   - **Tell the user:** "Secret detected in conversation logs. Rotate this key immediately. The key has been sent to the AI provider's API and is stored in plaintext on disk."
   - **Recommend:** Delete the affected `.jsonl` files after rotation.
   - **Recommend:** Add sensitive paths to `~/.claude/settings.json` deny list to prevent future reads.

**Critical finding:** Any real secret in HEAD, history, or agent logs. Stop and alert immediately.

**Rule:** NEVER print the actual secret value. Report file, line number, and pattern matched only.

---

### Category 3: Authentication & Authorization

**How it goes wrong:** An endpoint gets added without auth middleware. A role check uses string comparison instead of proper RBAC. JWTs never expire. Rate limiting is missing on login.

**Scan:**

1. **Missing authentication on endpoints**
   - List all route definitions (Express routes, FastAPI endpoints, Django views, etc.)
   - Cross-reference with auth middleware/decorators
   - Flag any public endpoint that handles user data

2. **Broken access control patterns**
   - Check for IDOR vulnerabilities: `req.params.id` used directly without ownership check
   - Look for role checks that compare strings instead of using proper RBAC
   - Check for horizontal privilege escalation (user A accessing user B's data)

3. **JWT security**
   - Verify tokens have expiration (`exp` claim)
   - Check signing algorithm isn't `none` or `HS256` with a weak secret
   - Verify refresh token rotation is implemented
   - Check that JWTs aren't stored in localStorage (XSS risk)

4. **Session management**
   - Session timeout configured?
   - Session invalidation on password change?
   - Session fixation protection?
   - Secure cookie flags (`HttpOnly`, `Secure`, `SameSite`)

5. **Rate limiting**
   - Rate limiting on login/auth endpoints?
   - Rate limiting on password reset?
   - Rate limiting on API endpoints generally?
   - Account lockout after failed attempts?

6. **CSRF protection**
   - CSRF tokens on state-changing requests?
   - SameSite cookie attribute set?
   - Origin/Referer header validation?

**Focus areas by framework:**
- Express/Node: check for `helmet`, `express-rate-limit`, `csurf`/`csrf-csrf`
- FastAPI/Python: check for `slowapi`, auth dependencies, CORS middleware
- Django: check `CSRF_COOKIE_SECURE`, `SESSION_COOKIE_SECURE`, `SECURE_SSL_REDIRECT`
- Next.js: check middleware auth, API route protection, server actions auth

---

### Category 4: Input Validation & Injection

**How it goes wrong:** User input flows into a SQL query, a shell command, an HTML template, or a file path without sanitization. AI-generated code is especially prone to this because models often write the "happy path" without considering malicious input.

**Scan:**

1. **SQL injection**
   - String concatenation in SQL: `f"SELECT * FROM users WHERE id = {user_id}"`
   - Missing parameterized queries
   - ORM raw query methods without parameter binding

2. **Command injection**
   - `exec()`, `eval()`, `child_process.exec()`, `os.system()`, `subprocess.run(shell=True)`
   - Any shell command constructed with user input
   - Template strings in shell commands

3. **Cross-site scripting (XSS)**
   - `dangerouslySetInnerHTML` in React without sanitization
   - `innerHTML` assignments with user data
   - `v-html` in Vue without sanitization
   - Template literals rendered as HTML
   - Missing output encoding

4. **Path traversal**
   - File paths constructed from user input without sanitization
   - `../` sequences not stripped
   - `fs.readFile(req.params.filename)` patterns

5. **Server-side request forgery (SSRF)**
   - URLs from user input passed to `fetch()`, `requests.get()`, `http.get()`
   - Missing allowlist for external URLs
   - Internal network addresses reachable via user-controlled URLs

6. **Unsafe deserialization**
   - `pickle.loads()` with untrusted data (Python)
   - `JSON.parse()` on untrusted input followed by prototype access
   - YAML `load()` instead of `safe_load()` (Python)
   - Java `ObjectInputStream` with untrusted data

7. **Regex denial of service (ReDoS)**
   - Catastrophic backtracking patterns: `(a+)+$`, `(a|a)*$`
   - User input used as regex pattern without escaping

8. **File upload**
   - Missing file type validation (check magic bytes, not just extension)
   - Missing file size limits
   - Uploaded files served from same origin (XSS via SVG/HTML uploads)
   - Missing malware scanning

---

### Category 5: Configuration

**How it goes wrong:** Debug mode ships to production. CORS allows any origin. Security headers are missing. An admin panel is exposed. Error messages leak stack traces.

**Scan:**

1. **Debug/development mode in production configs**
   - `DEBUG = True` (Django), `NODE_ENV !== 'production'`
   - Verbose error pages enabled
   - Source maps served in production
   - GraphQL introspection enabled in production

2. **CORS misconfiguration**
   - `Access-Control-Allow-Origin: *` with credentials
   - Origin reflection (echoing back the Origin header)
   - Overly broad allowed origins

3. **Missing security headers**
   - `Content-Security-Policy`
   - `Strict-Transport-Security` (HSTS)
   - `X-Frame-Options` / `frame-ancestors`
   - `X-Content-Type-Options: nosniff`
   - `Referrer-Policy`
   - `Permissions-Policy`

4. **Exposed endpoints**
   - Admin panels without auth (`/admin`, `/dashboard`, `/debug`)
   - Health/status endpoints leaking system info
   - API documentation accessible in production (`/swagger`, `/docs`, `/graphql`)
   - `.git/` directory in deployment config

5. **TLS/SSL**
   - HTTP endpoints accepting traffic (should redirect to HTTPS)
   - Self-signed certificates in production
   - Weak cipher suites configured

6. **Error handling**
   - Stack traces in error responses
   - Database errors exposed to users
   - Internal paths/versions in error messages

---

### Category 6: Infrastructure

**How it goes wrong:** Docker runs as root. A database port is exposed to the internet. Cloud IAM policies are too permissive. An S3 bucket is public.

**Scan:**

1. **Dockerfile security**
   - Running as root (missing `USER` directive)
   - Using `latest` tag (non-reproducible)
   - Unnecessary packages installed (`curl`, `wget`, `netcat` in production)
   - `--privileged` flag in docker-compose
   - Secrets passed as build args

2. **Docker Compose / orchestration**
   - Internal ports exposed to host (`0.0.0.0:5432:5432` instead of `127.0.0.1:5432:5432`)
   - Missing network isolation between services
   - Volumes mounting sensitive host paths
   - Missing resource limits (memory, CPU)

3. **Cloud configuration (if present)**
   - IaC files (Terraform, CloudFormation) with overly permissive IAM
   - S3 buckets with public access
   - Security groups allowing `0.0.0.0/0` on sensitive ports
   - Missing encryption at rest

4. **File permissions**
   - World-writable files: `find . -type f -perm -o+w`
   - Executable files that shouldn't be: scripts in content directories
   - Config files with secrets readable by all

---

### Category 7: Code Quality (Security-Relevant)

**How it goes wrong:** `Math.random()` generates a session token. Sensitive data gets logged. A race condition allows double-spending. AI models love `eval()`.

**Scan:**

1. **Dangerous function usage**
   - `eval()`, `exec()`, `Function()` constructor
   - `document.write()`
   - `__import__()` with user input
   - `setInterval`/`setTimeout` with string arguments

2. **Insecure randomness**
   - `Math.random()` for security-sensitive values (tokens, IDs, passwords)
   - Python `random` module for cryptographic purposes (should use `secrets`)

3. **Sensitive data in logs**
   - Passwords, tokens, credit card numbers in log statements
   - PII (email, phone, SSN) in log output
   - Request bodies logged without redaction

4. **Cryptography issues**
   - Hardcoded encryption keys or IVs
   - Deprecated algorithms (MD5, SHA1 for security, DES, RC4)
   - ECB mode for block ciphers
   - Missing salt in password hashing

5. **Race conditions**
   - Check-then-act patterns without locking
   - Non-atomic read-modify-write on shared resources
   - Double-submit vulnerabilities in payment/transaction code

6. **Error handling that leaks information**
   - Catch blocks that expose internal state
   - Different error messages for "user exists" vs "wrong password" (user enumeration)

---

### Category 8: AI/Agent-Specific Threats

**How it goes wrong:** An AI agent has access to production secrets. LLM output gets injected into a SQL query. A prompt injection in user content causes the agent to exfiltrate data. AI-generated code has subtle vulnerabilities the model doesn't recognize.

**This category is unique to AI-assisted development and is often missed by traditional security tools.**

**Scan:**

1. **Agent permission scope**
   - What files can the agent read/write? Are production secrets accessible?
   - Check `~/.claude/settings.json` deny list -- is it comprehensive?
   - Are `.env` files, credential stores, SSH keys accessible to the agent?
   - Can the agent execute arbitrary commands? What's blocked?

2. **LLM output used in dangerous contexts**
   - AI-generated strings inserted into SQL queries
   - AI-generated strings used in shell commands
   - AI-generated HTML rendered without sanitization
   - AI-generated code `eval()`'d at runtime

3. **Prompt injection surface**
   - User-facing content that gets included in AI prompts
   - Database fields that flow into prompt context
   - File names or contents that could manipulate agent behavior
   - API responses that get fed to the agent

4. **Context window data exposure**
   - Secrets read into the context window get sent to the AI provider's API
   - Sensitive code reviewed by the agent is transmitted externally
   - Conversation history may contain credentials from debugging sessions

5. **AI-generated code vulnerability patterns**
   - Models tend to: skip input validation, use string concatenation for SQL, omit error handling, hardcode example credentials, use insecure defaults
   - Review AI-generated code with extra scrutiny for Categories 3-4 patterns
   - Check if tests actually test security-relevant edge cases (not just happy path)

6. **Agent action guardrails**
   - Can the agent bypass git hooks (`--no-verify`)?
   - Can the agent force-push to main?
   - Can the agent delete branches, files, or data?
   - Can the agent modify its own configuration (CLAUDE.md, settings)?

---

### Category 9: CI/CD Pipeline

**How it goes wrong:** A GitHub Action runs with `write` permissions when it only needs `read`. A workflow trigger on `pull_request_target` lets external PRs execute code with repo secrets. Secrets appear in CI logs.

**Scan:**

1. **GitHub Actions permissions**
   - Check for `permissions: write-all` or missing permissions block (defaults to write)
   - Each workflow should declare minimal permissions
   - `GITHUB_TOKEN` permissions should be scoped

2. **Workflow injection**
   - `pull_request_target` trigger with `actions/checkout` of PR code (code injection)
   - Expression injection: `${{ github.event.issue.title }}` in `run:` blocks
   - Untrusted input in workflow names, labels, or branch names

3. **Action pinning**
   - Actions pinned to SHA vs tag vs branch
   - Third-party actions from untrusted authors
   - Forked actions diverging from upstream

4. **Secret handling in CI**
   - Secrets echoed in logs (`echo $SECRET` or debug logging)
   - Secrets passed as command-line arguments (visible in process list)
   - Secrets available to steps that don't need them

5. **Artifact security**
   - Build artifacts uploaded without integrity verification
   - Docker images pushed without signing
   - Release artifacts without checksums

---

### Category 10: Process & Governance

**How it goes wrong:** There's no CODEOWNERS file so anyone can merge anything. Branch protection is off. There's no audit log. Nobody knows the incident response process because there isn't one.

**Scan:**

1. **Branch protection**
   - Run `scripts/validate-github-protection.sh`
   - Verify: PR required, external approval, no self-approve, squash-only, no force-push
   - Verify no bypass actors configured

2. **CODEOWNERS**
   - `.github/CODEOWNERS` exists?
   - Security-critical paths have explicit owners?
   - `require_code_owner_review` enabled in ruleset?

3. **Audit logging**
   - Authentication events logged?
   - Authorization failures logged?
   - Data access/modification logged?
   - Admin actions logged?

4. **Security documentation**
   - Threat model exists? (`docs/rules/trust-model.md` or similar)
   - Data classification documented?
   - Security contact documented? (`SECURITY.md`)

5. **Dependency management**
   - Dependabot or Renovate configured?
   - Covering all ecosystems in use?
   - Auto-merge for patch versions?

6. **Settings and deny list**
   - Verify `~/.claude/settings.json` blocks dangerous commands
   - Verify git hooks are installed and executable
   - Verify pre-commit hook catches secrets

---

## Execution Flow

### Full Audit

Run all 10 categories in order. For each:

1. Run the scans listed
2. Record findings with severity (Critical / High / Medium / Low / Info)
3. Move to the next category
4. At the end, produce the report

### Quick Audit (`--quick`)

Run only Categories 1-2 (dependencies + secrets). Takes <2 minutes.

### Focused Audit (`--focus <category>`)

Deep-dive a single category. Options: `deps`, `secrets`, `auth`, `injection`, `config`, `infra`, `code`, `ai`, `cicd`, `governance`.

---

## Severity Levels

| Level | Meaning | Action |
|---|---|---|
| **Critical** | Active exploitation risk. Leaked secrets, RCE, auth bypass. | Stop. Alert human immediately. Do not continue audit. |
| **High** | Exploitable with moderate effort. Known CVEs, SQL injection, missing auth. | Flag for immediate fix. Block PR if in pre-push. |
| **Medium** | Exploitable with specific conditions. Weak crypto, missing headers, debug mode. | Flag for fix in current sprint. |
| **Low** | Defense-in-depth gap. Missing rate limiting, verbose errors, outdated deps. | Track for future fix. |
| **Info** | Observation. Missing best practice, potential improvement. | Document. |

---

## Report Format

```markdown
## Security Review - [date]

**Scope:** Full audit / Quick / Focus: [category]
**Repository:** [repo name]
**Branch:** [current branch]

### Critical Findings
- [None / list with file:line and description]

### Summary by Category

| # | Category | Findings | Severity |
|---|----------|----------|----------|
| 1 | Supply Chain | X issues | highest severity |
| 2 | Secrets | X issues | highest severity |
| 3 | Auth & Access | X issues | highest severity |
| 4 | Input Validation | X issues | highest severity |
| 5 | Configuration | X issues | highest severity |
| 6 | Infrastructure | X issues | highest severity |
| 7 | Code Quality | X issues | highest severity |
| 8 | AI/Agent Security | X issues | highest severity |
| 9 | CI/CD Pipeline | X issues | highest severity |
| 10 | Governance | X issues | highest severity |

### Detailed Findings

#### [Category Name]

**[SEVERITY] [Finding title]**
- File: `path/to/file.ts:42`
- Pattern: [what was detected]
- Risk: [what could happen]
- Fix: [specific remediation]

### Action Items (Priority Order)

1. [Critical/High items first]
2. [Medium items]
3. [Low items for backlog]

### Positive Findings

- [Things that are done well -- reinforcement matters]
```

---

## Rules

1. **NEVER print actual secret values.** File + line number + pattern type only.
2. **On Critical findings: stop audit and alert immediately.** Don't continue.
3. **Don't auto-fix security issues.** Report for human review. Security fixes need careful thought.
4. **Adapt to the stack.** Only run scans relevant to the languages/frameworks in the repo.
5. **Check for false positives.** Test fixtures, example configs, and documentation may contain patterns that look like secrets but aren't. Note these as Info, not High.
6. **Category 8 (AI/Agent) is not optional.** This is unique to our workflow and missed by every traditional scanner.

## Priority Order

**Security's #1 job: protect the main branch.** Everything else is secondary. If branch protection is misconfigured, fix that before anything else.

**#2: Secrets never get recorded anywhere.** Not in source, not in git history, not in agent logs. If a secret is found anywhere, the immediate action is rotation -- not cleanup.

## Deterministic Tooling

For Categories 1-2, use the deterministic scanner:

```bash
# Quick: repo working tree only
scripts/scan-secrets.sh

# Full: also scan git history
scripts/scan-secrets.sh --history

# Everything: repo + history + agent conversation logs
scripts/scan-secrets.sh --all
```

This script uses exact regex patterns for all major providers (OpenAI, Anthropic, Google, AWS, GitHub, Stripe, Slack, etc.) and scans Claude/Codex log files at `~/.claude/projects/`. No false negatives for known key formats.

The pre-push hook runs a lightweight version of this on every push. The full script runs as part of the periodic security review.

## Next Steps

If Critical or High findings were reported, run `/redteam` to verify exploitability.
Pattern-matching finds possibilities; red teaming confirms realities.

## Related

- `/redteam` -- Active exploit verification (confirms or disproves findings from this review)
- `docs/rules/trust-model.md` -- Trust boundaries and zero-trust philosophy
- `scripts/scan-secrets.sh` -- Deterministic secret scanner (standalone)
- `/repo-assessment` -- General code quality (runs at the same cadence)
- Pre-push hook -- Runs lightweight Category 1-2 checks on every push
- `.github/dependabot.yml` -- Automated dependency updates (Category 1 prevention)
- `.github/CODEOWNERS` -- Code ownership enforcement (Category 10)
