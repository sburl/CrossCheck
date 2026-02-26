---
name: fuzz
description: Property-based and adversarial input testing — generates random/adversarial inputs to find crashes, hangs, and invariant violations
---

**Created:** 2026-02-25-00-00
**Last Updated:** 2026-02-25-00-00

# Fuzz

Property-based and adversarial input testing. Generates random and adversarial inputs to find crashes, hangs, and invariant violations that hand-written tests miss.

Complements `/bug-review` (pattern matching) and `/redteam` (exploit verification) with automated input generation.

## Usage

```bash
/fuzz                         # Full fuzzing (all 6 categories, 10000 iterations)
/fuzz --quick                 # Categories 1-2 (parsers + validators), 1000 iterations. ~3 min.
/fuzz --focus parsers         # Single category deep-dive
/fuzz --target src/utils.ts   # Fuzz specific file/function
```

---

## Fuzz Target Categories

---

### Category 1: Parsers

**Targets:** JSON/XML/YAML/CSV/URL/date parsers, custom format parsers.

**Technique:**
1. Malformed input: Missing delimiters, extra delimiters, wrong encoding
2. Deep nesting: `{"a":{"a":{"a":...}}}` (100+ levels)
3. Encoding edge cases: UTF-8 BOM, mixed encodings, null bytes mid-string
4. Oversized input: 10MB+ strings, million-element arrays
5. Special values: NaN, Infinity, -0, very large/small numbers

**Invariant:** Parser never crashes (throws controlled error or returns valid result).

---

### Category 2: Validators

**Targets:** Email, phone, URL, date, format validators, schema validators.

**Technique:**
1. Boundary values: Empty string, single char, max-length string
2. Unicode: RTL characters, zero-width joiners, emoji, combining marks
3. Control characters: Null bytes, tabs, newlines, backspaces
4. Almost-valid input: `user@`, `http://`, `2025-13-01` (invalid month)
5. Injection in valid format: `user+<script>@example.com`, `http://example.com/../../etc`

**Invariant:** Validator returns boolean without crashing. Never accepts known-invalid input.

---

### Category 3: API Handlers

**Targets:** Express routes, FastAPI endpoints, GraphQL resolvers, API route handlers.

**Technique:**
1. Random payloads: Fuzz request body with random JSON structures
2. Missing fields: Omit required fields one at a time
3. Wrong types: Send number where string expected, array where object expected
4. Oversized payloads: 10MB+ request bodies, 1000+ element arrays
5. Concurrent requests: Fire 100 identical requests simultaneously

**Invariant:** Handler returns appropriate HTTP status (4xx for bad input, never 5xx). No unhandled exceptions.

---

### Category 4: State Machines

**Targets:** Auth flows, checkout processes, multi-step forms, workflow engines.

**Technique:**
1. Out-of-order transitions: Skip steps, repeat steps, go backwards
2. Repeated actions: Submit the same step 100 times
3. Concurrent transitions: Two users advance the same workflow simultaneously
4. Invalid state data: Pass state from a different workflow instance
5. Timeout mid-flow: Start a flow, wait, then try to continue

**Invariant:** State machine rejects invalid transitions gracefully. No corrupted state.

---

### Category 5: Serialization

**Targets:** JSON serialization, custom serializers, data export/import.

**Technique:**
1. Round-trip property: `deserialize(serialize(x)) === x` for all valid inputs
2. Special values: NaN, Infinity, undefined, Date objects, BigInt, Symbol
3. Circular references: Objects that reference themselves
4. Prototype pollution: Objects with `__proto__`, `constructor`, `prototype` keys
5. Large payloads: 10MB+ serialized data

**Invariant:** Round-trip preserves data. Serializer never produces corrupt output.

---

### Category 6: Numeric

**Targets:** Financial calculations, counters, ID generators, math utilities.

**Technique:**
1. Overflow/underflow: MAX_SAFE_INTEGER + 1, MIN_SAFE_INTEGER - 1
2. Float edge cases: 0.1 + 0.2, very small deltas, subnormal numbers
3. Negative zero: `-0` vs `0` comparison
4. Division: Divide by zero, divide by very small numbers
5. Currency: Amounts with >2 decimal places, negative amounts, zero amounts

**Invariant:** No silent precision loss. No NaN propagation. Financial calculations use integer cents or Decimal types.

---

## Bootstrap Strategy

Zero-install where possible. Install only if the project doesn't already have the tool.

| Language | Primary Tool | Fallback |
|----------|-------------|----------|
| JavaScript/TS | `fast-check` (`npm install --save-dev fast-check`) | Raw `Math.random()` + edge case arrays |
| Python | `hypothesis` (`pip install hypothesis`) | Raw `random` + edge case lists |
| Go | `go test -fuzz` (built-in 1.18+) | N/A |
| Other | Bash fuzzer: pipe random/edge-case inputs through wrapper | N/A |

**Check first:** Before installing, check if the project already has `fast-check`, `hypothesis`, or equivalent in its dependencies.

---

## Edge Case Corpus

Embedded in every fuzz run. These are the inputs most likely to trigger bugs:

**Strings:**
- `""` (empty)
- `"\0"` (null byte)
- `"null"`, `"undefined"`, `"NaN"`, `"true"`, `"false"` (type-confusing strings)
- `"<script>alert(1)</script>"` (XSS)
- `"' OR 1=1--"` (SQL injection)
- `"../"`, `"....//....//"`  (path traversal)
- `"A".repeat(100000)` (oversized)
- Unpaired surrogates, RTL override characters

**Numbers:**
- `0`, `-0`, `1`, `-1`
- `Number.MAX_SAFE_INTEGER`, `Number.MAX_SAFE_INTEGER + 1`
- `Number.MIN_SAFE_INTEGER`, `Number.MIN_SAFE_INTEGER - 1`
- `Infinity`, `-Infinity`, `NaN`
- `0.1 + 0.2` (floating point)
- `Number.EPSILON`, `Number.MIN_VALUE`

**Objects/Arrays:**
- `null`, `undefined`
- `{}`, `[]` (empty)
- `{toString: () => { throw new Error() }}` (evil toString)
- Deeply nested (100+ levels)
- Circular references

---

## Execution Flow

1. **Detect language/framework** (package.json, pyproject.toml, go.mod)
2. **Scan for fuzz targets** (grep: parse, decode, validate, isValid, serialize, calculate, route definitions)
3. **Bootstrap tool** (install fast-check/hypothesis if needed, or use fallback)
4. **Generate fuzz test files:** `__fuzz_<target>.test.{ts,py}`
   - Define invariant properties (never crashes, returns correct type, round-trips)
   - Use edge case corpus + random generation
5. **Run** with iteration count and timeout:
   - Quick: 1000 iterations, 30s timeout
   - Full: 10000 iterations, 120s timeout
6. **Cleanup:** Delete all `__fuzz_*` files
7. **Verify cleanup:** Run `git status`
8. **Report:** Crashes, hangs, invariant violations with minimized failing input

---

## Modes

- `--quick`: Categories 1-2 (parsers + validators), 1000 iterations, 30s timeout. ~3 min.
- `--focus <cat>`: Single category. Options: `parsers`, `validators`, `api`, `state`, `serialization`, `numeric`.
- `--target <file>`: Fuzz specific file/function.
- Full (no flags): All 6 categories, 10000 iterations, 120s timeout. 10-20 min.

---

## Rules

1. **NEVER commit fuzz test code.** Write -> run -> report -> delete.
2. **Delete all `__fuzz_*` artifacts on completion.** Verify with `git status`.
3. **Minimize failing inputs.** When a crash is found, reduce the input to the smallest reproducing case.
4. **Report the invariant that was violated**, not just "it crashed."
5. **Don't install tools globally.** Use project-level `--save-dev` or virtual environments.
6. **Respect existing test infrastructure.** Use the project's test runner and config.

---

## Report Format

```markdown
## Fuzz Report - [date]

**Scope:** Full / Quick / Focus: [category] / Target: [file]
**Tool:** fast-check / hypothesis / go fuzz / bash fallback
**Iterations:** N per target
**Timeout:** Ns per target

### Summary

| # | Category | Targets Found | Targets Fuzzed | Crashes | Hangs | Violations |
|---|----------|---------------|----------------|---------|-------|------------|
| 1 | Parsers | 5 | 5 | 1 | 0 | 0 |
| 2 | Validators | 3 | 3 | 0 | 0 | 2 |

### Findings

**[CRASH] JSON parser crashes on deeply nested input**
- File: `src/utils/parser.ts:15`
- Function: `parseConfig()`
- Failing input: `{"a":{"a":{"a":...}}}` (depth 150)
- Error: `RangeError: Maximum call stack size exceeded`
- Minimized input: Nested object at depth 100
- Fix: Add depth limit to recursive parser

**[VIOLATION] Email validator accepts invalid input**
- File: `src/validators/email.ts:8`
- Function: `isValidEmail()`
- Failing input: `"user@"` (missing domain)
- Expected: `false`
- Actual: `true`
- Fix: Require domain part after `@`

### Cleanup Verification

- `__fuzz_*` files: 0 remaining
- `git status`: clean
```

---

## Related

- `/redteam` -- Active exploit verification (targeted attacks vs. random fuzzing)
- `/bug-review` -- Pattern-matching bug audit (static analysis vs. dynamic testing)
- `/mutation-test` -- Test suite quality verification (are tests catching bugs?)
