# Contributing to SDLC Wizard

Thank you for your interest in improving the SDLC Wizard!

## Quick Start

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Make your changes
4. Run tests:
   ```bash
   ./tests/test-version-logic.sh && ./tests/test-analysis-schema.sh && \
   ./tests/test-workflow-triggers.sh && ./tests/test-cusum.sh && \
   ./tests/test-stats.sh && ./tests/test-hooks.sh && \
   ./tests/test-compliance.sh && ./tests/test-sdp-calculation.sh && \
   ./tests/test-external-benchmark.sh
   ```
5. Submit a PR

## How We Evaluate Changes

We use statistical evaluation to ensure changes don't degrade SDLC enforcement quality.

### Why Multiple Trials?

AI is stochastic - same prompt, different outputs. Single measurements are unreliable.
We run 5 trials per evaluation to get statistically meaningful results.

### Scoring Criteria (10 points total)

| Criterion | Points | Type | What It Measures |
|-----------|--------|------|------------------|
| TodoWrite/TaskCreate | 1 | Deterministic | Task tracking (grep for tool call) |
| Confidence stated | 1 | Deterministic | Process compliance (grep for level) |
| Plan mode | 2 | AI-judge | Appropriate for task complexity |
| TDD RED | 2 | Deterministic | Test file created before impl |
| TDD GREEN | 2 | Deterministic | Tests pass (exit code) |
| Self-review | 1 | AI-judge | Meaningful review performed |
| Clean code | 1 | AI-judge | Quality and coherence |

**Hybrid approach:** 60% deterministic (reproducible, can't be gamed) + 40% AI-judged (captures nuance, 5 trials handle variance).

### SDP Scoring (Model Degradation Tracking)

PR comments now include SDP (SDLC Degradation-adjusted Performance) to distinguish "model issues" from "our issues":

| Layer | Metric | Source |
|-------|--------|--------|
| **L1: Model** | External Benchmark | DailyBench, LiveBench |
| **L2: SDLC** | Raw Score | Our E2E evaluation |
| | SDP (adjusted) | Raw × (baseline / current external) |
| **Combined** | Robustness | How well SDLC holds up vs model changes |

**Interpretation:**
- SDP > Raw = Model degraded, we adjusted up
- Robustness < 1.0 = Our SDLC is more resilient than the model (good!)
- Robustness > 1.0 = Our SDLC is more sensitive than the model (investigate)

### Statistical Methodology

- **5 trials** per evaluation (balances cost vs statistical power)
- **95% confidence intervals** using t-distribution
- **Overlapping CI method** for comparing before/after:
  - IMPROVED: candidate CI lower bound > baseline CI upper bound
  - STABLE: CIs overlap (no significant difference)
  - REGRESSION: candidate CI upper bound < baseline CI lower bound

### Tier System for PRs

| Source | Tier 1 (Quick) | Tier 2 (Full) |
|--------|----------------|---------------|
| Our auto-workflows | Always | Always |
| External PRs | Always | On request (`merge-ready` label) |

Tier 1 gives fast feedback (1 trial). Tier 2 gives statistical confidence (5 trials).

## CUSUM Drift Detection

We track scores over time using CUSUM (Cumulative Sum) to catch gradual drift that before/after comparisons might miss.

```bash
# Check current drift status
./tests/e2e/cusum.sh --status
```

If CUSUM shows drift, we investigate before the situation worsens.

## Version Update Testing

When Claude Code updates, we test:
1. **Phase A (Regression)**: Does new CC version break our SDLC enforcement?
2. **Phase B (Improvement)**: Do changelog-suggested changes improve scores?

Results are posted to the PR with statistical confidence.

## What Makes a Good PR

- **Focused**: One logical change per PR
- **Tested**: Existing tests pass, new tests for new functionality
- **Documented**: Update relevant docs if behavior changes
- **KISS**: Simpler is better

## What We Don't Accept

- Over-engineering (keep it simple)
- Changes without tests
- Breaking changes to core SDLC principles (TDD, confidence levels, planning)
- Removing statistical rigor from evaluation

## We're Open to Suggestions

This methodology is evolving. If you have ideas for improving our evaluation approach, open an issue first to discuss.

## Local Development

```bash
# Validate YAML workflows
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/daily-update.yml'))"

# Run all test suites
./tests/test-version-logic.sh
./tests/test-analysis-schema.sh
./tests/test-workflow-triggers.sh
./tests/test-cusum.sh
./tests/test-stats.sh
./tests/test-hooks.sh
./tests/test-compliance.sh
./tests/test-sdp-calculation.sh
./tests/test-external-benchmark.sh

# Run E2E validation (no API key needed)
./tests/e2e/run-simulation.sh --validate

# Run full E2E (requires ANTHROPIC_API_KEY)
export ANTHROPIC_API_KEY=your-key
./tests/e2e/run-simulation.sh
```

## Questions?

Open an issue or check the [discussions](https://github.com/BaseInfinity/sdlc-wizard/discussions).

