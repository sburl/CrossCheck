---
name: techdebt
description: Find and eliminate technical debt (run at end of every session)
---

**Created:** 2026-02-09-00-00
**Last Updated:** 2026-02-09-16-00

# Tech Debt Hunter

Find and eliminate technical debt. **Automatically runs checks and reports issues.**

## Usage

```bash
/techdebt [--fix] [--report-only]
```

**Modes:**
- Default: Run checks, report issues, suggest fixes
- `--fix`: Automatically fix simple issues
- `--report-only`: Just report, don't offer fixes

## How It Works

This skill ACTUALLY RUNS checks (not just documentation):
1. Checks for critical issues (silenced lint errors)
2. Runs available tools (jscpd, knip, etc.)
3. Reports findings with severity
4. Suggests fixes or auto-fixes if requested

## Critical Checks (Always Run)

### 1. Silenced Linter Errors ⚠️ BLOCKER

**What:** Find eslint-disable, @ts-ignore, prettier-ignore, etc.
**Why:** Agents silence errors instead of fixing them
**Impact:** BLOCKS PR submission

```bash
# Check for silenced errors
grep -r "eslint-disable\|@ts-ignore\|@ts-expect-error\|prettier-ignore" src/ 2>/dev/null

# Also check Python
grep -r "pylint: disable\|type: ignore\|noqa" . --include="*.py" 2>/dev/null

# Also check Rust
grep -r "#\[allow(" . --include="*.rs" 2>/dev/null
```

**Allowed exception (rare):**
```typescript
// EXCEPTION: External library bug in @stripe/stripe-js v1.2.3
// Issue: https://github.com/stripe/stripe-js/issues/456
// Remove when upgrading to v2.0.0
// @ts-expect-error - Library types incorrect for loadStripe
const stripe = await loadStripe(apiKey);
```

**If found without EXCEPTION comment → CRITICAL, blocks PR.**

### 2. Console.log / Debug Statements

```bash
# JavaScript/TypeScript
grep -r "console\.log\|console\.debug\|debugger" src/ --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' 2>/dev/null | wc -l

# Python
grep -r "print(" . --include="*.py" 2>/dev/null | grep -v "# allowed" | wc -l
```

**Auto-fixable in --fix mode.**

### 3. TODO/FIXME Comments

```bash
# Find all TODO/FIXME comments
grep -r "TODO\|FIXME" src/ 2>/dev/null | wc -l
```

**Report only - not critical.**

## Optional Checks (Run If Tools Available)

### 4. Code Duplication (jscpd)

```bash
# Check if jscpd is available
if command -v jscpd &> /dev/null || [ -f "node_modules/.bin/jscpd" ]; then
  npx jscpd src/ --min-lines 5 --min-tokens 50 --reporters json
fi
```

**What it finds:**
- Duplicated code blocks
- Copy-pasted functions
- Similar patterns that should be abstracted

### 5. Dead Code (knip)

```bash
# Check if knip is available
if command -v knip &> /dev/null || [ -f "node_modules/.bin/knip" ]; then
  npx knip --reporter json
fi
```

**What it finds:**
- Unused exports
- Unreferenced files
- Unused dependencies
- Unused types/interfaces

### 6. Circular Dependencies (madge)

```bash
# Check if madge is available
if command -v madge &> /dev/null || [ -f "node_modules/.bin/madge" ]; then
  npx madge --circular src/
fi
```

**What it finds:**
- Circular import chains
- Module dependency issues

## Execution Protocol

When `/techdebt` is invoked, Codex executes these bash commands:

```bash
#!/bin/bash

echo "🔍 Running tech debt checks..."
echo ""

# Critical Check 1: Silenced linter errors
echo "Checking for silenced linter errors..."
SILENCED=$(grep -r "eslint-disable\|@ts-ignore\|@ts-expect-error\|prettier-ignore" src/ 2>/dev/null | grep -v "EXCEPTION:" | wc -l | tr -d ' ')

if [ "$SILENCED" -gt 0 ]; then
  echo "❌ CRITICAL: Found $SILENCED silenced linter errors (BLOCKS PR)"
  grep -rn "eslint-disable\|@ts-ignore\|@ts-expect-error\|prettier-ignore" src/ 2>/dev/null | grep -v "EXCEPTION:"
  CRITICAL=true
else
  echo "✅ No silenced linter errors"
fi

# Critical Check 2: Debug statements
echo ""
echo "Checking for debug statements..."
CONSOLE=$(grep -r "console\.log\|console\.debug\|debugger" src/ --include='*.js' --include='*.ts' --include='*.jsx' --include='*.tsx' 2>/dev/null | wc -l | tr -d ' ')

if [ "$CONSOLE" -gt 0 ]; then
  echo "⚠️  Found $CONSOLE debug statements"
else
  echo "✅ No debug statements"
fi

# Check 3: TODO comments
echo ""
echo "Checking for TODO/FIXME comments..."
TODOS=$(grep -r "TODO\|FIXME" src/ 2>/dev/null | wc -l | tr -d ' ')
echo "📝 Found $TODOS TODO/FIXME comments"

# Optional tools
echo ""
echo "Running optional checks..."

if command -v jscpd &> /dev/null || [ -f "node_modules/.bin/jscpd" ]; then
  echo "Checking for code duplication..."
  npx jscpd src/ --min-lines 5 --min-tokens 50 --silent 2>/dev/null || echo "⚠️  jscpd check skipped"
else
  echo "ℹ️  jscpd not installed (npm i -D jscpd)"
fi

if command -v knip &> /dev/null || [ -f "node_modules/.bin/knip" ]; then
  echo "Checking for dead code..."
  npx knip 2>/dev/null || echo "⚠️  knip check skipped"
else
  echo "ℹ️  knip not installed (npm i -D knip)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Tech Debt Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$CRITICAL" = "true" ]; then
  echo "🚨 CRITICAL: $SILENCED silenced linter errors found"
  echo "⚠️  MUST FIX before PR submission"
  echo "⚠️  NEVER silence errors - fix underlying issues"
  exit 1
fi

echo "✅ No critical issues"
echo "⚠️  $CONSOLE debug statements"
echo "📝 $TODOS TODO comments"
```

## Auto-Fix Mode

When `--fix` flag is used, Codex runs:

```bash
# Remove console.log statements
find src/ -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -exec sed -i.bak '/console\.log/d' {} + && find src/ -name '*.bak' -delete

# Remove debugger statements
find src/ -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -exec sed -i.bak '/debugger;/d' {} + && find src/ -name '*.bak' -delete

echo "✅ Auto-fixed debug statements"
```

## Integration with /submit-pr

```
/submit-pr workflow:
  1. Runs /techdebt
  2. If CRITICAL issues → STOP
  3. If warnings only → Continue with note
  4. Runs /pre-pr-check
  5. Creates PR
  6. Starts /pr-review
```

## Example Output

```
🔍 Running tech debt checks...

Checking for silenced linter errors...
✅ No silenced linter errors

Checking for debug statements...
⚠️  Found 3 debug statements

Checking for TODO/FIXME comments...
📝 Found 5 TODO/FIXME comments

Running optional checks...
Checking for code duplication...
✅ jscpd: No significant duplication

Checking for dead code...
⚠️  knip: 2 unused exports found

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Tech Debt Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ No critical issues
⚠️  3 debug statements
📝 5 TODO comments

💡 Run /techdebt --fix to auto-remove debug statements
```

## Tools Installation (Optional)

```bash
# For JavaScript/TypeScript
npm install -D jscpd knip madge

# For Python
pip install vulture radon
```

## Related Commands

- `/pre-pr-check` - Comprehensive pre-PR checklist
- `/submit-pr` - Auto PR submission (calls /techdebt)
- Enforce-no-disable checks are built into this skill
