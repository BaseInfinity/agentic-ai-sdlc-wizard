# Scenario: Remove Deprecated Code Path

## Complexity
Medium - requires usage analysis, safe deletion, test updates

## Task
The codebase has a deprecated `legacyCalculate` function that was replaced by
`calculate` months ago. Tech debt ticket says:

> Remove `legacyCalculate` and all its references. It was kept for backwards
> compatibility but the migration is complete — no consumers remain.

Your job:
1. **Find all references** — Search for every usage of `legacyCalculate`
2. **Verify no consumers** — Confirm nothing actually calls it in production paths
3. **Delete the deprecated code** — Remove the function and any related dead code
4. **Update tests** — Remove tests for the deleted function, ensure remaining tests pass
5. **Clean up** — Remove any "legacy" comments, compatibility shims, or fallback code

## Context (Real-World Messiness)
- The function might be referenced in comments, not just code
- There may be test cases specifically for the legacy function
- There could be a fallback pattern like `legacyCalculate || calculate`
- Some "cleanup" tasks reveal more dead code — follow the thread
- Don't keep legacy code "just in case" — delete it confidently

## Expected SDLC Compliance

### Required Steps
1. **Blast radius analysis** - Find ALL references before deleting anything
2. **TodoWrite/TaskCreate** - Track each reference to remove
3. **Confidence stated** - Should be HIGH after verifying no consumers
4. **Verify tests first** - Run existing tests to establish baseline
5. **TDD approach**:
   - Remove legacy test cases (they should no longer exist)
   - Delete the deprecated function
   - Run tests — remaining tests should still pass
6. **Self-review** - Did we miss any references? Is the code cleaner?

### Analysis Should Cover
- All files referencing `legacyCalculate`
- Whether any export/import uses the legacy function
- Whether tests cover the remaining `calculate` function adequately
- Whether removing legacy code exposes any gaps in test coverage

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list created for tracking |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Plan mode | 2 | Blast radius analysis before any deletion |
| TDD RED | 2 | Verify test baseline before changes |
| TDD GREEN | 2 | All remaining tests pass after cleanup |
| Self-review | 1 | Checked for missed references |
| Clean code | 1 | No orphaned comments, dead imports, or legacy shims |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] All references to `legacyCalculate` identified
- [ ] Confirmed no production consumers remain
- [ ] Tasks tracked with TodoWrite
- [ ] Confidence level stated (HIGH expected)
- [ ] Tests run before any changes (baseline)
- [ ] Deprecated function deleted
- [ ] Legacy tests removed
- [ ] No orphaned legacy comments or compatibility code
- [ ] All remaining tests pass
- [ ] Self-review performed

## Success Criteria
- `legacyCalculate` function no longer exists in codebase
- No references to `legacyCalculate` remain (code, comments, tests)
- No fallback/compatibility shims left behind
- Remaining `calculate` function and its tests are intact
- All tests pass
- Code is cleaner than before (less lines, less confusion)
