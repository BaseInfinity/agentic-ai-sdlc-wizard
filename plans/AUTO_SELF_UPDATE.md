# Auto Self-Update Plan

> Status: IMPLEMENTED & VALIDATED - See `.github/workflows/`
> Last Validated: 2026-02-02 (E2E workflow fix - proper Claude simulation before evaluation)

## Overview

A self-evolving system that keeps the wizard in sync with Claude Code updates and community best practices through automated research and human-approved updates.

## Unified Workflow Pattern

All three auto-update workflows now follow the same pattern:

```
Detect something new → Suggest changes → Test with E2E → Create PR with results
```

| Workflow | Detects | Suggests Changes To | Tests | Output |
|----------|---------|---------------------|-------|--------|
| **daily-update** | New CC version | N/A (Phase A) or SDLC docs (Phase B) | Regression/Improvement | PR with scores |
| **weekly-community** | Community patterns | SDLC docs based on patterns | Do patterns improve us? | PR with scores |
| **monthly-research** | Research trends | SDLC docs based on trends | Do trends improve us? | PR with scores |

### Two-Phase Version Testing

**Phase A: Regression Test** ("Did the update break us?")
- Install new Claude Code version in CI
- Run E2E with current SDLC wizard (unchanged)
- Compare to stored baseline
- STABLE or IMPROVED → Safe to upgrade
- REGRESSION → Don't upgrade, investigate

**Phase B: Improvement Test** ("Does incorporating changes help?")
- Claude analyzes changelog → auto-applies SDLC doc changes
- Run E2E with modified docs
- Compare to Phase A baseline using 95% CI
- IMPROVED → Merge suggested changes
- STABLE → Changes neutral, merge optional
- REGRESSION → Don't merge changes

### Tier System

| Tier | Runs | Statistical Power | Cost |
|------|------|-------------------|------|
| **Tier 1 (Quick)** | 1x | Low (directional only) | ~$0.50 |
| **Tier 2 (Full)** | 5x | High (95% CI) | ~$2.50 |

**Who Gets What:**
- **Our auto-workflows** (daily/weekly/monthly): Tier 1 + Tier 2 always
- **External PRs**: Tier 1 only (Tier 2 on request via `merge-ready` label)

## What's Implemented

### Daily Update Check (`.github/workflows/daily-update.yml`)
- **Trigger:** Daily at 9 AM UTC + manual dispatch
- **Checks:** Claude Code GitHub releases
- **Action:** Creates PR for ALL updates (relevance shown in title)
- **E2E Testing:** Phase A (regression) + Phase B (improvement) with Tier 1 + 2

### Weekly Community Scan (`.github/workflows/weekly-community.yml`)
- **Trigger:** Sundays at 9 AM UTC + manual dispatch
- **Checks:** Reddit, HN, dev blogs, official channels
- **Action:** Creates digest issue for notable findings
- **E2E Testing:** Baseline vs with-changes comparison (Tier 2)

### Monthly Research Deep Dive (`.github/workflows/monthly-research.yml`)
- **Trigger:** 1st of month at 9 AM UTC + manual dispatch
- **Checks:** Academic papers, major announcements, deep community analysis
- **Action:** Creates issue with trend report and recommendations
- **E2E Testing:** Baseline vs with-changes comparison (Tier 2)

### PR Code Review (`.github/workflows/pr-review.yml`)
- **Trigger:** All PRs
- **Action:** AI code review using GitHub MCP tools
- **Tools:** Proper review workflow (pending review → comments → submit)

### CI with E2E Evaluation (`.github/workflows/ci.yml`)
- **Trigger:** All PRs and pushes to main
- **Tests:** YAML validation, shell checks, state files, unit tests
- **E2E:** Full SDLC evaluation for bot/owner PRs (score 0-10, threshold 7.0)

## Summary of Workflows

| Trigger | Workflow | What It Does |
|---------|----------|--------------|
| Daily 9AM | daily-update.yml | Check releases → Always PR |
| Sundays | weekly-community.yml | Scan community → Issue |
| 1st of month | monthly-research.yml | Deep research → Issue |
| On PR | ci.yml | Run tests + E2E eval |
| On PR | pr-review.yml | AI code review |

## Who Gets What on PR

| Source | Tests | Review | E2E Eval |
|--------|-------|--------|----------|
| Bot | Yes | Yes | Yes |
| Owner | Yes | Yes | Yes |
| External | Yes | Yes | No |

## Key Design Decisions

| Decision | Choice | Why |
|----------|--------|-----|
| Official sources | Daily | Releases every 1-2 days, need timely updates |
| Community sources | Weekly | Less urgent, more noise, digest format |
| Deep research | Monthly | Papers/trends don't change daily |
| State storage | Files in repo | Simple, transparent, version-controlled |
| Analysis | Claude API | Nuanced understanding of wizard philosophy |
| PR threshold | All updates | Human decides relevance, not automation |
| E2E threshold | 7.0/10 | Balance between strictness and practicality |
| Default stance | Don't add | Only suggest if genuinely needed |

## Files Structure

```
.github/
├── workflows/
│   ├── daily-update.yml      # Official release monitoring
│   ├── weekly-community.yml  # Community discussion scanning
│   ├── monthly-research.yml  # Deep research and trends
│   ├── ci.yml                # Tests + E2E evaluation
│   └── pr-review.yml         # AI code review
├── prompts/
│   ├── analyze-release.md    # Claude prompt for release analysis
│   └── analyze-community.md  # Claude prompt for community scan
├── last-checked-version.txt  # Last processed Claude Code version
└── last-community-scan.txt   # Last community scan date

tests/
├── test-version-logic.sh     # Version comparison tests
├── test-cusum.sh             # CUSUM drift detection tests
├── test-analysis-schema.sh   # Analysis schema tests
└── e2e/
    ├── fixtures/             # Sample projects for testing
    │   ├── test-repo/        # Basic JS
    │   ├── nextjs-typescript/# Next.js + TS + Prisma
    │   ├── python-fastapi/   # FastAPI + LangChain
    │   ├── mern-stack/       # MongoDB + Express + React + Node
    │   ├── go-api/           # Go + PostgreSQL
    │   └── legacy-messy/     # Intentionally bad code
    ├── scenarios/            # Test scenarios
    │   ├── add-feature.md
    │   ├── fix-bug.md
    │   ├── refactor.md
    │   └── version-upgrade.md # Version testing scenario
    ├── lib/
    │   ├── stats.sh          # Statistical functions (CI, compare)
    │   └── json-utils.sh     # JSON extraction utilities
    ├── run-simulation.sh     # Full E2E test runner
    ├── run-tier2-evaluation.sh # Shared 5-trial evaluation script
    ├── evaluate.sh           # AI-powered scoring (0-10)
    ├── check-compliance.sh   # Pattern-based checks
    ├── cusum.sh              # CUSUM drift detection
    ├── score-history.txt     # Historical scores for CUSUM
    └── baselines.json        # Baseline scores per scenario
```

## E2E Evaluation Flow

```
1. Pick scenario (add-feature, fix-bug, refactor)
2. Set up fixture (nextjs-typescript, python-fastapi, etc.)
3. Run Claude with scenario task
4. AI evaluates output against SDLC criteria:
   - TodoWrite used? (1 point)
   - Confidence stated? (1 point)
   - Plan mode? (2 points)
   - TDD RED? (2 points)
   - TDD GREEN? (2 points)
   - Self-review? (1 point)
   - Clean code? (1 point)
5. Score 0-10, pass if >= 7.0
```

## Required Secrets

- `ANTHROPIC_API_KEY` - for Claude analysis in workflows
- `GITHUB_TOKEN` - for PR/issue creation (automatic)

## Philosophy Preserved

- KISS - minimal files, simple flow
- Human-in-the-loop - PRs/issues require review, you always decide
- Wizard philosophy - baked into analysis prompts
- Use official when available - prompts check for plugin replacements
- Self-evolving - system improves itself through research and feedback

## Organic Improvement

**Baselines evolve with you:**
- Start conservative (D/C level, scores 4.0-6.0)
- Raise baselines after 3 consecutive runs above current baseline
- This is a journey, not a destination

**Low scores are feedback, not failure:**
- Score < baseline? That's information about where to improve
- Analyze criteria breakdown to see specific gaps
- Each PR is a data point in your improvement trend

**Regression detection:**
| Condition | Result |
|-----------|--------|
| `score >= baseline` | PASS - meets or exceeds expectations |
| `score >= min_acceptable` | WARN - below baseline but acceptable |
| `score < min_acceptable` | FAIL - regression detected |

**The goal:** A virtuous cycle where the system gets better AND measures itself getting better.

**Milestone targets:**
- Start: D/C level (4.0-6.0)
- Q2 2026: B level (7.0-8.0)
- Q3 2026: A level (8.0-9.0)

## Statistical Methodology

_Inspired by [aistupidlevel.info](https://aistupidlevel.info/methodology)_

### Why Multiple Trials?

AI models are stochastic - same prompt → different outputs. Single measurements are unreliable.

### 95% Confidence Intervals

- **5 trials** per evaluation (optimal cost vs statistical power)
- **t-distribution** with df=4 for small samples
- **Formula:** `mean ± (t_value × std_error)`
- **Interpretation:** "95% confident true score is within interval"

### Scoring Axes (7 criteria → 10 points)

| Criterion | Weight | What It Measures |
|-----------|--------|------------------|
| TodoWrite | 1pt | Task planning |
| Confidence | 1pt | State HIGH/MEDIUM/LOW |
| Plan mode | 2pt | Complex task planning |
| TDD RED | 2pt | Write failing test first |
| TDD GREEN | 2pt | Make test pass |
| Self-review | 1pt | Code review before done |
| Clean code | 1pt | Quality and coherence |

### Regression Detection (Overlapping CI Method)

_Both baseline AND candidate have uncertainty - account for both._

| Condition | Result | Meaning |
|-----------|--------|---------|
| `candidate_lower_CI > baseline_upper_CI` | **IMPROVED** | Statistically significant improvement |
| CIs overlap | **STABLE** | No significant difference (pass) |
| `candidate_upper_CI < baseline_lower_CI` | **REGRESSION** | Statistically significant regression (fail) |

**Why this is correct:**
- Both measurements have uncertainty (stochastic AI)
- Only claim improvement/regression when CIs don't overlap
- Overlapping CIs = can't distinguish = assume stable

### Implementation

Stats library: `tests/e2e/lib/stats.sh`

```bash
# Calculate 95% CI
source tests/e2e/lib/stats.sh
CI_RESULT=$(calculate_confidence_interval "5.1 5.3 5.0 5.2 5.4")
# Output: "5.2 ± 0.2 (95% CI: [5.0, 5.4])"

# Compare two sets of scores
VERDICT=$(compare_ci "$BASELINE_SCORES" "$CANDIDATE_SCORES")
# Output: IMPROVED | STABLE | REGRESSION
```

### CUSUM Drift Detection

Before/after comparison catches sudden changes but misses gradual drift.
CUSUM (Cumulative Sum) tracks deviation from target over time.

```bash
# Add score to history and check drift
./tests/e2e/cusum.sh --add 6.5
# Output: CUSUM=-1.5 (Status: NORMAL)

# Check current drift status
./tests/e2e/cusum.sh --status
# Shows: Target, Warning/Alert thresholds, CUSUM value, Status
```

**Drift thresholds:**
- Normal: |CUSUM| < 2.0
- Warning: 2.0 ≤ |CUSUM| < 3.0
- Alert: |CUSUM| ≥ 3.0

**Why this matters:**
- Individual evaluations might look "okay" (6.5 is close to 7.0)
- But consistent small declines compound
- CUSUM catches this before it becomes a big problem

### Version Upgrade Scenario

New scenario for testing SDLC enforcement with new CC versions:
`tests/e2e/scenarios/version-upgrade.md`

Used in daily-update workflow to validate that:
1. New CC version doesn't break SDLC enforcement (Phase A)
2. Changelog-suggested improvements help (Phase B)

---

## E2E Coverage & Scoring Updates (2026-02-02)

### Items 6-9: New Features Testing & Coverage Awareness

| Item | Description | Status |
|------|-------------|--------|
| 6 | E2E scenarios for new wizard features | DONE |
| 7 | Coverage-aware PR review | DONE |
| 8 | Scoring criteria update (UI scenarios) | DONE |
| 9 | Adaptive code coverage in wizard | DONE |

### Item 6: New E2E Scenarios

Added scenarios to test new wizard features:

| Scenario | Tests | File |
|----------|-------|------|
| `ui-styling-change.md` | Design system check triggers | `tests/e2e/scenarios/` |
| `add-ui-component.md` | Visual consistency in review | `tests/e2e/scenarios/` |
| `tool-permissions.md` | allowedTools compliance | `tests/e2e/scenarios/` |

**Purpose:** Validate that new wizard features (design system check, tool permissions) are being followed during SDLC execution.

### Item 7: Coverage-Aware PR Review

Updated `pr-review.yml` to detect E2E coverage gaps:

```yaml
# When changes affect SDLC behavior, check for E2E coverage:
# - .claude/hooks/ → SDLC enforcement
# - .claude/skills/ → SDLC guidance
# - CLAUDE_CODE_SDLC_WIZARD.md → Wizard behavior
# - .github/workflows/ → CI/auto-update

# If no scenario tests the changed behavior:
# "Warning: This change affects [area] but has no E2E scenario testing it."
```

**Why:** Self-improving feedback loop - when wizard changes lack test coverage, PR review flags it.

### Item 8: UI Scenario Scoring (11 points)

Updated `evaluate.sh` to handle UI scenarios:

| Scenario Type | Max Score | Criteria |
|---------------|-----------|----------|
| Standard | 10 points | 7 criteria |
| UI (styling/components) | 11 points | 7 criteria + design_system |

**Design system criterion (1pt):** Did Claude check DESIGN_SYSTEM.md before making UI changes?

**Detection:** Scenario mentions UI, styling, CSS, components, colors, fonts, or visual changes.

### Item 9: Adaptive Code Coverage

Added optional Q16 to wizard Step 1:

**For projects with test framework:**
- Traditional coverage (enforce threshold / report only / skip)
- AI coverage suggestions (Claude notes missing test cases)

**For docs/AI-heavy projects:**
- AI coverage suggestions (recommended)
- Skip

**Key insight:** Traditional coverage and AI suggestions are complementary, not mutually exclusive:
- Traditional: "You have 80% line coverage" (deterministic)
- AI: "You changed X but didn't test edge case Y" (context-aware)

### Files Modified

| File | Change |
|------|--------|
| `tests/e2e/evaluate.sh` | Added design_system criterion for UI scenarios |
| `tests/e2e/baselines.json` | Added 3 new scenarios, max_score field, UI flags |
| `tests/e2e/scenarios/ui-styling-change.md` | NEW: Tests design system check |
| `tests/e2e/scenarios/add-ui-component.md` | NEW: Tests visual consistency |
| `tests/e2e/scenarios/tool-permissions.md` | NEW: Tests allowedTools compliance |
| `.github/workflows/pr-review.yml` | Added E2E coverage awareness to prompt |
| `CLAUDE_CODE_SDLC_WIZARD.md` | Added Q16 (adaptive code coverage) |

### The Virtuous Cycle

```
Wizard changes → PR review flags missing coverage → Add E2E scenario →
Scoring updated → Future changes validated → Wizard stays high quality
```

**This is meta/self-improving:**
1. AI evaluates AI (E2E scenarios scored by Claude)
2. Coverage for non-code (AI-suggested for docs/YAML)
3. Adaptive by project type (detect if traditional or AI approach is better)
4. Scoring evolves with wizard (new features get new criteria)

---

## Item 10: CI Integrity Checks (2026-02-02)

**Purpose:** Automatically verify E2E tests are REAL, not mocked/broken.

### Checks Added to `ci.yml`

| Check | Implementation | Catches |
|-------|----------------|---------|
| **Timing >30s** | Record start/end time of each simulation | Mocked API, skipped steps |
| **Score bounds** | Assert 0 ≤ score ≤ 11 | Parse errors, malformed output |
| **Output JSON valid** | Verify output file exists | Empty/corrupt output files |

### Implementation

Added to both `e2e-quick-check` (Tier 1) and `e2e-full-evaluation` (Tier 2) jobs:

```yaml
# Before each simulation:
- name: Record simulation start time
  run: echo "START_TIME=$SECONDS" >> $GITHUB_ENV

# After each simulation:
- name: Integrity check simulation
  run: |
    ELAPSED=$((SECONDS - START_TIME))

    # Timing check
    if [ "$ELAPSED" -lt 30 ]; then
      echo "::error::Integrity Check Failed: Took ${ELAPSED}s (expected >30s)"
      exit 1
    fi

    # Output file check
    if [ ! -f "$OUTPUT_FILE" ]; then
      echo "::error::Integrity Check Failed: Output file not found"
      exit 1
    fi

    # JSON structure check (warning only)
    if ! jq -e '.result or .output or .messages' "$OUTPUT_FILE" > /dev/null 2>&1; then
      echo "::warning::Output file may have unexpected structure"
    fi

# In evaluation loops:
# Score bounds check
if [ "$(echo "$SCORE < 0 || $SCORE > 11" | bc -l)" -eq 1 ]; then
  echo "::error::Integrity Check Failed: Score $SCORE out of bounds [0-11]"
  exit 1
fi
```

### Why This Matters

| Problem | Without Integrity Checks | With Integrity Checks |
|---------|--------------------------|----------------------|
| API key expired | Scores silently = 0 | Immediate failure with explanation |
| Output file missing | Cryptic jq errors | Clear "Output file not found" error |
| Mocked/skipped simulation | Passes with fake scores | Fails timing check |
| Malformed evaluation | Garbage scores accepted | Bounds check catches it |

### Files Modified

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Added integrity checks to 4 simulation points (baseline/candidate × Tier1/Tier2) |
