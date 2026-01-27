---
name: testing
description: TDD and testing philosophy for writing tests, test-driven development, integration tests, and unit tests. Use this skill when writing tests, doing TDD, or debugging test issues.
argument-hint: [test type] [target]
---
# Testing Skill - TDD & Testing Philosophy

## Task
$ARGUMENTS

## Testing Diamond (CRITICAL)

```
    /\         <- Few E2E (automated or manual sign-off at end)
   /  \
  /    \
 /------\
|        |     <- MANY Integration (real DB, real cache - BEST BANG FOR BUCK)
|        |
 \------/
  \    /
   \  /
    \/         <- Few Unit (pure logic only)
```

**Why Integration Tests are Best Bang for Buck:**
- **Speed**: Fast enough to run on every change
- **Stability**: Touch real code, not mocks that lie
- **Confidence**: If they pass, production usually works
- **Real bugs**: Integration tests with real DB catch real bugs
- Unit tests with mocks can "pass" while production fails

## Minimal Mocking Philosophy

| What | Mock? | Why |
|------|-------|-----|
| Database | NEVER | Use test DB or in-memory |
| Cache | NEVER | Use isolated test instance |
| External APIs | YES | Real calls = flaky + expensive |
| Time/Date | YES | Determinism |

**Mocks MUST come from REAL captured data:**
- Capture real API response
- Save to your fixtures directory (Claude will discover where yours is, e.g., `tests/fixtures/`, `test-data/`, etc.)
- Import in tests
- Never guess mock shapes!

## TDD Tests Must PROVE

| Phase | What It Proves |
|-------|----------------|
| RED | Test FAILS -> Bug exists or feature missing |
| GREEN | Test PASSES -> Fix works or feature implemented |
| Forever | Regression protection |

**WRONG approach:**
```
// Writing test that passes with current (buggy) code
assert currentBuggyBehavior == currentBuggyBehavior  // pseudocode
```

**CORRECT approach:**
```
// Writing test that FAILS with buggy code, PASSES with fix
assert result.status == 'success'   // pseudocode - adapt to your framework
assert result.data != null
```

## Unit Tests = Pure Logic ONLY

A function qualifies for unit testing ONLY if:
- No database calls
- No external API calls
- No file system access
- No cache calls
- Input -> Output transformation only

Everything else needs integration tests.

## When Stuck on Tests

1. Add console.logs -> Check output
2. Run single test in isolation
3. Check fixtures match real API
4. **STILL stuck?** ASK USER

## This Repo's Testing (Meta-Project)

Since this is a meta-repo (docs/workflows, not app code):
- **Unit tests**: Test bash script logic (`test-version-logic.sh`)
- **Integration tests**: Test schema validation (`test-analysis-schema.sh`)
- **E2E tests**: Run wizard on test repos, verify compliance (`run-simulation.sh`)
- **Workflow tests**: Use `act` to test GitHub Actions locally

## After Session (Capture Learnings)

If this session revealed testing insights, update the right place:
- **Testing patterns, gotchas** -> `TESTING.md`
- **Feature-specific test quirks** -> Feature docs (`*_PLAN.md`)
- **General project context** -> `CLAUDE.md` (or `/revise-claude-md`)

---

**Full reference:** TESTING.md
