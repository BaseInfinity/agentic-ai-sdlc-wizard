---
name: sdlc
description: Full SDLC workflow for implementing features, fixing bugs, refactoring code, and creating new functionality. Use this skill when implementing, fixing, refactoring, adding features, or building new code.
argument-hint: [task description]
---
# SDLC Skill - Full Development Workflow

## Task
$ARGUMENTS

## Full SDLC Checklist

Your FIRST action must be TodoWrite with these steps:

```
TodoWrite([
  // PLANNING PHASE (Plan Mode for non-trivial tasks)
  { content: "Find and read relevant documentation", status: "in_progress", activeForm: "Reading docs" },
  { content: "Assess doc health - flag issues (ask before cleaning)", status: "pending", activeForm: "Checking doc health" },
  { content: "DRY scan: What patterns exist to reuse?", status: "pending", activeForm: "Scanning for reusable patterns" },
  { content: "Blast radius: What depends on code I'm changing?", status: "pending", activeForm: "Checking dependencies" },
  { content: "Restate task in own words - verify understanding", status: "pending", activeForm: "Verifying understanding" },
  { content: "Scrutinize test design - right things tested? Follow TESTING.md?", status: "pending", activeForm: "Reviewing test approach" },
  { content: "Present approach + STATE CONFIDENCE LEVEL", status: "pending", activeForm: "Presenting approach" },
  { content: "Signal ready - user exits plan mode", status: "pending", activeForm: "Awaiting plan approval" },
  // TRANSITION PHASE (After plan mode, before compact)
  { content: "Update feature docs with discovered gotchas", status: "pending", activeForm: "Updating feature docs" },
  { content: "Request /compact before TDD", status: "pending", activeForm: "Requesting compact" },
  // IMPLEMENTATION PHASE (After compact)
  { content: "TDD RED: Write failing test FIRST", status: "pending", activeForm: "Writing failing test" },
  { content: "TDD GREEN: Implement, verify test passes", status: "pending", activeForm: "Implementing feature" },
  { content: "Run lint/typecheck", status: "pending", activeForm: "Running lint and typecheck" },
  { content: "Run ALL tests", status: "pending", activeForm: "Running all tests" },
  { content: "Production build check", status: "pending", activeForm: "Verifying production build" },
  // REVIEW PHASE
  { content: "DRY check: Is logic duplicated elsewhere?", status: "pending", activeForm: "Checking for duplication" },
  { content: "Self-review: code-reviewer subagent", status: "pending", activeForm: "Running code review" },
  { content: "Security review (if warranted)", status: "pending", activeForm: "Checking security implications" },
  // CI FEEDBACK LOOP (After local tests pass)
  { content: "Commit and push to remote", status: "pending", activeForm: "Pushing to remote" },
  { content: "Watch CI - fix failures, iterate until green (max 2x)", status: "pending", activeForm: "Watching CI" },
  // FINAL
  { content: "Present summary: changes, tests, CI status", status: "pending", activeForm: "Presenting final summary" }
])
```

## New Pattern & Test Design Scrutiny (PLANNING)

**New design patterns require human approval:**
1. Search first - do similar patterns exist in codebase?
2. If YES and they're good - use as building block
3. If YES but they're bad - propose improvement, get approval
4. If NO (new pattern) - explain why needed, get explicit approval

**Test design scrutiny during planning:**
- Are we testing the right things?
- Does test approach follow TESTING.md philosophies?
- If introducing new test patterns, same scrutiny as code patterns

## Plan Mode Integration

**Use plan mode for:** Multi-file changes, new features, LOW confidence, bugs needing investigation.

**Workflow:**
1. **Plan Mode** (editing blocked): Research -> Write plan file -> Present approach + confidence
2. **Transition** (after approval): Update feature docs -> Request /compact
3. **Implementation** (after compact): TDD RED -> GREEN -> PASS

**Before TDD, MUST ask:** "Docs updated. Run `/compact` before implementation?"

## Confidence Check (REQUIRED)

Before presenting approach, STATE your confidence:

| Level | Meaning | Action |
|-------|---------|--------|
| HIGH (90%+) | Know exactly what to do | Present approach, proceed after approval |
| MEDIUM (60-89%) | Solid approach, some uncertainty | Present approach, highlight uncertainties |
| LOW (<60%) | Not sure | ASK USER before proceeding |
| FAILED 2x | Something's wrong | STOP. ASK USER immediately |
| CONFUSED | Can't diagnose why something is failing | STOP. Describe what you tried, ask for help |

## Self-Review Loop (CRITICAL)

```
PLANNING -> DOCS -> TDD RED -> TDD GREEN -> Tests Pass -> Self-Review
    ^                                                      |
    |                                                      v
    |                                            Issues found?
    |                                            |-- NO -> Present to user
    |                                            +-- YES v
    +------------------------------------------- Ask user: fix in new plan?
```

**The loop goes back to PLANNING, not TDD RED.** When self-review finds issues:
1. Ask user: "Found issues. Want to create a plan to fix?"
2. If yes -> back to PLANNING phase with new plan doc
3. Then -> docs update -> TDD -> review (proper SDLC loop)

**How to self-review:**
1. Use Task tool with `subagent_type="general-purpose"` as code-reviewer
2. Provide context: the diff, ARCHITECTURE.md, relevant feature docs
3. Ask it to review for quality, DRY, consistency, and domain-specific patterns
4. If low confidence on a pattern, search for 2026 best practices and weigh against your repo
5. Address issues by going back through the proper SDLC loop

## Test Review (Harder Than Implementation)

During self-review, critique tests HARDER than app code:
1. **Testing the right things?** - Not just that tests pass
2. **Tests prove correctness?** - Or just verify current behavior?
3. **Follow our philosophies (TESTING.md)?**
   - Testing Diamond (integration-heavy)?
   - Minimal mocking (real DB, mock external APIs only)?
   - Real fixtures from captured data?

**Tests are the foundation.** Bad tests = false confidence = production bugs.

## Scope Guard (Stay in Your Lane)

**Only make changes directly related to the task.**

If you notice something else that should be fixed:
- NOTE it in your summary ("I noticed X could be improved")
- DON'T fix it unless asked

**Why this matters:** AI agents can drift into "helpful" changes that weren't requested. This creates unexpected diffs, breaks unrelated things, and makes code review harder.

## Test Failure Recovery (SDET Philosophy)

```
┌─────────────────────────────────────────────────────────────────────┐
│  ALL TESTS MUST PASS. NO EXCEPTIONS.                                │
│                                                                     │
│  This is not negotiable. This is not flexible. This is absolute.   │
└─────────────────────────────────────────────────────────────────────┘
```

**Not acceptable:**
- "Those were already failing" → Fix them first
- "Not related to my changes" → Doesn't matter, fix it
- "It's flaky" → Flaky = bug, investigate

**Treat test code like app code.** Test failures are bugs. Investigate them the way a 15-year SDET would - with thought and care, not by brushing them aside.

If tests fail:
1. Identify which test(s) failed
2. Diagnose WHY - this is the important part:
   - Your code broke it? Fix your code (regression)
   - Test is for deleted code? Delete the test
   - Test has wrong assertions? Fix the test
   - Test is "flaky"? Investigate - flakiness is just another word for bug
3. Fix appropriately (fix code, fix test, or delete dead test)
4. Run specific test individually first
5. Then run ALL tests
6. Still failing? ASK USER - don't spin your wheels

**Flaky tests are bugs, not mysteries:**
- Sometimes the bug is in app code (race condition, timing issue)
- Sometimes the bug is in test code (shared state, not parallel-safe)
- Sometimes the bug is in test environment (cleanup not proper)

Debug it. Find root cause. Fix it properly. Tests ARE code.

## CI Feedback Loop (After Commit)

**The SDLC doesn't end at local tests.** CI must pass too.

```
Local tests pass -> Commit -> Push -> Watch CI
                                         |
                              CI passes? -+-> YES -> Present for review
                                         |
                                         +-> NO -> Fix -> Push -> Watch CI
                                                           |
                                                   (max 2 attempts)
                                                           |
                                                   Still failing?
                                                           |
                                                   STOP and ASK USER
```

**How to watch CI:**
1. Push changes to remote
2. Check CI status (use `gh` CLI or GitHub MCP)
3. If CI fails:
   - Read failure logs
   - Diagnose root cause (same as local test failures)
   - Fix and push again
4. Max 2 fix attempts - if still failing, ASK USER
5. If CI passes - proceed to present final summary

**CI failures follow same rules as test failures:**
- Your code broke it? Fix your code
- CI config issue? Fix the config
- Flaky? Investigate - flakiness is a bug
- Stuck? ASK USER

## DRY Principle

**Before coding:** "What patterns exist I can reuse?"
**After coding:** "Did I accidentally duplicate anything?"

## DELETE Legacy Code

- Legacy code? DELETE IT
- Backwards compatibility? NO - DELETE IT
- "Just in case" fallbacks? DELETE IT

**THE RULE:** Delete old code first. If it breaks, fix it properly.

---

**Full reference:** SDLC.md
