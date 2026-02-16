# CI/CD Documentation

## Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR, push to main | Validation, tests, E2E evaluation |
| `daily-update.yml` | Manual only (schedule paused) | Check for Claude Code updates |
| `weekly-community.yml` | Manual only (schedule paused) | Scan community for patterns |
| `monthly-research.yml` | Manual only (schedule paused) | Deep research and trends |
| `ci-autofix.yml` | CI fail / review findings | Auto-fix loop |
| `pr-review.yml` | PR opened/ready/labeled | AI code review |

## CI Workflow (`ci.yml`)

### What It Does

**Validation Job:**
1. YAML validation of all workflow files
2. Shell script checks for unsafe variable interpolation
3. Prompt file validation (required prompts exist)
4. State file validation (version tracking files exist)
5. Test suites: version logic, analysis schema, workflow triggers
6. E2E fixture validation

**E2E Quick Check (Tier 1) - Every PR:**
1. Checkout PR branch + main branch
2. Install BASELINE wizard (main) into test fixture
3. Run simulation with Claude + integrity check (timing >20s, output file, JSON)
4. Evaluate baseline score (0-10, bounds check)
5. Reset fixture, install CANDIDATE wizard (PR)
6. Run simulation + integrity check
7. Evaluate candidate score + SDP scoring + token metrics
8. Compare scores, post results as sticky PR comment

**E2E Full Evaluation (Tier 2) - On `merge-ready` label:**
1. Same baseline/candidate flow as Tier 1
2. 5x evaluation runs per side (not just 1x)
3. 95% CI using t-distribution (df=4)
4. Statistical comparison using overlapping CI method
5. Criteria breakdown in PR comment

### Multi-Call LLM Judge (v3)

The evaluation pipeline uses per-criterion API calls instead of a single monolithic prompt:

| Step | What Happens |
|------|-------------|
| 1. Deterministic pre-checks | Grep-based scoring for task_tracking, confidence, tdd_red (free, fast) |
| 2. Per-criterion LLM calls | Each subjective criterion (plan_mode, tdd_green, self_review, clean_code, design_system) scored independently with focused calibration examples |
| 3. Aggregation | Individual results merged into standard JSON structure |
| 4. Validation | Schema check, bounds clamping, deterministic merge |

**Why per-criterion:** Reduces score variance. If the LLM hallucinates one score, it doesn't drag down others. Improves Tier 2 statistical power without more trials.

**Cost:** 4 smaller API calls instead of 1 large one. Net tokens similar.

**Golden output regression:** 3 saved outputs with verified expected score ranges catch prompt drift when the eval prompt changes.

**Per-criterion CUSUM:** Tracks individual criterion drift over time. A decline in `plan_mode` won't be masked by improvement in `clean_code`.

### Pairwise Tiebreaker (v3.1)

When two outputs have close pointwise scores (|scoreA - scoreB| <= 1.0), a pairwise tiebreaker runs:

| Step | What Happens |
|------|-------------|
| 1. Threshold check | If score difference > 1.0, skip pairwise — winner is clear |
| 2. AB ordering | Holistic "which output better follows SDLC?" comparison |
| 3. BA ordering | Same comparison with outputs swapped (position bias mitigation) |
| 4. Verdict | Both agree = winner. Disagree = TIE (position bias detected) |

**Why tiebreaker-only:** Pointwise per-criterion scoring (v3) is better for instruction-following tasks like SDLC compliance. Pairwise is only more reliable for close calls where scale drift could mislead.

**Cost:** 2 extra API calls, only when triggered (rare — most score differences exceed 1.0).

**Position bias mitigation:** Full swap is the standard approach — run both orderings, only count consistent wins. This catches the ~40% position bias that LLM judges exhibit.

### Tier System

| Tier | Runs | Statistical Power | When |
|------|------|-------------------|------|
| **Tier 1 (Quick)** | 1x each | Low (directional) | Every PR commit |
| **Tier 2 (Full)** | 5x each | High (95% CI) | `merge-ready` label |

### SDP (Model Degradation Tracking)

E2E evaluations include SDP scoring to distinguish "model issues" from "wizard issues":

| Layer | What It Measures | Source |
|-------|------------------|--------|
| **L1: Model** | General model quality | External benchmarks (DailyBench, LiveBench) |
| **L2: SDLC** | SDLC compliance | Our E2E evaluation |

**PR comments show:**
- Raw Score: Actual E2E score
- SDP Score: Adjusted for model conditions
- Robustness: How well our SDLC holds up vs model changes

**Interpretation Matrix:**
| L1 (Model) | L2 (SDLC) | Meaning |
|------------|-----------|---------|
| Stable | Stable | All good |
| Dropped | Dropped proportionally | Model issue, not us |
| Stable | Dropped | **Our SDLC broke** - investigate |
| Dropped | Stable | **Our SDLC is robust** - good! |

### Integrity Checks

Every simulation has automated integrity checks:

| Check | What It Catches |
|-------|----------------|
| Timing >20s | Mocked API, skipped steps |
| Output file exists | Empty/corrupt output |
| JSON structure valid | Malformed responses |
| Score bounds [0-11] | Parse errors |

### Token / Resource Metrics

Token and cost tracking was removed in PR #33. `claude-code-action@v1` does not expose usage data in its execution output file. All extracted values were N/A.

Token tracking can be re-enabled when the action starts exposing usage fields (`duration`, `input_tokens`, `output_tokens`, etc.).

### Runs On
- Every pull request (Tier 1)
- Push to main branch (validation only)
- `merge-ready` label (Tier 2)

## Daily Update Workflow (`daily-update.yml`)

### What It Does

1. Reads last checked version from state file
2. Fetches latest Claude Code release from GitHub API
3. Validates version format (security: prevents injection)
4. Compares versions
5. If different: Analyzes release with Claude
6. Creates PR with analysis and relevance level
7. Closes stale auto-update PRs

### Two-Phase Version Testing

**Phase A (Regression):** Does new CC version break our SDLC enforcement?
**Phase B (Improvement):** Do changelog-suggested changes improve scores?

Both use Tier 1 (quick) + Tier 2 (full statistical) evaluation.

### Runs On
- Manual trigger only (workflow_dispatch)
- Schedule paused until roadmap items 15-22 complete (see `plans/AUTO_SELF_UPDATE.md`)

### Required Secrets
- `ANTHROPIC_API_KEY`: For Claude analysis

## Weekly Community Workflow (`weekly-community.yml`)

### What It Does
- Scans GitHub for Claude Code community patterns
- Identifies useful integrations, plugins, workflows
- Creates digest issues for notable findings
- Closes stale digest issues when new ones created
- E2E tests community-suggested improvements (Tier 2)

### Runs On
- Manual trigger only (workflow_dispatch)
- Schedule paused until roadmap items 15-22 complete

## Monthly Research Workflow (`monthly-research.yml`)

### What It Does
- Deep research into AI coding agent trends
- Academic papers, major announcements
- Creates issue with trend report and recommendations
- E2E tests research-suggested improvements (Tier 2)

### Runs On
- Manual trigger only (workflow_dispatch)
- Schedule paused until roadmap items 15-22 complete

## CI Auto-Fix Workflow (`ci-autofix.yml`)

### What It Does

Automated fix loop that responds to CI failures and PR review findings.

**Review architecture:**
```
Solo:   Code → /code-review → Fix locally → Push → CI tests → Done
Team:   Code → /code-review → Push → CI tests → CI PR Review → Team discusses
        (optional: CI autofix addresses findings automatically)
```

**How it works:**

1. **CI failure mode**: Downloads failure logs, Claude reads them, fixes code, commits, re-triggers CI
2. **Review findings mode**: Fetches `claude-review` sticky comment, checks for findings (criticals + suggestions) based on `AUTOFIX_LEVEL`, Claude fixes them

### Loop Architecture

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
                      └── has findings ──► ci-autofix ──► Claude fixes all ──► loop back
```

### Safety Measures

| Measure | Purpose |
|---------|---------|
| `head_branch != 'main'` | Never auto-fix production |
| `MAX_AUTOFIX_RETRIES: 3` | Prevent infinite loops (configurable) |
| `AUTOFIX_LEVEL` | Controls what findings to act on (`ci-only`, `criticals` (default), `all-findings`) |
| Restricted Claude tools | No git, no npm - only read/edit/write/test |
| `--max-turns 30` | Limit Claude execution |
| `[autofix N/M]` commits | Audit trail in git history |
| Sticky PR comments | User always sees status |
| Self-modification ban | Prompt forbids editing ci-autofix.yml |

### Token Approaches

| Approach | When | How |
|----------|------|-----|
| **GITHUB_TOKEN** (default) | No app secrets | Commit + `gh workflow run ci.yml` to re-trigger |
| **GitHub App** | `CI_AUTOFIX_APP_ID` secret exists | `actions/create-github-app-token` → push triggers `synchronize` |

### Runs On
- `workflow_run` completion of CI (on failure)
- `workflow_run` completion of PR Code Review (on success, to check findings)
- Only on PR branches (never main)

## PR Review Workflow (`pr-review.yml`)

### What It Does
- Triggers on PR open, ready_for_review, or `needs-review` label
- Waits for CI to pass before reviewing (saves API costs)
- Skips trivial PRs (docs-only, config-only)
- Uses Claude Code action for AI review
- Posts review as **sticky PR comment**
- Checks E2E coverage for SDLC-affecting changes

### Review Focus
- SDLC compliance
- Security considerations
- Code quality
- Testing coverage
- E2E coverage awareness

### Back-and-Forth Review Workflow

```
1. PR opens -> Claude posts sticky review comment
2. You read the review
3. Have questions? -> Comment on the PR
4. Add `needs-review` label -> Claude re-reviews
5. Sticky comment UPDATES (not a new comment)
6. Label auto-removed -> Ready for next round
```

### Smart Features
- **Skips trivial PRs**: Docs-only, config-only changes skip review
- **Waits for CI**: No point reviewing broken code
- **Label-driven re-review**: Add `needs-review` for fresh review

## Testing Workflows Locally

Workflows require the GitHub Actions environment (secrets, runner context, `claude-code-action@v1`). They cannot be tested locally with `act` or similar tools.

**What you can test locally:**
- YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
- Shell script logic: `./tests/test-workflow-triggers.sh`
- E2E simulation (with API key): `ANTHROPIC_API_KEY=xxx ./tests/e2e/run-simulation.sh`

## Secrets Required

| Secret | Used By | Purpose |
|--------|---------|---------|
| `ANTHROPIC_API_KEY` | daily-update, weekly-community, monthly-research, ci, pr-review, ci-autofix | Claude API access |
| `GITHUB_TOKEN` | All workflows | Auto-provided by GitHub |
| `CI_AUTOFIX_APP_ID` | ci-autofix (optional) | GitHub App ID for token generation |
| `CI_AUTOFIX_PRIVATE_KEY` | ci-autofix (optional) | GitHub App private key |

## Workflow Permissions

```yaml
permissions:
  contents: write      # For commits
  pull-requests: write # For PR creation/comments
  id-token: write      # For OIDC authentication
```

## Troubleshooting

### CI Failing
1. Check YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
2. Check test scripts locally: `./tests/test-version-logic.sh`
3. Check fixtures are valid JSON: `jq . tests/fixtures/releases/*.json`

### Daily Update Not Running
1. Verify `ANTHROPIC_API_KEY` secret is set
2. Check workflow is enabled in repo settings
3. Check schedule syntax (cron format)

### PR Review Not Commenting
1. Verify Claude Code action version
2. Check PR is from same repo (not fork)
3. Review action logs for errors
