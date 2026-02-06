# CI/CD Documentation

## Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR, push to main | Validation, tests, E2E evaluation |
| `daily-update.yml` | Daily 9 AM UTC, manual | Check for Claude Code updates |
| `weekly-community.yml` | Weekly Sunday 9 AM UTC | Scan community for patterns |
| `monthly-research.yml` | 1st of month 9 AM UTC | Deep research and trends |
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

### Native Task Metrics

PR comments include resource usage (collapsed):

| Metric | Description |
|--------|-------------|
| Duration | Simulation time in seconds |
| Tool uses | Number of tool calls |
| Input/Output tokens | Token consumption |
| Est. cost | API cost estimate |
| Tokens/point | Efficiency metric |

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
- Daily at 9 AM UTC (cron)
- Manual trigger (workflow_dispatch)

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
- Weekly on Sunday at 9 AM UTC

## Monthly Research Workflow (`monthly-research.yml`)

### What It Does
- Deep research into AI coding agent trends
- Academic papers, major announcements
- Creates issue with trend report and recommendations
- E2E tests research-suggested improvements (Tier 2)

### Runs On
- 1st of month at 9 AM UTC

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

### Prerequisites
- Install [act](https://github.com/nektos/act): `brew install act`
- Create `.env.test` with required secrets:
  ```
  ANTHROPIC_API_KEY=sk-ant-xxx
  ```

### Running Workflows

```bash
# Test CI workflow (no secrets needed)
act pull_request -W .github/workflows/ci.yml

# Test daily update workflow
act workflow_dispatch -W .github/workflows/daily-update.yml \
    --secret-file .env.test
```

## Secrets Required

| Secret | Used By | Purpose |
|--------|---------|---------|
| `ANTHROPIC_API_KEY` | daily-update, weekly-community, monthly-research, ci, pr-review | Claude API access |
| `GITHUB_TOKEN` | All workflows | Auto-provided by GitHub |

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
