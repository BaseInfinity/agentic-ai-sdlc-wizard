# Legacy Messy Fixture

E2E test fixture with **intentionally bad code** for testing refactoring scenarios.

## Known Issues (By Design)
- Global mutable state
- Copy-pasted validation logic
- Magic numbers
- Inconsistent naming (camelCase/snake_case mixed)
- No password hashing (security issue)
- Linear searches instead of maps
- Functions doing too many things
- Callback-style code
- No proper error handling
- No input sanitization

## Purpose
Test that the SDLC Wizard can:
1. Identify code smells
2. Suggest appropriate refactoring
3. Write tests before refactoring (TDD)
4. Incrementally improve code quality

## Commands
- `npm start` - Start server
- `npm test` - Run tests

## Refactoring Scenarios
- Extract validation functions
- Add password hashing
- Replace linear searches with maps
- Add proper error handling
- Split large functions
- Add consistent naming
