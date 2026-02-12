#!/bin/bash
# Eval prompt regression test — golden output validation
#
# Runs the eval pipeline against saved "golden outputs" (execution outputs
# with manually verified expected score ranges). Asserts that scores fall
# within tolerance to catch prompt drift (judge becoming too lenient/strict).
#
# Two modes:
#   1. Deterministic-only (no API key): Validates deterministic scores match
#   2. Full eval (with API key): Also validates LLM scores within tolerance
#
# Usage:
#   ./test-eval-prompt-regression.sh              # Deterministic checks only
#   ANTHROPIC_API_KEY=sk-... ./test-eval-prompt-regression.sh  # Full eval
#
# Golden outputs: tests/e2e/golden-outputs/*.txt
# Expected scores: tests/e2e/golden-scores.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/json-utils.sh"
source "$SCRIPT_DIR/lib/deterministic-checks.sh"
source "$SCRIPT_DIR/lib/eval-validation.sh"
source "$SCRIPT_DIR/lib/eval-criteria.sh"

GOLDEN_DIR="$SCRIPT_DIR/golden-outputs"
SCORES_FILE="$SCRIPT_DIR/golden-scores.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
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

echo "=== Eval Prompt Regression Tests ==="
echo ""

# -----------------------------------------------
# Validate test fixtures exist
# -----------------------------------------------

echo "--- Fixture validation ---"

test_golden_dir_exists() {
    if [ -d "$GOLDEN_DIR" ]; then
        pass "Golden outputs directory exists"
    else
        fail "Golden outputs directory not found: $GOLDEN_DIR"
    fi
}

test_scores_file_exists() {
    if [ -f "$SCORES_FILE" ]; then
        pass "Golden scores file exists"
    else
        fail "Golden scores file not found: $SCORES_FILE"
    fi
}

test_scores_file_valid_json() {
    if jq -e '.' "$SCORES_FILE" > /dev/null 2>&1; then
        pass "Golden scores file is valid JSON"
    else
        fail "Golden scores file is not valid JSON"
    fi
}

test_golden_outputs_exist() {
    local count
    count=$(ls "$GOLDEN_DIR"/*.txt 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -ge 3 ]; then
        pass "At least 3 golden output files exist ($count found)"
    else
        fail "Expected at least 3 golden output files, found $count"
    fi
}

test_golden_scores_match_outputs() {
    local mismatches=""
    for golden_file in "$GOLDEN_DIR"/*.txt; do
        local name
        name=$(basename "$golden_file" .txt)
        if ! jq -e --arg name "$name" 'has($name)' "$SCORES_FILE" > /dev/null 2>&1; then
            mismatches="$mismatches $name"
        fi
    done
    if [ -z "$mismatches" ]; then
        pass "All golden outputs have matching score entries"
    else
        fail "Missing score entries for:$mismatches"
    fi
}

# -----------------------------------------------
# Deterministic score validation (no API key needed)
# -----------------------------------------------

echo ""
echo "--- Deterministic score validation ---"

test_deterministic_scores() {
    local golden_name="$1"
    local golden_file="$GOLDEN_DIR/${golden_name}.txt"

    if [ ! -f "$golden_file" ]; then
        fail "$golden_name: golden output file not found"
        return
    fi

    local output_content
    output_content=$(cat "$golden_file")

    # Run deterministic checks
    local det_result
    det_result=$(run_deterministic_checks "$output_content")

    # Get expected deterministic scores
    local expected_task expected_confidence expected_tdd
    expected_task=$(jq -r --arg name "$golden_name" '.[$name].deterministic.task_tracking' "$SCORES_FILE")
    expected_confidence=$(jq -r --arg name "$golden_name" '.[$name].deterministic.confidence' "$SCORES_FILE")
    expected_tdd=$(jq -r --arg name "$golden_name" '.[$name].deterministic.tdd_red' "$SCORES_FILE")

    # Get actual scores
    local actual_task actual_confidence actual_tdd
    actual_task=$(echo "$det_result" | jq -r '.task_tracking.points')
    actual_confidence=$(echo "$det_result" | jq -r '.confidence.points')
    actual_tdd=$(echo "$det_result" | jq -r '.tdd_red.points')

    # Compare
    local all_match=true
    if [ "$actual_task" != "$expected_task" ]; then
        fail "$golden_name: task_tracking expected=$expected_task actual=$actual_task"
        all_match=false
    fi
    if [ "$actual_confidence" != "$expected_confidence" ]; then
        fail "$golden_name: confidence expected=$expected_confidence actual=$actual_confidence"
        all_match=false
    fi
    if [ "$actual_tdd" != "$expected_tdd" ]; then
        fail "$golden_name: tdd_red expected=$expected_tdd actual=$actual_tdd"
        all_match=false
    fi

    if [ "$all_match" = true ]; then
        pass "$golden_name: deterministic scores match (task=$actual_task conf=$actual_confidence tdd=$actual_tdd)"
    fi
}

# -----------------------------------------------
# Full eval regression (requires API key)
# -----------------------------------------------

run_full_eval_regression() {
    echo ""
    echo "--- Full eval regression (API-backed) ---"

    for golden_file in "$GOLDEN_DIR"/*.txt; do
        local golden_name
        golden_name=$(basename "$golden_file" .txt)

        local scenario_name
        scenario_name=$(jq -r --arg name "$golden_name" '.[$name].scenario' "$SCORES_FILE")
        local scenario_file="$SCRIPT_DIR/scenarios/${scenario_name}.md"

        if [ ! -f "$scenario_file" ]; then
            fail "$golden_name: scenario file not found: $scenario_file"
            continue
        fi

        echo "Evaluating $golden_name (scenario: $scenario_name)..." >&2

        # Run full evaluation
        local eval_output
        eval_output=$("$SCRIPT_DIR/evaluate.sh" "$scenario_file" "$golden_file" --json 2>/dev/null) || true

        if [ -z "$eval_output" ] || ! is_valid_json "$eval_output"; then
            fail "$golden_name: evaluation produced no valid JSON output"
            continue
        fi

        local total_score
        total_score=$(echo "$eval_output" | jq '.score')

        # Check total score within expected range
        local expected_min expected_max
        expected_min=$(jq --arg name "$golden_name" '.[$name].expected_total.min' "$SCORES_FILE")
        expected_max=$(jq --arg name "$golden_name" '.[$name].expected_total.max' "$SCORES_FILE")

        if echo "$total_score $expected_min $expected_max" | awk '{exit !($1 >= $2 && $1 <= $3)}'; then
            pass "$golden_name: total score $total_score within [$expected_min, $expected_max]"
        else
            fail "$golden_name: total score $total_score outside expected [$expected_min, $expected_max]"
        fi

        # Check individual LLM criterion scores
        local criteria_names
        criteria_names=$(jq -r --arg name "$golden_name" '.[$name].expected_llm | keys[]' "$SCORES_FILE")
        for crit in $criteria_names; do
            local crit_pts crit_min crit_max
            crit_pts=$(echo "$eval_output" | jq --arg c "$crit" '.criteria[$c].points // -1')
            crit_min=$(jq --arg name "$golden_name" --arg c "$crit" '.[$name].expected_llm[$c].min' "$SCORES_FILE")
            crit_max=$(jq --arg name "$golden_name" --arg c "$crit" '.[$name].expected_llm[$c].max' "$SCORES_FILE")

            if echo "$crit_pts $crit_min $crit_max" | awk '{exit !($1 >= $2 && $1 <= $3)}'; then
                pass "$golden_name.$crit: $crit_pts within [$crit_min, $crit_max]"
            else
                fail "$golden_name.$crit: $crit_pts outside expected [$crit_min, $crit_max]"
            fi
        done
    done
}

# -----------------------------------------------
# Run tests
# -----------------------------------------------

test_golden_dir_exists
test_scores_file_exists
test_scores_file_valid_json
test_golden_outputs_exist
test_golden_scores_match_outputs

# Deterministic validation for each golden output
for golden_file in "$GOLDEN_DIR"/*.txt; do
    golden_name=$(basename "$golden_file" .txt)
    test_deterministic_scores "$golden_name"
done

# Full eval only if API key is available
if [ -n "$ANTHROPIC_API_KEY" ]; then
    run_full_eval_regression
else
    echo ""
    echo -e "${YELLOW}SKIP${NC}: Full eval regression requires ANTHROPIC_API_KEY"
    echo "  Set ANTHROPIC_API_KEY to run API-backed regression tests"
fi

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All eval prompt regression tests passed!"
