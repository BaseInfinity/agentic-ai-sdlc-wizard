#!/bin/bash
# Test statistical functions (stats.sh)
# Tests: n=1 handling, identical scores, df>4, mean/CI correctness, compare_ci edges

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATS_LIB="$SCRIPT_DIR/e2e/lib/stats.sh"
PASSED=0
FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Stats Library Tests ==="
echo ""

# Source the stats library
source "$STATS_LIB"

# Test 1: n=1 returns value with "no CI" message
test_n1_handling() {
    local result
    result=$(calculate_confidence_interval "7.0")
    if echo "$result" | grep -q "n=1"; then
        pass "n=1 scores show 'no CI' message: $result"
    else
        fail "n=1 should indicate no CI, got: $result"
    fi
}

# Test 2: n=1 get_mean returns the single value
test_n1_mean() {
    local result
    result=$(get_mean "5.5")
    if [ "$result" = "5.5" ]; then
        pass "n=1 mean returns single value: $result"
    else
        fail "n=1 mean should be 5.5, got: $result"
    fi
}

# Test 3: n=1 get_ci_lower returns the single value
test_n1_ci_lower() {
    local result
    result=$(get_ci_lower "6.0")
    if [ "$result" = "6.0" ]; then
        pass "n=1 CI lower returns single value: $result"
    else
        fail "n=1 CI lower should be 6.0, got: $result"
    fi
}

# Test 4: n=1 get_ci_upper returns the single value
test_n1_ci_upper() {
    local result
    result=$(get_ci_upper "6.0")
    if [ "$result" = "6.0" ]; then
        pass "n=1 CI upper returns single value: $result"
    else
        fail "n=1 CI upper should be 6.0, got: $result"
    fi
}

# Test 5: Identical scores produce zero-width CI
test_identical_scores() {
    local result
    result=$(calculate_confidence_interval "5.0 5.0 5.0 5.0 5.0")
    local lower upper
    lower=$(get_ci_lower "5.0 5.0 5.0 5.0 5.0")
    upper=$(get_ci_upper "5.0 5.0 5.0 5.0 5.0")

    if [ "$lower" = "5.0" ] && [ "$upper" = "5.0" ]; then
        pass "Identical scores produce zero-width CI: [$lower, $upper]"
    else
        fail "Identical scores should have CI [5.0, 5.0], got: [$lower, $upper]"
    fi
}

# Test 6: Mean calculation with known values
test_mean_correctness() {
    local result
    result=$(get_mean "2.0 4.0 6.0 8.0 10.0")
    if [ "$result" = "6.0" ]; then
        pass "Mean of 2,4,6,8,10 = 6.0: $result"
    else
        fail "Mean should be 6.0, got: $result"
    fi
}

# Test 7: CI lower < mean < CI upper (basic sanity)
test_ci_ordering() {
    local scores="5.0 6.0 7.0 8.0 9.0"
    local mean lower upper
    mean=$(get_mean "$scores")
    lower=$(get_ci_lower "$scores")
    upper=$(get_ci_upper "$scores")

    local ok
    ok=$(echo "$lower <= $mean && $mean <= $upper" | bc -l 2>/dev/null || echo "0")
    if [ "$ok" = "1" ]; then
        pass "CI ordering: $lower <= $mean <= $upper"
    else
        fail "CI should satisfy lower <= mean <= upper, got: $lower, $mean, $upper"
    fi
}

# Test 8: df>4 uses t=2.571 approximation (6 data points, df=5)
test_df_greater_than_4() {
    local scores="5.0 6.0 7.0 8.0 9.0 10.0"
    local result
    result=$(calculate_confidence_interval "$scores")
    if echo "$result" | grep -q "95% CI"; then
        pass "df>4 (6 scores) produces valid CI: $result"
    else
        fail "df>4 should produce CI output, got: $result"
    fi
}

# Test 9: n=2 uses t=12.706 (very wide CI)
test_n2_wide_ci() {
    local scores="5.0 7.0"
    local lower upper
    lower=$(get_ci_lower "$scores")
    upper=$(get_ci_upper "$scores")

    # With t=12.706, CI should be very wide for n=2
    local width
    width=$(echo "$upper - $lower" | bc -l)
    local is_wide
    is_wide=$(echo "$width > 5" | bc -l 2>/dev/null || echo "0")
    if [ "$is_wide" = "1" ]; then
        pass "n=2 produces wide CI (width=$width): [$lower, $upper]"
    else
        fail "n=2 should produce very wide CI, width=$width: [$lower, $upper]"
    fi
}

# Test 10: compare_ci returns IMPROVED when candidate clearly better
test_compare_ci_improved() {
    local result
    result=$(compare_ci "3.0 3.0 3.0 3.0 3.0" "9.0 9.0 9.0 9.0 9.0")
    if [ "$result" = "IMPROVED" ]; then
        pass "compare_ci detects clear improvement: $result"
    else
        fail "Should be IMPROVED, got: $result"
    fi
}

# Test 11: compare_ci returns REGRESSION when candidate clearly worse
test_compare_ci_regression() {
    local result
    result=$(compare_ci "9.0 9.0 9.0 9.0 9.0" "3.0 3.0 3.0 3.0 3.0")
    if [ "$result" = "REGRESSION" ]; then
        pass "compare_ci detects clear regression: $result"
    else
        fail "Should be REGRESSION, got: $result"
    fi
}

# Test 12: compare_ci returns STABLE when scores overlap
test_compare_ci_stable() {
    local result
    result=$(compare_ci "5.0 6.0 7.0 5.5 6.5" "5.5 6.5 7.5 6.0 7.0")
    if [ "$result" = "STABLE" ]; then
        pass "compare_ci detects overlapping CIs as STABLE: $result"
    else
        fail "Should be STABLE for overlapping scores, got: $result"
    fi
}

# Test 13: compare_ci with identical scores returns STABLE
test_compare_ci_identical() {
    local result
    result=$(compare_ci "5.0 5.0 5.0 5.0 5.0" "5.0 5.0 5.0 5.0 5.0")
    if [ "$result" = "STABLE" ]; then
        pass "compare_ci with identical scores = STABLE: $result"
    else
        fail "Identical scores should be STABLE, got: $result"
    fi
}

# Test 14: CI width decreases with more consistent scores
test_ci_width_consistency() {
    local wide_lower wide_upper narrow_lower narrow_upper
    # High variance
    wide_lower=$(get_ci_lower "1.0 3.0 5.0 7.0 9.0")
    wide_upper=$(get_ci_upper "1.0 3.0 5.0 7.0 9.0")
    # Low variance
    narrow_lower=$(get_ci_lower "4.8 5.0 5.2 4.9 5.1")
    narrow_upper=$(get_ci_upper "4.8 5.0 5.2 4.9 5.1")

    local wide_width narrow_width
    wide_width=$(echo "$wide_upper - $wide_lower" | bc -l)
    narrow_width=$(echo "$narrow_upper - $narrow_lower" | bc -l)

    local correct
    correct=$(echo "$wide_width > $narrow_width" | bc -l 2>/dev/null || echo "0")
    if [ "$correct" = "1" ]; then
        pass "Higher variance = wider CI ($wide_width > $narrow_width)"
    else
        fail "High variance CI ($wide_width) should be wider than low variance ($narrow_width)"
    fi
}

# Run all tests
test_n1_handling
test_n1_mean
test_n1_ci_lower
test_n1_ci_upper
test_identical_scores
test_mean_correctness
test_ci_ordering
test_df_greater_than_4
test_n2_wide_ci
test_compare_ci_improved
test_compare_ci_regression
test_compare_ci_stable
test_compare_ci_identical
test_ci_width_consistency

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All stats tests passed!"
