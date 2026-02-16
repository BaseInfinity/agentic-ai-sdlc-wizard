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
| `tests/test-evaluate-bugs.sh` | Evaluate bug regression | Regression tests for evaluate.sh bugs |
| `tests/test-score-analytics.sh` | Score analytics | History parsing, trends, reports |

**How to run:**
```bash
./tests/test-version-logic.sh
./tests/test-analysis-schema.sh
./tests/test-workflow-triggers.sh
./tests/test-cusum.sh
./tests/test-stats.sh
./tests/test-hooks.sh
./tests/test-compliance.sh
./tests/test-evaluate-bugs.sh
./tests/test-score-analytics.sh
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

### Layer 5: E2E Tests

**Location**: `tests/e2e/`

| Test File | What It Covers |
|-----------|----------------|
| `tests/e2e/test-json-extraction.sh` | JSON parsing utilities |
| `tests/e2e/test-multi-call-eval.sh` | Per-criterion prompts + aggregation |
| `tests/e2e/test-eval-prompt-regression.sh` | Golden output validation |
| `tests/e2e/test-eval-validation.sh` | Schema/bounds validation |
| `tests/e2e/test-deterministic-checks.sh` | Grep-based scoring checks |
| `tests/e2e/test-pairwise-compare.sh` | Pairwise tiebreaker logic |
| `tests/e2e/test-scenario-rotation.sh` | Scenario selection/rotation |
| `tests/e2e/test-simulation-prompt.sh` | Simulation prompt construction |

```bash
./tests/e2e/test-json-extraction.sh
./tests/e2e/test-multi-call-eval.sh
./tests/e2e/test-eval-prompt-regression.sh
./tests/e2e/test-eval-validation.sh
./tests/e2e/test-deterministic-checks.sh
./tests/e2e/test-pairwise-compare.sh
./tests/e2e/test-scenario-rotation.sh
./tests/e2e/test-simulation-prompt.sh
```

## E2E Library Scripts

These are sourced by tests and workflows, not run directly:

| Script | Purpose |
|--------|---------|
| `tests/e2e/lib/stats.sh` | 95% CI calculation, t-distribution, compare_ci |
| `tests/e2e/lib/json-utils.sh` | JSON extraction from Claude output |
| `tests/e2e/lib/external-benchmark.sh` | Multi-source benchmark fetcher |
| `tests/e2e/lib/sdp-score.sh` | SDP calculation logic |
| `tests/e2e/lib/eval-criteria.sh` | Per-criterion prompts + aggregation (v3) |
| `tests/e2e/lib/eval-validation.sh` | Schema/bounds validation + prompt version |
| `tests/e2e/lib/deterministic-checks.sh` | Grep-based scoring (task_tracking, confidence, tdd_red) |
| `tests/e2e/lib/scenario-selector.sh` | Scenario auto-discovery and rotation |
| `tests/e2e/evaluate.sh` | AI-powered SDLC scoring (0-10) |
| `tests/e2e/check-compliance.sh` | Pattern-based compliance checks |
| `tests/e2e/cusum.sh` | CUSUM drift detection (total + per-criterion) |
| `tests/e2e/run-simulation.sh` | E2E test runner |
| `tests/e2e/run-tier2-evaluation.sh` | 5-trial statistical evaluation |
| `tests/e2e/pairwise-compare.sh` | Pairwise tiebreaker comparison |
| `tests/e2e/score-analytics.sh` | Score history analytics and trends |

## Test Scenarios

| Scenario | Complexity | File |
|----------|-----------|------|
| Typo Fix | Simple | `tests/e2e/scenarios/simple-typo-fix.md` |
| Add Feature (original) | Medium | `tests/e2e/scenarios/add-feature.md` |
| Add Feature (medium) | Medium | `tests/e2e/scenarios/medium-add-feature.md` |
| Fix Bug | Medium | `tests/e2e/scenarios/fix-bug.md` |
| Refactor (original) | Medium | `tests/e2e/scenarios/refactor.md` |
| Refactor (hard) | Hard | `tests/e2e/scenarios/hard-refactor.md` |
| Version Upgrade | Medium | `tests/e2e/scenarios/version-upgrade.md` |
| UI Styling | Medium | `tests/e2e/scenarios/ui-styling-change.md` |
| UI Component | Medium | `tests/e2e/scenarios/add-ui-component.md` |
| Tool Permissions | Medium | `tests/e2e/scenarios/tool-permissions.md` |
| Multi-File API Endpoint | Medium | `tests/e2e/scenarios/multi-file-api-endpoint.md` |
| Production Bug Investigation | Hard | `tests/e2e/scenarios/production-bug-investigation.md` |
| Technical Debt Cleanup | Medium | `tests/e2e/scenarios/technical-debt-cleanup.md` |

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

Workflows require the GitHub Actions environment (secrets, runner context, `claude-code-action@v1`). They cannot be tested locally with `act`.

**What you can test locally:**
```bash
# YAML syntax validation
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"

# All script-based tests (no API key needed)
./tests/test-version-logic.sh && ./tests/test-analysis-schema.sh

# E2E simulation (requires ANTHROPIC_API_KEY)
ANTHROPIC_API_KEY=xxx ./tests/e2e/run-simulation.sh
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
