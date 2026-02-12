#!/bin/bash
# Test pairwise tiebreaker: tiebreaker-only pairwise comparison
#
# Tests the lightweight pairwise comparison that only triggers
# when pointwise scores are close (|scoreA - scoreB| <= threshold).
# Validates:
#   - should_run_pairwise: threshold gating logic
#   - build_holistic_pairwise_prompt: prompt construction with swap
#   - validate_pairwise_result: JSON structure validation
#   - run_pairwise_tiebreaker: verdict logic (consistent wins, ties)
#   - pairwise-compare.sh: main script integration
#
# Does NOT make real API calls — tests logic, prompts, and verdict only.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/eval-criteria.sh"

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

echo "=== Pairwise Tiebreaker Tests ==="
echo ""

# -----------------------------------------------
# should_run_pairwise tests
# -----------------------------------------------

echo "--- should_run_pairwise ---"

test_pairwise_triggered_within_threshold() {
    # Scores differ by 0.5 (within default 1.0 threshold)
    if should_run_pairwise 7.0 7.5; then
        pass "Pairwise triggered when |7.0 - 7.5| = 0.5 <= 1.0"
    else
        fail "Pairwise should trigger when scores within threshold"
    fi
}

test_pairwise_triggered_equal_scores() {
    # Same score — should trigger pairwise
    if should_run_pairwise 6.0 6.0; then
        pass "Pairwise triggered when scores equal (0.0 <= 1.0)"
    else
        fail "Pairwise should trigger when scores are equal"
    fi
}

test_pairwise_triggered_at_threshold() {
    # Exactly at threshold boundary (1.0 <= 1.0)
    if should_run_pairwise 5.0 6.0; then
        pass "Pairwise triggered at exact threshold boundary (|5.0 - 6.0| = 1.0)"
    else
        fail "Pairwise should trigger at exact threshold boundary"
    fi
}

test_pairwise_not_triggered_beyond_threshold() {
    # Scores differ by 3.0 (well beyond default 1.0 threshold)
    if should_run_pairwise 5.0 8.0; then
        fail "Pairwise should NOT trigger when |5.0 - 8.0| = 3.0 > 1.0"
    else
        pass "Pairwise not triggered when scores differ by 3.0"
    fi
}

test_pairwise_custom_threshold() {
    # Custom threshold of 2.0 — scores differ by 1.5
    if should_run_pairwise 5.0 6.5 2.0; then
        pass "Pairwise triggered with custom threshold (|5.0 - 6.5| = 1.5 <= 2.0)"
    else
        fail "Pairwise should trigger with custom threshold 2.0"
    fi
}

test_pairwise_custom_threshold_exceeded() {
    # Custom threshold of 0.5 — scores differ by 1.0
    if should_run_pairwise 5.0 6.0 0.5; then
        fail "Pairwise should NOT trigger when |5.0 - 6.0| = 1.0 > 0.5"
    else
        pass "Pairwise not triggered when custom threshold exceeded"
    fi
}

# -----------------------------------------------
# build_holistic_pairwise_prompt tests
# -----------------------------------------------

echo ""
echo "--- build_holistic_pairwise_prompt ---"

test_prompt_ab_order() {
    local prompt
    prompt=$(build_holistic_pairwise_prompt "Output A text" "Output B text" "Scenario text" "AB")
    if echo "$prompt" | grep -q "Output A" && echo "$prompt" | grep -q "Output B"; then
        pass "AB prompt contains both outputs"
    else
        fail "AB prompt should contain both outputs"
    fi
}

test_prompt_ba_order_swaps() {
    local prompt_ab prompt_ba
    prompt_ab=$(build_holistic_pairwise_prompt "First output" "Second output" "Scenario" "AB")
    prompt_ba=$(build_holistic_pairwise_prompt "First output" "Second output" "Scenario" "BA")

    # In BA order, "Second output" should appear first (as Output A)
    # Check that the order is actually different
    if [ "$prompt_ab" != "$prompt_ba" ]; then
        pass "BA prompt has different ordering than AB prompt"
    else
        fail "BA prompt should swap the order of outputs"
    fi
}

test_prompt_includes_scenario() {
    local prompt
    prompt=$(build_holistic_pairwise_prompt "out A" "out B" "My scenario content here" "AB")
    if echo "$prompt" | grep -q "My scenario content here"; then
        pass "Pairwise prompt includes scenario content"
    else
        fail "Pairwise prompt should include scenario content"
    fi
}

test_prompt_requests_json() {
    local prompt
    prompt=$(build_holistic_pairwise_prompt "out A" "out B" "scenario" "AB")
    if echo "$prompt" | grep -qi "json"; then
        pass "Pairwise prompt requests JSON output"
    else
        fail "Pairwise prompt should request JSON output"
    fi
}

test_prompt_asks_for_winner() {
    local prompt
    prompt=$(build_holistic_pairwise_prompt "out A" "out B" "scenario" "AB")
    if echo "$prompt" | grep -qiE "winner|better|which.*output"; then
        pass "Pairwise prompt asks for a winner"
    else
        fail "Pairwise prompt should ask which output is better"
    fi
}

# -----------------------------------------------
# validate_pairwise_result tests
# -----------------------------------------------

echo ""
echo "--- validate_pairwise_result ---"

test_validate_valid_result() {
    local json='{"winner": "A", "reasoning": "Output A showed better TDD"}'
    if validate_pairwise_result "$json"; then
        pass "Valid pairwise result accepted"
    else
        fail "Valid pairwise result should be accepted"
    fi
}

test_validate_winner_b() {
    local json='{"winner": "B", "reasoning": "Output B had plan mode"}'
    if validate_pairwise_result "$json"; then
        pass "Winner B accepted"
    else
        fail "Winner B should be accepted"
    fi
}

test_validate_tie() {
    local json='{"winner": "TIE", "reasoning": "Both outputs equally followed SDLC"}'
    if validate_pairwise_result "$json"; then
        pass "TIE verdict accepted"
    else
        fail "TIE should be a valid winner value"
    fi
}

test_validate_missing_winner() {
    local json='{"reasoning": "Some reasoning"}'
    if validate_pairwise_result "$json" 2>/dev/null; then
        fail "Missing winner should be rejected"
    else
        pass "Missing winner rejected"
    fi
}

test_validate_invalid_winner() {
    local json='{"winner": "C", "reasoning": "Invalid"}'
    if validate_pairwise_result "$json" 2>/dev/null; then
        fail "Winner 'C' should be rejected (only A, B, TIE allowed)"
    else
        pass "Invalid winner 'C' rejected"
    fi
}

test_validate_missing_reasoning() {
    local json='{"winner": "A"}'
    if validate_pairwise_result "$json" 2>/dev/null; then
        fail "Missing reasoning should be rejected"
    else
        pass "Missing reasoning rejected"
    fi
}

test_validate_not_json() {
    local raw="This is just plain text"
    if validate_pairwise_result "$raw" 2>/dev/null; then
        fail "Non-JSON input should be rejected"
    else
        pass "Non-JSON input rejected"
    fi
}

# -----------------------------------------------
# run_pairwise_tiebreaker (verdict logic) tests
# -----------------------------------------------

echo ""
echo "--- run_pairwise_tiebreaker verdict logic ---"

test_verdict_consistent_a() {
    # Both orderings agree: A wins
    local result
    result=$(compute_pairwise_verdict \
        '{"winner": "A", "reasoning": "A was better"}' \
        '{"winner": "A", "reasoning": "A still better after swap"}')
    local verdict consistent
    verdict=$(echo "$result" | jq -r '.verdict')
    consistent=$(echo "$result" | jq -r '.consistent')
    if [ "$verdict" = "A" ] && [ "$consistent" = "true" ]; then
        pass "Consistent A verdict from both orderings"
    else
        fail "Expected verdict=A consistent=true, got verdict=$verdict consistent=$consistent"
    fi
}

test_verdict_consistent_b() {
    # Both orderings agree: B wins
    local result
    result=$(compute_pairwise_verdict \
        '{"winner": "B", "reasoning": "B was better"}' \
        '{"winner": "B", "reasoning": "B still better after swap"}')
    local verdict consistent
    verdict=$(echo "$result" | jq -r '.verdict')
    consistent=$(echo "$result" | jq -r '.consistent')
    if [ "$verdict" = "B" ] && [ "$consistent" = "true" ]; then
        pass "Consistent B verdict from both orderings"
    else
        fail "Expected verdict=B consistent=true, got verdict=$verdict consistent=$consistent"
    fi
}

test_verdict_inconsistent_tie() {
    # Orderings disagree: A in first, B in second = position bias = TIE
    local result
    result=$(compute_pairwise_verdict \
        '{"winner": "A", "reasoning": "A seemed better"}' \
        '{"winner": "B", "reasoning": "B seemed better"}')
    local verdict consistent
    verdict=$(echo "$result" | jq -r '.verdict')
    consistent=$(echo "$result" | jq -r '.consistent')
    if [ "$verdict" = "TIE" ] && [ "$consistent" = "false" ]; then
        pass "Inconsistent orderings produce TIE"
    else
        fail "Expected verdict=TIE consistent=false, got verdict=$verdict consistent=$consistent"
    fi
}

test_verdict_both_tie() {
    # Both orderings say TIE
    local result
    result=$(compute_pairwise_verdict \
        '{"winner": "TIE", "reasoning": "Equal quality"}' \
        '{"winner": "TIE", "reasoning": "Still equal"}')
    local verdict consistent
    verdict=$(echo "$result" | jq -r '.verdict')
    consistent=$(echo "$result" | jq -r '.consistent')
    if [ "$verdict" = "TIE" ] && [ "$consistent" = "true" ]; then
        pass "Both TIE produces consistent TIE verdict"
    else
        fail "Expected verdict=TIE consistent=true, got verdict=$verdict consistent=$consistent"
    fi
}

test_verdict_one_tie_one_winner() {
    # One ordering says TIE, other says A = inconsistent = TIE
    local result
    result=$(compute_pairwise_verdict \
        '{"winner": "TIE", "reasoning": "Equal"}' \
        '{"winner": "A", "reasoning": "A better"}')
    local verdict consistent
    verdict=$(echo "$result" | jq -r '.verdict')
    consistent=$(echo "$result" | jq -r '.consistent')
    if [ "$verdict" = "TIE" ] && [ "$consistent" = "false" ]; then
        pass "TIE + A = inconsistent TIE"
    else
        fail "Expected verdict=TIE consistent=false, got verdict=$verdict consistent=$consistent"
    fi
}

# -----------------------------------------------
# pairwise-compare.sh integration tests
# -----------------------------------------------

echo ""
echo "--- pairwise-compare.sh integration ---"

PAIRWISE_SCRIPT="$SCRIPT_DIR/pairwise-compare.sh"

test_script_exists() {
    if [ -x "$PAIRWISE_SCRIPT" ]; then
        pass "pairwise-compare.sh exists and is executable"
    else
        fail "pairwise-compare.sh should exist and be executable"
    fi
}

test_not_triggered_output() {
    # Create temp output files
    local tmp_a tmp_b
    tmp_a=$(mktemp)
    tmp_b=$(mktemp)
    echo "Output A content" > "$tmp_a"
    echo "Output B content" > "$tmp_b"

    # Scores are far apart — should not trigger pairwise
    local result
    result=$("$PAIRWISE_SCRIPT" "$tmp_a" "$tmp_b" "scenario text" 5.0 8.0 --no-api 2>/dev/null) || true

    rm -f "$tmp_a" "$tmp_b"

    local triggered
    triggered=$(echo "$result" | jq -r '.triggered')
    if [ "$triggered" = "false" ]; then
        pass "Not-triggered result has triggered=false"
    else
        fail "Expected triggered=false when scores far apart, got: $triggered"
    fi
}

test_not_triggered_has_verdict() {
    local tmp_a tmp_b
    tmp_a=$(mktemp)
    tmp_b=$(mktemp)
    echo "Output A" > "$tmp_a"
    echo "Output B" > "$tmp_b"

    local result
    result=$("$PAIRWISE_SCRIPT" "$tmp_a" "$tmp_b" "scenario" 5.0 8.0 --no-api 2>/dev/null) || true

    rm -f "$tmp_a" "$tmp_b"

    local verdict
    verdict=$(echo "$result" | jq -r '.verdict')
    if [ "$verdict" = "B" ]; then
        pass "Not-triggered result picks higher-scoring output as verdict"
    else
        fail "Expected verdict=B (higher score), got: $verdict"
    fi
}

# -----------------------------------------------
# Run all tests
# -----------------------------------------------

test_pairwise_triggered_within_threshold
test_pairwise_triggered_equal_scores
test_pairwise_triggered_at_threshold
test_pairwise_not_triggered_beyond_threshold
test_pairwise_custom_threshold
test_pairwise_custom_threshold_exceeded

test_prompt_ab_order
test_prompt_ba_order_swaps
test_prompt_includes_scenario
test_prompt_requests_json
test_prompt_asks_for_winner

test_validate_valid_result
test_validate_winner_b
test_validate_tie
test_validate_missing_winner
test_validate_invalid_winner
test_validate_missing_reasoning
test_validate_not_json

test_verdict_consistent_a
test_verdict_consistent_b
test_verdict_inconsistent_tie
test_verdict_both_tie
test_verdict_one_tie_one_winner

test_script_exists
test_not_triggered_output
test_not_triggered_has_verdict

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All pairwise tiebreaker tests passed!"
