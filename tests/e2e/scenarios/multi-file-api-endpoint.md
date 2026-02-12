# Scenario: Add a New REST API Endpoint

## Complexity
Medium - multi-file changes, requires cross-module coordination

## Task
A product manager requests a new `/api/users/:id/preferences` endpoint.

Requirements:
1. **GET /api/users/:id/preferences** — returns user preferences object
2. **PUT /api/users/:id/preferences** — updates preferences, validates input
3. Preferences include: `{ theme: "light"|"dark", notifications: boolean, language: string }`
4. Return 404 if user not found, 400 for invalid input

You need to create/modify:
- Route handler (register the new route)
- Controller logic (validation + business logic)
- Data layer (storage/retrieval — can use in-memory for this task)
- Tests for each layer

## Context (Real-World Messiness)
- The existing codebase has routes in `src/app.js` — follow the existing pattern
- There's no formal validation library — use manual checks
- The existing test file has examples of how HTTP-style tests are structured
- This is a typical "ticket from the backlog" task — clear requirements but
  you decide the implementation details

## Expected SDLC Compliance

### Required Steps
1. **Plan approach** - Multi-file feature needs upfront design
2. **TodoWrite/TaskCreate** - Break down into subtasks (route, controller, data, tests)
3. **Confidence stated** - Should state MEDIUM (clear requirements, multiple files)
4. **TDD approach**:
   - Write tests for the preferences functions FIRST
   - Tests should fail (no implementation yet)
   - Implement the feature across files
   - Tests pass
5. **Self-review** - Check for missing edge cases, consistent patterns

### Planning Should Cover
- File structure decisions (where does each piece go?)
- Data storage approach (in-memory object, module-level state)
- Validation rules for each preference field
- Error response format consistency with existing endpoints
- Test coverage plan (happy path + error cases)

### SDLC Checklist (Score-able)
| Step | Weight | Description |
|------|--------|-------------|
| TodoWrite used | 1 | Task list created for tracking |
| Confidence stated | 1 | HIGH/MEDIUM/LOW stated |
| Plan mode | 2 | Multi-file approach planned before coding |
| TDD RED | 2 | Tests written before implementation |
| TDD GREEN | 2 | Tests pass after implementation |
| Self-review | 1 | Code reviewed before presenting |
| Clean code | 1 | Consistent patterns, no obvious issues |

**Total possible: 10 points**
**Pass threshold: 7 points**

## Verification Criteria
- [ ] Plan covers all files to be created/modified
- [ ] Tasks tracked with TodoWrite
- [ ] Confidence level stated
- [ ] Tests written FIRST covering GET and PUT
- [ ] Tests initially fail
- [ ] All preference functions implemented
- [ ] Input validation works (invalid theme, missing fields)
- [ ] Error handling (404, 400) implemented
- [ ] All tests pass
- [ ] Self-review performed

## Success Criteria
- GET endpoint returns preferences for existing user
- PUT endpoint validates and stores preferences
- 404 for non-existent user
- 400 for invalid preference values
- Tests cover happy path and error cases
- TDD sequence verified
- Code follows existing project patterns
