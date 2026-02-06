# Testing Strategy

## The Absolute Rule

```
ALL TESTS MUST PASS. NO EXCEPTIONS.

This is not negotiable. This is not flexible. This is absolute.
```

**Not acceptable excuses:**
- "Those tests were already failing" -> Then fix them first
- "That's not related to my changes" -> Doesn't matter, fix it
- "It's flaky, just ignore it" -> Flaky = bug, investigate it
- "It passes locally" -> CI is the source of truth

**The process:**
1. Tests fail -> STOP
2. Investigate -> Find root cause
3. Fix -> Whatever is actually broken
4. All tests pass -> THEN commit

---

## Meta-Testing Challenge

This is a **meta-project** - it's a wizard that sets up other projects. Traditional testing doesn't directly apply.

| Normal Project | This Project |
|----------------|--------------|
| Test source code | Test wizard installation |
| Unit test functions | Test script logic |
| Integration test APIs | Test workflow behavior |
| E2E test user flows | Simulate wizard usage |

## Test Files

### Layer 1: Script Logic Tests

| Test File | Tests | What It Covers |
|-----------|-------|----------------|
| `tests/test-version-logic.sh` | Version comparison | Semver parsing, upgrade detection |
| `tests/test-analysis-schema.sh` | Schema validation | JSON analysis response format |
| `tests/test-workflow-triggers.sh` | Workflow triggers | Dispatch, schedule, event configs |
| `tests/test-cusum.sh` | CUSUM drift detection | Threshold alerts, status tracking |
| `tests/test-stats.sh` | Statistical functions | CI calculation, n=1 handling, compare_ci |
| `tests/test-hooks.sh` | Hook scripts | Output keywords, JSON format, TDD checks |
| `tests/test-compliance.sh` | Compliance checker | Complexity extraction, pattern matching |
| `tests/test-token-extraction.sh` | Token extraction | Native metrics parsing |

**How to run:**
```bash
./tests/test-version-logic.sh
./tests/test-analysis-schema.sh
./tests/test-workflow-triggers.sh
./tests/test-cusum.sh
./tests/test-stats.sh
./tests/test-hooks.sh
./tests/test-compliance.sh
./tests/test-token-extraction.sh
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
- Scoring criteria (7 criteria, 10/11 points)

**How to run:**
```bash
# Validation only (no API key needed)
./tests/e2e/run-simulation.sh

# Full simulation (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=xxx ./tests/e2e/run-simulation.sh
```

### Layer 4: SDP / Statistical Validation

| Test File | Tests | What It Covers |
|-----------|-------|----------------|
| `tests/test-sdp-calculation.sh` | SDP scoring | Raw/adjusted, caps, robustness, interpretations |
| `tests/test-external-benchmark.sh` | External benchmarks | Source fallback, caching, model mapping |

These validate the model-adjusted scoring that distinguishes "model issues" from "wizard issues".

**How to run:**
```bash
./tests/test-sdp-calculation.sh
./tests/test-external-benchmark.sh
```

### Layer 5: E2E JSON Extraction

**Location**: `tests/e2e/test-json-extraction.sh`

Tests JSON parsing utilities used in E2E evaluation.

```bash
./tests/e2e/test-json-extraction.sh
```

## E2E Library Scripts

These are sourced by tests and workflows, not run directly:

| Script | Purpose |
|--------|---------|
| `tests/e2e/lib/stats.sh` | 95% CI calculation, t-distribution, compare_ci |
| `tests/e2e/lib/json-utils.sh` | JSON extraction from Claude output |
| `tests/e2e/lib/external-benchmark.sh` | Multi-source benchmark fetcher |
| `tests/e2e/lib/sdp-score.sh` | SDP calculation logic |
| `tests/e2e/evaluate.sh` | AI-powered SDLC scoring (0-10) |
| `tests/e2e/check-compliance.sh` | Pattern-based compliance checks |
| `tests/e2e/cusum.sh` | CUSUM drift detection |
| `tests/e2e/run-simulation.sh` | E2E test runner |
| `tests/e2e/run-tier2-evaluation.sh` | 5-trial statistical evaluation |

## Test Scenarios

| Scenario | Complexity | File |
|----------|-----------|------|
| Typo Fix | Simple | `tests/e2e/scenarios/simple-typo-fix.md` |
| Add Feature | Medium | `tests/e2e/scenarios/medium-add-feature.md` |
| Refactor | Hard | `tests/e2e/scenarios/hard-refactor.md` |
| Version Upgrade | Medium | `tests/e2e/scenarios/version-upgrade.md` |
| UI Styling | Medium | `tests/e2e/scenarios/ui-styling-change.md` |
| UI Component | Medium | `tests/e2e/scenarios/add-ui-component.md` |
| Tool Permissions | Medium | `tests/e2e/scenarios/tool-permissions.md` |

## CI Integration

Tests run automatically on:
- Every pull request
- Push to main branch

CI runs:
1. YAML validation
2. Shell script checks
3. Prompt file validation
4. State file validation
5. All Layer 1 script tests
6. E2E fixture validation (Layer 3)
7. E2E quick check (Tier 1, 1x run)
8. E2E full evaluation (Tier 2, 5x runs, on `merge-ready` label)

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
