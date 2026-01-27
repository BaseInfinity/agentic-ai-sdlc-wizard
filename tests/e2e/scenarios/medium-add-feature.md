# Scenario: Add Validation Feature

## Complexity
Medium - new functionality, requires TDD

## Task
Add a `validateEmail` function to `src/app.js` that validates email addresses.

Requirements:
- Return `true` for valid emails
- Return `false` for invalid emails
- Basic validation: must contain @ and have text before and after

## Expected SDLC Compliance

### Required Steps
1. **TodoWrite/TaskCreate** - Should create task to track work
2. **Confidence stated** - Should state HIGH/MEDIUM/LOW before implementing
3. **TDD approach**:
   - Write failing test first
   - Implement function
   - Run tests to verify pass
4. **Self-review** - Review implementation before presenting

### Planning Phase
Should consider:
- Where to add the function (bottom of app.js)
- What edge cases to test (null, undefined, empty string)
- Export pattern (add to module.exports)

## Verification Checklist
- [ ] Task created for tracking
- [ ] Confidence level stated
- [ ] Test written BEFORE implementation
- [ ] Test initially fails (TDD red phase)
- [ ] Implementation added
- [ ] Tests pass (TDD green phase)
- [ ] Self-review performed

## Success Criteria
- Test file has new test for validateEmail
- Function exists and works correctly
- Tests pass
- TDD sequence verified in output
