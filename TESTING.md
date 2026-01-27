# Testing Strategy

## Meta-Testing Challenge

This is a **meta-project** - it's a wizard that sets up other projects. Traditional testing doesn't directly apply.

| Normal Project | This Project |
|----------------|--------------|
| Test source code | Test wizard installation |
| Unit test functions | Test script logic |
| Integration test APIs | Test workflow behavior |
| E2E test user flows | Simulate wizard usage |

## Test Layers

### Layer 1: Script Logic Tests

**Location**: `tests/test-version-logic.sh`, `tests/test-analysis-schema.sh`

**What they test**:
- Version comparison logic
- JSON schema validation
- Relevance filtering logic

**How to run**:
```bash
./tests/test-version-logic.sh
./tests/test-analysis-schema.sh
```

### Layer 2: Fixture Validation

**Location**: `tests/fixtures/releases/`

**What they test**:
- Analysis response format
- Relevance categorization (HIGH/MEDIUM/LOW)
- Required JSON fields present

### Layer 3: E2E Simulation

**Location**: `tests/e2e/`

**What it tests**:
- Wizard installation on test repo
- SDLC compliance during tasks
- Hook firing behavior

**How to run**:
```bash
# Validation only (no API key needed)
./tests/e2e/run-simulation.sh

# Full simulation (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=xxx ./tests/e2e/run-simulation.sh
```

## Test Scenarios

### Simple: Typo Fix
- Basic SDLC flow
- Read before edit
- Verify change works

### Medium: Add Feature
- TDD approach verified
- Confidence level stated
- Task tracking used

### Hard: Refactor
- Plan mode required
- Multi-step task list
- Full SDLC compliance

## CI Integration

Tests run automatically on:
- Every pull request
- Push to main branch

CI runs:
1. YAML validation
2. Script logic tests
3. Schema validation
4. E2E fixture validation

## Manual Testing

For workflow changes, test locally with `act`:

```bash
# Test daily update workflow
act workflow_dispatch -W .github/workflows/daily-update.yml \
    --secret-file .env.test

# Test CI workflow
act pull_request -W .github/workflows/ci.yml
```

## Known Gaps

### Cannot Fully Test in CI
- Actual Claude API responses (mocked in fixtures)
- PR/issue creation (requires repo permissions)
- Hook firing during real sessions

### Mitigation
- Validate structure/logic in CI
- Manual testing before merge
- E2E simulation with real API locally
