---
name: publish-repo
description: Prepare a repo for public release on GitHub. Scans for secrets, cleans dead code, updates docs, verifies LICENSE, and pushes to public remote.
---

**Created:** 2026-03-07-00-00
**Last Updated:** 2026-03-07-00-00

# Publish Repo

Prepare and publish a repository for public visibility on GitHub.

## Step 1: Security Scan

Run `/security-review` first. This is non-negotiable for public repos.

Pay special attention to:
- **Hardcoded secrets** (API keys, tokens, passwords in source or config)
- **`.env` files** checked into git history (even if gitignored now)
- **Personal data** (email addresses, file paths with usernames, internal URLs)
- **Internal references** (private repo URLs, internal tool names, internal docs)

```bash
# Check git history for secrets that were committed then removed
git log --all --diff-filter=D -- '*.env' '.env*' '*.key' '*.pem' 2>/dev/null
git log --all -p -- '*.env' 2>/dev/null | head -50

# Check for personal paths in code
grep -r "$HOME" . --include='*.{js,ts,py,go,rs,sh}' 2>/dev/null || true
grep -r "/Users/" . --include='*.{js,ts,py,go,rs,sh}' 2>/dev/null || true
```

If secrets are found in git history, the user must decide whether to rewrite history or accept the risk. Do NOT rewrite history without explicit approval.

## Step 2: Clean Dead Code

Look for:
- Unused files (test data, scratch scripts, debug utilities)
- Empty directories
- Commented-out blocks of code (>10 lines)
- Files referenced nowhere in imports

Remove only what is clearly dead. When in doubt, leave it.

## Step 3: Documentation Check

Verify these exist and are current:

1. **README.md** — Has: project description, how to install, how to run, how to contribute
2. **LICENSE** — Exists and is a recognized open-source license
3. **.gitignore** — Covers common patterns for the project's language

```bash
# Check for README
[ -f "README.md" ] && echo "README exists" || echo "MISSING: README.md"

# Check for LICENSE
[ -f "LICENSE" ] || [ -f "LICENSE.md" ] && echo "LICENSE exists" || echo "MISSING: LICENSE"

# Check gitignore
[ -f ".gitignore" ] && echo ".gitignore exists" || echo "MISSING: .gitignore"
```

If README is outdated or missing, update it to reflect current project state. Don't over-document — keep it practical.

## Step 4: Final Review

Before pushing, show the user a summary:
```
Ready to publish:
  Repo: {name}
  Remote: {github URL}
  Branch: {branch}
  Files: {count}
  Security: {pass/fail with details}
  README: {present/updated}
  LICENSE: {present/type}

Issues found: {list any remaining concerns}
```

Wait for user confirmation before pushing.

## Step 5: Push

```bash
# Set remote if not already configured
git remote get-url origin 2>/dev/null || git remote add origin {user-provided URL}

# Push
git push -u origin main
```

## Step 6: Verify

```bash
# Confirm the repo is accessible
gh repo view --json name,visibility,url
```

Report the public URL to the user.
