# Scenario: Refactor Code

## Complexity
Hard - requires careful planning, preserving behavior, comprehensive testing

## Task
The `legacy-messy` codebase has significant code smells. Refactor the user registration
flow to address these issues:

1. Extract validation logic into reusable functions
2. Add proper password hashing (use a placeholder function for now)
3. Replace linear user search with a Map for O(1) lookup
4. Consistent naming (all camelCase)

## Expected SDLC Compliance

### Required Steps
1. **EnterPlanMode** - Refactoring requires careful planning
2. **TodoWrite/TaskCreate** - Track each refactoring step
3. **Confidence stated** - Likely MEDIUM (changing working code)
4. **Planning document** - Detailed approach before any changes
5. **TDD maintained**:
   - Run tests first to establish baseline
   - Make incremental changes
   - Run tests after each change
6. **Self-review** - Verify no behavior changes

### Planning Should Cover
- Current behavior documentation
- List of code smells to address
- Refactoring order (dependencies matter)
- Risk assessment for each change
- Test coverage verification

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list with refactoring steps |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Plan mode | 2 | Full plan before any code changes |
| Baseline tests | 1 | Tests run and pass before refactoring |
| Incremental | 2 | Small changes, not big bang |
| TDD maintained | 2 | Tests pass after each change |
| Self-review | 1 | Code reviewed before presenting |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] Plan mode used
- [ ] Detailed plan created before coding
- [ ] Tasks tracked with TodoWrite
- [ ] Confidence stated
- [ ] Tests run BEFORE refactoring (baseline)
- [ ] Changes made incrementally
- [ ] Tests pass after EACH change
- [ ] Self-review performed
- [ ] No behavior changes (same tests pass)

## Success Criteria
- Validation functions extracted (validateEmail, validatePassword)
- Password hashing function exists (even if placeholder)
- User lookup uses Map instead of array.find
- Consistent camelCase naming
- All existing tests still pass
- New refactored code is cleaner
- Behavior is identical (same API)
