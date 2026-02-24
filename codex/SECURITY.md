**Created:** 2026-02-19-00-00
**Last Updated:** 2026-02-19-00-00

# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| main (latest) | Yes |

## Reporting a Vulnerability

If you discover a security vulnerability in CrossCheck, please report it responsibly:

1. **Do NOT open a public issue.** Security vulnerabilities disclosed publicly put all users at risk.

2. **Use GitHub Security Advisories:** Go to [Security > Advisories > New draft advisory](https://github.com/sburl/CrossCheck/security/advisories/new) to report privately.

3. **Or email:** spence.burleigh@gmail.com with subject line `[SECURITY] CrossCheck: <brief description>`

## What to Include

- Description of the vulnerability
- Steps to reproduce
- Affected files/components
- Potential impact
- Suggested fix (if any)

## Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial assessment:** Within 1 week
- **Fix or mitigation:** Depends on severity, targeting within 2 weeks for High/Critical

## Scope

CrossCheck is a developer workflow tool (git hooks, shell scripts, CLI skills). Security-relevant areas include:

- **Settings deny list** (`settings.template.json`) — command blocking rules
- **Git hooks** (`git-hooks/`) — pre-commit, pre-push enforcement
- **Secret scanning** (`scripts/scan-secrets.sh`) — credential detection
- **Bootstrap script** (`scripts/bootstrap-crosscheck.sh`) — installation security
- **Trust model** (`docs/rules/trust-model.md`) — agent permission boundaries

## Known Limitations

Documented in `docs/rules/trust-model.md`:

- General-purpose runtimes (python3, node) can bypass the deny list
- The "Codex Approved" commit gate is advisory, not cryptographic
- Server-side GitHub branch protection is the real security boundary
