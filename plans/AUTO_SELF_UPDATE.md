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
- **Trigger:** Manual dispatch only (schedule paused until roadmap items 15-22 complete)
- **Checks:** Claude Code GitHub releases
- **Action:** Creates PR for ALL updates (relevance shown in title)
- **E2E Testing:** Phase A (regression) + Phase B (improvement) with Tier 1 + 2

### Weekly Community Scan (`.github/workflows/weekly-community.yml`)
- **Trigger:** Manual dispatch only (schedule paused until roadmap items 15-22 complete)
- **Checks:** Reddit, HN, dev blogs, official channels
- **Action:** Creates digest issue for notable findings
- **E2E Testing:** Baseline vs with-changes comparison (Tier 2)

### Monthly Research Deep Dive (`.github/workflows/monthly-research.yml`)
- **Trigger:** Manual dispatch only (schedule paused until roadmap items 15-22 complete)
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
| Manual only (schedule paused) | daily-update.yml | Check releases → Always PR |
| Manual only (schedule paused) | weekly-community.yml | Scan community → Issue |
| Manual only (schedule paused) | monthly-research.yml | Deep research → Issue |
| On PR | ci.yml | Run tests + E2E eval |
| On PR | pr-review.yml | AI code review |
| On CI fail / review findings | ci-autofix.yml | Auto-fix loop |

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
│   ├── ci-autofix.yml         # Auto-fix loop (CI + review)
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
    │   ├── json-utils.sh     # JSON extraction utilities
    │   ├── eval-criteria.sh  # Per-criterion prompts + aggregation (v3)
    │   ├── eval-validation.sh # Schema/bounds validation + prompt version
    │   └── deterministic-checks.sh # Grep-based scoring (free, fast)
    ├── run-simulation.sh     # Full E2E test runner
    ├── run-tier2-evaluation.sh # Shared 5-trial evaluation script
    ├── evaluate.sh           # AI-powered scoring (0-10)
    ├── check-compliance.sh   # Pattern-based checks
    ├── cusum.sh              # CUSUM drift detection (total + per-criterion)
    ├── score-history.txt     # Historical total scores (legacy format)
    ├── score-history.jsonl   # Historical per-criterion scores (JSON-lines)
    ├── golden-outputs/       # Saved outputs with verified expected scores
    ├── golden-scores.json    # Expected score ranges per golden output
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

---

## Item 11: SDP Scoring (Model Degradation Tracking) (2026-02-03)

**Purpose:** Distinguish "model issues" from "wizard issues" when E2E scores drop.

### The Problem

When E2E scores drop, we don't know if:
- Our SDLC wizard broke (we need to fix something)
- The model got worse globally (not our fault, wait it out)

### The Solution: Two-Layer Scoring

| Layer | What It Measures | Source |
|-------|------------------|--------|
| **L1: General Model Quality** | Did the model get dumber overall? | External benchmarks (DailyBench, LiveBench) |
| **L2: SDLC Compliance** | Did the model get worse at following OUR methodology? | Our E2E scores |

### SDP Formula

```
Raw Score = Our E2E result (0-10)
External Score = General model benchmark (0-100)
SDP = Raw × (baseline_external / current_external)

Robustness = How well our SDLC holds up vs model changes
  - Robustness < 1.0 = SDLC MORE resilient than model (good!)
  - Robustness ≈ 1.0 = SDLC tracks model exactly (expected)
  - Robustness > 1.0 = SDLC MORE sensitive than model (fragile - investigate)
```

### Interpretation Matrix

| L1 (Model) | L2 (SDLC) | Interpretation |
|------------|-----------|----------------|
| Stable | Stable | All good |
| Dropped | Dropped proportionally | Model issue, not us |
| Stable | Dropped | **Our SDLC setup broke** - investigate |
| Dropped | Stable | **Our SDLC is robust** - good sign! |

### External Benchmark Sources (Cheapest First)

| Priority | Source | Method | Cost |
|----------|--------|--------|------|
| 1 | DailyBench | GitHub raw CSV | Free |
| 2 | LiveBench | GitHub data | Free |
| 3 | Cached baseline | Local file | Free (fallback) |

### PR Comment Format

PR comments now show:

```markdown
| Layer | Metric | Value |
|-------|--------|-------|
| **L1: Model** | External Benchmark | 67.5 (-10% vs baseline) |
| **L2: SDLC** | Raw Score | 6.0/10 |
| | SDP (adjusted) | 6.67/10 |
| **Combined** | Robustness | 0.85 (ROBUST) |
```

### Self-Healing

- 24-hour cache for external benchmarks
- Falls back to baseline on fetch failure
- Tracks consecutive failures (3x = warning)

### Files Added/Modified

| File | Action | Purpose |
|------|--------|---------|
| `tests/e2e/lib/external-benchmark.sh` | CREATE | Multi-source benchmark fetcher |
| `tests/e2e/lib/sdp-score.sh` | CREATE | SDP calculation logic |
| `tests/e2e/external-baseline.json` | CREATE | Baseline external benchmarks |
| `tests/e2e/evaluate.sh` | MODIFY | Output SDP alongside raw |
| `.github/workflows/ci.yml` | MODIFY | Include SDP in PR comments |
| `tests/test-external-benchmark.sh` | CREATE | Test fallback logic |
| `tests/test-sdp-calculation.sh` | CREATE | Test SDP math |
| `README.md` | MODIFY | Document SDP scoring |
| `CONTRIBUTING.md` | MODIFY | Add SDP to scoring criteria |
| `CI_CD.md` | MODIFY | Explain SDP in E2E section |

### Why This Matters

| Without SDP | With SDP |
|-------------|----------|
| Score dropped → panic, investigate wizard | Score dropped → check if model dropped too |
| False positives when model has bad day | Context for when to investigate vs wait |
| No visibility into model condition | Robustness metric shows SDLC resilience |

---

## Item 12: Deployment Docs + Token Tracking (2026-02-03)

### Part 1: Deployment Documentation

**Problem:** Claude doesn't know how to deploy correctly (dev vs prod).

**Solution:**
- Auto-detect deployment targets (Dockerfile, k8s/, vercel.json, etc.) in Step 0.4
- Added Q8.5 in wizard setup for deployment confirmation
- Expanded ARCHITECTURE.md template with Environments table and Deployment Checklist
- Added deployment confidence requirements (HIGH for prod, MEDIUM for staging)
- Added deployment guidance to SKILL.md

**Detection Patterns:**

| File/Pattern | Detected As | Deploy Command |
|--------------|-------------|----------------|
| `Dockerfile` | Container | `docker build && docker push` |
| `k8s/`, `kubernetes/` | Kubernetes | `kubectl apply -f k8s/` |
| `vercel.json`, `.vercel/` | Vercel | `vercel --prod` |
| `netlify.toml` | Netlify | `netlify deploy --prod` |
| `fly.toml` | Fly.io | `fly deploy` |
| `.github/workflows/deploy*.yml` | GitHub Actions | Auto (on push) |
| `deploy.sh`, `deploy/` | Custom script | `./deploy.sh` |
| `package.json` scripts | npm scripts | `npm run deploy:*` |
| `Procfile` | Heroku | `git push heroku` |
| `railway.json` | Railway | `railway up` |
| `render.yaml` | Render | Auto (on push) |

### Part 2: Token Usage Tracking

**Problem:** Token usage should be measured even if not scored.

**Solution:**
- Extract tokens from claude-code-action output (`.usage`, `.token_usage`, or top-level)
- Display in PR comments (collapsible Resource Usage section)
- Calculate cost estimates (~$3/1M input, ~$15/1M output)
- Track tokens/point efficiency metric
- Track but don't score yet (need baseline data first)

**Why Measure But Not Score (Yet):**

| Reason | Explanation |
|--------|-------------|
| Data first | Need baseline data before weighting |
| Avoid perverse incentives | Don't penalize thoroughness |
| Task variance | Some tasks legitimately need more tokens |
| Informational value | Useful for monitoring even without scoring |

### Files Modified

| File | Change |
|------|--------|
| `CLAUDE_CODE_SDLC_WIZARD.md` | Deployment detection in Step 0.4, Q8.5, ARCHITECTURE.md template |
| `.claude/skills/sdlc/SKILL.md` | Deployment-aware guidance section |
| `.github/workflows/ci.yml` | Token extraction + display in PR comments |
| `CONTRIBUTING.md` | Token tracking documentation |
| `tests/test-token-extraction.sh` | Test token extraction logic |

### PR Comment Format

```markdown
<details>
<summary>Resource Usage (informational)</summary>

| Metric | Value |
|--------|-------|
| Duration | 45s |
| Tool uses | 12 |
| Input tokens | 12,345 |
| Output tokens | 8,901 |
| Total tokens | 21,246 |
| Est. cost | ~$0.85 |
| Tokens/point | 2,125 |

_Native Task metrics (duration, tool uses) + token tracking. Not scored yet._
</details>
```

---

## Item 13: Native Task Metrics (2026-02-05)

**Purpose:** Leverage Claude Code Task tool's native metrics for richer E2E telemetry.

### Native Fields

Claude Code's Task tool now provides these fields natively in execution output:

| Field | Description | Source |
|-------|-------------|--------|
| `duration` | Total execution time in seconds | Task tool output |
| `tool_uses` | Number of tool calls made | Task tool output |
| `total_tokens` | Combined token count | Task tool output |

### What Changed

| File | Change |
|------|--------|
| `.github/workflows/ci.yml` | Extract native metrics, show in PR comments |
| `tests/e2e/evaluate.sh` | Track evaluation duration, include in JSON output |
| `tests/test-token-extraction.sh` | Tests for native metric extraction |
| `plans/AUTO_SELF_UPDATE.md` | This documentation |

### CI Audit Fixes (bundled)

Also includes fixes from CI audit:

| Fix | Severity | Description |
|-----|----------|-------------|
| Model mismatch | CRITICAL | evaluate.sh now uses claude-opus-4-6 |
| SDP robustness negation | CRITICAL | Removed `* -1`, use absolute ratio |
| Silent failures | CRITICAL | Missing output files now exit 1 |
| Hardcoded output path | HIGH | Use `RUNNER_TEMP` env var |
| Timing threshold | HIGH | Reduced to 20s, warning for 20-30s |
| API retry | MEDIUM | 1 retry with 5s delay |
| Pricing | MEDIUM | Updated to Opus 4.6 rates ($15/$75 per 1M) |

---

## Item 14: CI Auto-Fix Loop (2026-02-09)

**Purpose:** Close the full SDLC feedback cycle — when CI fails or PR review has critical findings, Claude automatically reads the context, fixes the code, commits, and re-triggers CI.

### Architecture

```
Push to PR
    |
    v
CI runs ──► FAIL ──► ci-autofix ──► Claude fixes ──► commit [autofix N/M] ──► re-trigger CI
    |                                                                              |
    |   <──────────────────────────────────────────────────────────────────────────┘
    |
    └── PASS ──► PR Review ──► APPROVE, no findings at level ──► DONE
                      |
                      └── has findings ──► ci-autofix ──► Claude reads review, fixes all ──► loop
```

### Two Modes

| Mode | Trigger | What Claude Reads |
|------|---------|-------------------|
| **CI failure** | CI workflow completes with `failure` | `gh run view --log-failed` output |
| **Review findings** | PR Code Review completes with `success` | `claude-review` sticky comment body |

### Safety Measures

| Measure | Purpose |
|---------|---------|
| `head_branch != 'main'` | Never auto-fix production |
| `MAX_AUTOFIX_RETRIES: 3` | Prevent infinite loops (configurable env var) |
| Restricted Claude tools | `Read,Edit,Write,Bash(./tests/*),Bash(python3 *),Glob,Grep` |
| `--max-turns 30` | Limit Claude execution per attempt |
| `[autofix N/M]` commits | Audit trail in git history |
| Self-modification ban | Prompt forbids editing ci-autofix.yml |
| Sticky PR comments | User always sees autofix status |
| APPROVE detection | Loop exits when review is clean |
| Suggestion handling | Autofix addresses ALL review findings, not just criticals |
| `AUTOFIX_LEVEL` env var | 3 strictness levels: `ci-only`, `criticals` (default), `all-findings` (configurable per-repo) |

### Token Approach (Auto-Detected)

| Approach | When | How |
|----------|------|-----|
| **GITHUB_TOKEN** (default) | No app secrets configured | Commit + `gh workflow run ci.yml` to re-trigger |
| **GitHub App** (recommended) | `CI_AUTOFIX_APP_ID` + `CI_AUTOFIX_PRIVATE_KEY` exist | `actions/create-github-app-token` → push triggers `synchronize` naturally |

### Key Constraint

`workflow_run` only fires for workflows on the default branch. The ci-autofix workflow is dormant until first merged to main.

### Files Added/Modified

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/ci-autofix.yml` | CREATE | Core auto-fix workflow |
| `.github/workflows/ci.yml` | MODIFY | Added `workflow_dispatch` trigger for re-triggering |
| `tests/test-workflow-triggers.sh` | MODIFY | Added 10 tests (22-31) for ci-autofix |
| `CI_CD.md` | MODIFY | Documented ci-autofix workflow + secrets |
| `ARCHITECTURE.md` | MODIFY | Added ci-autofix to file tree |
| `CLAUDE_CODE_SDLC_WIZARD.md` | MODIFY | Added optional CI Auto-Fix section |
| `plans/AUTO_SELF_UPDATE.md` | MODIFY | This documentation |

### Test Coverage

| Test # | What It Checks |
|--------|---------------|
| 22 | `ci-autofix.yml` file exists |
| 23 | Triggers on `workflow_run` |
| 24 | Watches both `"CI"` and `"PR Code Review"` workflows |
| 25 | Has `MAX_AUTOFIX_RETRIES` config |
| 26 | Excludes main branch |
| 27 | Uses `claude-code-action` |
| 28 | Uses `[autofix` commit tag pattern |
| 29 | Posts sticky PR comment |
| 30 | ci.yml has `workflow_dispatch` trigger |
| 31 | Reads review comment (`claude-review` header) |
| 37 | Checks for suggestions (not just criticals) |
| 38 | Prompt addresses both criticals and suggestions |

---

## Future Roadmap

| # | Item | Priority | Description | Status |
|---|------|----------|-------------|--------|
| 15 | Eval framework improvements | HIGH | Multi-call LLM judge, golden output regression, per-criterion CUSUM | DONE |
| 16 | Pairwise tiebreaker | HIGH | Tiebreaker-only pairwise with full swap when scores within 1.0 | DONE |
| 17 | Multi-model evaluation | MED | Test with Sonnet vs Opus to validate robustness across models | PLANNED |
| 18 | Deterministic pre-checks | MED | Pattern match for TodoWrite/test-first before LLM judge (cheaper, faster) | DONE |
| 19 | Real-world scenarios | MED | Extract from public repos like SWE-bench for realistic E2E testing | PLANNED |
| 20 | Observability/tracing | LOW | Structured logging for debugging score changes across runs | PLANNED |
| 21 | Mutation testing | MED | Two tracks: (a) Wizard recommendation - detect stack and offer mutation testing setup (Stryker for JS/TS, mutmut for Python, pitest for Java, cargo-mutants for Rust). (b) Our own CI - explore "SDLC document mutation testing": mutate wizard doc sections, run E2E, verify score drops to prove which sections are load-bearing. | PLANNED |
| 22 | Color-coded PR comments | LOW | Add visual indicators to E2E scoring PR comments - green/red/yellow emoji or status badges for PASS/WARN/FAIL per criterion. Makes it easier to scan results at a glance instead of reading raw numbers. | PLANNED |
| 23 | Phased workflow re-enablement | HIGH | Re-enable daily → weekly → monthly schedules after roadmap complete + audit. Phase 1: daily (most critical, tracks CC releases). Phase 2: weekly (after daily stable 1 week). Phase 3: monthly (lowest urgency). Gate: all items 15-22 addressed, Tier 2 E2E passes, workflow audit. | PLANNED |

### Item 15: Eval Framework Improvements (Targeted, Not Framework Adoption)

**Decision:** Don't adopt Promptfoo/DeepEval. Items 10-14 already solved most of what Item 15 originally described. Adding a Python/Node framework violates the bash-only project philosophy for marginal gain.

**What we did instead:**

| Improvement | Description | Files |
|-------------|-------------|-------|
| **Multi-call LLM judge** | Each subjective criterion scored by its own focused API call with dedicated calibration examples. Reduces variance vs monolithic single-call. | `lib/eval-criteria.sh`, `evaluate.sh` |
| **Golden output regression** | 3 golden outputs (high/medium/low) with manually verified expected score ranges. Catches prompt drift when eval prompt changes. | `golden-outputs/`, `golden-scores.json`, `test-eval-prompt-regression.sh` |
| **Per-criterion CUSUM** | JSON-lines history tracks individual criterion drift, not just total. Catches masked regressions (e.g., plan_mode declining while clean_code improves). | `cusum.sh`, `score-history.jsonl` |
| **Prompt version v3** | Bumped `EVAL_PROMPT_VERSION` to track the multi-call refactor. | `lib/eval-validation.sh` |

**Cost impact:** 4 smaller API calls instead of 1 large one. Net tokens similar (calibration examples split across calls).

**Test coverage:**
- `test-multi-call-eval.sh` — 22 tests for per-criterion prompts + aggregation
- `test-eval-prompt-regression.sh` — 8 tests for golden output validation (deterministic + API-backed)
- `test-cusum.sh` — 17 tests (11 original + 6 new per-criterion)

### Item 16: Pairwise Tiebreaker ✅ DONE

**Problem:** Independent scoring (score A, score B, compare) is less reliable than direct comparison when scores are close.

**Solution:** Lightweight tiebreaker-only pairwise comparison:
- Only triggers when |scoreA - scoreB| <= 1.0 (configurable threshold)
- Holistic "which output better follows SDLC?" comparison (not per-criterion)
- Full swap: both orderings (A,B) and (B,A) evaluated — only consistent wins count
- Binary output (A/B/TIE) — more reliable than numeric pairwise scores
- Pointwise per-criterion scoring (Item 15) remains the primary signal

**Why tiebreaker-only:** Research (2025-2026) shows pointwise is better for instruction-following tasks like SDLC compliance (r=0.78 vs r=0.35 for holistic). Pairwise adds value only for close-call tiebreaking where scale drift could mislead.

**Files:**
- `tests/e2e/lib/eval-criteria.sh` — 4 functions: `should_run_pairwise`, `build_holistic_pairwise_prompt`, `validate_pairwise_result`, `compute_pairwise_verdict`
- `tests/e2e/pairwise-compare.sh` — Main script with `--no-api` mode for testing
- `tests/e2e/test-pairwise-compare.sh` — 26 tests

**Test coverage:**
- `test-pairwise-compare.sh` — 26 tests for threshold gating, prompt construction, validation, verdict logic, integration

### Item 17: Multi-Model Evaluation

**Problem:** We only test with one model. If the wizard only works with Sonnet, that's fragile.

**Solution:**
- Run E2E with both Sonnet and Opus
- Compare scores across models
- Flag if wizard only works well with one model
- Validates robustness beyond SDP's external benchmark approach

### Item 18: Deterministic Pre-Checks (Already Implemented)

**Status:** Already done as part of Items 10-14. `lib/deterministic-checks.sh` provides grep-based scoring for task_tracking, confidence, and tdd_red. The LLM judge only scores subjective criteria (plan_mode, tdd_green, self_review, clean_code, design_system). Marked DONE.

### Item 19: Real-World Scenarios

**Problem:** Our E2E scenarios are synthetic. Real-world tasks are messier.

**Solution:**
- Extract scenarios from public repos (SWE-bench style)
- Real bug reports, feature requests, refactoring needs
- More diverse complexity levels
- Better validates wizard effectiveness on actual work

### Item 20: Observability/Tracing

**Problem:** When scores change, debugging why requires manual log reading.

**Solution:**
- Structured JSON logging for each evaluation step
- Trace ID linking simulation -> evaluation -> scoring
- Dashboard showing score trends over time
- Alert on anomalies beyond CUSUM (e.g., specific criteria regressing)

### Item 21: Mutation Testing

**Problem:** We don't know which wizard doc sections are load-bearing vs noise.

**Two tracks:**

**(a) Wizard recommendation for user projects:**
- Dynamically detect stack and offer mutation testing as optional setup
- Stryker for JS/TS, mutmut for Python, pitest for Java, cargo-mutants for Rust
- Validates test quality for ANY project, not just AI workflows
- Follows same dynamic detection pattern as test frameworks and lint tools

**(b) Our own CI - SDLC document mutation testing (novel):**
- Mutate wizard doc sections (remove a section, weaken guidance, change rules)
- Run E2E evaluation against mutated docs
- Verify score drops - proving which sections are load-bearing
- Sections where score doesn't drop = dead weight (candidates for removal)
- Sections where score drops significantly = critical (protect from regressions)
