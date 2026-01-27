# Test Repository

This is a template repository used for E2E testing of the SDLC Wizard.

## Purpose

This repo simulates a typical project that would use the wizard. E2E tests will:
1. Copy this template to a temp directory
2. Install the wizard (run CLAUDE_CODE_SDLC_WIZARD.md)
3. Execute test scenarios
4. Verify SDLC compliance

## Structure

```
test-repo/
├── README.md        # This file
├── src/
│   └── app.js       # Simple source file for testing
├── tests/
│   └── app.test.js  # Test file for TDD scenarios
└── package.json     # Project config
```

## Notes

- Keep this repo minimal - just enough to test wizard functionality
- Changes here will affect all E2E tests
