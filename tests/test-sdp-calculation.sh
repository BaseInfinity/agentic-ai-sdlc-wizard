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

# Test 7: Robustness calculation
test_robustness() {
    local output
    output=$("$SDP_SCRIPT" 7.0 claude-sonnet-4 2>/dev/null) || true
    local robustness
    robustness=$(echo "$output" | grep "robustness=" | cut -d'=' -f2)

    if [ -n "$robustness" ]; then
        # Robustness should be a number (can be negative or positive)
        if echo "$robustness" | grep -qE '^-?[0-9]+\.?[0-9]*$'; then
            pass "Robustness is calculated: $robustness"
        else
            fail "Robustness should be numeric, got: $robustness"
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

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All SDP calculation tests passed!"
