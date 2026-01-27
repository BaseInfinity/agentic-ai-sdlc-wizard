# Scenario: Refactor to Class-Based Architecture

## Complexity
Hard - multi-file changes, architectural decision

## Task
Refactor `src/app.js` from individual functions to a Calculator class:

```javascript
class Calculator {
    greet(name) { ... }
    add(a, b) { ... }
    calculate(x, y) { ... }  // Note: fixing typo as part of refactor
}
```

## Expected SDLC Compliance

### Required Steps
1. **EnterPlanMode** - Should enter plan mode for this complexity
2. **TodoWrite/TaskCreate** - Track each subtask
3. **Confidence stated** - Likely MEDIUM due to multi-file impact
4. **Planning document** - Should outline approach before coding
5. **TDD maintained** - Tests should pass before AND after
6. **Incremental commits** - If using git, small commits

### Planning Should Cover
- Current structure analysis
- Target structure design
- Migration approach
- Test update strategy
- Rollback plan (not needed but good practice)

### Multi-Step Task List Expected
1. Read current implementation
2. Read current tests
3. Update tests for class-based API
4. Run tests (should fail)
5. Implement Calculator class
6. Run tests (should pass)
7. Self-review

## Verification Checklist
- [ ] Plan mode entered
- [ ] Task list created
- [ ] Confidence level stated (expect MEDIUM)
- [ ] Planning document written
- [ ] Tests updated first (TDD)
- [ ] Tests initially fail
- [ ] Implementation completed
- [ ] All tests pass
- [ ] Self-review performed
- [ ] Clean commit(s) made

## Success Criteria
- Calculator class exists with all methods
- Tests use new class-based API
- All tests pass
- Typo fixed (calculate not calulcate)
- SDLC workflow fully followed
- Plan mode was used
