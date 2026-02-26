---
name: mutation-test
description: Verify test suite effectiveness — introduces small code mutations and checks if tests catch them. Surviving mutants reveal weak tests.
---

**Created:** 2026-02-25-00-00
**Last Updated:** 2026-02-25-00-00

# Mutation Test

Verify test suite effectiveness by introducing small code mutations and checking if tests catch them. If a mutation doesn't cause any test to fail, that mutant "survived" -- revealing a gap in your test suite.

The meta-question: "Are my tests actually catching bugs, or just achieving coverage?"

## Usage

```bash
/mutation-test                    # Full (all 6 categories, bash mutator). 10-20 min.
/mutation-test --quick            # Categories 1-3 only, max 20 mutations/file, max 5 files. ~5 min.
/mutation-test --focus boundary   # Single category deep-dive
/mutation-test --file src/auth.ts # Target specific file
/mutation-test --deep             # Use stryker/mutmut (language-specific). 30+ min.
```

---

## Mutation Operator Categories

---

### Category 1: Conditional Boundary

**Mutations:** Change boundary operators.

| Original | Mutant |
|----------|--------|
| `<` | `<=` |
| `>` | `>=` |
| `<=` | `<` |
| `>=` | `>` |
| `==` | `!=` |
| `!=` | `==` |

**Why it matters:** Off-by-one errors are the most common boundary bug. If your tests pass with `<` changed to `<=`, the boundary isn't tested.

---

### Category 2: Negation

**Mutations:** Flip boolean logic.

| Original | Mutant |
|----------|--------|
| `if (valid)` | `if (!valid)` |
| `if (!done)` | `if (done)` |
| `true` (in conditional) | `false` |
| `&&` | `\|\|` |
| `\|\|` | `&&` |

**Why it matters:** If negating a condition doesn't break a test, the condition may be dead code or the test doesn't cover both branches.

---

### Category 3: Return Value

**Mutations:** Change what functions return.

| Original | Mutant |
|----------|--------|
| `return true` | `return false` |
| `return false` | `return true` |
| `return 0` | `return 1` |
| `return 1` | `return 0` |
| `return null` | `return {}` |
| `return value` | `return null` |

**Why it matters:** If changing a return value doesn't break a test, either the return value isn't used or the test doesn't check it.

---

### Category 4: Arithmetic

**Mutations:** Change math operators.

| Original | Mutant |
|----------|--------|
| `+` | `-` |
| `-` | `+` |
| `*` | `/` |
| `/` | `*` |
| `%` | `*` |
| `++` | `--` |
| `--` | `++` |

**Why it matters:** If `total + tax` can be changed to `total - tax` without a test failing, the financial calculation isn't properly tested.

---

### Category 5: Removal

**Mutations:** Delete function calls, validation, and error handling.

| Original | Mutant |
|----------|--------|
| `validate(input)` | (removed) |
| `logger.error(msg)` | (removed) |
| `await cleanup()` | (removed) |
| `if (check) throw` | (removed) |
| `cache.invalidate(key)` | (removed) |

**Why it matters:** If removing a validation call doesn't break a test, either the validation is dead code or the test doesn't exercise the invalid case.

---

### Category 6: Constant

**Mutations:** Change literal values.

| Original | Mutant |
|----------|--------|
| `"error"` | `""` |
| `""` | `"mutant"` |
| `100` | `0` |
| `0` | `1` |
| `[]` | `[null]` |
| `timeout: 5000` | `timeout: 0` |

**Why it matters:** If changing a timeout from 5000 to 0 doesn't break a test, the timeout behavior isn't tested.

---

## Two-Tier Engine

### Default: Bash Mutator (zero-install)

Works on any language. Uses `sed` to apply one mutation at a time.

**How it works:**
1. Select a source file with corresponding tests
2. Backup: `cp file file.bak`
3. Apply ONE `sed` mutation (e.g., `sed -i.bak 's/< /<=/' file`)
4. Run tests (timeout: 2x normal test time)
5. Record result:
   - **Killed**: Tests fail (good -- mutation was caught)
   - **Survived**: Tests pass (bad -- mutation wasn't caught)
   - **Errored**: Syntax error from mutation (skip, don't count)
6. Restore: `mv file.bak file`
7. Repeat for next mutation

**Advantages:** Zero install, works everywhere, fast per-mutation.
**Limitations:** Text-level mutations may create syntax errors. No semantic understanding.

### Deep: Language-Specific Tooling (`--deep`)

| Language | Tool | Install |
|----------|------|---------|
| JavaScript/TS | Stryker | `npx stryker run` |
| Python | mutmut | `pip install mutmut && mutmut run` |
| Go | go-mutesting | `go install github.com/zimmski/go-mutesting/cmd/go-mutesting@latest` |

**Advantages:** Semantic mutations (AST-level), accurate, comprehensive.
**Limitations:** Requires installation, slow (30+ min for large codebases).

---

## Execution Flow

1. **Detect language and test framework** (package.json scripts, pytest.ini, go.mod)
2. **Select source files:**
   - Must have corresponding test files
   - Exclude: test files, config files, generated files, vendor/node_modules
   - Priority: files with most recent changes, files with lowest coverage
3. **Run baseline tests** to confirm they pass before mutating
4. **For each file, for each mutation:**
   a. Backup: `cp file file.bak`
   b. Apply ONE mutation via `sed`
   c. Run tests (timeout: 2x normal test time)
   d. Record: **killed** (tests fail) / **survived** (tests pass) / **errored** (syntax error)
   e. Restore: `mv file.bak file`
5. **Calculate mutation score:** `killed / (killed + survived)` (errored excluded)
6. **Report surviving mutants** with suggested tests to kill them

---

## Modes

- `--quick`: Categories 1-3 only, max 20 mutations per file, max 5 files. ~5 min.
- `--focus <cat>`: Single category. Options: `boundary`, `negation`, `return`, `arithmetic`, `removal`, `constant`.
- `--file <path>`: Target specific file.
- `--deep`: Use stryker/mutmut. All categories. 30+ min.
- Full (no flags): All 6 categories, max 50 mutations per file, bash mutator. 10-20 min.

---

## Score Interpretation

| Score | Rating | Meaning |
|-------|--------|---------|
| **>90%** | Strong | Test suite catches most mutations. High confidence in test quality. |
| **70-90%** | Moderate | Surviving mutants indicate specific gaps. Review and add targeted tests. |
| **<70%** | Weak | Tests pass but don't verify behavior. Many mutations go undetected. |

**Important:** A high mutation score is more meaningful than high code coverage. 100% coverage with 50% mutation score means tests execute all code but don't verify what it does.

---

## Rules

1. **ALWAYS restore files after mutation.** `mv file.bak file` after every mutation. Verify with diff.
2. **NEVER mutate test files.** Only mutate source code.
3. **NEVER mutate and commit.** Each mutation is applied, tested, and reverted.
4. **Skip files without tests.** No point mutating code that has no tests.
5. **Timeout mutations generously.** Use 2x the normal test time to avoid false kills from slow tests.
6. **Baseline must pass.** If tests fail before mutation, fix tests first.

---

## Report Format

```markdown
## Mutation Test Report - [date]

**Scope:** Full / Quick / Focus: [category] / File: [path]
**Engine:** bash mutator / stryker / mutmut
**Files mutated:** N
**Total mutations:** N

### Summary

| Metric | Count |
|--------|-------|
| Mutations applied | 150 |
| Killed (tests caught it) | 120 |
| Survived (tests missed it) | 25 |
| Errored (syntax error) | 5 |
| **Mutation Score** | **83%** (Moderate) |

### Surviving Mutants (tests missed these)

**File: `src/auth.ts:23`**
- Mutation: `if (age > 18)` -> `if (age >= 18)`
- Category: Conditional Boundary
- Tests that should catch this: `test/auth.test.ts`
- Suggested test: `test("rejects age exactly 18", () => expect(isAdult(18)).toBe(false))`

**File: `src/cart.ts:45`**
- Mutation: `total + tax` -> `total - tax`
- Category: Arithmetic
- Tests that should catch this: `test/cart.test.ts`
- Suggested test: `test("total includes tax", () => expect(getTotal(100, 10)).toBe(110))`

### Score by File

| File | Mutations | Killed | Survived | Score |
|------|-----------|--------|----------|-------|
| src/auth.ts | 30 | 25 | 5 | 83% |
| src/cart.ts | 20 | 14 | 6 | 70% |
| src/utils.ts | 15 | 15 | 0 | 100% |

### Score by Category

| Category | Mutations | Killed | Survived | Score |
|----------|-----------|--------|----------|-------|
| Conditional Boundary | 40 | 30 | 10 | 75% |
| Negation | 25 | 22 | 3 | 88% |
| Return Value | 30 | 28 | 2 | 93% |
| Arithmetic | 20 | 15 | 5 | 75% |
| Removal | 20 | 15 | 5 | 75% |
| Constant | 15 | 10 | 5 | 67% |
```

---

## Related

- `/fuzz` -- Property-based input testing (finds crashes via random inputs)
- `/redteam` -- Active exploit verification (security-focused)
- `/bug-review` -- Pattern-matching bug audit (static analysis)
