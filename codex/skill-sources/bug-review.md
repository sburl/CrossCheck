---
name: bug-review
description: Systematic audit for common failure modes and bugs
---

**Created:** 2026-02-11-00-00
**Last Updated:** 2026-02-25-00-00

# Bug Review

Systematic audit of the repository for common failure modes. The counterpart to `/security-review` -- this covers correctness, reliability, and maintainability.

AI-generated code is structurally sound but prone to specific failure patterns. This skill targets those patterns directly.

## Usage

```bash
/bug-review                    # Full audit (all 10 categories)
/bug-review --quick            # Categories 1-3 only (the most common AI bugs)
/bug-review --focus concurrency  # Single category deep-dive
/bug-review --reproduce          # Full audit + reproduce Critical/High findings
/bug-review --quick --reproduce  # Quick audit + reproduce
```

---

## Failure Taxonomy

---

### Category 1: AI-Generated Code Patterns

**Why this is first:** AI models produce predictable failure patterns. These are the bugs that ship most often because the code "looks right" but isn't.

**Scan:**

1. **Happy-path-only code**
   - Functions with no error handling or only catch-all try/except
   - API calls without timeout, retry, or error response handling
   - File operations without checking existence or permissions
   - Network calls assuming 200 OK

2. **Stale imports and references**
   - Imports for modules that don't exist or were renamed
   - Function calls using old signatures after refactoring
   - References to deleted files, variables, or classes
   - Wrong package names (AI confuses similar packages)

3. **Test assertions that don't test what they claim**
   - Tests that always pass (asserting constants, asserting truthy on non-empty)
   - Tests that test the mock instead of the code
   - Missing edge case tests (empty input, null, boundary values)
   - Tests that duplicate the implementation logic instead of checking behavior

4. **Copy-paste drift**
   - Code blocks that were duplicated and partially modified
   - Variable names that don't match their context (leftover from copied code)
   - Comments that describe different code than what's below them

5. **Hallucinated APIs and methods**
   - Calling methods that don't exist on the class/object
   - Using library APIs from wrong versions
   - Inventing configuration options that don't exist
   - Using deprecated APIs that were removed

**Check:** For every function the AI wrote, ask: what happens when this fails?

---

### Category 2: Error Handling & Resilience

**How it goes wrong:** A try/catch swallows the error. A retry loop has no backoff. A timeout is set to 30 seconds on a 100ms operation. An error message says "something went wrong."

**Scan:**

1. **Swallowed errors**
   - Empty catch blocks: `catch (e) {}` or `except: pass`
   - Catch-all that logs but doesn't re-throw or handle
   - Errors converted to booleans (`return false` on failure)
   - Async errors that aren't awaited

2. **Missing error propagation**
   - Functions that return `null`/`undefined` on error without signaling
   - Middleware that catches errors but doesn't pass to error handler
   - Background jobs that fail silently
   - Event handlers that swallow exceptions

3. **Retry/timeout issues**
   - Missing retries on transient failures (network, database)
   - Retries without exponential backoff (thundering herd)
   - Missing circuit breakers on external services
   - Timeouts too long (blocking resources) or too short (false failures)
   - Infinite retry loops

4. **Graceful degradation**
   - Single external service failure taking down the whole app
   - Missing fallbacks for optional features
   - Cache failures causing cascading errors
   - Missing health checks

5. **Error messages**
   - Generic "something went wrong" without actionable info
   - Error messages that leak internal state (see security-review Category 5)
   - Different error types returning the same message
   - Missing error codes for programmatic handling

---

### Category 3: State Management & Data Integrity

**How it goes wrong:** Two requests update the same record. A cache returns stale data. A transaction commits partially. An ID collision creates ghost records.

**Scan:**

1. **Race conditions**
   - Check-then-act patterns without locking
   - Read-modify-write on shared data without atomicity
   - Counter increments without atomic operations
   - File access from multiple processes without coordination
   - Database queries that assume state hasn't changed

2. **Transaction issues**
   - Missing transactions around multi-step operations
   - Partial failures leaving data inconsistent
   - Long-running transactions holding locks
   - Missing rollback on failure paths

3. **Cache coherence**
   - Cache invalidation missing or incorrect
   - Stale reads from cache after writes
   - Cache key collisions between different data types
   - Missing cache expiration (growing forever)
   - Thundering herd on cache miss

4. **ID/uniqueness problems**
   - Auto-increment IDs causing collisions in distributed systems
   - UUID version misuse (v1 leaks MAC address, v4 for all new code)
   - Missing unique constraints in database
   - Duplicate detection that doesn't work at scale

5. **Data lifecycle**
   - Missing soft delete (hard delete causes referential issues)
   - Orphaned records (parent deleted, children remain)
   - Missing data migration for schema changes
   - Timezone handling (storing local time instead of UTC)
   - Floating-point comparison for money/financial calculations

---

### Category 4: Concurrency & Async

**How it goes wrong:** A promise is never awaited. A deadlock freezes the server. A shared variable is modified from two threads. An event loop is blocked.

**Scan:**

1. **Unawaited promises / unhandled async**
   - `async` function called without `await` (JavaScript/Python)
   - Missing `.catch()` on promise chains
   - Unhandled promise rejections
   - `fire-and-forget` patterns without error handling

2. **Deadlocks**
   - Lock acquisition in inconsistent order
   - Holding locks across I/O operations
   - Recursive lock acquisition
   - Database deadlocks from conflicting queries

3. **Thread safety**
   - Shared mutable state without synchronization
   - Non-thread-safe singletons
   - Concurrent collection modification
   - Global variables modified by multiple handlers

4. **Event loop blocking**
   - Synchronous I/O on async event loop (Node.js, Python asyncio)
   - CPU-intensive computation blocking the main thread
   - Large JSON parsing on the main thread
   - Missing worker threads/processes for heavy computation

5. **Resource exhaustion**
   - Connection pool exhaustion (too many open connections)
   - File descriptor leaks
   - Goroutine/thread leaks
   - Unbounded queue growth

---

### Category 5: Memory & Resource Leaks

**How it goes wrong:** Event listeners accumulate. Database connections aren't returned to the pool. A closure holds a reference to a massive object. The app slowly consumes all available memory.

**Scan:**

1. **Event listener leaks**
   - Adding listeners without removing them (especially in React `useEffect` without cleanup)
   - Global event handlers that accumulate on re-render
   - WebSocket handlers not cleaned up on disconnect

2. **Connection leaks**
   - Database connections not returned to pool
   - HTTP connections not closed after use
   - File handles not closed (missing `finally` blocks, missing `with` statements)
   - Redis/cache connections not released

3. **Closure leaks**
   - Closures capturing large objects unnecessarily
   - Callbacks holding references to DOM elements (browser)
   - Timer callbacks (`setInterval`) not cleared on component unmount

4. **Unbounded growth**
   - In-memory caches without eviction
   - Log buffers that grow forever
   - Arrays that accumulate without bounds
   - Maps/Sets used as caches without size limits

5. **Framework-specific**
   - React: missing dependency arrays in `useEffect`, missing cleanup returns
   - Express/Node: middleware that doesn't call `next()`
   - Python: circular references preventing garbage collection
   - Go: goroutines that never exit

---

### Category 6: API & Integration

**How it goes wrong:** A breaking API change isn't caught. A webhook has no retry. A third-party service changes its response format. Rate limits aren't respected.

**Scan:**

1. **Contract violations**
   - API returning different types than documented/typed
   - Optional fields treated as required
   - Missing validation of external API responses
   - Assuming response order or structure

2. **Versioning**
   - No API versioning strategy
   - Breaking changes without version bump
   - Client and server schema drift
   - Database schema not matching code models

3. **Rate limiting and backpressure**
   - Missing rate limit handling on external API calls
   - No backpressure when consuming faster than processing
   - Missing queue for high-throughput operations
   - Retry storms on rate-limited APIs

4. **Webhook reliability**
   - Missing idempotency on webhook handlers
   - No retry mechanism for failed webhook delivery
   - Webhook signature verification missing
   - Webhook timeout too short for processing

5. **Serialization**
   - JSON serialization of dates (inconsistent formats)
   - BigInt/large number loss in JSON
   - Circular reference serialization errors
   - Missing Content-Type headers

---

### Category 7: Performance Anti-Patterns

**How it goes wrong:** N+1 queries. Entire tables loaded into memory. Regular expressions that take exponential time. Unnecessary re-renders.

**Scan:**

1. **N+1 queries**
   - Loop with database query inside (should be batch/join)
   - ORM eager loading missing
   - GraphQL resolvers without DataLoader
   - API calls in loops (should be batched)

2. **Unnecessary data loading**
   - `SELECT *` when only a few columns needed
   - Loading entire collections to count or check existence
   - Missing pagination on list endpoints
   - Large payloads without compression

3. **Missing indexes**
   - Queries filtering on unindexed columns
   - Compound queries without compound indexes
   - Full table scans on large tables
   - Missing index on foreign keys

4. **Frontend performance**
   - Unnecessary re-renders (missing `React.memo`, `useMemo`, `useCallback`)
   - Large bundle sizes (missing code splitting)
   - Unoptimized images (missing lazy loading, missing srcset)
   - Missing virtualization for long lists

5. **Algorithmic complexity**
   - O(n^2) or worse where O(n) or O(n log n) is possible
   - Sorting entire arrays to find min/max
   - String concatenation in loops (use StringBuilder/join)
   - Repeated computation that should be memoized

---

### Category 8: Configuration & Environment

**How it goes wrong:** Works on my machine. Missing environment variable crashes in production. Dev and prod use different database drivers. Feature flags are hardcoded.

**Scan:**

1. **Environment variable handling**
   - Missing validation of required env vars at startup
   - Default values that are only valid in development
   - Boolean env vars compared with `==` instead of truthy check
   - Missing `.env.example` documenting required variables

2. **Environment parity**
   - Different databases in dev vs prod (SQLite vs Postgres)
   - Different file storage (local fs vs S3)
   - Missing service dependencies in Docker Compose
   - Hardcoded URLs (localhost in production config)

3. **Feature flags**
   - Hardcoded feature toggles instead of configuration
   - Feature flags that are never cleaned up
   - Missing fallback when flag service is unavailable

4. **Build configuration**
   - Build works locally but fails in CI
   - Missing or incorrect `.dockerignore`
   - Development dependencies in production build
   - Missing build-time type checking

---

### Category 9: Testing Gaps

**How it goes wrong:** Tests pass but the feature is broken. Integration tests hit real services. Error paths are never tested. Flaky tests are ignored.

**Scan:**

1. **False confidence tests**
   - Tests that assert `toBeTruthy()` on non-empty values (always pass)
   - Tests that mock the thing they're testing
   - Tests with no assertions
   - Tests where the expected value is copy-pasted from the output

2. **Missing coverage areas**
   - Error/failure paths not tested
   - Edge cases: empty input, null, max values, unicode, special characters
   - Concurrent access scenarios
   - Timeout and retry behavior
   - Authorization (can user A access user B's data?)

3. **Test isolation**
   - Tests dependent on execution order
   - Shared mutable state between tests
   - Tests hitting real external services
   - Tests dependent on system time, locale, or timezone

4. **Flaky tests**
   - Tests with timing dependencies (`setTimeout`, `sleep`)
   - Tests dependent on random data
   - Tests that fail intermittently due to race conditions
   - Retry loops in tests that mask real failures

---

### Category 10: Documentation & Maintainability Debt

**How it goes wrong:** The README describes a different app. The API docs are auto-generated but wrong. Dead code accumulates. Nobody knows what the `handleLegacyCase` function does.

**Scan:**

1. **Dead code**
   - Unreachable code paths (after return, after throw)
   - Unused exports/functions/variables
   - Commented-out code (either remove or document why)
   - Feature flags for features that shipped months ago

2. **Documentation drift**
   - README doesn't match current behavior
   - API docs don't match implementation
   - Code comments describe old logic
   - Architecture diagrams are outdated

3. **Complexity hotspots**
   - Functions >50 lines
   - Files >500 lines
   - Cyclomatic complexity >10
   - Deeply nested conditionals (>3 levels)

4. **Naming and structure**
   - Misleading function/variable names
   - Inconsistent naming conventions across codebase
   - God objects (classes doing too many things)
   - Circular dependencies between modules

---

## Execution Flow

### Full Audit

Run all 10 categories in order. Focus on Categories 1-3 first (highest hit rate for AI-generated code). Record findings with severity: Critical / High / Medium / Low.

### Quick Audit (`--quick`)

Categories 1-3 only. These catch 80% of bugs in AI-generated codebases.

### Focused Audit (`--focus <category>`)

Options: `ai-patterns`, `errors`, `state`, `concurrency`, `memory`, `api`, `performance`, `config`, `testing`, `maintenance`.

### Reproduction Phase (`--reproduce`)

After the pattern-matching audit, attempt to reproduce each Critical/High finding:

1. Identify the specific code path from the finding
2. Write a minimal reproduction test:
   - Filename: `__bugrepro_<N>.test.{ts,py,go}` (prefixed to be obvious)
   - Import the target module directly
   - Exercise the exact failure scenario
   - Assert the buggy behavior (test should PASS if bug exists)
3. Run the test:
   - **REPRODUCED**: Bug confirmed. Include reproduction test as evidence.
   - **NOT REPRODUCED**: Could not trigger. Downgrade severity or note conditions.
   - **INCONCLUSIVE**: Complex setup required. Note for manual verification.
4. **Cleanup**: Delete ALL `__bugrepro_*` files. Verify with `git status`.

Adds 10-20 minutes to the audit. Only runs when `--reproduce` flag is passed.

---

## Report Format

```markdown
## Bug Review - [date]

**Scope:** Full / Quick / Focus: [category]

### Summary

| # | Category | Issues | Highest Severity |
|---|----------|--------|------------------|
| 1 | AI Code Patterns | X | ... |
| 2 | Error Handling | X | ... |
| ... | ... | ... | ... |

### Detailed Findings

**[SEVERITY] [Category] - [Finding]**
- File: `path/to/file:line`
- Pattern: [what was detected]
- Risk: [what could happen]
- Fix: [specific remediation]

### Positive Findings
- [Things done well]

### Reproduction Results (--reproduce)

| Finding | Category | Severity | Reproduced? | Evidence |
|---------|----------|----------|-------------|----------|
| Unawaited promise in auth.ts:23 | Async | High | YES | Silent failure on reject |
| Race condition in counter.ts:45 | State | Critical | YES | 3/100 runs wrong count |
```

---

## Rules

1. **Category 1 (AI patterns) is never skippable.** AI-generated code has predictable failure modes. Always check.
2. **Every finding needs a "Fix" suggestion.** Don't just report problems.
3. **Prioritize by blast radius.** A race condition in payment processing > a missing memo in a settings page.
4. **Check tests for the bug, not just the code.** If you find a bug, verify the test suite doesn't already cover it. If it does, the test is probably wrong too.

## Related

- `/security-review` -- Security-focused audit (complementary)
- `/techdebt` -- Technical debt identification
- `/repo-assessment` -- Comprehensive quality review
