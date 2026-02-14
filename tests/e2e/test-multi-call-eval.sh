#!/bin/bash
# Test multi-call LLM judge: binary (YES/NO) per-criterion evaluation
#
# Tests the binary evaluation where each subjective criterion is a YES/NO
# question answered by the LLM. Multi-point criteria are split into
# sub-questions worth 1pt each. Validates:
#   - Per-criterion prompts use binary YES/NO format
#   - Sub-criteria for multi-point criteria (plan_mode, tdd_green)
#   - Aggregation of binary results matches expected schema
#   - EVAL_PROMPT_VERSION bumped to v4
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

echo "=== Binary LLM Judge Tests ==="
echo ""

# -----------------------------------------------
# Prompt version tests
# -----------------------------------------------

echo "--- Prompt version ---"

test_prompt_version_v4() {
    if [ "$EVAL_PROMPT_VERSION" = "v4" ]; then
        pass "EVAL_PROMPT_VERSION is v4"
    else
        fail "EVAL_PROMPT_VERSION should be v4, got: $EVAL_PROMPT_VERSION"
    fi
}

# -----------------------------------------------
# Criterion list tests — sub-criteria for multi-point
# -----------------------------------------------

echo ""
echo "--- Criterion definitions (binary sub-criteria) ---"

test_criteria_list_standard() {
    local criteria
    criteria=$(get_llm_criteria "standard")
    local count
    count=$(echo "$criteria" | wc -w | tr -d ' ')
    # plan_mode_outline, plan_mode_tool, tdd_green_ran, tdd_green_pass, self_review, clean_code = 6
    if [ "$count" -eq 6 ]; then
        pass "Standard scenarios have 6 binary sub-criteria"
    else
        fail "Standard scenarios should have 6 binary sub-criteria, got $count: $criteria"
    fi
}

test_criteria_list_ui() {
    local criteria
    criteria=$(get_llm_criteria "ui")
    local count
    count=$(echo "$criteria" | wc -w | tr -d ' ')
    # 6 standard + design_system = 7
    if [ "$count" -eq 7 ]; then
        pass "UI scenarios have 7 binary sub-criteria (includes design_system)"
    else
        fail "UI scenarios should have 7 binary sub-criteria, got $count: $criteria"
    fi
}

test_criteria_names_standard() {
    local criteria
    criteria=$(get_llm_criteria "standard")
    local has_all=true
    for name in plan_mode_outline plan_mode_tool tdd_green_ran tdd_green_pass self_review clean_code; do
        if ! echo "$criteria" | grep -qw "$name"; then
            has_all=false
            fail "Standard criteria missing: $name"
        fi
    done
    if [ "$has_all" = true ]; then
        pass "Standard criteria has all 6 expected sub-criteria names"
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
# All criteria max points = 1 (binary)
# -----------------------------------------------

echo ""
echo "--- All criteria are binary (max=1) ---"

test_all_criteria_max_1() {
    local criteria
    criteria=$(get_llm_criteria "ui")  # UI has all criteria
    local all_one=true
    for name in $criteria; do
        local max
        max=$(get_criterion_max "$name")
        if [ "$max" != "1" ]; then
            all_one=false
            fail "$name max should be 1, got $max"
        fi
    done
    if [ "$all_one" = true ]; then
        pass "All criteria have max=1 (binary)"
    fi
}

test_total_llm_max_standard() {
    local criteria total=0
    criteria=$(get_llm_criteria "standard")
    for name in $criteria; do
        local max
        max=$(get_criterion_max "$name")
        total=$((total + max))
    done
    # 6 sub-criteria * 1pt = 6
    if [ "$total" -eq 6 ]; then
        pass "Standard LLM max total is 6 (same as before: plan=2 + tdd=2 + review=1 + clean=1)"
    else
        fail "Standard LLM max total should be 6, got $total"
    fi
}

test_total_llm_max_ui() {
    local criteria total=0
    criteria=$(get_llm_criteria "ui")
    for name in $criteria; do
        local max
        max=$(get_criterion_max "$name")
        total=$((total + max))
    done
    # 7 sub-criteria * 1pt = 7
    if [ "$total" -eq 7 ]; then
        pass "UI LLM max total is 7 (same as before: 6 standard + design_system=1)"
    else
        fail "UI LLM max total should be 7, got $total"
    fi
}

# -----------------------------------------------
# Per-criterion prompt generation — binary format
# -----------------------------------------------

echo ""
echo "--- Binary prompt format ---"

test_prompt_asks_yes_no() {
    local criteria
    criteria=$(get_llm_criteria "standard")
    local all_binary=true
    for name in $criteria; do
        local prompt
        prompt=$(build_criterion_prompt "$name" "Sample scenario" "Sample output")
        if ! echo "$prompt" | grep -qi "YES.*NO\|YES/NO\|yes.*no"; then
            all_binary=false
            fail "$name prompt does not ask YES/NO question"
        fi
    done
    if [ "$all_binary" = true ]; then
        pass "All standard prompts ask YES/NO questions"
    fi
}

test_prompt_requests_met_field() {
    local prompt
    prompt=$(build_criterion_prompt "plan_mode_outline" "Sample scenario" "Sample output")
    if echo "$prompt" | grep -q '"met"'; then
        pass "Prompt requests 'met' field in JSON output"
    else
        fail "Prompt should request 'met' field in JSON format"
    fi
}

test_prompt_no_partial_credit() {
    local prompt
    prompt=$(build_criterion_prompt "self_review" "Sample scenario" "Sample output")
    if echo "$prompt" | grep -qi "partial credit\|0\.5"; then
        fail "Prompt should NOT mention partial credit"
    else
        pass "No partial credit in self_review prompt"
    fi
}

test_prompt_has_criterion_name() {
    local prompt
    prompt=$(build_criterion_prompt "plan_mode_outline" "Sample scenario" "Sample output")
    if echo "$prompt" | grep -qi "plan_mode_outline\|plan.*outline\|outline.*steps"; then
        pass "plan_mode_outline prompt references the criterion"
    else
        fail "plan_mode_outline prompt should reference the criterion"
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
# Aggregation tests — binary results
# -----------------------------------------------

echo ""
echo "--- Result aggregation (binary) ---"

test_aggregate_binary_met_true() {
    local result='{"met": true, "points": 1, "max": 1, "evidence": "Outlined steps before coding"}'
    local aggregated
    aggregated=$(aggregate_criterion_results "plan_mode_outline" "$result")

    if echo "$aggregated" | jq -e '.criteria.plan_mode_outline.points == 1' > /dev/null 2>&1; then
        pass "Binary met=true aggregated as points=1"
    else
        fail "Binary met=true should aggregate as points=1"
    fi
}

test_aggregate_binary_met_false() {
    local result='{"met": false, "points": 0, "max": 1, "evidence": "No planning observed"}'
    local aggregated
    aggregated=$(aggregate_criterion_results "plan_mode_outline" "$result")

    if echo "$aggregated" | jq -e '.criteria.plan_mode_outline.points == 0' > /dev/null 2>&1; then
        pass "Binary met=false aggregated as points=0"
    else
        fail "Binary met=false should aggregate as points=0"
    fi
}

test_aggregate_all_binary_criteria() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode_outline" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "plan_mode_tool" '{"met": false, "points": 0, "max": 1, "evidence": "no tool"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_ran" '{"met": true, "points": 1, "max": 1, "evidence": "ran tests"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_pass" '{"met": true, "points": 1, "max": 1, "evidence": "all pass"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"met": true, "points": 1, "max": 1, "evidence": "reviewed"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"met": true, "points": 1, "max": 1, "evidence": "clean"}' "$result")

    local count
    count=$(echo "$result" | jq '.criteria | length')
    if [ "$count" -eq 6 ]; then
        pass "All 6 binary criteria present in aggregated result"
    else
        fail "Expected 6 criteria in aggregated result, got $count"
    fi
}

test_aggregate_preserves_evidence() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode_outline" '{"met": true, "points": 1, "max": 1, "evidence": "Outlined steps before writing code"}' "$result")

    local evidence
    evidence=$(echo "$result" | jq -r '.criteria.plan_mode_outline.evidence')
    if [ "$evidence" = "Outlined steps before writing code" ]; then
        pass "Evidence preserved in binary aggregation"
    else
        fail "Evidence should be preserved, got: $evidence"
    fi
}

test_finalize_adds_summary() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode_outline" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "plan_mode_tool" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_ran" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_pass" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")

    local finalized
    finalized=$(finalize_eval_result "$result")

    if echo "$finalized" | jq -e 'has("summary") and has("improvements")' > /dev/null 2>&1; then
        pass "Finalized result has summary and improvements"
    else
        fail "Finalized result should have summary and improvements"
    fi
}

test_finalize_validates_schema() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode_outline" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "plan_mode_tool" '{"met": false, "points": 0, "max": 1, "evidence": "missing"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_ran" '{"met": true, "points": 1, "max": 1, "evidence": "ok"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_pass" '{"met": true, "points": 1, "max": 1, "evidence": "pass"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"met": false, "points": 0, "max": 1, "evidence": "none"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"met": true, "points": 1, "max": 1, "evidence": "ok"}' "$result")

    local finalized
    finalized=$(finalize_eval_result "$result")

    if validate_eval_schema "$finalized"; then
        pass "Finalized binary result passes schema validation"
    else
        fail "Finalized binary result should pass schema validation"
    fi
}

test_finalize_perfect_score_no_improvements() {
    local result='{}'
    result=$(aggregate_criterion_results "plan_mode_outline" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "plan_mode_tool" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_ran" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "tdd_green_pass" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "self_review" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")
    result=$(aggregate_criterion_results "clean_code" '{"met": true, "points": 1, "max": 1, "evidence": "good"}' "$result")

    local finalized
    finalized=$(finalize_eval_result "$result")

    local improvement_count
    improvement_count=$(echo "$finalized" | jq '.improvements | length')
    if [ "$improvement_count" -eq 0 ]; then
        pass "Perfect score produces no improvements"
    else
        fail "Perfect score should produce 0 improvements, got $improvement_count"
    fi
}

# -----------------------------------------------
# Run all tests
# -----------------------------------------------

test_prompt_version_v4
test_criteria_list_standard
test_criteria_list_ui
test_criteria_names_standard
test_criteria_names_ui
test_all_criteria_max_1
test_total_llm_max_standard
test_total_llm_max_ui
test_prompt_asks_yes_no
test_prompt_requests_met_field
test_prompt_no_partial_credit
test_prompt_has_criterion_name
test_prompt_includes_scenario
test_prompt_includes_output
test_prompt_requests_json
test_design_system_prompt_exists
test_aggregate_binary_met_true
test_aggregate_binary_met_false
test_aggregate_all_binary_criteria
test_aggregate_preserves_evidence
test_finalize_adds_summary
test_finalize_validates_schema
test_finalize_perfect_score_no_improvements

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All binary eval tests passed!"
