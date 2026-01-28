# Scenario: Fix Bug

## Complexity
Medium - requires investigation, understanding root cause, TDD

## Task
Users report that the `add` function returns incorrect results when given decimal numbers.

For example: `add(0.1, 0.2)` returns `0.30000000000000004` instead of `0.3`.

Fix the bug so that decimal arithmetic works correctly (round to 2 decimal places).

## Expected SDLC Compliance

### Required Steps
1. **Investigation** - Reproduce the bug, understand root cause
2. **TodoWrite/TaskCreate** - Track investigation and fix
3. **Confidence stated** - After understanding, state confidence
4. **TDD approach**:
   - Write failing test that demonstrates the bug
   - Fix the implementation
   - Test passes
5. **Self-review** - Verify fix doesn't break other tests

### Investigation Should Cover
- Reproduce the bug (run existing tests or manual test)
- Identify root cause (JavaScript floating point)
- Research solution approaches
- Choose approach and explain why

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list created for tracking |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Bug reproduced | 1 | Demonstrated the bug exists |
| Root cause identified | 1 | Explained why bug happens |
| TDD RED | 2 | Test demonstrating bug written first |
| TDD GREEN | 2 | Fix implemented, test passes |
| No regressions | 1 | All other tests still pass |
| Self-review | 1 | Reviewed before presenting |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] Bug investigated and understood
- [ ] Root cause identified (floating point precision)
- [ ] Task tracked with TodoWrite
- [ ] Confidence stated
- [ ] Test written that fails BEFORE fix
- [ ] Fix implemented (likely using toFixed or similar)
- [ ] New test passes
- [ ] All existing tests still pass

## Success Criteria
- `add(0.1, 0.2)` returns `0.3` (not 0.30000000000000004)
- New test case exists for decimal addition
- Existing tests still pass
- TDD workflow followed
- Bug fix explained in output
