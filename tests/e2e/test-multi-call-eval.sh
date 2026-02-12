#!/bin/bash
# Test multi-call LLM judge: per-criterion prompt format + aggregation
#
# Tests the refactored evaluation where each subjective criterion gets
# its own API call instead of one monolithic prompt. Validates:
#   - Per-criterion prompts are generated correctly
#   - Aggregation of individual results matches expected schema
#   - EVAL_PROMPT_VERSION bumped to v3
#   - Criterion list is complete and correct
#
# Does NOT make real API calls — tests prompt construction + aggregation logic only.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/eval-validation.sh"
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

echo "=== Multi-Call LLM Judge Tests ==="
echo ""

# -----------------------------------------------
# Prompt version tests
# -----------------------------------------------

echo "--- Prompt version ---"

test_prompt_version_v3() {
    if [ "$EVAL_PROMPT_VERSION" = "v3" ]; then
        pass "EVAL_PROMPT_VERSION is v3"
    else
        fail "EVAL_PROMPT_VERSION should be v3, got: $EVAL_PROMPT_VERSION"
    fi
}

# -----------------------------------------------
# Criterion list tests
# -----------------------------------------------

echo ""
echo "--- Criterion definitions ---"

test_criteria_list_standard() {
    local criteria
    criteria=$(get_llm_criteria "standard")
    local count
    count=$(echo "$criteria" | wc -w | tr -d ' ')
    if [ "$count" -eq 4 ]; then
        pass "Standard scenarios have 4 LLM criteria"
    else
        fail "Standard scenarios should have 4 LLM criteria, got $count: $criteria"
    fi
}

test_criteria_list_ui() {
    local criteria
    criteria=$(get_llm_criteria "ui")
    local count
    count=$(echo "$criteria" | wc -w | tr -d ' ')
    if [ "$count" -eq 5 ]; then
        pass "UI scenarios have 5 LLM criteria (includes design_system)"
    else
        fail "UI scenarios should have 5 LLM criteria, got $count: $criteria"
    fi
}

test_criteria_names_standard() {
    local criteria
    criteria=$(get_llm_criteria "standard")
    local has_all=true
    for name in plan_mode tdd_green self_review clean_code; do
        if ! echo "$criteria" | grep -qw "$name"; then
            has_all=false
            fail "Standard criteria missing: $name"
        fi
    done
    if [ "$has_all" = true ]; then
        pass "Standard criteria has all 4 expected names"
    fi
}

test_criteria_names_ui() {
    local criteria
    criteria=$(get_llm_criteria "ui")
    if echo "$criteria" | grep -qw "design_system"; then
        pass "UI criteria includes design_system"
    else
        fail "UI criteria should include design_system"
    fi
}

# -----------------------------------------------
# Per-criterion prompt generation tests
# -----------------------------------------------

echo ""
echo "--- Per-criterion prompt generation ---"

test_prompt_has_criterion_name() {
    local prompt
    prompt=$(build_criterion_prompt "plan_mode" "Sample scenario" "Sample output")
    if echo "$prompt" | grep -qi "plan_mode\|plan mode"; then
        pass "plan_mode prompt references the criterion"
    else
        fail "plan_mode prompt should reference the criterion name"
    fi
}

test_prompt_has_max_points() {
    local prompt
    prompt=$(build_criterion_prompt "plan_mode" "Sample scenario" "Sample output")
    # plan_mode is 2 points
    if echo "$prompt" | grep -q "2"; then
        pass "plan_mode prompt mentions max points (2)"
    else
        fail "plan_mode prompt should mention max points"
    fi
}

test_prompt_has_calibration() {
    local prompt
    prompt=$(build_criterion_prompt "tdd_green" "Sample scenario" "Sample output")
    # Should have calibration examples specific to tdd_green
    if echo "$prompt" | grep -qi "calibration\|example\|2/2\|1/2\|0/2"; then
        pass "tdd_green prompt includes calibration examples"
    else
        fail "tdd_green prompt should include calibration examples"
    fi
}

test_prompt_includes_scenario() {
    local prompt
    prompt=$(build_criterion_prompt "clean_code" "My test scenario content" "My test output content")
    if echo "$prompt" | grep -q "My test scenario content"; then
        pass "Prompt includes scenario content"
    else
        fail "Prompt should include scenario content"
    fi
}

test_prompt_includes_output() {
    local prompt
    prompt=$(build_criterion_prompt "clean_code" "My test scenario content" "My test output content")
    if echo "$prompt" | grep -q "My test output content"; then
        pass "Prompt includes execution output content"
    else
        fail "Prompt should include execution output content"
    fi
}

test_prompt_requests_json() {
    local prompt
    prompt=$(build_criterion_prompt "self_review" "scenario" "output")
    if echo "$prompt" | grep -qi "json"; then
        pass "Prompt requests JSON output"
    else
        fail "Prompt should request JSON output format"
    fi
}

test_design_system_prompt_exists() {
    local prompt
    prompt=$(build_criterion_prompt "design_system" "UI scenario" "UI output")
    if echo "$prompt" | grep -qi "design.system\|DESIGN_SYSTEM"; then
        pass "design_system prompt references design system"
    else
        fail "design_system prompt should reference DESIGN_SYSTEM.md"
    fi
}

# -----------------------------------------------
# Aggregation tests
# -----------------------------------------------

echo ""
echo "--- Result aggregation ---"

test_aggregate_single_criterion() {
    # Simulate a single criterion result
    local plan_mode_result='{"points": 1.5, "max": 2, "evidence": "Had a plan but informal"}'
    local aggregated
    aggregated=$(aggregate_criterion_results "plan_mode" "$plan_mode_result")

    if echo "$aggregated" | jq -e '.criteria.plan_mode.points == 1.5' > /dev/null 2>&1; then
        pass "Single criterion aggregated correctly"
    else
        fail "Single criterion aggregation failed"
    fi
}

test_aggregate_multiple_criteria() {
    # Build up criteria one by one as the loop would
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode" '{"points": 2, "max": 2, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green" '{"points": 1.5, "max": 2, "evidence": "ok"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"points": 1, "max": 1, "evidence": "done"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"points": 0.5, "max": 1, "evidence": "messy"}' "$result")

    # Check all 4 criteria present
    local count
    count=$(echo "$result" | jq '.criteria | length')
    if [ "$count" -eq 4 ]; then
        pass "All 4 criteria present in aggregated result"
    else
        fail "Expected 4 criteria in aggregated result, got $count"
    fi
}

test_aggregate_preserves_evidence() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode" '{"points": 2, "max": 2, "evidence": "Entered plan mode, created plan file"}' "$result")

    local evidence
    evidence=$(echo "$result" | jq -r '.criteria.plan_mode.evidence')
    if [ "$evidence" = "Entered plan mode, created plan file" ]; then
        pass "Evidence preserved in aggregation"
    else
        fail "Evidence should be preserved, got: $evidence"
    fi
}

test_finalize_adds_summary() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode" '{"points": 2, "max": 2, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green" '{"points": 2, "max": 2, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"points": 1, "max": 1, "evidence": "good"}' "$result")

    local finalized
    finalized=$(finalize_eval_result "$result")

    # Should have summary and improvements
    if echo "$finalized" | jq -e 'has("summary") and has("improvements")' > /dev/null 2>&1; then
        pass "Finalized result has summary and improvements"
    else
        fail "Finalized result should have summary and improvements"
    fi
}

test_finalize_validates_schema() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode" '{"points": 2, "max": 2, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green" '{"points": 1, "max": 2, "evidence": "late"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"points": 0.5, "max": 1, "evidence": "brief"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"points": 1, "max": 1, "evidence": "ok"}' "$result")

    local finalized
    finalized=$(finalize_eval_result "$result")

    # Should pass our existing schema validation
    if validate_eval_schema "$finalized"; then
        pass "Finalized result passes schema validation"
    else
        fail "Finalized result should pass schema validation"
    fi
}

# -----------------------------------------------
# Criterion max points tests
# -----------------------------------------------

echo ""
echo "--- Criterion max points ---"

test_max_points_plan_mode() {
    local max
    max=$(get_criterion_max "plan_mode")
    if [ "$max" = "2" ]; then
        pass "plan_mode max is 2"
    else
        fail "plan_mode max should be 2, got $max"
    fi
}

test_max_points_tdd_green() {
    local max
    max=$(get_criterion_max "tdd_green")
    if [ "$max" = "2" ]; then
        pass "tdd_green max is 2"
    else
        fail "tdd_green max should be 2, got $max"
    fi
}

test_max_points_self_review() {
    local max
    max=$(get_criterion_max "self_review")
    if [ "$max" = "1" ]; then
        pass "self_review max is 1"
    else
        fail "self_review max should be 1, got $max"
    fi
}

test_max_points_clean_code() {
    local max
    max=$(get_criterion_max "clean_code")
    if [ "$max" = "1" ]; then
        pass "clean_code max is 1"
    else
        fail "clean_code max should be 1, got $max"
    fi
}

test_max_points_design_system() {
    local max
    max=$(get_criterion_max "design_system")
    if [ "$max" = "1" ]; then
        pass "design_system max is 1"
    else
        fail "design_system max should be 1, got $max"
    fi
}

# -----------------------------------------------
# Run all tests
# -----------------------------------------------

test_prompt_version_v3
test_criteria_list_standard
test_criteria_list_ui
test_criteria_names_standard
test_criteria_names_ui
test_prompt_has_criterion_name
test_prompt_has_max_points
test_prompt_has_calibration
test_prompt_includes_scenario
test_prompt_includes_output
test_prompt_requests_json
test_design_system_prompt_exists
test_aggregate_single_criterion
test_aggregate_multiple_criteria
test_aggregate_preserves_evidence
test_finalize_adds_summary
test_finalize_validates_schema
test_max_points_plan_mode
test_max_points_tdd_green
test_max_points_self_review
test_max_points_clean_code
test_max_points_design_system

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All multi-call eval tests passed!"
