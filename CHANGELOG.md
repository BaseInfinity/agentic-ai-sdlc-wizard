# Changelog

All notable changes to the SDLC Wizard.

> **Note:** This changelog is for humans to read. Don't manually apply these changes - just run the wizard ("Check for SDLC wizard updates") and it handles everything automatically.

## [1.7.0] - 2026-02-15

### Added
- CI Auto-Fix Loop (`ci-autofix.yml`) — automated fix cycle for CI failures and PR review findings
- Multi-call LLM judge (v3) — per-criterion API calls with dedicated calibration examples
- Golden output regression — 3 saved outputs with verified expected score ranges catch prompt drift
- Per-criterion CUSUM — tracks individual criterion drift, not just total score
- Pairwise tiebreaker (v3.1) — holistic comparison with full swap when scores within 1.0
- Deterministic pre-checks — grep-based scoring for task_tracking, confidence, tdd_red (free, fast)
- 3 real-world scenarios: multi-file-api-endpoint, production-bug-investigation, technical-debt-cleanup
- Score analytics (`score-analytics.sh`) — history parsing, trends, per-criterion averages, reports
- Score history persistence — results committed back to repo after each E2E evaluation
- Historical context in PR comments — scenario average and weakest criterion
- Color-coded PR comments — emoji indicators for PASS/WARN/FAIL per criterion
- Binary sub-criteria scoring with workflow input validation (PR #32)
- Evaluate bug regression tests (`test-evaluate-bugs.sh`)
- Score analytics tests (`test-score-analytics.sh`)

### Fixed
- Tier 1 E2E flakiness — regression threshold widened from -0.5 to -1.5 (absorbs ±1 LLM noise)
- Silent zero scores from `2>&1` mixing stderr into stdout (PR #33)
- Token/cost metrics always N/A — removed dead extraction code (action doesn't expose usage data)
- Score history never persisting (ephemeral runner) — added git commit step
- `show_full_output` invalid action input — deleted
- `configureGitAuth` crash — added `git init` before simulation
- `error_max_turns` on hard scenarios — bumped from 45 to 55
- Autofix can't push workflow files — added `workflows: write` permission
- `git push` silent error swallowing in `weekly-community.yml` — removed `|| echo` fallback
- Missing `pull-requests: write` permission in `monthly-research.yml` — e2e-test job creates PRs but permission wasn't declared
- Workflow input validation audit — removed `prompt_file`, `direct_prompt`, `model` invalid inputs across all 3 auto-update workflows
- `outputs.response` doesn't exist — read from execution output file instead

### Changed
- `monthly-research.yml` schedule enabled (1st of month, 11 AM UTC) — Item 23 Phase 3
- `weekly-community.yml` schedule enabled (Mondays 10 AM UTC) — Item 23 Phase 2
- `daily-update.yml` schedule re-enabled (9 AM UTC) — Item 23 Phase 1
- All auto-update workflows create PRs (removed "LOW → direct commit" path)
- Evaluation uses `claude-opus-4-6` model (was hardcoded to `claude-sonnet-4`)
- E2E scenarios expanded from 10 to 13

## [1.6.0] - 2026-02-06

### Added
- Full test coverage for stats library, hooks, and compliance checker (34 new tests)
- Extended SDP calculation and external benchmark tests (9 new tests)
- Future roadmap items 14-19 in AUTO_SELF_UPDATE.md

### Fixed
- Version format validation before npm install (security: prevents injection)
- Hardcoded `/home/runner/work/_temp/` paths replaced with `${RUNNER_TEMP:-/tmp}`
- Silent fallback to v0.0.0 on API failure (now fails loudly)
- Duplicate prompt sources in daily-update workflow (prompt_file + inline prompt)
- Hardcoded output path in pr-review workflow
- Weekly community workflow hardcoded output path

### Changed
- Documentation overhaul: TESTING.md, CI_CD.md, CONTRIBUTING.md, README.md updated
- SDLC.md version tracking updated from 1.0.0 to 1.6.0

### Files Added
- `tests/test-stats.sh` - Statistical functions tests (14 tests)
- `tests/test-hooks.sh` - Hook script tests (11 tests)
- `tests/test-compliance.sh` - Compliance checker tests (9 tests)

### Files Modified
- `.github/workflows/daily-update.yml` - Security + correctness fixes
- `.github/workflows/pr-review.yml` - Hardcoded path fix
- `.github/workflows/weekly-community.yml` - Hardcoded path fix
- `tests/test-sdp-calculation.sh` - Extended (5 new tests)
- `tests/test-external-benchmark.sh` - Extended (4 new tests)

## [1.5.0] - 2026-02-03

### Added
- SDP (SDLC Degradation-adjusted Performance) scoring to distinguish "model issues" from "wizard issues"
- External benchmark tracking (DailyBench, LiveBench) with 24-hour caching
- Robustness metric showing how well SDLC holds up vs model changes
- Two-layer scoring: L1 (Model Quality) + L2 (SDLC Compliance)

### How It Works
PR comments now show three metrics:
- **Raw Score**: Actual E2E measurement
- **SDP Score**: Adjusted for external model conditions
- **Robustness**: < 1.0 = resilient, > 1.0 = sensitive

When model benchmarks drop but your SDLC score holds steady, that's a sign your wizard setup is robust.

### Files Added
- `tests/e2e/lib/external-benchmark.sh` - Multi-source benchmark fetcher
- `tests/e2e/lib/sdp-score.sh` - SDP calculation logic
- `tests/e2e/external-baseline.json` - Baseline external benchmarks
- `tests/test-external-benchmark.sh` - Benchmark fetcher tests
- `tests/test-sdp-calculation.sh` - SDP calculation tests

### Files Modified
- `tests/e2e/evaluate.sh` - Outputs SDP alongside raw scores
- `.github/workflows/ci.yml` - PR comments include SDP metrics
- Documentation updated (README, CONTRIBUTING, CI_CD, AUTO_SELF_UPDATE)

## [1.4.0] - 2026-01-26

### Added
- Auto-update system for staying current with Claude Code releases
- Daily workflow: monitors official releases, creates PRs for relevant updates
- Weekly workflow: scans community discussions, creates digest issues
- Analysis prompts with wizard philosophy baked in
- Version tracking files for state management

### How It Works
GitHub Actions check for Claude Code updates daily (official releases) and weekly (community discussions). Claude analyzes relevance to the wizard, and HIGH/MEDIUM confidence updates create PRs for human review. Most community content is filtered as noise - that's expected.

### Files Added
- `.github/workflows/daily-update.yml`
- `.github/workflows/weekly-community.yml`
- `.github/prompts/analyze-release.md`
- `.github/prompts/analyze-community.md`
- `.github/last-checked-version.txt`
- `.github/last-community-scan.txt`

### Required Setup
Add `ANTHROPIC_API_KEY` to repository secrets for workflows to function.

## [1.3.0] - 2026-01-24

### Added
- Idempotent wizard - safe to run on any existing setup
- Setup tracking comments in SDLC.md (version, completed steps, preferences)
- Wizard step registry for tracking what's been done
- Backwards compatibility for old wizard users

### Changed
- "Staying Updated" section rewritten for idempotent approach
- Update flow now checks plugins and questions, not just files
- One unified flow for setup AND updates (no separate paths)

### How It Works
The wizard now tracks completed steps in SDLC.md metadata comments. Old users running "check for updates" will be walked through only the new steps they haven't done yet.

## [1.2.0] - 2026-01-24

### Added
- Official plugin integration (claude-md-management, code-review, claude-code-setup)
- Step 0.1-0.4: Plugin setup before auto-scan
- "Leverage Official Tools" principle in Philosophy section
- Post-mortem learnings table (what goes where)
- Testing skill "After Session" section for capturing learnings
- Clear update workflow in "Staying Updated" section

### Changed
- Step 0 restructured: plugins first, then SDLC setup, then auto-scan
- Stay Lightweight section now includes official plugin table
- Clarified plugin scope: claude-md-management = CLAUDE.md only

### Files Affected
- `.claude/skills/testing/SKILL.md` - Add "After Session" section
- `SDLC.md` - Consider adding version comment

## [1.1.0] - 2026-01-23

### Added
- Tasks system documentation (v2.1.16+)
- $ARGUMENTS skill parameter support (v2.1.19+)
- Ike the cat easter egg (8 pounds, Fancy Feast enthusiast)
- Iron Man analogy for human+AI partnership

### Changed
- Test review preference: user chooses oversight level
- Shared environment awareness (not everyone runs isolated)

## [1.0.0] - 2026-01-20

### Added
- Initial SDLC Wizard release
- TDD enforcement hooks
- SDLC and Testing skills
- Confidence levels (HIGH/MEDIUM/LOW)
- Planning mode integration
- Self-review workflow
- Testing Diamond philosophy
- Mini-retro after tasks

