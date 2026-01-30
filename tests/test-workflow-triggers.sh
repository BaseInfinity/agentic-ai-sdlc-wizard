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

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All workflow trigger tests passed!"
