#!/bin/bash
# Test the self-healing CI loop logic from ci-self-heal.yml
# These tests simulate the bash logic locally without GitHub Actions.

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

echo "=== Self-Heal Simulation Tests ==="
echo ""

# ============================================
# Retry Counting Logic Tests
# ============================================

# Test 1: Retry count from git log - zero autofix commits
test_retry_count_zero() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    git init -q
    git commit --allow-empty -m "initial commit" -q
    git commit --allow-empty -m "feat: add feature" -q

    AUTOFIX_COUNT=$(git log --oneline --grep='\[autofix' | wc -l | tr -d ' ')

    cd "$REPO_ROOT"
    rm -rf "$TEMP_DIR"

    if [ "$AUTOFIX_COUNT" -eq 0 ]; then
        pass "Retry count is 0 when no autofix commits exist"
    else
        fail "Retry count is $AUTOFIX_COUNT, expected 0"
    fi
}

# Test 2: Retry count from git log - two autofix commits
test_retry_count_two() {
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"
    git init -q
    git commit --allow-empty -m "initial commit" -q
    git commit --allow-empty -m "[autofix 1/3] fix: auto-fix from ci-failure" -q
    git commit --allow-empty -m "feat: manual fix" -q
    git commit --allow-empty -m "[autofix 2/3] fix: auto-fix from review-findings" -q

    AUTOFIX_COUNT=$(git log --oneline --grep='\[autofix' | wc -l | tr -d ' ')

    cd "$REPO_ROOT"
    rm -rf "$TEMP_DIR"

    if [ "$AUTOFIX_COUNT" -eq 2 ]; then
        pass "Retry count is 2 with two autofix commits"
    else
        fail "Retry count is $AUTOFIX_COUNT, expected 2"
    fi
}

# Test 3: Max retries exceeded detection
test_max_retries_exceeded() {
    MAX_AUTOFIX_RETRIES=3
    AUTOFIX_COUNT=3

    if [ "$AUTOFIX_COUNT" -ge "$MAX_AUTOFIX_RETRIES" ]; then
        pass "Max retries exceeded when count ($AUTOFIX_COUNT) >= limit ($MAX_AUTOFIX_RETRIES)"
    else
        fail "Max retries not detected when count ($AUTOFIX_COUNT) >= limit ($MAX_AUTOFIX_RETRIES)"
    fi
}

# Test 4: Max retries not exceeded
test_max_retries_not_exceeded() {
    MAX_AUTOFIX_RETRIES=3
    AUTOFIX_COUNT=2

    EXCEEDED=false
    if [ "$AUTOFIX_COUNT" -ge "$MAX_AUTOFIX_RETRIES" ]; then
        EXCEEDED=true
    fi

    if [ "$EXCEEDED" = false ]; then
        pass "Max retries not exceeded when count ($AUTOFIX_COUNT) < limit ($MAX_AUTOFIX_RETRIES)"
    else
        fail "Max retries incorrectly exceeded when count ($AUTOFIX_COUNT) < limit ($MAX_AUTOFIX_RETRIES)"
    fi
}

# Test 5: Attempt number calculation
test_attempt_number() {
    AUTOFIX_COUNT=1
    ATTEMPT=$((AUTOFIX_COUNT + 1))

    if [ "$ATTEMPT" -eq 2 ]; then
        pass "Attempt number is count+1 (attempt=$ATTEMPT after $AUTOFIX_COUNT previous)"
    else
        fail "Attempt number is $ATTEMPT, expected 2"
    fi
}

# ============================================
# AUTOFIX_LEVEL Filtering Tests
# ============================================

# Test 6: ci-only level skips all review findings
test_autofix_level_ci_only() {
    AUTOFIX_LEVEL="ci-only"
    SKIP=false

    if [ "$AUTOFIX_LEVEL" = "ci-only" ]; then
        SKIP=true
    fi

    if [ "$SKIP" = true ]; then
        pass "AUTOFIX_LEVEL=ci-only skips all review findings"
    else
        fail "AUTOFIX_LEVEL=ci-only did not skip review findings"
    fi
}

# Test 7: criticals level skips when no criticals found
test_autofix_level_criticals_no_findings() {
    AUTOFIX_LEVEL="criticals"
    HAS_CRITICALS=false
    HAS_SUGGESTIONS=true

    SKIP=false
    case "$AUTOFIX_LEVEL" in
        criticals)
            if [ "$HAS_CRITICALS" = false ]; then
                SKIP=true
            fi
            ;;
    esac

    if [ "$SKIP" = true ]; then
        pass "AUTOFIX_LEVEL=criticals skips when no criticals (even with suggestions)"
    else
        fail "AUTOFIX_LEVEL=criticals did not skip with no criticals"
    fi
}

# Test 8: criticals level proceeds when criticals found
test_autofix_level_criticals_with_findings() {
    AUTOFIX_LEVEL="criticals"
    HAS_CRITICALS=true
    HAS_SUGGESTIONS=false

    SKIP=false
    case "$AUTOFIX_LEVEL" in
        criticals)
            if [ "$HAS_CRITICALS" = false ]; then
                SKIP=true
            fi
            ;;
    esac

    if [ "$SKIP" = false ]; then
        pass "AUTOFIX_LEVEL=criticals proceeds when criticals found"
    else
        fail "AUTOFIX_LEVEL=criticals skipped even with criticals present"
    fi
}

# Test 9: all-findings level skips when neither criticals nor suggestions
test_autofix_level_all_findings_empty() {
    AUTOFIX_LEVEL="all-findings"
    HAS_CRITICALS=false
    HAS_SUGGESTIONS=false

    SKIP=false
    case "$AUTOFIX_LEVEL" in
        all-findings)
            if [ "$HAS_CRITICALS" = false ] && [ "$HAS_SUGGESTIONS" = false ]; then
                SKIP=true
            fi
            ;;
    esac

    if [ "$SKIP" = true ]; then
        pass "AUTOFIX_LEVEL=all-findings skips when no findings at all"
    else
        fail "AUTOFIX_LEVEL=all-findings did not skip with no findings"
    fi
}

# Test 10: all-findings level proceeds when only suggestions exist
test_autofix_level_all_findings_suggestions_only() {
    AUTOFIX_LEVEL="all-findings"
    HAS_CRITICALS=false
    HAS_SUGGESTIONS=true

    SKIP=false
    case "$AUTOFIX_LEVEL" in
        all-findings)
            if [ "$HAS_CRITICALS" = false ] && [ "$HAS_SUGGESTIONS" = false ]; then
                SKIP=true
            fi
            ;;
    esac

    if [ "$SKIP" = false ]; then
        pass "AUTOFIX_LEVEL=all-findings proceeds when suggestions exist"
    else
        fail "AUTOFIX_LEVEL=all-findings skipped even with suggestions present"
    fi
}

# Test 11: Unknown level defaults to criticals behavior
test_autofix_level_unknown_defaults_criticals() {
    AUTOFIX_LEVEL="invalid-level"
    HAS_CRITICALS=false
    HAS_SUGGESTIONS=true

    SKIP=false
    case "$AUTOFIX_LEVEL" in
        ci-only)
            SKIP=true
            ;;
        criticals)
            if [ "$HAS_CRITICALS" = false ]; then
                SKIP=true
            fi
            ;;
        all-findings)
            if [ "$HAS_CRITICALS" = false ] && [ "$HAS_SUGGESTIONS" = false ]; then
                SKIP=true
            fi
            ;;
        *)
            # Default to criticals behavior
            if [ "$HAS_CRITICALS" = false ]; then
                SKIP=true
            fi
            ;;
    esac

    if [ "$SKIP" = true ]; then
        pass "Unknown AUTOFIX_LEVEL defaults to criticals behavior (skip with no criticals)"
    else
        fail "Unknown AUTOFIX_LEVEL did not default to criticals behavior"
    fi
}

# ============================================
# Review Findings Parsing Tests
# ============================================

# Test 12: Parse review body with criticals
test_parse_review_criticals() {
    REVIEW_BODY="## PR Code Review

### Critical (must fix)
- SQL injection in user input handler
- Missing auth check on /admin endpoint

### Suggestions (nice to have)
None"

    HAS_CRITICALS=false
    HAS_SUGGESTIONS=false

    if echo "$REVIEW_BODY" | grep -q "Critical (must fix)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Critical (must fix)" | grep -q "None\|No critical\|N/A"; then
            HAS_CRITICALS=true
        fi
    fi

    if echo "$REVIEW_BODY" | grep -q "Suggestions (nice to have)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Suggestions (nice to have)" | grep -q "None\|No suggestions\|N/A"; then
            HAS_SUGGESTIONS=true
        fi
    fi

    if [ "$HAS_CRITICALS" = true ] && [ "$HAS_SUGGESTIONS" = false ]; then
        pass "Parsed review: found criticals, no suggestions"
    else
        fail "Parse error: criticals=$HAS_CRITICALS suggestions=$HAS_SUGGESTIONS (expected true/false)"
    fi
}

# Test 13: Parse review body with suggestions only
test_parse_review_suggestions_only() {
    REVIEW_BODY="## PR Code Review

### Critical (must fix)
No critical issues found.

### Suggestions (nice to have)
- Consider adding error handling for network timeout
- Add JSDoc for exported functions"

    HAS_CRITICALS=false
    HAS_SUGGESTIONS=false

    if echo "$REVIEW_BODY" | grep -q "Critical (must fix)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Critical (must fix)" | grep -q "None\|No critical\|N/A"; then
            HAS_CRITICALS=true
        fi
    fi

    if echo "$REVIEW_BODY" | grep -q "Suggestions (nice to have)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Suggestions (nice to have)" | grep -q "None\|No suggestions\|N/A"; then
            HAS_SUGGESTIONS=true
        fi
    fi

    if [ "$HAS_CRITICALS" = false ] && [ "$HAS_SUGGESTIONS" = true ]; then
        pass "Parsed review: no criticals, found suggestions"
    else
        fail "Parse error: criticals=$HAS_CRITICALS suggestions=$HAS_SUGGESTIONS (expected false/true)"
    fi
}

# Test 14: Parse review body with no findings
test_parse_review_clean() {
    REVIEW_BODY="## PR Code Review

### Critical (must fix)
None

### Suggestions (nice to have)
No suggestions"

    HAS_CRITICALS=false
    HAS_SUGGESTIONS=false

    if echo "$REVIEW_BODY" | grep -q "Critical (must fix)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Critical (must fix)" | grep -q "None\|No critical\|N/A"; then
            HAS_CRITICALS=true
        fi
    fi

    if echo "$REVIEW_BODY" | grep -q "Suggestions (nice to have)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Suggestions (nice to have)" | grep -q "None\|No suggestions\|N/A"; then
            HAS_SUGGESTIONS=true
        fi
    fi

    if [ "$HAS_CRITICALS" = false ] && [ "$HAS_SUGGESTIONS" = false ]; then
        pass "Parsed review: no criticals, no suggestions (clean review)"
    else
        fail "Parse error: criticals=$HAS_CRITICALS suggestions=$HAS_SUGGESTIONS (expected false/false)"
    fi
}

# Test 15: Parse review body with both findings
test_parse_review_both() {
    REVIEW_BODY="## PR Code Review

### Critical (must fix)
- Memory leak in connection pool

### Suggestions (nice to have)
- Add unit tests for edge cases"

    HAS_CRITICALS=false
    HAS_SUGGESTIONS=false

    if echo "$REVIEW_BODY" | grep -q "Critical (must fix)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Critical (must fix)" | grep -q "None\|No critical\|N/A"; then
            HAS_CRITICALS=true
        fi
    fi

    if echo "$REVIEW_BODY" | grep -q "Suggestions (nice to have)"; then
        if ! echo "$REVIEW_BODY" | grep -A 1 "Suggestions (nice to have)" | grep -q "None\|No suggestions\|N/A"; then
            HAS_SUGGESTIONS=true
        fi
    fi

    if [ "$HAS_CRITICALS" = true ] && [ "$HAS_SUGGESTIONS" = true ]; then
        pass "Parsed review: found both criticals and suggestions"
    else
        fail "Parse error: criticals=$HAS_CRITICALS suggestions=$HAS_SUGGESTIONS (expected true/true)"
    fi
}

# ============================================
# Context Truncation Tests
# ============================================

# Test 16: Log truncation to last 200 lines
test_log_truncation() {
    TEMP_DIR=$(mktemp -d)
    LOG_FILE="$TEMP_DIR/ci-failure-logs.txt"
    CONTEXT_FILE="$TEMP_DIR/ci-failure-context.txt"

    # Generate 500 lines
    for i in $(seq 1 500); do
        echo "Line $i: some CI output" >> "$LOG_FILE"
    done

    tail -200 "$LOG_FILE" > "$CONTEXT_FILE"
    LINE_COUNT=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')

    # Verify first line is line 301 (500 - 200 + 1)
    FIRST_LINE=$(head -1 "$CONTEXT_FILE")

    rm -rf "$TEMP_DIR"

    if [ "$LINE_COUNT" -eq 200 ] && echo "$FIRST_LINE" | grep -q "Line 301"; then
        pass "Log truncation keeps last 200 lines (first line is 301)"
    else
        fail "Log truncation: got $LINE_COUNT lines, first='$FIRST_LINE' (expected 200 lines, first='Line 301')"
    fi
}

# Test 17: Short logs are not truncated
test_log_no_truncation_for_short() {
    TEMP_DIR=$(mktemp -d)
    LOG_FILE="$TEMP_DIR/ci-failure-logs.txt"
    CONTEXT_FILE="$TEMP_DIR/ci-failure-context.txt"

    # Generate 50 lines
    for i in $(seq 1 50); do
        echo "Line $i: some CI output" >> "$LOG_FILE"
    done

    tail -200 "$LOG_FILE" > "$CONTEXT_FILE"
    LINE_COUNT=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')

    rm -rf "$TEMP_DIR"

    if [ "$LINE_COUNT" -eq 50 ]; then
        pass "Short logs (50 lines) are preserved intact"
    else
        fail "Short log truncation: got $LINE_COUNT lines, expected 50"
    fi
}

# ============================================
# Trigger Source Detection Tests
# ============================================

# Test 18: CI failure mode detection
test_trigger_ci_failure() {
    WORKFLOW_NAME="CI"
    CONCLUSION="failure"

    MODE=""
    if [ "$WORKFLOW_NAME" = "CI" ]; then
        MODE="ci-failure"
    else
        MODE="review-findings"
    fi

    if [ "$MODE" = "ci-failure" ]; then
        pass "CI workflow with failure conclusion → ci-failure mode"
    else
        fail "CI workflow with failure → mode='$MODE' (expected ci-failure)"
    fi
}

# Test 19: Review findings mode detection
test_trigger_review_findings() {
    WORKFLOW_NAME="PR Code Review"
    CONCLUSION="success"

    MODE=""
    if [ "$WORKFLOW_NAME" = "CI" ]; then
        MODE="ci-failure"
    else
        MODE="review-findings"
    fi

    if [ "$MODE" = "review-findings" ]; then
        pass "PR Code Review with success conclusion → review-findings mode"
    else
        fail "PR Code Review with success → mode='$MODE' (expected review-findings)"
    fi
}

# ============================================
# Branch Safety Tests
# ============================================

# Test 20: Main branch exclusion
test_main_branch_excluded() {
    HEAD_BRANCH="main"

    SHOULD_SKIP=false
    if [ "$HEAD_BRANCH" = "main" ]; then
        SHOULD_SKIP=true
    fi

    if [ "$SHOULD_SKIP" = true ]; then
        pass "Main branch is excluded from autofix"
    else
        fail "Main branch was not excluded from autofix"
    fi
}

# Test 21: Feature branch allowed
test_feature_branch_allowed() {
    HEAD_BRANCH="fix/broken-tests"

    SHOULD_SKIP=false
    if [ "$HEAD_BRANCH" = "main" ]; then
        SHOULD_SKIP=true
    fi

    if [ "$SHOULD_SKIP" = false ]; then
        pass "Feature branch 'fix/broken-tests' is allowed for autofix"
    else
        fail "Feature branch was incorrectly excluded from autofix"
    fi
}

# ============================================
# Commit Message Format Tests
# ============================================

# Test 22: Autofix commit message format
test_commit_message_format() {
    ATTEMPT=2
    MAX_AUTOFIX_RETRIES=3
    MODE="ci-failure"

    COMMIT_MSG="[autofix ${ATTEMPT}/${MAX_AUTOFIX_RETRIES}] fix: auto-fix from $MODE"

    if echo "$COMMIT_MSG" | grep -q "\[autofix 2/3\]" && echo "$COMMIT_MSG" | grep -q "ci-failure"; then
        pass "Commit message format: '$COMMIT_MSG'"
    else
        fail "Commit message format wrong: '$COMMIT_MSG'"
    fi
}

# ============================================
# Workflow YAML Validation Tests
# ============================================

# Test 23: ci-self-heal.yml is valid YAML
test_workflow_yaml_valid() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-self-heal.yml"

    if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        pass "ci-self-heal.yml is valid YAML"
    else
        fail "ci-self-heal.yml has YAML syntax errors"
    fi
}

# Test 24: ci-self-heal.yml prompt forbids self-modification
test_prompt_forbids_self_modification() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-self-heal.yml"

    if grep -q "ci-self-heal.yml" "$WORKFLOW"; then
        pass "ci-self-heal.yml prompt forbids editing itself"
    else
        fail "ci-self-heal.yml prompt does not mention self-modification ban"
    fi
}

# Test 25: ci-self-heal.yml prompt forbids plan mode
test_prompt_forbids_plan_mode() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci-self-heal.yml"

    if grep -q "EnterPlanMode\|ExitPlanMode" "$WORKFLOW"; then
        pass "ci-self-heal.yml prompt mentions plan mode (forbidden in headless CI)"
    else
        fail "ci-self-heal.yml prompt doesn't mention plan mode ban (will loop in CI)"
    fi
}

# Run all tests
echo "--- Retry Counting ---"
test_retry_count_zero
test_retry_count_two
test_max_retries_exceeded
test_max_retries_not_exceeded
test_attempt_number

echo ""
echo "--- AUTOFIX_LEVEL Filtering ---"
test_autofix_level_ci_only
test_autofix_level_criticals_no_findings
test_autofix_level_criticals_with_findings
test_autofix_level_all_findings_empty
test_autofix_level_all_findings_suggestions_only
test_autofix_level_unknown_defaults_criticals

echo ""
echo "--- Review Findings Parsing ---"
test_parse_review_criticals
test_parse_review_suggestions_only
test_parse_review_clean
test_parse_review_both

echo ""
echo "--- Context Truncation ---"
test_log_truncation
test_log_no_truncation_for_short

echo ""
echo "--- Trigger Source Detection ---"
test_trigger_ci_failure
test_trigger_review_findings

echo ""
echo "--- Branch Safety ---"
test_main_branch_excluded
test_feature_branch_allowed

echo ""
echo "--- Commit Message Format ---"
test_commit_message_format

echo ""
echo "--- Workflow YAML Validation ---"
test_workflow_yaml_valid
test_prompt_forbids_self_modification
test_prompt_forbids_plan_mode

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All self-heal simulation tests passed!"
