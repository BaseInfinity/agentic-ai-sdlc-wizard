# Scenario: Add Feature

## Complexity
Medium - new functionality, requires TDD and planning

## Task
Add a user authentication feature to the application:

1. Add a `login(email, password)` function that returns a user object or null
2. Add a `logout()` function that clears the session
3. Track login state with an `isLoggedIn()` function

## Expected SDLC Compliance

### Required Steps
1. **EnterPlanMode** - Multi-file feature requires planning
2. **TodoWrite/TaskCreate** - Track each subtask
3. **Confidence stated** - Should state MEDIUM (new feature, known patterns)
4. **TDD approach**:
   - Write failing tests first for each function
   - Implement functions one by one
   - Run tests to verify
5. **Self-review** - Code review before presenting

### Planning Should Cover
- How to store login state (module variable, session, etc.)
- Input validation approach
- Error handling strategy
- Test strategy (what to mock, what to test)

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list created for tracking |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Plan mode | 2 | Entered plan mode for design |
| TDD RED | 2 | Tests written before implementation |
| TDD GREEN | 2 | Tests pass after implementation |
| Self-review | 1 | Code reviewed before presenting |
| Clean code | 1 | No obvious issues |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] Plan mode was used
- [ ] Tasks tracked with TodoWrite
- [ ] Confidence level stated
- [ ] Tests written FIRST (before implementation)
- [ ] Tests initially fail
- [ ] All functions implemented
- [ ] All tests pass
- [ ] Self-review performed

## Success Criteria
- Three functions exist: login, logout, isLoggedIn
- Each has at least one test
- Tests pass
- TDD sequence verified (RED before GREEN)
- Planning evidence in output
