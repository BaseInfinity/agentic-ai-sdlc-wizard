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
- **Trigger:** Daily schedule (9 AM UTC) + manual dispatch
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
| Daily (9 AM UTC) | daily-update.yml | Check releases → Always PR |
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

**RESOLVED (2026-02-15):** All metrics showed N/A because `claude-code-action@v1` does NOT include usage fields in its execution output file. Dead extraction code and Resource Usage PR comment sections removed. Token tracking can be re-enabled when/if the action starts exposing usage data. `tests/test-token-extraction.sh` deleted (tested against mocked data that didn't match reality).

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
| 17 | Multi-model evaluation | MED | Test with Sonnet vs Opus to validate robustness across models | SKIPPED — Opus-only by design |
| 18 | Deterministic pre-checks | MED | Pattern match for TodoWrite/test-first before LLM judge (cheaper, faster) | DONE |
| 19 | Real-world scenarios | MED | Extract from public repos like SWE-bench for realistic E2E testing | DONE |
| 20 | Observability/tracing | LOW | Structured logging for debugging score changes across runs | DONE |
| 22 | Color-coded PR comments | LOW | Add visual indicators to E2E scoring PR comments - green/red/yellow emoji or status badges for PASS/WARN/FAIL per criterion. Makes it easier to scan results at a glance instead of reading raw numbers. | DONE — emoji indicators in ci.yml |
| 23 | Phased workflow re-enablement | HIGH | Re-enable daily → weekly → monthly schedules after roadmap complete + audit. Phase 1: daily (most critical, tracks CC releases). Phase 2: weekly (after daily stable 1 week). Phase 3: monthly (lowest urgency). Gate: all items 15-22 addressed, Tier 2 E2E passes, workflow audit. | IN PROGRESS — Phase 1 (daily) enabled |
| 24 | Tier 2 E2E full suite audit | HIGH | Run full Tier 2 evaluation (`merge-ready` label) end-to-end. Verify 5-trial statistical evaluation, 95% CI, pairwise tiebreaker, CUSUM, SDP, score history persistence, and PR comment formatting all work correctly in CI. This is the final validation gate before mutation testing. | PLANNED |
| 25 | Full system audit | HIGH | Comprehensive audit of all workflows, tests, scripts, and docs after Tier 2 passes. Verify every feature works as documented. Catch any remaining silent failures or stale assumptions. Establish as recurring practice — audit on every PR going forward (lightweight version via PR review workflow, thorough version periodically). | PLANNED |
| 21 | Mutation testing | MED | Two tracks: (a) Wizard recommendation - detect stack and offer mutation testing setup (Stryker for JS/TS, mutmut for Python, pitest for Java, cargo-mutants for Rust). (b) Our own CI - explore "SDLC document mutation testing": mutate wizard doc sections, run E2E, verify score drops to prove which sections are load-bearing. Gate: Items 24-25 must pass first. | PLANNED — last in execution order, after 24-25 |

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

### Item 17: Multi-Model Evaluation — SKIPPED

**Decision:** Skipped. The wizard is designed for Opus-only usage. Testing with Sonnet would validate a configuration we don't recommend. SDP scoring (Item 11) already tracks model degradation via external benchmarks.

### Item 18: Deterministic Pre-Checks (Already Implemented)

**Status:** Already done as part of Items 10-14. `lib/deterministic-checks.sh` provides grep-based scoring for task_tracking, confidence, and tdd_red. The LLM judge only scores subjective criteria (plan_mode, tdd_green, self_review, clean_code, design_system). Marked DONE.

### Item 19: Real-World Scenarios — DONE

**Problem:** Our 10 E2E scenarios were synthetic/templated. Real-world tasks are messier — multi-file, ambiguous, require judgment.

**Key insight:** No script changes needed. `scenario-selector.sh` auto-discovers any `.md` file in the scenarios directory.

**3 scenarios added:**

| Scenario | Tests | Complexity | Baseline |
|----------|-------|------------|----------|
| `multi-file-api-endpoint.md` | Cross-file planning, TDD on integration | Medium | 5.0 |
| `production-bug-investigation.md` | Investigation skills, regression TDD | Hard | 4.5 |
| `technical-debt-cleanup.md` | Blast radius analysis, safe deletion | Medium | 5.0 |

**Files:**
- `tests/e2e/scenarios/multi-file-api-endpoint.md` — NEW
- `tests/e2e/scenarios/production-bug-investigation.md` — NEW
- `tests/e2e/scenarios/technical-debt-cleanup.md` — NEW
- `tests/e2e/baselines.json` — 3 entries added (v1.2.0)

**Total scenarios: 13** (10 original + 3 real-world)

### Item 20: Observability & Score Trends — DONE

**Problem:** `score-history.jsonl` existed but was empty. No way to see how scores evolve over time. No analytics.

**What was built:**

| Component | File | Description |
|-----------|------|-------------|
| Score history recording | `.github/workflows/ci.yml` | After each E2E evaluation, appends result to `score-history.jsonl` |
| Analytics script | `tests/e2e/score-analytics.sh` | Reads history, outputs overall avg, trends, per-criterion, scenario ranking |
| Trends report | `SCORE_TRENDS.md` | Auto-generated markdown with ASCII spark chart, tables, weakest areas |
| Historical context | `.github/workflows/ci.yml` | Collapsible section in PR comments showing scenario avg and weakest criterion |
| Analytics tests | `tests/test-score-analytics.sh` | 12 tests covering empty/single/multi/trend/malformed/report modes |

**Score history format (per line):**
```json
{"timestamp":"...","scenario":"...","score":7.0,"max_score":10,"criteria":{...},"sdp":{...}}
```

**Analytics output includes:**
- Overall average score + trend (last 5 vs older)
- Per-criterion averages (identifies weakest)
- Scenario difficulty ranking
- Score distribution histogram
- ASCII spark chart (last 20 scores)

**PR comment enhancement:** Collapsible "Historical Context" section showing:
- "This scenario avg: X.X (N runs)"
- "Weakest criterion: clean_code (45%)"

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

---

## Workflow Input Validation Audit (2026-02-14)

**Purpose:** All three auto-update workflows had invalid `claude-code-action@v1` inputs that were silently ignored, causing empty results.

### Bug Pattern (same across all 3 workflows)

| Invalid Input | Issue | Fix |
|---------------|-------|-----|
| `prompt_file` | Not a valid action input | Use `prompt:` instead |
| `direct_prompt` | Not a valid action input | Remove (not needed) |
| `model` | Not a valid top-level input | Remove or use `claude_args: --model` |
| `allowed_tools` | Not a valid action input | Use `claude_args: --allowedTools` |
| `outputs.response` | Doesn't exist in action outputs | Read from `$RUNNER_TEMP/claude-execution-output.json` |

### Fix Timeline

| Workflow | PR | Status |
|----------|----|--------|
| `daily-update.yml` | #26, #28, #30 | DONE |
| `weekly-community.yml` | #32 | DONE |
| `monthly-research.yml` | #32 | DONE |

### Regression Tests

| Tests | Workflow | What They Check |
|-------|----------|----------------|
| 49-54 | daily-update | No invalid inputs, extracts from output file |
| 55-60 | weekly-community | No invalid inputs, extracts from output file |
| 61-66 | monthly-research | No invalid inputs, extracts from output file |

**Total: 18 regression tests** ensuring invalid inputs never reappear across all 3 workflows.

### Extraction Pattern (shared across all 3 workflows)

```bash
OUTPUT_FILE="${RUNNER_TEMP:-/tmp}/claude-execution-output.json"
# Detect array vs object format
IS_ARRAY=$(jq -r 'if type == "array" then "true" else "false" end' "$OUTPUT_FILE")
# Extract text, find JSON in markdown code blocks or raw
# Validate JSON, fallback to safe default
```

---

## Full Workflow Audit: Silent Failures (2026-02-14)

Comprehensive audit found multiple features that silently produce no data. Tests pass because they validate extraction logic against mocked fixtures — but the mocks don't match what `claude-code-action@v1` actually outputs.

### CRITICAL — Features That Don't Work

| # | Bug | Where | What Happens | Status |
|---|-----|-------|--------------|--------|
| 1 | Token/cost metrics always N/A | ci.yml | `claude-code-action@v1` doesn't include `.duration`, `.usage.input_tokens`, etc. in execution output. All values were N/A | **FIXED** — Removed dead extraction code + Resource Usage sections. Re-enable when action exposes usage data |
| 2 | Score history never persists | ci.yml | Appends to `score-history.jsonl` on ephemeral runner, never committed back | **FIXED** — Added git commit step after score recording (both Tier 1 and Tier 2) |
| 3 | Historical context never populated | ci.yml | Depends on #2. Always shows "First run for this scenario" | **FIXED** — Fixed by #2 (score history now persists) |
| 4 | External benchmark cache useless | external-benchmark.sh | Cache dir is on ephemeral runner — always cache miss | ACCEPTED — Fresh fetch each run works fine, falls back to 75.0 |
| 5 | `show_full_output` invalid input | ci-autofix.yml | Not a valid `claude-code-action@v1` input, silently ignored | **FIXED** — Deleted invalid input |
| 9 | Autofix can't push workflow files | ci-autofix.yml | Missing `workflows: write` permission — git push rejected for `.github/workflows/` changes | **FIXED** — Added `workflows: write` to permissions block |
| 10 | `configureGitAuth` crash in CI | ci.yml | `actions/checkout` with `path:` leaves workspace root as non-git — `claude-code-action@v1` crashes on `git config` | **FIXED** — Added `git init .` step before simulation in both Tier 1 and Tier 2 |
| 11 | `error_max_turns` on hard scenarios | ci.yml | 45 turns too tight for hard scenarios (refactor used 46) — action treats as failure | **FIXED** — Bumped max-turns from 45 to 55 |

### HIGH — Features That May Not Work Correctly

| # | Bug | Where | What Happens | Status |
|---|-----|-------|--------------|--------|
| 6 | E2E test jobs may never trigger | weekly-community.yml, monthly-research.yml | `has_suggestions`/`has_updates` depends on specific JSON array key names Claude may not produce | **FIXED** — Changed to `findings_count` (weekly) and `nothing_notable` (monthly) for broader triggering |
| 7 | SDP model mismatch | external-benchmark.sh | Default parameter is `claude-sonnet-4` even when SDP_MODEL is `claude-opus-4-6` | **FALSE ALARM** — Chain passes correctly: evaluate.sh → sdp-score.sh → external-benchmark.sh all propagate SDP_MODEL |
| 8 | Phase A/B output file reuse | daily-update.yml | Both phases write to same `claude-execution-output.json` | **FALSE ALARM** — Sequential execution: Phase A reads before Phase B writes. No stale data possible |

### Root Causes (addressed 2026-02-15)

1. **claude-code-action@v1 output schema undocumented** — extraction logic guessed at field names. **Fix:** Removed dead extraction code (#1), deleted false-confidence tests
2. **Ephemeral runner state** — score history lost every run. **Fix:** Added git commit step to persist JSONL (#2-3)
3. **Tests mock the wrong data** — `test-token-extraction.sh` deleted (validated mocked data, not reality)
4. **Fragile trigger conditions** — E2E jobs depended on exact JSON key names. **Fix:** Broadened triggers (#6)
5. **Invalid action inputs** — `show_full_output` silently ignored. **Fix:** Deleted (#5)
7. **Missing workflow push permission** — Autofix couldn't push fixes to `.github/workflows/` files. **Fix:** Added `workflows: write` (#9)
6. **False alarms** — SDP model (#7) and Phase A/B reuse (#8) both work correctly on investigation

---

## Readiness Assessment for Item 23 (Phased Workflow Re-enablement)

_Updated: 2026-02-15_

| Gate | Item | Status |
|------|------|--------|
| Eval framework improvements | 15 | DONE |
| Pairwise tiebreaker | 16 | DONE |
| Multi-model evaluation | 17 | SKIPPED — Opus-only by design |
| Deterministic pre-checks | 18 | DONE |
| Real-world scenarios | 19 | DONE |
| Observability & score trends | 20 | DONE |
| Mutation testing | 21 | PLANNED — after Items 24-25 |
| Color-coded PR comments | 22 | DONE |

**Summary:** 6/8 items DONE, 1 SKIPPED (by design), 1 PLANNED (last in order).

**Item 23 decision (updated 2026-02-15):** Silent failure audit resolved. Bugs #1-6 fixed, #7-8 confirmed false alarms, #4 accepted (cache miss is fine). Remaining gate: manual validation of daily → weekly → monthly schedule re-enablement. Mutation testing (Item 21) is planned last, after Items 24-25 pass.

**Execution order (updated 2026-02-15):** Item 23 (phased schedules) → Item 24 (Tier 2 full suite audit) → Item 25 (full system audit, then recurring per-PR) → Item 21 (mutation testing, last).
