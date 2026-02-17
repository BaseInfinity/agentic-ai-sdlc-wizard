#!/bin/bash
# Test workflow trigger configurations and state file handling

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASSED=0
FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Workflow Trigger Tests ==="
echo ""

# Test 1: Daily workflow has workflow_dispatch trigger
test_daily_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "Daily workflow file not found"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "Daily workflow has workflow_dispatch trigger"
    else
        fail "Daily workflow missing workflow_dispatch trigger"
    fi
}

# Test 2: Weekly workflow has workflow_dispatch trigger
test_weekly_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "Weekly workflow file not found"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "Weekly workflow has workflow_dispatch trigger"
    else
        fail "Weekly workflow missing workflow_dispatch trigger"
    fi
}

# Test 3: Monthly workflow has workflow_dispatch trigger
test_monthly_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "Monthly workflow file not found"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "Monthly workflow has workflow_dispatch trigger"
    else
        fail "Monthly workflow missing workflow_dispatch trigger"
    fi
}

# Test 4: Daily workflow has active schedule trigger (Item 23 Phase 1)
test_daily_has_schedule() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if grep -q "schedule:" "$WORKFLOW" && grep -q "cron:" "$WORKFLOW"; then
        pass "Daily workflow has active schedule with cron trigger"
    else
        fail "Daily workflow missing schedule trigger (should have cron for Item 23)"
    fi
}

# Test 35: Weekly workflow has active schedule trigger (Item 23 Phase 2)
test_weekly_has_schedule() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if grep -q "schedule:" "$WORKFLOW" && grep -q "cron:" "$WORKFLOW"; then
        pass "Weekly workflow has active schedule with cron trigger"
    else
        fail "Weekly workflow missing schedule trigger (should have cron for Item 23)"
    fi
}

# Test 36: Monthly workflow has active schedule trigger (Item 23 Phase 3)
test_monthly_has_schedule() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if grep -q "schedule:" "$WORKFLOW" && grep -q "cron:" "$WORKFLOW"; then
        pass "Monthly workflow has active schedule with cron trigger"
    else
        fail "Monthly workflow missing schedule trigger (should have cron for Item 23)"
    fi
}

# Test 5: State file path is valid in daily workflow
test_state_file_path() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if grep -q "last-checked-version.txt" "$WORKFLOW"; then
        pass "Daily workflow references state file correctly"
    else
        fail "Daily workflow missing state file reference"
    fi
}

# Test 6: State file round-trip (write then read)
test_state_file_roundtrip() {
    TEMP_DIR=$(mktemp -d)
    STATE_FILE="$TEMP_DIR/last-checked-version.txt"
    TEST_VERSION="v2.1.20"

    # Write
    echo "$TEST_VERSION" > "$STATE_FILE"

    # Read back (same logic as workflow)
    if [ -f "$STATE_FILE" ]; then
        READ_VERSION=$(cat "$STATE_FILE" | tr -d '\n')
    else
        READ_VERSION="v0.0.0"
    fi

    rm -rf "$TEMP_DIR"

    if [ "$READ_VERSION" = "$TEST_VERSION" ]; then
        pass "State file round-trip works correctly"
    else
        fail "State file round-trip failed: wrote '$TEST_VERSION', read '$READ_VERSION'"
    fi
}

# Test 7: Workflow has proper permissions
test_workflow_permissions() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if grep -q "permissions:" "$WORKFLOW"; then
        pass "Daily workflow declares permissions"
    else
        fail "Daily workflow missing permissions declaration"
    fi
}

# Test 8: Workflow uses checkout action
test_workflow_checkout() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if grep -q "actions/checkout" "$WORKFLOW"; then
        pass "Daily workflow uses checkout action"
    else
        fail "Daily workflow missing checkout action"
    fi
}

# Test 9: Error handling - jq fallback for missing release
test_error_handling_pattern() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    # Check for error handling pattern (|| echo for fallback)
    if grep -q '|| echo' "$WORKFLOW" || grep -q '2>/dev/null' "$WORKFLOW"; then
        pass "Daily workflow has error handling patterns"
    else
        fail "Daily workflow missing error handling"
    fi
}

# Test 10: All workflows are valid YAML (basic check)
test_yaml_validity() {
    WORKFLOWS="$REPO_ROOT/.github/workflows"
    ALL_VALID=true

    for workflow in "$WORKFLOWS"/*.yml; do
        # Basic check: file starts with valid YAML (name: or on:)
        FIRST_LINE=$(head -n 1 "$workflow")
        if [[ ! "$FIRST_LINE" =~ ^(name:|on:|\#) ]]; then
            fail "Workflow $(basename "$workflow") may have invalid YAML"
            ALL_VALID=false
        fi
    done

    if [ "$ALL_VALID" = true ]; then
        pass "All workflow files have valid YAML structure"
    fi
}

# ============================================
# E2E Bootstrapping Detection Regression Tests
# ============================================
# These tests ensure the bootstrapping logic in ci.yml
# is not accidentally removed or broken.

# Test 11: CI has bootstrapping detection step
test_e2e_bootstrapping_detection() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    if grep -q "check-baseline" "$WORKFLOW" && \
       grep -q "has_baseline" "$WORKFLOW"; then
        pass "CI has bootstrapping detection step"
    else
        fail "CI missing bootstrapping detection (check-baseline + has_baseline)"
    fi
}

# Test 12: Baseline steps are conditional on has_baseline
test_e2e_conditional_baseline() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if grep -q "if:.*has_baseline.*true" "$WORKFLOW"; then
        pass "Baseline steps are conditional on has_baseline"
    else
        fail "Baseline steps not properly conditional on has_baseline"
    fi
}

# Test 13: Bootstrapping is handled in compare step
test_e2e_bootstrapping_handling() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if grep -q "is_bootstrapping" "$WORKFLOW"; then
        pass "Compare step handles bootstrapping case"
    else
        fail "Compare step missing bootstrapping handling (is_bootstrapping)"
    fi
}

# ============================================
# CI Label Trigger Tests
# ============================================
# These tests ensure the CI workflow properly handles
# the `labeled` event for merge-ready label triggering.

# Test 14: CI pull_request trigger includes 'labeled' type
test_ci_labeled_trigger() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    if grep -q "labeled" "$WORKFLOW"; then
        pass "CI pull_request trigger includes 'labeled' type"
    else
        fail "CI pull_request trigger missing 'labeled' type"
    fi
}

# Test 15: e2e-quick-check is guarded from labeled events
test_quick_check_labeled_guard() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    # The e2e-quick-check job should skip on labeled events
    # Look for the guard condition near the e2e-quick-check job
    if grep -A 3 "e2e-quick-check:" "$WORKFLOW" | grep -q "labeled"; then
        pass "e2e-quick-check is guarded from labeled events"
    else
        fail "e2e-quick-check missing guard for labeled events"
    fi
}

# Test 16: cleanup-old-comments is guarded from labeled events
test_cleanup_labeled_guard() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    # The cleanup-old-comments job should skip on labeled events
    if grep -A 3 "cleanup-old-comments:" "$WORKFLOW" | grep -q "labeled"; then
        pass "cleanup-old-comments is guarded from labeled events"
    else
        fail "cleanup-old-comments missing guard for labeled events"
    fi
}

# Test 17: Daily workflow checks for existing PR before creating
test_daily_existing_pr_check() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "Daily workflow file not found"
        return
    fi

    if grep -q "existing-pr" "$WORKFLOW" && grep -q "skip" "$WORKFLOW"; then
        pass "Daily workflow checks for existing PR before creating"
    else
        fail "Daily workflow missing existing PR check"
    fi
}

# ============================================
# PR Review Re-trigger Tests
# ============================================
# These tests ensure the PR review workflow re-runs
# on each push (synchronize event), not just on open.

# Test 18: PR review triggers on synchronize (re-review on push)
test_pr_review_synchronize_trigger() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "PR review workflow file not found"
        return
    fi

    # Check the types: line specifically includes synchronize
    if grep "types:" "$WORKFLOW" | grep -q "synchronize"; then
        pass "PR review workflow triggers on synchronize"
    else
        fail "PR review workflow missing synchronize trigger (reviews only run once per PR)"
    fi
}

# Test 19: PR review if-condition allows synchronize events through
test_pr_review_synchronize_condition() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "PR review workflow file not found"
        return
    fi

    # The job-level if condition must include synchronize
    if grep -A 5 "if:" "$WORKFLOW" | grep -q "synchronize"; then
        pass "PR review if-condition handles synchronize events"
    else
        fail "PR review if-condition does not handle synchronize events (reviews won't run on push)"
    fi
}

# ============================================
# E2E AllowedTools Coverage Tests
# ============================================
# These tests ensure Claude simulations have access
# to the tools that scenarios actually need.

# Test 20: CI allowedTools excludes plan mode tools (they loop in headless CI)
test_ci_allowed_tools_no_plan_mode() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    if grep "allowedTools" "$WORKFLOW" | grep -q "EnterPlanMode\|ExitPlanMode"; then
        fail "CI allowedTools should NOT include EnterPlanMode/ExitPlanMode (loops in headless CI)"
    else
        pass "CI allowedTools excludes plan mode tools (headless-safe)"
    fi
}

# Test 21: CI allowedTools includes task tracking tools (needed for scoring)
test_ci_allowed_tools_task_tracking() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    if grep "allowedTools" "$WORKFLOW" | grep -q "TaskCreate"; then
        pass "CI allowedTools includes TaskCreate"
    else
        fail "CI allowedTools missing TaskCreate (8/10 scenarios score on task tracking)"
    fi
}

# ============================================
# CI Auto-Fix Workflow Tests
# ============================================
# These tests ensure the ci-autofix.yml workflow
# is properly configured for the automated fix loop.

# Test 22: ci-autofix.yml file exists
test_ci_autofix_exists() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ -f "$WORKFLOW" ]; then
        pass "ci-autofix.yml file exists"
    else
        fail "ci-autofix.yml file not found"
    fi
}

# Test 23: ci-autofix triggers on workflow_run
test_ci_autofix_workflow_run_trigger() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for trigger test)"
        return
    fi

    if grep -q "workflow_run:" "$WORKFLOW"; then
        pass "ci-autofix triggers on workflow_run"
    else
        fail "ci-autofix missing workflow_run trigger"
    fi
}

# Test 24: ci-autofix watches both CI and PR Code Review workflows
test_ci_autofix_watches_both_workflows() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for workflows test)"
        return
    fi

    if grep -q '"CI"' "$WORKFLOW" && grep -q '"PR Code Review"' "$WORKFLOW"; then
        pass "ci-autofix watches both CI and PR Code Review workflows"
    else
        fail "ci-autofix not watching both CI and PR Code Review workflows"
    fi
}

# Test 25: ci-autofix has MAX_AUTOFIX_RETRIES config
test_ci_autofix_max_retries() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for retries test)"
        return
    fi

    if grep -q "MAX_AUTOFIX_RETRIES" "$WORKFLOW"; then
        pass "ci-autofix has MAX_AUTOFIX_RETRIES config"
    else
        fail "ci-autofix missing MAX_AUTOFIX_RETRIES config"
    fi
}

# Test 26: ci-autofix excludes main branch
test_ci_autofix_excludes_main() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for branch exclusion test)"
        return
    fi

    if grep -q "main" "$WORKFLOW" && grep -q "head_branch" "$WORKFLOW"; then
        pass "ci-autofix excludes main branch"
    else
        fail "ci-autofix missing main branch exclusion"
    fi
}

# Test 27: ci-autofix uses claude-code-action
test_ci_autofix_uses_claude() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for claude action test)"
        return
    fi

    if grep -q "claude-code-action" "$WORKFLOW"; then
        pass "ci-autofix uses claude-code-action"
    else
        fail "ci-autofix missing claude-code-action"
    fi
}

# Test 28: ci-autofix uses [autofix] commit tag pattern
test_ci_autofix_commit_tag() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for commit tag test)"
        return
    fi

    if grep -q '\[autofix' "$WORKFLOW"; then
        pass "ci-autofix uses [autofix] commit tag pattern"
    else
        fail "ci-autofix missing [autofix] commit tag pattern"
    fi
}

# Test 29: ci-autofix posts sticky PR comment
test_ci_autofix_sticky_comment() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for sticky comment test)"
        return
    fi

    if grep -q "sticky-pull-request-comment" "$WORKFLOW" && grep -q "ci-autofix" "$WORKFLOW"; then
        pass "ci-autofix posts sticky PR comment"
    else
        fail "ci-autofix missing sticky PR comment"
    fi
}

# Test 30: ci.yml has workflow_dispatch trigger
test_ci_workflow_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for dispatch test)"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "ci.yml has workflow_dispatch trigger"
    else
        fail "ci.yml missing workflow_dispatch trigger"
    fi
}

# Test 31: ci-autofix reads review comment for findings
test_ci_autofix_reads_review() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for review reading test)"
        return
    fi

    if grep -q "claude-review" "$WORKFLOW"; then
        pass "ci-autofix reads review comment (claude-review header)"
    else
        fail "ci-autofix missing review comment reading (claude-review)"
    fi
}

# ============================================
# CI Autofix Prompt & E2E Turns Tests
# ============================================
# These tests ensure the ci-autofix prompt passes
# context via file paths (not broken step outputs)
# and that simulations have enough turns.

# Test 32: ci-autofix prompt references /tmp/ci-failure-context.txt
test_ci_autofix_prompt_failure_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for prompt file test)"
        return
    fi

    if grep -q "/tmp/ci-failure-context.txt" "$WORKFLOW"; then
        pass "ci-autofix prompt references /tmp/ci-failure-context.txt"
    else
        fail "ci-autofix prompt missing /tmp/ci-failure-context.txt reference (Claude gets empty context)"
    fi
}

# Test 33: ci-autofix prompt references /tmp/review-findings.md
test_ci_autofix_prompt_review_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for prompt file test)"
        return
    fi

    if grep -q "/tmp/review-findings.md" "$WORKFLOW"; then
        pass "ci-autofix prompt references /tmp/review-findings.md"
    else
        fail "ci-autofix prompt missing /tmp/review-findings.md reference (Claude gets empty context)"
    fi
}

# Test 34: ci.yml max-turns is >= 35 for all simulations
test_ci_max_turns_sufficient() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for max-turns test)"
        return
    fi

    # Extract all --max-turns values and check they're all >= 35
    ALL_SUFFICIENT=true
    while IFS= read -r line; do
        TURNS=$(echo "$line" | grep -oE '[0-9]+')
        if [ "$TURNS" -lt 35 ]; then
            fail "ci.yml has --max-turns $TURNS (need >= 35 to avoid error_max_turns flakiness)"
            ALL_SUFFICIENT=false
            break
        fi
    done < <(grep -- "--max-turns" "$WORKFLOW")

    if [ "$ALL_SUFFICIENT" = true ]; then
        pass "ci.yml max-turns is >= 35 for all simulations"
    fi
}

# Run all tests
test_daily_dispatch
test_weekly_dispatch
test_monthly_dispatch
test_daily_has_schedule
test_weekly_has_schedule
test_monthly_has_schedule
test_state_file_path
test_state_file_roundtrip
test_workflow_permissions
test_workflow_checkout
test_error_handling_pattern
test_yaml_validity
test_e2e_bootstrapping_detection
test_e2e_conditional_baseline
test_e2e_bootstrapping_handling
test_ci_labeled_trigger
test_quick_check_labeled_guard
test_cleanup_labeled_guard
test_daily_existing_pr_check
test_pr_review_synchronize_trigger
test_pr_review_synchronize_condition
test_ci_allowed_tools_no_plan_mode
test_ci_allowed_tools_task_tracking
test_ci_autofix_exists
test_ci_autofix_workflow_run_trigger
test_ci_autofix_watches_both_workflows
test_ci_autofix_max_retries
test_ci_autofix_excludes_main
test_ci_autofix_uses_claude
test_ci_autofix_commit_tag
test_ci_autofix_sticky_comment
test_ci_workflow_dispatch
test_ci_autofix_reads_review
test_ci_autofix_prompt_failure_file
test_ci_autofix_prompt_review_file
test_ci_max_turns_sufficient

# ============================================
# CI Autofix Suggestion Handling Tests
# ============================================
# These tests ensure ci-autofix addresses ALL review
# findings (both criticals and suggestions), not just criticals.

# Test 37: ci-autofix checks for suggestions (not just criticals)
test_ci_autofix_checks_suggestions() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for suggestions test)"
        return
    fi

    if grep -q "Suggestions (nice to have)" "$WORKFLOW"; then
        pass "ci-autofix checks for suggestions (not just criticals)"
    else
        fail "ci-autofix only checks for criticals, ignores suggestions"
    fi
}

# Test 38: ci-autofix prompt addresses all findings
test_ci_autofix_prompt_all_findings() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for prompt test)"
        return
    fi

    if grep -q "suggestions" "$WORKFLOW" && grep -q "critical" "$WORKFLOW"; then
        pass "ci-autofix prompt addresses both criticals and suggestions"
    else
        fail "ci-autofix prompt only addresses criticals"
    fi
}

# Test 39: ci-autofix prompt tells Claude to use Read tool (not Bash) for context files
test_ci_autofix_prompt_read_tool() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for Read tool test)"
        return
    fi

    if grep -q "Use the Read tool" "$WORKFLOW" && grep -q "NOT Bash" "$WORKFLOW"; then
        pass "ci-autofix prompt steers Claude to Read tool (prevents wasted Bash denials)"
    else
        fail "ci-autofix prompt missing Read tool guidance (Claude will waste turns on denied Bash calls)"
    fi
}

test_ci_autofix_checks_suggestions
test_ci_autofix_prompt_all_findings
test_ci_autofix_prompt_read_tool

# ============================================
# CI Autofix Max-Turns & Prompt Hygiene Tests
# ============================================

# Test 40: ci-autofix --max-turns >= 30
test_ci_autofix_max_turns() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for max-turns test)"
        return
    fi

    # Extract --max-turns value from ci-autofix.yml
    TURNS=$(grep -oE '\-\-max-turns [0-9]+' "$WORKFLOW" | grep -oE '[0-9]+')

    if [ -z "$TURNS" ]; then
        fail "ci-autofix.yml missing --max-turns flag"
        return
    fi

    if [ "$TURNS" -ge 30 ]; then
        pass "ci-autofix --max-turns is >= 30 ($TURNS)"
    else
        fail "ci-autofix --max-turns is $TURNS (need >= 30 for complex fixes)"
    fi
}

# Test 41: ci-autofix prompt has no literal \n ternary pattern
test_ci_autofix_no_ternary_newlines() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml file not found (needed for ternary test)"
        return
    fi

    # Check for the problematic pattern: ${{ expr && 'text\n' || '' }}
    if grep -q "&&.*\\\\n.*||" "$WORKFLOW"; then
        fail "ci-autofix prompt uses ternary with literal \\n (renders as literal backslash-n, not newline)"
    else
        pass "ci-autofix prompt has no ternary \\n pattern"
    fi
}

test_ci_autofix_max_turns
test_ci_autofix_no_ternary_newlines

# ============================================
# CI Cosmetic Step Resilience Tests
# ============================================
# These tests ensure cosmetic CI steps (PR comments)
# don't fail the build, while the real quality gate does.

# Test 42: "Build quick check comment message" has continue-on-error
test_quick_check_comment_continue_on_error() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for continue-on-error test)"
        return
    fi

    # Check that the "Build quick check comment message" step has continue-on-error: true
    if grep -A 2 "Build quick check comment message" "$WORKFLOW" | grep -q "continue-on-error: true"; then
        pass "Build quick check comment message has continue-on-error: true"
    else
        fail "Build quick check comment message missing continue-on-error: true (cosmetic step can fail the build)"
    fi
}

# Test 43: "Comment quick check results on PR" has continue-on-error
test_quick_check_post_comment_continue_on_error() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for continue-on-error test)"
        return
    fi

    # Check that the "Comment quick check results on PR" step has continue-on-error: true
    if grep -A 2 "Comment quick check results on PR" "$WORKFLOW" | grep -q "continue-on-error: true"; then
        pass "Comment quick check results on PR has continue-on-error: true"
    else
        fail "Comment quick check results on PR missing continue-on-error: true (cosmetic step can fail the build)"
    fi
}

# Test 44: "Fail on regression" does NOT have continue-on-error
test_fail_on_regression_no_continue_on_error() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for quality gate test)"
        return
    fi

    # The quality gate must NOT have continue-on-error
    if grep -A 2 "Fail on regression" "$WORKFLOW" | grep -q "continue-on-error"; then
        fail "Fail on regression has continue-on-error (quality gate would be bypassed!)"
    else
        pass "Fail on regression does NOT have continue-on-error (quality gate intact)"
    fi
}

# ============================================
# CI Comment Safety Tests
# ============================================
# These tests ensure untrusted LLM output (criteria evidence)
# is NOT assigned via ${{ }} inline in bash (backtick injection).

# Test 45: CRITERIA is passed via env block, not inline ${{ }} in bash
test_criteria_not_inline_expanded() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for criteria safety test)"
        return
    fi

    # Check that CRITERIA is NOT set via inline ${{ }} in a bash variable assignment
    # Bad:  CRITERIA="${{ steps.eval-candidate.outputs.criteria }}"
    # Good: env: CRITERIA: ${{ steps.eval-candidate.outputs.criteria }}
    if grep -E 'CRITERIA="\$\{\{' "$WORKFLOW"; then
        fail "CRITERIA uses inline \${{ }} expansion (backticks in LLM evidence text execute as commands)"
    else
        pass "CRITERIA is not inline-expanded in bash (safe from backtick injection)"
    fi
}

# Test 46: Comment-building steps use env block for untrusted outputs
test_comment_steps_use_env_block() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for env block test)"
        return
    fi

    # Both "Build quick check comment message" and "Build full evaluation comment message"
    # should have an env: block that includes CRITERIA
    QUICK_HAS_ENV=false
    FULL_HAS_ENV=false

    # Use python for reliable multi-line YAML parsing
    python3 -c "
import yaml, sys
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        name = step.get('name', '')
        env = step.get('env', {})
        if 'Build quick check comment message' in name:
            if 'CRITERIA' in env:
                print('QUICK_ENV_OK')
        if 'Build full evaluation comment message' in name:
            if 'CRITERIA' in env:
                print('FULL_ENV_OK')
" > /tmp/env_check_result.txt 2>&1

    if grep -q "QUICK_ENV_OK" /tmp/env_check_result.txt; then
        QUICK_HAS_ENV=true
    fi
    if grep -q "FULL_ENV_OK" /tmp/env_check_result.txt; then
        FULL_HAS_ENV=true
    fi

    if [ "$QUICK_HAS_ENV" = true ] && [ "$FULL_HAS_ENV" = true ]; then
        pass "Both comment-building steps pass CRITERIA via env block (safe)"
    else
        if [ "$QUICK_HAS_ENV" = false ]; then
            fail "Quick check comment step missing CRITERIA in env block"
        fi
        if [ "$FULL_HAS_ENV" = false ]; then
            fail "Full evaluation comment step missing CRITERIA in env block"
        fi
    fi
}

test_criteria_not_inline_expanded
test_comment_steps_use_env_block

test_quick_check_comment_continue_on_error
test_quick_check_post_comment_continue_on_error
test_fail_on_regression_no_continue_on_error

# ============================================
# Full E2E Dependency Compatibility Tests
# ============================================
# These tests ensure the e2e-full-evaluation job can actually run
# when triggered by the 'labeled' event (merge-ready label).

# Test 47: e2e-full-evaluation must not depend on jobs that skip on 'labeled' events
test_full_eval_deps_run_on_labeled() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # Parse the workflow to check that every job in e2e-full-evaluation's 'needs'
    # does NOT have a condition that excludes 'labeled' events
    python3 -c "
import yaml, sys
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
jobs = wf.get('jobs', {})
full_eval = jobs.get('e2e-full-evaluation', {})
needs = full_eval.get('needs', [])
if isinstance(needs, str):
    needs = [needs]

blocked = []
for dep in needs:
    dep_job = jobs.get(dep, {})
    condition = str(dep_job.get('if', ''))
    # If the dependency skips on 'labeled' events, full-eval can never run
    if \"event.action != 'labeled'\" in condition:
        blocked.append(dep)

if blocked:
    print('BLOCKED_BY:' + ','.join(blocked))
else:
    print('DEPS_OK')
" > /tmp/full_eval_deps.txt 2>&1

    if grep -q "DEPS_OK" /tmp/full_eval_deps.txt; then
        pass "e2e-full-evaluation dependencies all run on 'labeled' events"
    else
        BLOCKERS=$(grep "BLOCKED_BY:" /tmp/full_eval_deps.txt | sed 's/BLOCKED_BY://')
        fail "e2e-full-evaluation depends on jobs that skip on 'labeled': $BLOCKERS (full eval can never run)"
    fi
}

test_full_eval_deps_run_on_labeled

# ============================================
# PR Review Prompt Hygiene Tests
# ============================================
# Ensure the review prompt doesn't contain shell
# constructs that won't expand in YAML strings.

# Test 48: pr-review prompt must not use $(cat ...) in YAML prompt field
test_review_prompt_no_shell_subst() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml file not found"
        return
    fi

    # $(cat ...) in a YAML 'prompt: |' field is dead code —
    # YAML strings don't execute shell commands.
    # claude-code-action provides comments through its own mechanism.
    if grep -E '\$\(cat ' "$WORKFLOW"; then
        fail "pr-review.yml prompt contains \$(cat ...) — won't expand in YAML string (dead code)"
    else
        pass "pr-review.yml prompt has no shell command substitution in YAML strings"
    fi
}

test_review_prompt_no_shell_subst

# ============================================
# Daily-Update Workflow Input Validation Tests
# ============================================
# Ensure claude-code-action steps use valid inputs only.

# Test 49: daily-update must NOT use 'prompt_file' (not a valid action input)
test_daily_no_prompt_file_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    # claude-code-action@v1 does not accept 'prompt_file' — use 'prompt' instead
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'prompt_file' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/prompt_file_check.txt 2>&1

    if grep -q "FOUND:" /tmp/prompt_file_check.txt; then
        STEP=$(grep "FOUND:" /tmp/prompt_file_check.txt | head -1 | sed 's/FOUND://')
        fail "daily-update uses 'prompt_file' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "daily-update does not use invalid 'prompt_file' input"
    fi
}

# Test 50: daily-update must NOT use 'direct_prompt' (not a valid action input)
test_daily_no_direct_prompt_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'direct_prompt' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/direct_prompt_check.txt 2>&1

    if grep -q "FOUND:" /tmp/direct_prompt_check.txt; then
        STEP=$(grep "FOUND:" /tmp/direct_prompt_check.txt | head -1 | sed 's/FOUND://')
        fail "daily-update uses 'direct_prompt' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "daily-update does not use invalid 'direct_prompt' input"
    fi
}

# Test 51: daily-update must NOT use 'model' as a top-level action input
test_daily_no_model_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        uses = step.get('uses', '')
        with_block = step.get('with', {})
        if 'claude-code-action' in uses and 'model' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/model_input_check.txt 2>&1

    if grep -q "FOUND:" /tmp/model_input_check.txt; then
        STEP=$(grep "FOUND:" /tmp/model_input_check.txt | head -1 | sed 's/FOUND://')
        fail "daily-update uses 'model' as action input in step '$STEP' — use claude_args --model instead"
    else
        pass "daily-update does not use invalid 'model' action input"
    fi
}

# Test 52: daily-update evaluate.sh calls must NOT use 2>&1 (stderr corruption)
test_daily_no_stderr_mixing_in_eval() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    # evaluate.sh calls with 2>&1 corrupt JSON output with stderr messages.
    # The command may span multiple lines with \ continuations, so we check
    # all 'run:' blocks in version-test steps that call evaluate.sh
    python3 -c "
import yaml, re
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        if 'evaluate.sh' in run and '2>&1' in run:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/stderr_mix_check.txt 2>&1

    if grep -q "FOUND:" /tmp/stderr_mix_check.txt; then
        STEP=$(grep "FOUND:" /tmp/stderr_mix_check.txt | head -1 | sed 's/FOUND://')
        fail "daily-update step '$STEP' pipes evaluate.sh stderr to stdout (2>&1) — causes jq parse failures"
    else
        pass "daily-update.yml does not mix stderr into evaluate.sh output"
    fi
}

test_daily_no_prompt_file_input
test_daily_no_direct_prompt_input
test_daily_no_model_input
test_daily_no_stderr_mixing_in_eval

# Test 53: daily-update must NOT reference outputs.response (doesn't exist in claude-code-action@v1)
test_daily_no_outputs_response() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    # claude-code-action@v1 exposes 'structured_output', not 'response'
    # Any reference to outputs.response will always be empty
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    content = f.read()
if 'outputs.response' in content:
    print('FOUND')
" > /tmp/outputs_response_check.txt 2>&1

    if grep -q "FOUND" /tmp/outputs_response_check.txt; then
        fail "daily-update references 'outputs.response' — claude-code-action@v1 uses 'outputs.structured_output' instead"
    else
        pass "daily-update does not reference non-existent 'outputs.response'"
    fi
}

# Test 54: daily-update must extract analysis from execution output file
test_daily_extracts_from_output_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "daily-update.yml not found"
        return
    fi

    # The analysis result must be extracted from claude-execution-output.json
    # (not from outputs.response or outputs.structured_output which don't exist)
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        if 'claude-execution-output.json' in run and 'analysis' in step.get('name', '').lower():
            print('READS_OUTPUT_FILE')
" > /tmp/output_file_check.txt 2>&1

    if grep -q "READS_OUTPUT_FILE" /tmp/output_file_check.txt; then
        pass "daily-update extracts analysis from execution output file"
    else
        fail "daily-update does not read claude-execution-output.json for analysis (result will be empty)"
    fi
}

test_daily_no_outputs_response
test_daily_extracts_from_output_file

# ============================================
# Weekly-Community Workflow Input Validation Tests
# ============================================
# Same class of bugs as daily-update: invalid claude-code-action inputs.

# Test 55: weekly-community must NOT use 'prompt_file' (not a valid action input)
test_weekly_no_prompt_file_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'prompt_file' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/weekly_prompt_file_check.txt 2>&1

    if grep -q "FOUND:" /tmp/weekly_prompt_file_check.txt; then
        STEP=$(grep "FOUND:" /tmp/weekly_prompt_file_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-community uses 'prompt_file' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "weekly-community does not use invalid 'prompt_file' input"
    fi
}

# Test 56: weekly-community must NOT use 'direct_prompt' (not a valid action input)
test_weekly_no_direct_prompt_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'direct_prompt' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/weekly_direct_prompt_check.txt 2>&1

    if grep -q "FOUND:" /tmp/weekly_direct_prompt_check.txt; then
        STEP=$(grep "FOUND:" /tmp/weekly_direct_prompt_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-community uses 'direct_prompt' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "weekly-community does not use invalid 'direct_prompt' input"
    fi
}

# Test 57: weekly-community must NOT use 'model' as a top-level action input
test_weekly_no_model_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        uses = step.get('uses', '')
        with_block = step.get('with', {})
        if 'claude-code-action' in uses and 'model' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/weekly_model_check.txt 2>&1

    if grep -q "FOUND:" /tmp/weekly_model_check.txt; then
        STEP=$(grep "FOUND:" /tmp/weekly_model_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-community uses 'model' as action input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "weekly-community does not use invalid 'model' action input"
    fi
}

# Test 58: weekly-community must NOT use 'allowed_tools' as action input (use claude_args)
test_weekly_no_allowed_tools_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'allowed_tools' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/weekly_allowed_tools_check.txt 2>&1

    if grep -q "FOUND:" /tmp/weekly_allowed_tools_check.txt; then
        STEP=$(grep "FOUND:" /tmp/weekly_allowed_tools_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-community uses 'allowed_tools' input in step '$STEP' — use claude_args --allowedTools instead"
    else
        pass "weekly-community does not use invalid 'allowed_tools' input"
    fi
}

# Test 59: weekly-community must NOT reference outputs.response
test_weekly_no_outputs_response() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    content = f.read()
if 'outputs.response' in content:
    print('FOUND')
" > /tmp/weekly_outputs_response_check.txt 2>&1

    if grep -q "FOUND" /tmp/weekly_outputs_response_check.txt; then
        fail "weekly-community references 'outputs.response' — claude-code-action@v1 has no response output"
    else
        pass "weekly-community does not reference non-existent 'outputs.response'"
    fi
}

# Test 60: weekly-community must extract scan result from execution output file
test_weekly_extracts_from_output_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        name = step.get('name', '').lower()
        if 'claude-execution-output.json' in run and ('scan' in name or 'extract' in name or 'save' in name):
            print('READS_OUTPUT_FILE')
" > /tmp/weekly_output_file_check.txt 2>&1

    if grep -q "READS_OUTPUT_FILE" /tmp/weekly_output_file_check.txt; then
        pass "weekly-community extracts scan result from execution output file"
    else
        fail "weekly-community does not read claude-execution-output.json for scan result"
    fi
}

test_weekly_no_prompt_file_input
test_weekly_no_direct_prompt_input
test_weekly_no_model_input
test_weekly_no_allowed_tools_input
test_weekly_no_outputs_response
test_weekly_extracts_from_output_file

# ============================================
# Monthly-Research Workflow Input Validation Tests
# ============================================
# Same class of bugs as daily-update and weekly-community.

# Test 61: monthly-research must NOT use 'prompt_file' (not a valid action input)
test_monthly_no_prompt_file_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'prompt_file' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/monthly_prompt_file_check.txt 2>&1

    if grep -q "FOUND:" /tmp/monthly_prompt_file_check.txt; then
        STEP=$(grep "FOUND:" /tmp/monthly_prompt_file_check.txt | head -1 | sed 's/FOUND://')
        fail "monthly-research uses 'prompt_file' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "monthly-research does not use invalid 'prompt_file' input"
    fi
}

# Test 62: monthly-research must NOT use 'direct_prompt' (not a valid action input)
test_monthly_no_direct_prompt_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'direct_prompt' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/monthly_direct_prompt_check.txt 2>&1

    if grep -q "FOUND:" /tmp/monthly_direct_prompt_check.txt; then
        STEP=$(grep "FOUND:" /tmp/monthly_direct_prompt_check.txt | head -1 | sed 's/FOUND://')
        fail "monthly-research uses 'direct_prompt' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "monthly-research does not use invalid 'direct_prompt' input"
    fi
}

# Test 63: monthly-research must NOT use 'model' as a top-level action input
test_monthly_no_model_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        uses = step.get('uses', '')
        with_block = step.get('with', {})
        if 'claude-code-action' in uses and 'model' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/monthly_model_check.txt 2>&1

    if grep -q "FOUND:" /tmp/monthly_model_check.txt; then
        STEP=$(grep "FOUND:" /tmp/monthly_model_check.txt | head -1 | sed 's/FOUND://')
        fail "monthly-research uses 'model' as action input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "monthly-research does not use invalid 'model' action input"
    fi
}

# Test 64: monthly-research must NOT use 'allowed_tools' as action input (use claude_args)
test_monthly_no_allowed_tools_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'allowed_tools' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/monthly_allowed_tools_check.txt 2>&1

    if grep -q "FOUND:" /tmp/monthly_allowed_tools_check.txt; then
        STEP=$(grep "FOUND:" /tmp/monthly_allowed_tools_check.txt | head -1 | sed 's/FOUND://')
        fail "monthly-research uses 'allowed_tools' input in step '$STEP' — use claude_args --allowedTools instead"
    else
        pass "monthly-research does not use invalid 'allowed_tools' input"
    fi
}

# Test 65: monthly-research must NOT reference outputs.response
test_monthly_no_outputs_response() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    content = f.read()
if 'outputs.response' in content:
    print('FOUND')
" > /tmp/monthly_outputs_response_check.txt 2>&1

    if grep -q "FOUND" /tmp/monthly_outputs_response_check.txt; then
        fail "monthly-research references 'outputs.response' — claude-code-action@v1 has no response output"
    else
        pass "monthly-research does not reference non-existent 'outputs.response'"
    fi
}

# Test 66: monthly-research must extract research result from execution output file
test_monthly_extracts_from_output_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        name = step.get('name', '').lower()
        if 'claude-execution-output.json' in run and ('research' in name or 'extract' in name or 'save' in name):
            print('READS_OUTPUT_FILE')
" > /tmp/monthly_output_file_check.txt 2>&1

    if grep -q "READS_OUTPUT_FILE" /tmp/monthly_output_file_check.txt; then
        pass "monthly-research extracts research result from execution output file"
    else
        fail "monthly-research does not read claude-execution-output.json for research result"
    fi
}

test_monthly_no_prompt_file_input
test_monthly_no_direct_prompt_input
test_monthly_no_model_input
test_monthly_no_allowed_tools_input
test_monthly_no_outputs_response
test_monthly_extracts_from_output_file

# ============================================
# Silent Workflow Failure Regression Tests
# ============================================
# These tests ensure previously-identified silent failures
# remain fixed after the post-audit cleanup.

# Test 67: ci.yml has no dead token extraction showing N/A
test_ci_no_dead_token_extraction() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # The execution output file from claude-code-action@v1 does NOT contain
    # .usage.input_tokens, .token_usage, .total_tokens, etc.
    # Any jq paths extracting these are dead code producing N/A values.
    if grep -q '\.usage\.input_tokens\|\.token_usage\|\.total_tokens' "$WORKFLOW"; then
        fail "ci.yml still has dead token extraction code (all values show N/A)"
    else
        pass "ci.yml has no dead token extraction code"
    fi
}

# Test 68: ci.yml has score history git commit step
test_ci_score_history_committed() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # score-history.jsonl must be committed back to the repo
    # so it persists across CI runs (ephemeral runners lose it otherwise)
    if grep -A 5 'score-history.jsonl' "$WORKFLOW" | grep -q 'git commit'; then
        pass "ci.yml commits score-history.jsonl back to repo"
    else
        fail "ci.yml does not commit score-history.jsonl (history lost on ephemeral runner)"
    fi
}

# Test 69: ci-autofix has no show_full_output input
test_ci_autofix_no_show_full_output() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix.yml not found"
        return
    fi

    if grep -q 'show_full_output' "$WORKFLOW"; then
        fail "ci-autofix.yml still has invalid 'show_full_output' input"
    else
        pass "ci-autofix.yml has no invalid 'show_full_output' input"
    fi
}

# Test 70: weekly-community e2e-test triggers on findings (not just actions)
test_weekly_e2e_triggers_on_findings() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-community.yml not found"
        return
    fi

    # has_suggestions should be based on findings_count (not actions_count)
    # because Claude may structure output without .recommended_actions key
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
jobs = wf.get('jobs', {})
scan_job = jobs.get('scan-community', {})
outputs = scan_job.get('outputs', {})
has_suggestions = str(outputs.get('has_suggestions', ''))
# Should reference findings_count, not actions_count
if 'findings_count' in has_suggestions:
    print('USES_FINDINGS')
elif 'actions_count' in has_suggestions:
    print('USES_ACTIONS')
else:
    print('UNKNOWN')
" > /tmp/weekly_trigger_check.txt 2>&1

    if grep -q "USES_FINDINGS" /tmp/weekly_trigger_check.txt; then
        pass "weekly-community e2e-test triggers on findings_count (robust)"
    else
        fail "weekly-community e2e-test triggers on actions_count (fragile — depends on exact JSON key name)"
    fi
}

# Test 71: monthly-research e2e-test triggers on notable research
test_monthly_e2e_triggers_on_notable() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    # has_updates should NOT depend solely on .recommended_wizard_updates
    # because Claude may structure output without that exact key
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
jobs = wf.get('jobs', {})
research_job = jobs.get('deep-research', {})
outputs = research_job.get('outputs', {})
has_updates = str(outputs.get('has_updates', ''))
# Should NOT reference updates_count alone (fragile)
# Should use nothing_notable or a broader condition
if 'nothing_notable' in has_updates:
    print('USES_NOTHING_NOTABLE')
elif 'updates_count' in has_updates:
    print('USES_UPDATES_COUNT')
else:
    print('UNKNOWN')
" > /tmp/monthly_trigger_check.txt 2>&1

    if grep -q "USES_NOTHING_NOTABLE" /tmp/monthly_trigger_check.txt; then
        pass "monthly-research e2e-test triggers on notable research (robust)"
    else
        fail "monthly-research e2e-test triggers on updates_count (fragile — depends on exact JSON key name)"
    fi
}

# Test 72: ci.yml score history push uses explicit branch ref (not bare git push)
test_ci_score_history_push_explicit_ref() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # On pull_request events, actions/checkout checks out refs/pull/N/merge (detached HEAD).
    # Bare `git push` on detached HEAD fails silently with continue-on-error.
    # Must use explicit ref: git push origin HEAD:refs/heads/<branch>
    if grep -A 10 'Commit score history' "$WORKFLOW" | grep -q 'git push origin HEAD:refs/heads/'; then
        pass "ci.yml score history push uses explicit branch ref (detached HEAD safe)"
    else
        fail "ci.yml score history push uses bare 'git push' (fails silently on detached HEAD)"
    fi
}

# Test 73: ci-autofix.yml has workflows: write permission (needed to push workflow file changes)
test_ci_autofix_has_workflows_write() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-autofix.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci-autofix workflow file not found"
        return
    fi

    # Without workflows: write, autofix can't push fixes to .github/workflows/ files.
    # Git rejects with: "refusing to allow a GitHub App to create or update workflow without workflows permission"
    if grep -q 'workflows: write' "$WORKFLOW"; then
        pass "ci-autofix.yml has workflows: write permission (can push workflow file fixes)"
    else
        fail "ci-autofix.yml missing workflows: write permission (can't push workflow file fixes)"
    fi
}

# Test 74: ci.yml initializes git in workspace root before claude-code-action
test_ci_workspace_git_init() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # actions/checkout with path: creates subdirectories, leaving workspace root as non-git.
    # claude-code-action@v1 configureGitAuth runs git config in workspace root and crashes.
    # Fix: git init in workspace root before the first simulation step.
    if grep -q 'git init' "$WORKFLOW"; then
        pass "ci.yml initializes git in workspace root (prevents configureGitAuth crash)"
    else
        fail "ci.yml missing git init for workspace root (configureGitAuth will crash)"
    fi
}

# Test 75: ci.yml max-turns is sufficient for hard scenarios (>= 50)
test_ci_max_turns_sufficient() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # Hard scenarios (refactor) need more than 45 turns.
    # error_max_turns causes action failure even with is_error: false.
    MAX_TURNS=$(grep 'max-turns' "$WORKFLOW" | head -1 | sed 's/.*max-turns //' | sed 's/[^0-9].*//')
    if [ -z "$MAX_TURNS" ]; then
        fail "Could not find max-turns in ci.yml"
        return
    fi

    if [ "$MAX_TURNS" -ge 50 ]; then
        pass "ci.yml max-turns ($MAX_TURNS) is sufficient for hard scenarios"
    else
        fail "ci.yml max-turns ($MAX_TURNS) is too low for hard scenarios (need >= 50)"
    fi
}

# Test 76: Tier 1 regression threshold must be >= 1.5 (absorbs ±1 LLM noise)
test_tier1_regression_threshold() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # Tier 1 uses single-trial comparison. LLM judge + simulation has ±1 point
    # stochastic variance. A threshold < 1.5 causes false REGRESSION failures.
    # Extract the threshold from the "Compare scores" step's bc comparison.
    # Pattern: DELTA < -X.X where X.X is the threshold
    THRESHOLD=$(grep -oE 'DELTA < -[0-9]+\.?[0-9]*' "$WORKFLOW" | head -1 | grep -oE '[0-9]+\.?[0-9]*')

    if [ -z "$THRESHOLD" ]; then
        fail "Could not find Tier 1 regression threshold in ci.yml"
        return
    fi

    # Compare using bc: threshold must be >= 1.5
    if [ "$(echo "$THRESHOLD >= 1.5" | bc -l)" -eq 1 ]; then
        pass "Tier 1 regression threshold is $THRESHOLD (absorbs LLM noise)"
    else
        fail "Tier 1 regression threshold is $THRESHOLD (too tight — causes false regressions from ±1 LLM noise, need >= 1.5)"
    fi
}

# ============================================
# Monthly-Research Permission Tests
# ============================================
# Ensure monthly-research has the permissions its
# e2e-test job needs (creates PRs via peter-evans/create-pull-request).

# Test 77: monthly-research has pull-requests: write permission
test_monthly_has_pr_write_permission() {
    WORKFLOW="$REPO_ROOT/.github/workflows/monthly-research.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "monthly-research.yml not found"
        return
    fi

    if grep -q 'pull-requests: write' "$WORKFLOW"; then
        pass "monthly-research has pull-requests: write permission"
    else
        fail "monthly-research missing pull-requests: write permission (e2e-test creates PRs)"
    fi
}

test_monthly_has_pr_write_permission
test_tier1_regression_threshold
test_ci_no_dead_token_extraction
test_ci_score_history_committed
test_ci_autofix_no_show_full_output
test_weekly_e2e_triggers_on_findings
test_monthly_e2e_triggers_on_notable
test_ci_score_history_push_explicit_ref
test_ci_autofix_has_workflows_write
test_ci_workspace_git_init
test_ci_max_turns_sufficient

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All workflow trigger tests passed!"
