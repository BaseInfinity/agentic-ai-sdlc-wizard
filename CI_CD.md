# CI/CD Documentation

## Workflows Overview

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `ci.yml` | PR | Validation, tests, E2E evaluation |
| `ci.yml` | Push to main | Validation only |
| `weekly-update.yml` | Manual only (cron disabled per #212; full migration tracked in #231) | Check for Claude Code updates + community scan |
| `pr-review.yml` | PR opened/ready/labeled | AI code review |
| `release.yml` | Tag push (`v*`) | Publish to npm + create GitHub Release |

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
7. Evaluate candidate score + SDP scoring
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
| 4. Consistency guards | `enforce_tdd_consistency`: if tdd_green_ran=NO, force tdd_green_pass=NO (prevents LLM hallucination) |
| 5. Validation | Schema check, bounds clamping, deterministic merge |

**Prompt version:** v5 (tightened self_review and clean_code prompts 2026-03-28). self_review now requires evidence of actually inspecting work product (not just stating intent). clean_code now requires a single coherent approach.

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
| **Tier 1 (Quick)** | 1x each | Low (directional, -3.0 threshold) | Every PR commit |
| **Tier 2 (Full)** | 5x each | High (95% CI) | `merge-ready` label |

**Tier 1 regression threshold:** Delta must be worse than -3.0 to fail. Single-trial LLM scoring has 6/10 criteria LLM-judged (binary), so a single run typically swings ±2-3 points (rare extremes reach ±4, caught by Tier 2). Deltas within ±3 are noise, not regressions.

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

CI-level token tracking was removed in PR #33 — `claude-code-action@v1` does not expose usage data in its execution output file.

**Available cost controls:**
- `--max-budget-usd` and `--max-turns` via `claude_args` (hard caps per CI invocation)
- `--effort low|medium|high` controls thinking token consumption

**Available tracking (outside CI):**
- `/usage` command shows session totals (USD, API time, code changes). Aliases: `/cost`, `/stats` (legacy names still work)
- Status line JSON provides real-time `cost.total_cost_usd` and per-request token counts
- OpenTelemetry export (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) sends per-request `cost_usd`, `input_tokens`, `output_tokens` to any OTLP backend

### Runs On
- Every pull request (Tier 1)
- Push to main branch (validation only)
- `merge-ready` label (Tier 2)

## Weekly Update Workflow (`weekly-update.yml`)

### What It Does (post-#231 Phase 3 cumulative deletes — v1.53.0+)

1. Reads last checked version from state file
2. Fetches latest Claude Code release from GitHub API
3. Validates version format (security: prevents injection)
4. Compares versions
5. If different: analyzes release with Claude (still in CI — Claude-ranker)
6. Creates auto-update PR with analysis and relevance level
7. Closes stale auto-update PRs

**Removed via ROADMAP #231 Phase 3a/3b/3c (2026-04-27 → 2026-04-29):**
- `version-test` job (Phase 3a) — manual `npm i -g @anthropic-ai/claude-code@<v> && tests/e2e/local-shepherd.sh <PR> --compare-baseline` replaces it
- `community-e2e-test` job (Phase 3b) — maintainer reviews scan-community digest, applies findings, runs local-shepherd
- `scan-community` job (Phase 3c, v1.53.0) — manual `claude --print --allowedTools "WebFetch,Read,Bash" "$(cat .github/prompts/analyze-community.md)"` replaces it
- `friction-signal` issue feedback loop — folded into the manual `claude --print` invocation when the maintainer scans
- Digest issues for notable findings — maintainer creates them via the manual scan output if desired

### Two-Phase Version Testing — DELETED (ROADMAP #231 Phase 3a, v1.51.0)

The CI `version-test` job ($8-20/run, 0 merged artifacts in 30d) was deleted on 2026-04-27. Replacement is a manual local-Max procedure:

```bash
# When the auto-update PR opens for a new CC version, run locally:
npm i -g @anthropic-ai/claude-code@<new_version>
gh pr checkout <auto_update_pr>
tests/e2e/local-shepherd.sh <auto_update_pr> --compare-baseline
# OR for prove-it (custom features intact vs stripped):
tests/e2e/local-shepherd.sh <auto_update_pr> --compare-baseline --strip-paths '[paths]'
```

The shepherd posts a check-run + PR comment with the score delta. Same Phase A/Phase B verdict semantics, run on maintainer's Max ($0 sim leg) instead of CI ($8-20 API).

**Why migrated:** The CI job ran on every CC release detection regardless of relevance. Manual local run lets the maintainer batch detection across multiple releases and only run when a release looks risky.

### Runs On
- Weekly schedule: 9 AM UTC Mondays (`cron: '0 9 * * 1'`)
- Manual trigger also available (workflow_dispatch)

### Required Secrets
- `ANTHROPIC_API_KEY`: For Claude analysis

### Plugin Discovery (Roadmap Item 18)

The weekly-update pipeline doubles as plugin/feature discovery automation:
- Release analysis (`analyze-release.md`) includes a Custom Feature Inventory table comparing wizard features against native CC capabilities
- `plugin_check.replaces_custom` field flags overlap between wizard custom features and new CC native features
- When overlap is detected, the maintainer runs `tests/e2e/local-shepherd.sh <PR> --compare-baseline --strip-paths '[paths]'` locally on Max to A/B compare wizard vs native (ROADMAP #231 Phase 2 — replaces the deleted `prove-it-test` cron job that burned $6-12/run for zero merged artifacts)
- Community scan covers competitive repos and new tools in the CC ecosystem

No separate marketplace registry exists for Claude Code — the LLM-driven release analysis approach captures all feature information from release notes.

## Monthly Research Workflow — REMOVED (ROADMAP #231 Phase 1)

The `monthly-research.yml` workflow was deleted on 2026-04-24. Over its lifetime it produced **zero merged artifacts in 30d** while burning $11-23/month in Anthropic API. The "perplexity-as-CI" pattern was a poor fit: research questions are better asked inline in a Claude Code session with full repo context than batched into a scheduled LLM call.

**If you want periodic research:** open a Claude Code session and ask. No workflow replacement was shipped — the session-start nudge hook (`instructions-loaded-check.sh`) surfaces open PRs and stale state, which covers the "reminder" role without scheduled API burn.

## CI Fix Model — Local Shepherd

The SDLC skill's CI feedback loops (`.claude/skills/sdlc/SKILL.md`) run during active development sessions. Claude watches CI via `gh pr checks --watch`, reads failure logs via `gh run view <RUN_ID> --log-failed`, fixes locally, and pushes — all within one session with full context.

**Advantages:** Full codebase context, zero extra commits, immediate iteration, no API cost beyond the session.

> **Note:** A CI auto-fix bot was previously used as a fallback for unattended PRs. It was deprecated in March 2026 because the local shepherd provides higher-quality fixes with full context, at lower cost.

## PR Review Workflow (`pr-review.yml`)

### What It Does
- Triggers on PR open, ready_for_review, or `needs-review` label
- Waits for CI to pass before reviewing (saves API costs)
- Skips trivial PRs (docs-only, config-only)
- Uses Claude Code action for AI review, pinned to `claude-opus-4-7`
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

### Self-PR Skip on the Wizard Repo (v1.42.1+)

The `review` job is **skipped on `BaseInfinity/claude-sdlc-wizard` self-PRs** — the workflow's `if:` gate checks `github.repository != 'BaseInfinity/claude-sdlc-wizard'`.

**Why**: the wizard maintainer keeps `ANTHROPIC_API_KEY` credit balance dead as an "API canary" — any unexpected API draw is detected by failed CI. `claude-code-action@v1` needs that key with positive balance, so self-PRs were failing every run with "Credit balance is too low". Seven PRs (v1.39.0–v1.42.0) shipped to main with the review job red, normalizing red CI and masking any real review failure that might have appeared.

**Why this is safe**: the wizard uses Codex (`codex exec` with `model_reasoning_effort=xhigh`) for cross-model review during the SDLC skill's review phase. Claude PR review is redundant on self-repo. Consumers using `pr-review.yml` in their own projects WILL run this job normally — the skip only fires when the workflow runs on the wizard's own repo.

**Recovery for new failures**: if claude-code-action ever has a real issue affecting consumers (not just our dead canary), the consumer projects' runs will surface it. We rely on consumer signal + Codex reviews on self-repo to catch problems.

### Smart Features
- **Skips trivial PRs**: Docs-only, config-only changes skip review
- **Waits for CI**: No point reviewing broken code
- **Label-driven re-review**: Add `needs-review` for fresh review

## Local Codex Audit of CI Logs (Cross-Model)

The GH `pr-review.yml` workflow uses whichever Claude model `claude-code-action@v1` defaults to (the action's upstream default — currently Opus 4.8, may change with action updates). For adversarial diversity, the local shepherd loop runs a **second pass with Codex xhigh** against the CI logs themselves — not just the code. A second model catches things the first missed (silent test exclusions, degraded E2E scores on a green checkmark, warnings promoted to errors in a later version). The wizard's local recommendation is Opus 4.6 max (v1.80.0+), but the CI action runs its own default independently.

```bash
# After CI reports pass/fail:
gh run view <RUN_ID> --log > /tmp/ci.log
codex exec -c 'model_reasoning_effort="xhigh"' -s danger-full-access \
  "Audit /tmp/ci.log for silent failures, skipped tests, degraded metrics, \
   or warnings-that-should-be-errors. Green checkmark is necessary but not \
   sufficient. List findings with severity." < /dev/null
```

**Cost:** one extra `codex exec` per PR (~30s, a few cents). **Value:** catches the "green but broken" class of bugs the GH reviewer misses because it reviews diffs, not runs. Documented in `skills/sdlc/SKILL.md` under "The full shepherd sequence" step 4.

## Release Workflow (`release.yml`)

### What It Does
- Triggers on tag push matching `v*` (e.g., `git tag v1.25.0 && git push --tags`)
- Verifies tagged commit is on `main` branch (prevents accidental publish from feature branches)
- Publishes to npm via [Trusted Publishing](https://docs.npmjs.com/trusted-publishers) (OIDC, no token). SLSA provenance is auto-generated by trusted publish — the `--provenance` flag was retired in v1.75.0.
- Creates GitHub Release with auto-generated release notes

### Release Process
1. Bump version in `package.json`, `SDLC.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
2. Commit, tag: `git tag v1.25.0`
3. Push tag: `git push --tags`
4. Workflow publishes to npm + creates GitHub Release automatically

### Post-Release Distribution Verification
After each release, verify ALL distribution channels work:

| Channel | Verification Command | What to Check |
|---------|---------------------|---------------|
| npm | `npx agentic-sdlc-wizard --version` | Correct version |
| curl | `curl -fsSL <url> \| bash` in temp dir | All CLI files created, hooks executable |
| Homebrew | `brew upgrade sdlc-wizard && sdlc-wizard --version` | Formula SHA-256 updated, correct version |
| gh extension | `gh extension upgrade gh-sdlc-wizard && gh sdlc-wizard --version` | Correct version |
| GitHub Release | Check releases page | Notes generated, tag matches |

**Homebrew requires manual formula update** after npm publish:
1. Get new tarball SHA: `curl -sL <tarball-url> | shasum -a 256`
2. Update `Formula/sdlc-wizard.rb` in `BaseInfinity/homebrew-sdlc-wizard`

### CI-Testable Distribution Checks (in `test-install-script.sh`)
- Piped install creates all CLI files (simulates `curl | bash`)
- Piped install sets hooks as executable
- Piped `--help` works
- Shebang is `#!` not `#\!` (regression from heredoc escaping)

## Testing Workflows Locally

Workflows require the GitHub Actions environment (secrets, runner context, `claude-code-action@v1`). They cannot be tested locally with `act` or similar tools.

**What you can test locally:**
- YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
- Shell script logic: `./tests/test-workflow-triggers.sh`
- E2E simulation (requires Claude Code CLI + API key): `ANTHROPIC_API_KEY=xxx ./tests/e2e/run-simulation.sh`

## Secrets Required

| Secret | Used By | Purpose |
|--------|---------|---------|
| `ANTHROPIC_API_KEY` | weekly-update, ci, pr-review | Claude API access (monthly-research removed per #231 Phase 1) |
| `GITHUB_TOKEN` | All workflows | Auto-provided by GitHub |

**No `NPM_TOKEN` required** as of v1.75.0 — `release.yml` uses [npm Trusted Publishing](https://docs.npmjs.com/trusted-publishers) (OIDC via GitHub Actions `id-token: write`). The publisher is configured per-package on npm's side: npmjs.com → `agentic-sdlc-wizard` → Settings → Publishing access → GitHub Actions → repo `BaseInfinity/claude-sdlc-wizard`, workflow filename `release.yml`. Provenance attestations are auto-generated; no long-lived secret to rotate.

## Workflow Permissions

**ci.yml** uses least-privilege: workflow-level is read-only, write permissions added at job level only where needed.

```yaml
# ci.yml workflow-level (inherited by validate job)
permissions:
  contents: read
  pull-requests: read

# ci.yml job-level overrides (cleanup-old-comments, e2e-quick-check, e2e-full-evaluation)
permissions:
  contents: write      # For score-history artifacts + PR branch operations
  pull-requests: write # For sticky PR comments
```

**Other workflows** (pr-review, weekly-update):

```yaml
permissions:
  contents: write      # For commits
  pull-requests: write # For PR creation/comments
```

## Troubleshooting

### CI Failing
1. Check YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"`
2. Check test scripts locally: `./tests/test-version-logic.sh`
3. Check fixtures are valid JSON: `jq . tests/fixtures/releases/*.json`

### Weekly Update Not Running
1. Verify `ANTHROPIC_API_KEY` secret is set
2. Check workflow is enabled in repo settings
3. Check schedule syntax (cron format)

### PR Review Not Commenting
1. Verify Claude Code action version
2. Check PR is from same repo (not fork)
3. Review action logs for errors
