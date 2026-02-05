# CI/CD Documentation

## Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR, push to main | Validation and tests |
| `daily-update.yml` | Daily 9 AM UTC, manual | Check for Claude Code updates |
| `weekly-community.yml` | Weekly Monday 10 AM UTC | Scan community for patterns |
| `pr-review.yml` | PR opened/updated | AI code review |

## CI Workflow (`ci.yml`)

### What It Does

1. **YAML Validation**: Checks all workflow files are valid YAML
2. **Shell Script Checks**: Scans for unsafe variable interpolation
3. **Prompt File Validation**: Verifies required prompts exist
4. **State File Validation**: Checks version tracking files exist
5. **Version Logic Tests**: Runs `test-version-logic.sh`
6. **Schema Tests**: Runs `test-analysis-schema.sh`
7. **E2E Validation**: Runs `run-simulation.sh` in validation mode
8. **SDP Scoring**: Tracks external model benchmarks and calculates degradation-adjusted scores

### SDP (Model Degradation Tracking)

E2E evaluations now include SDP scoring to distinguish "model issues" from "wizard issues":

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
| Dropped | Stable | **Our SDLC is robust** - good!

### Runs On
- Every pull request
- Push to main branch

## Daily Update Workflow (`daily-update.yml`)

### What It Does

1. Reads last checked version from state file
2. Fetches latest Claude Code release from GitHub
3. Compares versions
4. If different: Analyzes release with Claude
5. HIGH/MEDIUM relevance: Creates PR
6. LOW relevance: Direct commit

### Runs On
- Daily at 9 AM UTC (cron)
- Manual trigger (workflow_dispatch)

### Required Secrets
- `ANTHROPIC_API_KEY`: For Claude analysis

## Weekly Community Workflow (`weekly-community.yml`)

### What It Does
- Scans GitHub for Claude Code community patterns
- Identifies useful integrations, plugins, workflows
- Creates issues for interesting findings

### Runs On
- Weekly on Monday at 10 AM UTC

## PR Review Workflow (`pr-review.yml`)

### What It Does
- Triggers on PR open, ready_for_review, or `needs-review` label
- Waits for CI to pass before reviewing (saves API costs)
- Uses Claude Code action for AI review
- Posts review as **sticky PR comment** (not inline review comments)

### Review Focus
- SDLC compliance
- Security considerations
- Code quality
- Testing coverage

### Sticky Comments vs Inline Reviews

| Approach | Pros | Cons |
|----------|------|------|
| **Inline review comments** | Threading on specific lines | Pile up, clutter PR |
| **Sticky PR comment** | Clean, auto-updates | No line-specific threading |

**We use sticky comments because:**
- Bots shouldn't pile up review comments on every push
- Single sticky comment replaces itself (stays clean)
- User comments provide context, Claude responds in updated sticky
- `hide-comment-action` handles cleanup

### Back-and-Forth Review Workflow

```
1. PR opens → Claude posts sticky review comment
2. You read the review
3. Have questions? → Comment on the PR
4. Add `needs-review` label → Claude re-reviews
5. Sticky comment UPDATES with response (not a new comment)
6. Label auto-removed → Ready for next round
```

**How to trigger re-review:**
```bash
gh pr edit <PR_NUMBER> --add-label needs-review
```

### Smart Features
- **Skips trivial PRs**: Docs-only, config-only changes skip review
- **Waits for CI**: No point reviewing broken code
- **Label-driven re-review**: Add `needs-review` anytime for fresh review

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

# Test with specific event
act push --eventpath .github/test-events/push.json
```

## Known Gaps

### What CI Cannot Test

1. **Actual Claude API responses**
   - CI uses validation mode only
   - No real API calls in tests
   - Fixtures simulate expected responses

2. **PR/Issue creation**
   - Requires repo write permissions
   - Would create real PRs/issues
   - Tested manually before merge

3. **Hook firing behavior**
   - Hooks fire in real Claude sessions
   - Cannot be triggered in CI
   - E2E simulation validates structure only

### Mitigation Strategies

1. **Golden Fixtures**: Test against known-good response formats
2. **Schema Validation**: Verify structure without actual API calls
3. **Manual Testing**: Run locally before merge
4. **E2E with Real API**: Run simulation with API key locally

## Secrets Required

| Secret | Used By | Purpose |
|--------|---------|---------|
| `ANTHROPIC_API_KEY` | daily-update, weekly-community | Claude API access |
| `GITHUB_TOKEN` | All workflows | Auto-provided by GitHub |

## Workflow Permissions

```yaml
permissions:
  contents: write      # For commits
  pull-requests: write # For PR creation
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
