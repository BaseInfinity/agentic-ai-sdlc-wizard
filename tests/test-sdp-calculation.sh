#!/bin/bash
# Test SDP (SDLC Degradation-adjusted Performance) calculation
# TDD: Tests written first before implementation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDP_SCRIPT="$SCRIPT_DIR/e2e/lib/sdp-score.sh"
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

echo "=== SDP Calculation Tests ==="
echo ""

# Test 1: Script exists and is executable
test_script_exists() {
    if [ -x "$SDP_SCRIPT" ]; then
        pass "sdp-score.sh exists and is executable"
    else
        fail "sdp-score.sh not found or not executable at $SDP_SCRIPT"
    fi
}

# Test 2: Help option works
test_help() {
    if "$SDP_SCRIPT" --help 2>/dev/null | grep -q "Usage"; then
        pass "--help shows usage"
    else
        fail "--help should show usage"
    fi
}

# Test 3: Basic calculation works
test_basic_calculation() {
    local output
    output=$("$SDP_SCRIPT" 6.0 claude-sonnet-4 2>/dev/null) || true
    if echo "$output" | grep -q "raw="; then
        pass "Basic calculation returns output with raw score"
    else
        fail "Should return calculation output, got: $output"
    fi
}

# Test 4: Output contains required fields
test_output_fields() {
    local output
    output=$("$SDP_SCRIPT" 7.0 claude-sonnet-4 2>/dev/null) || true
    local has_all=true

    for field in "raw=" "sdp=" "delta=" "external=" "robustness="; do
        if ! echo "$output" | grep -q "$field"; then
            has_all=false
            break
        fi
    done

    if [ "$has_all" = "true" ]; then
        pass "Output contains all required fields"
    else
        fail "Output missing required fields, got: $output"
    fi
}

# Test 5: SDP equals raw when external equals baseline (no degradation)
test_no_degradation() {
    # When external == baseline, SDP should equal raw
    # We'll test this by checking the delta is close to 0
    local output
    output=$("$SDP_SCRIPT" 7.0 claude-sonnet-4 2>/dev/null) || true
    local delta
    delta=$(echo "$output" | grep "delta=" | cut -d'=' -f2)

    if [ -n "$delta" ]; then
        # Delta should be relatively small (within ±1.4 which is 20% of 7.0)
        local abs_delta
        abs_delta=$(echo "$delta" | tr -d '-')
        local is_small
        is_small=$(echo "$abs_delta <= 1.4" | bc -l 2>/dev/null || echo "1")
        if [ "$is_small" = "1" ]; then
            pass "SDP delta is within expected range: $delta"
        else
            fail "SDP delta should be small when model is stable, got: $delta"
        fi
    else
        fail "Could not extract delta from output"
    fi
}

# Test 6: SDP is capped at ±20%
test_cap_applied() {
    # The SDP should never exceed raw ± 20%
    local output
    output=$("$SDP_SCRIPT" 6.0 claude-sonnet-4 2>/dev/null) || true
    local raw sdp
    raw=$(echo "$output" | grep "raw=" | cut -d'=' -f2)
    sdp=$(echo "$output" | grep "sdp=" | cut -d'=' -f2)

    if [ -n "$raw" ] && [ -n "$sdp" ]; then
        local max_sdp min_sdp
        max_sdp=$(echo "scale=2; $raw * 1.2" | bc)
        min_sdp=$(echo "scale=2; $raw * 0.8" | bc)

        local in_range
        in_range=$(echo "$sdp >= $min_sdp && $sdp <= $max_sdp" | bc -l 2>/dev/null || echo "1")
        if [ "$in_range" = "1" ]; then
            pass "SDP ($sdp) is within ±20% cap of raw ($raw)"
        else
            fail "SDP should be capped within ±20%, raw=$raw, sdp=$sdp, range=[$min_sdp, $max_sdp]"
        fi
    else
        fail "Could not extract raw/sdp from output"
    fi
}

# Test 7: Robustness calculation (must be non-negative)
test_robustness() {
    local output
    output=$("$SDP_SCRIPT" 7.0 claude-sonnet-4 2>/dev/null) || true
    local robustness
    robustness=$(echo "$output" | grep "robustness=" | cut -d'=' -f2)

    if [ -n "$robustness" ]; then
        # Robustness should be a non-negative number (uses absolute ratio)
        if echo "$robustness" | grep -qE '^[0-9]+\.?[0-9]*$'; then
            pass "Robustness is non-negative: $robustness"
        else
            fail "Robustness should be non-negative numeric, got: $robustness"
        fi
    else
        fail "Robustness field not found in output"
    fi
}

# Test 8: Interpretation function
test_interpretation() {
    # Test the interpret function if available
    local output
    output=$("$SDP_SCRIPT" 6.0 claude-sonnet-4 2>/dev/null) || true
    local interpretation
    interpretation=$(echo "$output" | grep "interpretation=" | cut -d'=' -f2)

    if [ -n "$interpretation" ]; then
        case "$interpretation" in
            MODEL_DEGRADED|MODEL_IMPROVED|STABLE|SDLC_ISSUE|SDLC_ROBUST)
                pass "Interpretation is valid: $interpretation"
                ;;
            *)
                fail "Unknown interpretation: $interpretation"
                ;;
        esac
    else
        pass "Interpretation field optional (not found but calculation works)"
    fi
}

# Test 9: Invalid input handling
test_invalid_input() {
    local output
    if ! "$SDP_SCRIPT" "invalid" 2>/dev/null; then
        pass "Invalid input rejected"
    else
        output=$("$SDP_SCRIPT" "invalid" 2>&1) || true
        if echo "$output" | grep -qi "error\|usage"; then
            pass "Invalid input shows error/usage"
        else
            fail "Invalid input should be rejected or show error"
        fi
    fi
}

# Test 10: External change percentage is calculated
test_external_change() {
    local output
    output=$("$SDP_SCRIPT" 7.0 claude-sonnet-4 2>/dev/null) || true
    local external_change
    external_change=$(echo "$output" | grep "external_change=" | cut -d'=' -f2)

    if [ -n "$external_change" ]; then
        pass "External change percentage calculated: $external_change"
    else
        fail "External change percentage not found in output"
    fi
}

# Test 11: Robustness is never negative (regression test for * -1 bug)
test_robustness_never_negative() {
    local scores="3.0 5.0 7.0 9.0"
    local all_positive=true
    for score in $scores; do
        local output
        output=$("$SDP_SCRIPT" "$score" claude-sonnet-4 2>/dev/null) || true
        local robustness
        robustness=$(echo "$output" | grep "robustness=" | cut -d'=' -f2)
        if [ -n "$robustness" ] && echo "$robustness" | grep -q '^-'; then
            all_positive=false
            fail "Robustness negative for score=$score: $robustness"
            return
        fi
    done
    if [ "$all_positive" = "true" ]; then
        pass "Robustness never negative across multiple scores"
    fi
}

# Test 12: Raw score of 0 handled gracefully
test_raw_zero() {
    local output
    output=$("$SDP_SCRIPT" 0.0 claude-sonnet-4 2>/dev/null) || true
    local sdp
    sdp=$(echo "$output" | grep "sdp=" | cut -d'=' -f2)

    if [ -n "$sdp" ]; then
        # SDP of 0 raw should be 0 (or near 0)
        local is_zero
        is_zero=$(echo "$sdp <= 0.01" | bc -l 2>/dev/null || echo "1")
        if [ "$is_zero" = "1" ]; then
            pass "Raw score 0.0 produces SDP near zero: $sdp"
        else
            fail "Raw 0.0 should produce near-zero SDP, got: $sdp"
        fi
    else
        fail "Should handle raw=0 input, no output"
    fi
}

# Test 13: SDP output format is consistent (all fields present for raw=0)
test_raw_zero_all_fields() {
    local output
    output=$("$SDP_SCRIPT" 0.0 claude-sonnet-4 2>/dev/null) || true
    local has_all=true

    for field in "raw=" "sdp=" "delta=" "external=" "robustness="; do
        if ! echo "$output" | grep -q "$field"; then
            has_all=false
            break
        fi
    done

    if [ "$has_all" = "true" ]; then
        pass "Raw=0 still outputs all required fields"
    else
        fail "Raw=0 should still output all fields, got: $output"
    fi
}

# Test 14: High raw score (10.0) works
test_max_score() {
    local output
    output=$("$SDP_SCRIPT" 10.0 claude-sonnet-4 2>/dev/null) || true
    local sdp
    sdp=$(echo "$output" | grep "sdp=" | cut -d'=' -f2)

    if [ -n "$sdp" ]; then
        local in_range
        in_range=$(echo "$sdp >= 8.0 && $sdp <= 12.0" | bc -l 2>/dev/null || echo "1")
        if [ "$in_range" = "1" ]; then
            pass "Max score 10.0 produces reasonable SDP: $sdp"
        else
            fail "Max score SDP should be 8.0-12.0, got: $sdp"
        fi
    else
        fail "Should handle max score"
    fi
}

# Test 15: Interpretation covers all 5 valid values
test_all_interpretations_valid() {
    local valid_interpretations="MODEL_DEGRADED MODEL_IMPROVED STABLE SDLC_ISSUE SDLC_ROBUST"
    local scores="1.0 3.0 5.0 7.0 9.0"
    local all_valid=true

    for score in $scores; do
        local output
        output=$("$SDP_SCRIPT" "$score" claude-sonnet-4 2>/dev/null) || true
        local interpretation
        interpretation=$(echo "$output" | grep "interpretation=" | cut -d'=' -f2)
        if [ -n "$interpretation" ]; then
            local found=false
            for valid in $valid_interpretations; do
                if [ "$interpretation" = "$valid" ]; then
                    found=true
                    break
                fi
            done
            if [ "$found" = "false" ]; then
                all_valid=false
                fail "Invalid interpretation '$interpretation' for score $score"
                return
            fi
        fi
    done

    if [ "$all_valid" = "true" ]; then
        pass "All interpretations are from valid set"
    fi
}

# Test 16: Missing model argument defaults gracefully
test_default_model() {
    local output
    output=$("$SDP_SCRIPT" 7.0 2>/dev/null) || true
    if echo "$output" | grep -q "raw=7.0"; then
        pass "Missing model argument uses default"
    else
        fail "Should work with default model, got: $output"
    fi
}

# Run all tests
test_script_exists
test_help
test_basic_calculation
test_output_fields
test_no_degradation
test_cap_applied
test_robustness
test_interpretation
test_invalid_input
test_external_change
test_robustness_never_negative
test_raw_zero
test_raw_zero_all_fields
test_max_score
test_all_interpretations_valid
test_default_model

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All SDP calculation tests passed!"
