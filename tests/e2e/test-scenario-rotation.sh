#!/bin/bash
# Test scenario rotation logic for multi-scenario CI
#
# Tests the round-robin selection that picks different scenarios
# for different PR numbers while remaining deterministic.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/scenario-selector.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Scenario Rotation Tests ==="
echo ""

SCENARIOS_DIR="$SCRIPT_DIR/scenarios"

# Test 1: Returns a valid scenario file
test_returns_valid_file() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 1)
    if [ -f "$result" ]; then
        pass "PR #1: returns valid file ($result)"
    else
        fail "PR #1: file not found: $result"
    fi
}

# Test 2: Same PR number always returns same scenario (deterministic)
test_deterministic() {
    local result1 result2
    result1=$(select_scenario "$SCENARIOS_DIR" 42)
    result2=$(select_scenario "$SCENARIOS_DIR" 42)
    if [ "$result1" = "$result2" ]; then
        pass "Deterministic: PR #42 returns same scenario twice"
    else
        fail "Not deterministic: got '$result1' then '$result2'"
    fi
}

# Test 3: Different PR numbers can return different scenarios
test_different_prs() {
    local results=()
    local unique_count
    for i in 1 2 3 4 5 6 7 8 9 10 11; do
        results+=("$(select_scenario "$SCENARIOS_DIR" "$i")")
    done
    unique_count=$(printf '%s\n' "${results[@]}" | sort -u | wc -l | tr -d ' ')
    if [ "$unique_count" -gt 1 ]; then
        pass "Different PRs get different scenarios ($unique_count unique out of 11)"
    else
        fail "All 11 PRs got the same scenario"
    fi
}

# Test 4: All returned files end in .md
test_md_extension() {
    local all_md=true
    for i in 1 2 3 4 5; do
        local result
        result=$(select_scenario "$SCENARIOS_DIR" "$i")
        if [[ "$result" != *.md ]]; then
            all_md=false
            break
        fi
    done
    if [ "$all_md" = "true" ]; then
        pass "All selected scenarios are .md files"
    else
        fail "Non-.md file returned"
    fi
}

# Test 5: PR number 0 works (edge case)
test_pr_zero() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 0)
    if [ -f "$result" ]; then
        pass "PR #0: returns valid file"
    else
        fail "PR #0: file not found: $result"
    fi
}

# Test 6: Large PR number works
test_large_pr() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" 99999)
    if [ -f "$result" ]; then
        pass "PR #99999: returns valid file"
    else
        fail "PR #99999: file not found: $result"
    fi
}

# Test 7: list_scenarios returns all scenario files
test_list_scenarios() {
    local count
    count=$(list_scenarios "$SCENARIOS_DIR" | wc -l | tr -d ' ')
    local actual_count
    actual_count=$(ls "$SCENARIOS_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" = "$actual_count" ] && [ "$count" -gt 0 ]; then
        pass "list_scenarios returns all $count scenarios"
    else
        fail "list_scenarios returned $count, expected $actual_count"
    fi
}

# Test 8: Handles push events (no PR number) with fallback
test_push_fallback() {
    local result
    result=$(select_scenario "$SCENARIOS_DIR" "")
    if [ -f "$result" ]; then
        pass "Empty PR number: falls back to valid file"
    else
        fail "Empty PR number: file not found: $result"
    fi
}

# Run all tests
test_returns_valid_file
test_deterministic
test_different_prs
test_md_extension
test_pr_zero
test_large_pr
test_list_scenarios
test_push_fallback

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All scenario rotation tests passed!"
