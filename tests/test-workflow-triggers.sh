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

# Test 4: Daily workflow has schedule trigger
test_daily_schedule() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if grep -q "schedule:" "$WORKFLOW" && grep -q "cron:" "$WORKFLOW"; then
        pass "Daily workflow has schedule trigger with cron"
    else
        fail "Daily workflow missing schedule/cron trigger"
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
test_daily_schedule
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

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All workflow trigger tests passed!"
