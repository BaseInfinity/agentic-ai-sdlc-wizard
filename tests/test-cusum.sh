#!/bin/bash
# Test CUSUM drift detection logic
# TDD: Tests written first before implementation verification

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSUM_SCRIPT="$SCRIPT_DIR/e2e/cusum.sh"
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

echo "=== CUSUM Drift Detection Tests ==="
echo ""

# Test 1: Script exists and is executable
test_script_exists() {
    if [ -x "$CUSUM_SCRIPT" ]; then
        pass "cusum.sh exists and is executable"
    else
        fail "cusum.sh not found or not executable at $CUSUM_SCRIPT"
    fi
}

# Test 2: Help option works
test_help() {
    if "$CUSUM_SCRIPT" --help 2>/dev/null | grep -q "Usage"; then
        pass "--help shows usage"
    else
        fail "--help should show usage"
    fi
}

# Test 3: Reset works
test_reset() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    # After reset, history should be empty
    local history_file="$SCRIPT_DIR/e2e/score-history.txt"
    if [ ! -s "$history_file" ]; then
        pass "--reset clears history"
    else
        fail "--reset should clear history"
    fi
}

# Test 4: Add score works
test_add_score() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add 7.5 >/dev/null 2>&1

    local history_file="$SCRIPT_DIR/e2e/score-history.txt"
    if grep -q "7.5" "$history_file"; then
        pass "--add stores score in history"
    else
        fail "--add should store score in history"
    fi
}

# Test 5: CUSUM calculation with single score
test_cusum_single() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add 7.0 >/dev/null 2>&1  # Exactly at target

    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null)
    if echo "$output" | grep -q "CUSUM=0.00"; then
        pass "CUSUM=0 when score equals target"
    else
        fail "CUSUM should be 0 when score equals target, got: $output"
    fi
}

# Test 6: CUSUM goes negative with below-target scores
test_cusum_negative() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add 6.0 >/dev/null 2>&1  # 1 below target
    "$CUSUM_SCRIPT" --add 6.0 >/dev/null 2>&1  # 1 below target again

    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null)
    # CUSUM should be -2.0 (two scores 1.0 below target)
    if echo "$output" | grep -q "CUSUM=-2.00"; then
        pass "CUSUM negative when scores below target"
    else
        fail "CUSUM should be -2.00, got: $output"
    fi
}

# Test 7: CUSUM alert when crossing threshold
test_cusum_alert() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    # Add scores that will push CUSUM past -3.0 threshold
    "$CUSUM_SCRIPT" --add 5.0 >/dev/null 2>&1 || true  # -2
    "$CUSUM_SCRIPT" --add 5.0 >/dev/null 2>&1 || true  # -4 total (triggers alert exit 1)

    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null || true)
    if echo "$output" | grep -q "STATUS=ALERT"; then
        pass "ALERT status when CUSUM crosses threshold"
    else
        fail "Should be ALERT when CUSUM crosses threshold, got: $output"
    fi
}

# Test 8: Normal status when CUSUM is small
test_cusum_normal() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add 7.0 >/dev/null 2>&1  # At target
    "$CUSUM_SCRIPT" --add 7.5 >/dev/null 2>&1  # Slightly above

    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null)
    if echo "$output" | grep -q "STATUS=NORMAL"; then
        pass "NORMAL status when CUSUM is small"
    else
        fail "Should be NORMAL when CUSUM is small, got: $output"
    fi
}

# Test 9: Status command works
test_status() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add 6.5 >/dev/null 2>&1

    local output
    output=$("$CUSUM_SCRIPT" --status 2>/dev/null)
    if echo "$output" | grep -q "CUSUM Drift Detection Status"; then
        pass "--status shows detailed output"
    else
        fail "--status should show detailed status"
    fi
}

# Test 10: Invalid score rejected
test_invalid_score() {
    if "$CUSUM_SCRIPT" --add "abc" 2>/dev/null; then
        fail "Should reject non-numeric scores"
    else
        pass "Rejects non-numeric scores"
    fi
}

# Test 11: Score out of range rejected
test_score_range() {
    if "$CUSUM_SCRIPT" --add "15" 2>/dev/null; then
        fail "Should reject scores > 10"
    else
        pass "Rejects scores out of range (>10)"
    fi
}

# -----------------------------------------------
# Per-criterion CUSUM tests (JSON-lines format)
# -----------------------------------------------

echo ""
echo "--- Per-criterion CUSUM ---"

# Test 12: Add JSON score with per-criterion breakdown
test_add_json_score() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add-json '{"total": 7.0, "plan_mode": 2, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1

    local history_file="$SCRIPT_DIR/e2e/score-history.jsonl"
    if [ -f "$history_file" ] && [ -s "$history_file" ]; then
        # Verify the JSON-lines file has valid JSON
        if jq -e '.' "$history_file" > /dev/null 2>&1; then
            pass "--add-json stores JSON score in history"
        else
            fail "--add-json should store valid JSON"
        fi
    else
        fail "--add-json should create score-history.jsonl"
    fi
}

# Test 13: Per-criterion CUSUM check
test_per_criterion_check() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    # plan_mode target is 2; add scores below target
    "$CUSUM_SCRIPT" --add-json '{"total": 6.0, "plan_mode": 1, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1 || true
    "$CUSUM_SCRIPT" --add-json '{"total": 6.0, "plan_mode": 1, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1 || true

    local output
    output=$("$CUSUM_SCRIPT" --check-criteria 2>/dev/null) || true
    if echo "$output" | grep -q "plan_mode"; then
        pass "--check-criteria reports per-criterion CUSUM"
    else
        fail "--check-criteria should report per-criterion CUSUM, got: $output"
    fi
}

# Test 14: Per-criterion drift detection — plan_mode drifting
test_per_criterion_drift() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    # Add 4 scores where plan_mode is consistently 0 (target 2) — CUSUM should drift to -8
    for i in 1 2 3 4; do
        "$CUSUM_SCRIPT" --add-json '{"total": 5.0, "plan_mode": 0, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1 || true
    done

    local output
    output=$("$CUSUM_SCRIPT" --check-criteria 2>/dev/null) || true
    # plan_mode should show ALERT (CUSUM = -8, well past threshold)
    if echo "$output" | grep -q "plan_mode.*ALERT"; then
        pass "Per-criterion drift detected for plan_mode"
    else
        fail "plan_mode should show ALERT with persistent 0 scores, got: $output"
    fi
}

# Test 15: Stable criterion shows NORMAL
test_per_criterion_stable() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add-json '{"total": 7.0, "plan_mode": 2, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1

    local output
    output=$("$CUSUM_SCRIPT" --check-criteria 2>/dev/null) || true
    if echo "$output" | grep -q "tdd_green.*NORMAL"; then
        pass "Stable criterion tdd_green shows NORMAL"
    else
        fail "tdd_green at target should show NORMAL, got: $output"
    fi
}

# Test 16: JSON-lines backward compatibility — total CUSUM still works
test_jsonl_total_cusum() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    "$CUSUM_SCRIPT" --add-json '{"total": 7.0, "plan_mode": 2, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1

    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null)
    if echo "$output" | grep -qE "CUSUM=0\.00?"; then
        pass "Total CUSUM still works with JSON-lines data"
    else
        fail "Total CUSUM should work with JSON-lines data, got: $output"
    fi
}

# Test 17: Mixed format — old .txt scores + new .jsonl scores both supported
test_mixed_format() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1
    # Add old-style score
    "$CUSUM_SCRIPT" --add 7.0 >/dev/null 2>&1
    # Add new-style JSON score
    "$CUSUM_SCRIPT" --add-json '{"total": 7.0, "plan_mode": 2, "tdd_green": 2, "self_review": 1, "clean_code": 1, "task_tracking": 0, "confidence": 1, "tdd_red": 0}' >/dev/null 2>&1

    # Total CUSUM should still work (reads both files)
    local output
    output=$("$CUSUM_SCRIPT" --check 2>/dev/null)
    if echo "$output" | grep -q "CUSUM=0.00"; then
        pass "Mixed old/new score formats supported for total CUSUM"
    else
        fail "Mixed formats should work for total CUSUM, got: $output"
    fi
}

# Cleanup before tests
cleanup() {
    "$CUSUM_SCRIPT" --reset >/dev/null 2>&1 || true
}

# Run all tests
cleanup
test_script_exists
test_help
test_reset
test_add_score
test_cusum_single
test_cusum_negative
test_cusum_alert
test_cusum_normal
test_status
test_invalid_score
test_score_range

# Per-criterion tests
test_add_json_score
test_per_criterion_check
test_per_criterion_drift
test_per_criterion_stable
test_jsonl_total_cusum
test_mixed_format
cleanup

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All CUSUM tests passed!"
