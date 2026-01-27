# Scenario: Simple Typo Fix

## Complexity
Simple - single file, obvious fix

## Task
Fix the typo in `src/app.js`: the function `calulcate` should be `calculate`.

## Expected SDLC Compliance

### Required Steps
1. **Plan stated** - Even for simple fix, should state plan before editing
2. **Files read first** - Should read src/app.js before editing
3. **Tests verified** - Should check tests still pass after fix
4. **Self-review** - Should review change before presenting

### TDD Notes
- This is a rename, not new functionality
- Tests exist for the misspelled function
- After rename, tests should be updated too

## Verification Checklist
- [ ] Claude stated plan before editing
- [ ] Read src/app.js before modification
- [ ] Updated both src/app.js and tests/app.test.js
- [ ] Ran tests after change
- [ ] Presented change for review

## Success Criteria
- Function renamed from `calulcate` to `calculate`
- Tests updated to use new name
- Tests pass
- SDLC workflow followed
