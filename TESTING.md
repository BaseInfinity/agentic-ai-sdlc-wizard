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

## TDD: RED → GREEN, and what to do with an old test

**Write the test first. Run it. Watch it FAIL — that specific assertion, not just the suite.
Then implement. Run it again. It passes.** If it does not, the implementation is wrong, or
the test is asserting the wrong thing. Both are information.

**Watch each NEW assertion fail individually.** The common miss is observing red at the
*suite* level: one assertion fails, the suite is red, you implement, the suite goes green —
and an assertion that was green from birth is never noticed. It is testing nothing, and you
will not find out until it fails to catch a real regression.

**Editing an old test is the hard case, and the honest answer depends on what it guards.**

- **Guarding a bug you are about to fix?** RED is free. The bug exists, so write the test
  first and it fails for the right reason. This is the common case and needs no workaround.
- **Guarding behaviour that is ALREADY correct?** **You cannot get RED.** Correct code does
  not fail, and no amount of rewriting changes that. Say so plainly rather than claiming the
  test is verified — an unverified regression assertion is exactly how this repo shipped
  eight tests that passed against broken code. If the assertion is load-bearing enough to
  justify it, breaking the behaviour once to watch the test go red is the only mechanism that
  validates it; that is a deliberate exception, not the routine.

**Either way, prefer rewriting a suspect test over patching it.** Measured 2026-07-29/30: one
was found ineffective three separate times and patched twice; the rewrite worked first try.
Patching guesses which missing piece mattered; a rewrite from a known-good fixture with
exactly one deliberate defect does not have to guess.

**Signs a test needs rewriting rather than patching:**
- It passes when you would expect it to fail
- Its fixture is broken in more than one way, so you cannot tell which one it is detecting
- It asserts on a substring that appears in both the pass and the fail message

**Test behaviour in the executable that enforces it.** Grep a doc only when the doc content
IS the executable — a command or template followed verbatim — or the only pointer to one, and
nothing downstream fails closed without it. Measured 2026-08-08: a doc-grep protecting a rule
that the tested gate hook already enforces was defeated four times in review and protected nothing.

## Testing Diamond — the shape we aim for

| Layer | Share | What it is |
|---|---|---|
| E2E | ~5% | Slow, proves the real thing end to end |
| **Integration** | **~90%** | Real components through real interfaces; the best value |
| Unit | ~5% | Pure input → output logic only |

**Minimal mocking.** Never mock a database or cache — use a test instance. Mock external
APIs (real calls are flaky and cost money) and time. Any mock must be built from real captured
data, never a guessed shape.

### How that maps to THIS repo, and where we actually stand

This is a meta-repo of shell scripts, so "integration" means *run the real script against a
stubbed external binary* — e.g. `tests/test-cross-model-clearance.sh` puts a fake `gh` on
`PATH` and executes the real `scripts/merge-pr.sh`. That is the diamond's middle layer, and it
is where this repo's real bugs have been caught.

**The current distribution is NOT reliably known, and that is the honest state.** Two attempts
at classifying the 64 script suites disagreed with each other, and 39 fell through both
heuristics — so any ratio quoted here would be a number nobody has verified. What IS verified:
26 suites create a temp dir or stub a binary (integration-shaped), 8 E2E suites exist, and at
least 15 assert only on source text. Producing a real, reproducible per-suite census is the
first task of ROADMAP #490; until it lands, do not cite a distribution.

What is already clear without a census: **some suites test script behaviour by grepping source
text rather than executing it.** That is a unit test standing where an integration test belongs,
and it is the shape behind every ineffective test this repo has found. Prefer executing the real
script over asserting on its source.

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
| `tests/test-domain-detection.sh` | Domain detection | Domain-adaptive testing layers, detection patterns, fixture validation |
| `tests/test-autocompact-methodology.sh` | Autocompact benchmarking methodology | Methodology rigor, harness quality, task suite, canary facts |
| `tests/test-node24-compliance.sh` | Node 24 compliance | No deprecated node20 actions, correct versions, no node-version: 20 |
| `tests/test-effectiveness-scoreboard.sh` | Effectiveness scoreboard | Seed data quality, DDE calculation, escape rate, analytics output |
| `tests/test-firmware-fixture.sh` | Firmware fixture | Domain indicators, Python overlay, test infra, multi-device, no-web negative test |
| `tests/test-doc-consistency.sh` | Doc consistency | Workflow/file/skill/scenario counts match filesystem, no stale hardcoded counts; wizard-doc effort-section hardening (adaptive thinking, Pro/Max scope, anti-laziness mechanisms) |

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
./tests/test-domain-detection.sh
./tests/test-autocompact-methodology.sh
./tests/test-node24-compliance.sh
./tests/test-firmware-fixture.sh
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
- Scoring criteria (10 checks across 7 categories, up to 11 points on UI scenarios)

**How to run:**
```bash
./tests/e2e/run-simulation.sh
```
Falls back to validation-only mode (checks fixtures/scenarios, no live run) if
the `claude` CLI isn't on PATH. Otherwise runs the full simulation via
`claude --print` on your authenticated CLI session — no `ANTHROPIC_API_KEY`
needed or read.

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
| `tests/e2e/evaluate.sh` | AI-powered SDLC scoring (0-10, up to 11 for UI scenarios) |
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
| Expand Test Coverage | Medium | `tests/e2e/scenarios/expand-test-coverage.md` |
| Add Batch Operations | Medium | `tests/e2e/scenarios/add-batch-operations.md` |
| Add Task Persistence | Medium | `tests/e2e/scenarios/add-task-persistence.md` |

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

# E2E simulation (full run requires an authenticated Claude Code CLI)
./tests/e2e/run-simulation.sh
```

## Playwright MCP vs Playwright Tests

**They are different tools for different jobs. Don't confuse them.**

| | Playwright MCP (debugging) | Playwright Test Framework (automation) |
|---|---|---|
| **What** | MCP server Claude uses to interact with a live browser | Automated test runner (`npx playwright test`) |
| **When** | Debugging a visual issue, inspecting DOM state, verifying a fix looks right | Regression testing on every PR, CI gating |
| **Who runs it** | Claude (via MCP tool calls during a conversation) | CI pipeline (headless, no human) |
| **Repeatable** | No — interactive, exploratory, one-off | Yes — deterministic, runs the same every time |
| **Replaces** | A human opening DevTools to inspect the page | Nothing — this IS the automated test layer |

**Playwright MCP replaces a human doing visual testing.** Instead of you opening a browser, clicking around, and eyeballing whether things look right — Claude does it. For any web project, this is huge:
- "Does this CSS change actually look right?" — Claude screenshots it and tells you
- "Is the modal centered on mobile?" — Claude resizes the viewport and checks
- "Click through the checkout flow and tell me what breaks" — Claude does it like a QA tester would
- "What's the DOM state after this interaction?" — Claude inspects it like DevTools

**It does NOT replace `npx playwright test`.** Automated browser regression tests must:
- Run headless in CI on every PR
- Cover critical user flows (login, checkout, form submission)
- Catch regressions without human intervention
- Produce deterministic pass/fail results

**The rule:** Use Playwright MCP to debug and verify during development. Use Playwright tests to prevent regressions in CI. If someone tells you "we have Playwright MCP so we don't need E2E tests" — that's like saying "I have Chrome DevTools so I don't need a test suite."

## Known Gaps

### Cannot Fully Test in CI
- Real interactive hook firing inside live user sessions
- PR/issue creation side effects (requires repo permissions)

### What CI Does Test
- Script-level tests use fixtures (no API key needed)
- E2E quick-check and full-evaluation run real Claude API simulations on PRs
- Structure, logic, and scoring validation on every push
