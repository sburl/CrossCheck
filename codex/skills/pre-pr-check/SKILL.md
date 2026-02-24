---
name: pre-pr-check
description: Comprehensive pre-PR checklist - actually runs checks
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-12-12-00

# Pre-PR Check (Automated)

Comprehensive pre-PR checks that actually RUN, not just checklist items.

## Usage

```bash
/pre-pr-check
```

**This skill automatically:**
1. Runs all tests
2. Runs linting
3. Checks documentation timestamps
4. Verifies critical files updated
5. Reports pass/fail for each check

## Execution Protocol

When `/pre-pr-check` is invoked, Codex runs these checks:

### Step 1: Run Tests

```bash
echo "🧪 Running tests..."

# Detect test command from package.json or common patterns
if [ -f "package.json" ] && grep -q "\"test\":" package.json; then
  npm test
  TEST_EXIT=$?
elif [ -f "pytest.ini" ] || [ -f "pyproject.toml" ]; then
  pytest
  TEST_EXIT=$?
elif [ -f "Cargo.toml" ]; then
  cargo test
  TEST_EXIT=$?
else
  echo "⚠️  No test command found (skipping)"
  TEST_EXIT=0
fi

if [ $TEST_EXIT -eq 0 ]; then
  echo "✅ Tests passed"
  TESTS_PASS=true
else
  echo "❌ Tests failed"
  TESTS_PASS=false
fi
```

### Step 2: Run Linting

```bash
echo ""
echo "🔍 Running linting..."

# JavaScript/TypeScript
if [ -f "package.json" ] && grep -q "\"lint\":" package.json; then
  npm run lint
  LINT_EXIT=$?
# Python
elif command -v ruff &> /dev/null; then
  ruff check .
  LINT_EXIT=$?
elif command -v pylint &> /dev/null; then
  find . -name "*.py" -type f -exec pylint {} +
  LINT_EXIT=$?
# Rust
elif [ -f "Cargo.toml" ]; then
  cargo clippy
  LINT_EXIT=$?
else
  echo "⚠️  No linter found (skipping)"
  LINT_EXIT=0
fi

if [ $LINT_EXIT -eq 0 ]; then
  echo "✅ Linting passed"
  LINT_PASS=true
else
  echo "❌ Linting failed"
  LINT_PASS=false
fi
```

### Step 3: Check Documentation Timestamps

```bash
echo ""
echo "📝 Checking documentation timestamps..."

# Get modified .md files
MODIFIED_MD=$(git diff --name-only main...HEAD | grep "\.md$" || true)

if [ -n "$MODIFIED_MD" ]; then
  echo "Modified docs:"
  echo "$MODIFIED_MD"

  # Check if timestamps updated
  MISSING_TIMESTAMPS=0
  for file in $MODIFIED_MD; do
    if [ -f "$file" ]; then
      if ! grep -q "Last Updated.*$(date +%Y-%m-%d)" "$file"; then
        echo "⚠️  $file: timestamp not updated to today"
        MISSING_TIMESTAMPS=$((MISSING_TIMESTAMPS + 1))
      fi
    fi
  done

  if [ $MISSING_TIMESTAMPS -eq 0 ]; then
    echo "✅ All doc timestamps updated"
    TIMESTAMPS_PASS=true
  else
    echo "⚠️  $MISSING_TIMESTAMPS docs need timestamp update"
    echo "💡 Run: /doc-timestamp"
    TIMESTAMPS_PASS=false
  fi
else
  echo "ℹ️  No documentation modified"
  TIMESTAMPS_PASS=true
fi
```

### Step 4: Verify On Feature Branch

```bash
echo ""
echo "🌿 Checking branch..."

CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" = "main" ] || [ "$CURRENT_BRANCH" = "master" ]; then
  echo "❌ CRITICAL: You're on $CURRENT_BRANCH (should be feature branch)"
  BRANCH_PASS=false
else
  echo "✅ On feature branch: $CURRENT_BRANCH"
  BRANCH_PASS=true
fi
```

### Step 5: Check for Uncommitted Changes

```bash
echo ""
echo "💾 Checking for uncommitted changes..."

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "⚠️  Uncommitted changes found"
  echo "💡 Run: /commit-smart"
  UNCOMMITTED_PASS=false
else
  echo "✅ No uncommitted changes"
  UNCOMMITTED_PASS=true
fi
```

### Step 6: Generate Report

```bash
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Pre-PR Check Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Track overall pass/fail
ALL_PASS=true

if [ "$TESTS_PASS" = true ]; then
  echo "✅ Tests passing"
else
  echo "❌ Tests failing"
  ALL_PASS=false
fi

if [ "$LINT_PASS" = true ]; then
  echo "✅ Linting passing"
else
  echo "❌ Linting failing"
  ALL_PASS=false
fi

if [ "$TIMESTAMPS_PASS" = true ]; then
  echo "✅ Doc timestamps updated"
else
  echo "❌ Doc timestamps need update"
  ALL_PASS=false
fi

if [ "$BRANCH_PASS" = true ]; then
  echo "✅ On feature branch"
else
  echo "❌ NOT on feature branch"
  ALL_PASS=false
fi

if [ "$UNCOMMITTED_PASS" = true ]; then
  echo "✅ All changes committed"
else
  echo "⚠️  Uncommitted changes"
fi

echo ""
if [ "$ALL_PASS" = true ]; then
  echo "✅ All critical checks passed - Ready for PR!"
  exit 0
else
  echo "❌ Some checks failed - Fix issues before PR"
  exit 1
fi
```

## Integration with /submit-pr

```
/submit-pr workflow:
  1. Runs /techdebt (checks for tech debt)
  2. Runs /pre-pr-check (THIS SKILL)
  3. If any CRITICAL failures → STOP
  4. If warnings only → Continue with note
  5. Creates PR
  6. Starts /pr-review
```

## Example Output

### All Passing:

```
🧪 Running tests...
✅ Tests passed

🔍 Running linting...
✅ Linting passed

📝 Checking documentation timestamps...
Modified docs:
README.md
CODEX.md
✅ All doc timestamps updated

🌿 Checking branch...
✅ On feature branch: feat/auth-system

💾 Checking for uncommitted changes...
✅ No uncommitted changes

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Pre-PR Check Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ Tests passing
✅ Linting passing
✅ Doc timestamps updated
✅ On feature branch
✅ All changes committed

✅ All critical checks passed - Ready for PR!
```

### With Failures:

```
🧪 Running tests...
❌ Tests failed

🔍 Running linting...
❌ Linting failed

📝 Checking documentation timestamps...
Modified docs:
CODEX.md
⚠️  CODEX.md: timestamp not updated to today
⚠️  1 docs need timestamp update
💡 Run: /doc-timestamp

🌿 Checking branch...
✅ On feature branch: feat/auth-system

💾 Checking for uncommitted changes...
⚠️  Uncommitted changes found
💡 Run: /commit-smart

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Pre-PR Check Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❌ Tests failing
❌ Linting failing
❌ Doc timestamps need update
✅ On feature branch
⚠️  Uncommitted changes

❌ Some checks failed - Fix issues before PR

💡 Next steps:
1. Fix failing tests
2. Fix linting errors
3. Run /doc-timestamp
4. Run /commit-smart
5. Run /pre-pr-check again
```

## Handling Test Failures

If tests fail 3+ times in a row:
1. Document failures in PR description
2. Include error messages
3. Explain why tests can't be fixed immediately
4. Submit PR with failing tests noted

**This is allowed** - better to get code review than block on flaky tests.

## Manual Checks (Codex performs)

In addition to automated checks, Codex should verify:

- [ ] Code follows project conventions
- [ ] No obvious bugs or security issues
- [ ] Changes are focused and cohesive
- [ ] PR won't be too large (suggest splitting if >500 lines)
- [ ] Breaking changes documented

## Related Commands

- `/techdebt` - Find tech debt (runs before this)
- `/submit-pr` - Auto PR submission (calls this)
- `/doc-timestamp` - Update doc timestamps
- `/commit-smart` - Commit uncommitted changes
