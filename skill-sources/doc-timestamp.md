---
name: doc-timestamp
description: Add or update datetime timestamps in documentation files
---

**Created:** 2026-02-02-12-00
**Last Updated:** 2026-02-11-20-00

# Documentation Timestamp Management

All documentation must include creation and last updated timestamps. This command helps manage those timestamps.

## Get Current Timestamp

Always use this format:
```bash
date +"%Y-%m-%d-%H-%M"
```

## For New Documentation Files

When creating a new doc, include at the top:

```markdown
# Document Title

**Created:** $(date +"%Y-%m-%d-%H-%M")
**Last Updated:** $(date +"%Y-%m-%d-%H-%M")

[rest of content]
```

## For Updating Existing Documentation

When editing any doc:

1. **Read the current file** to get the Created date
2. **Update the Last Updated line** with current timestamp:
   ```markdown
   **Last Updated:** 2026-01-30-16-27
   ```
3. **Keep the Created date** unchanged

## Bulk Timestamp Check

To find docs missing timestamps:

```bash
# Find markdown files without "Created:" or "Last Updated:"
find . -name "*.md" -type f -exec grep -L "Created:" {} \; 2>/dev/null
find . -name "*.md" -type f -exec grep -L "Last Updated:" {} \; 2>/dev/null
```

## Pre-PR Documentation Audit

Before submitting any PR, verify:

1. **All modified docs have updated timestamps**
   ```bash
   # Get list of modified markdown files in current branch
   git diff --name-only main...HEAD | grep "\.md$"
   ```

2. **For each modified doc:**
   - Verify "Last Updated" timestamp is recent
   - Verify content is accurate and not stale
   - Delete doc if no longer relevant

3. **Check for stale docs**
   - Docs with old "Last Updated" dates that weren't modified
   - May need updating or deletion if related to PR changes

## Example: Good Documentation Header

```markdown
# Authentication System Documentation

**Created:** 2026-01-15-14-30
**Last Updated:** 2026-01-30-16-27

This document describes the authentication flow for the application.

## Overview
[content]
```

## Automation

The pre-commit hook already warns about stale timestamps on modified `.md` files. No manual checking needed.
