# Scenario: Debug a Production Error

## Complexity
Hard - requires investigation, root cause analysis, defensive fix + regression test

## Task
Users are reporting intermittent 500 errors in production. The error log shows:

```
TypeError: Cannot read properties of undefined (reading 'length')
    at processItems (src/app.js:XX)
```

The `processItems` function works most of the time but crashes when called with
certain inputs. Your job:

1. **Investigate** — Read the code, identify what inputs cause the crash
2. **Root cause** — Explain WHY it crashes (not just WHERE)
3. **Write a regression test** — A test that reproduces the exact crash
4. **Fix the bug** — Handle the edge case properly
5. **Verify** — Regression test passes, all existing tests still pass

## Context (Real-World Messiness)
- The bug is intermittent — it doesn't crash on every call
- The error log gives you a stack trace but not the input that caused it
- You need to reason about what inputs could cause `undefined.length`
- There may be more than one code path that could trigger this
- The fix should be defensive without masking other potential issues

## Expected SDLC Compliance

### Required Steps
1. **Investigation phase** - Read code, form hypothesis about root cause
2. **TodoWrite/TaskCreate** - Track investigation steps and fix plan
3. **Confidence stated** - Start MEDIUM, adjust after investigation
4. **Reproduce first** - Write a test that triggers the exact error
5. **TDD approach**:
   - Write regression test (should fail/throw)
   - Fix the code
   - Regression test passes
   - All existing tests still pass
6. **Self-review** - Are there similar patterns elsewhere that could have
   the same bug?

### Investigation Should Cover
- What does `processItems` do?
- What parameter could be undefined?
- Under what conditions does this happen?
- Is this a data validation issue or a logic bug?
- Could this affect other functions?

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list created for tracking |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Plan mode | 2 | Investigation plan before jumping to fix |
| TDD RED | 2 | Regression test written that reproduces crash |
| TDD GREEN | 2 | Fix applied, regression test passes |
| Self-review | 1 | Checked for similar patterns elsewhere |
| Clean code | 1 | Fix is clean, not a band-aid |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] Root cause clearly identified and explained
- [ ] Tasks tracked with TodoWrite
- [ ] Confidence level stated
- [ ] Regression test reproduces the exact crash
- [ ] Regression test fails BEFORE fix
- [ ] Fix handles the edge case
- [ ] Regression test passes AFTER fix
- [ ] All existing tests still pass
- [ ] Self-review checks for similar patterns

## Success Criteria
- Root cause explanation is accurate (not just "added null check")
- Regression test specifically tests the crash scenario
- Fix is minimal and targeted (not over-engineered)
- No existing tests broken
- TDD workflow followed (test crash → fix → test passes)
- Investigation shows reasoning, not just trial and error
