#!/bin/bash
# Tests for score-analytics.sh
#
# Validates analytics output for various history states:
# empty, single entry, multiple entries, trends, per-criterion

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ANALYTICS="$REPO_ROOT/tests/e2e/score-analytics.sh"

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

echo "=== Score Analytics Tests ==="
echo ""

# Create temp directory for test history files
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# --- Test 1: Script exists and is executable ---
test_script_exists() {
    if [ -x "$ANALYTICS" ]; then
        pass "score-analytics.sh exists and is executable"
    else
        fail "score-analytics.sh not found or not executable"
    fi
}

# --- Test 2: Empty history file — graceful output, no crash ---
test_empty_history() {
    local empty_file="$TMPDIR/empty.jsonl"
    touch "$empty_file"
    local output
    output=$("$ANALYTICS" --history "$empty_file" 2>&1) || true
    if echo "$output" | grep -qi "no.*data\|no.*history\|no.*entries\|empty\|0 entries"; then
        pass "Empty history: graceful message"
    else
        fail "Empty history: expected 'no data' message, got: $output"
    fi
}

# --- Test 3: Single entry — shows data without crashing ---
test_single_entry() {
    local single_file="$TMPDIR/single.jsonl"
    cat > "$single_file" << 'ENTRY'
{"timestamp":"2026-02-10T10:00:00Z","scenario":"add-feature","score":7.0,"max_score":10,"criteria":{"task_tracking":{"points":1,"max":1},"confidence":{"points":1,"max":1},"plan_mode_outline":{"points":1,"max":1},"plan_mode_tool":{"points":1,"max":1},"tdd_red":{"points":1,"max":2},"tdd_green_ran":{"points":1,"max":1},"tdd_green_pass":{"points":0,"max":1},"self_review":{"points":1,"max":1},"clean_code":{"points":0,"max":1}}}
ENTRY
    local output
    output=$("$ANALYTICS" --history "$single_file" 2>&1)
    if echo "$output" | grep -q "7.0\|7"; then
        pass "Single entry: shows score data"
    else
        fail "Single entry: expected score in output, got: $output"
    fi
}

# --- Test 4: Multiple entries — shows overall average ---
test_multiple_entries_average() {
    local multi_file="$TMPDIR/multi.jsonl"
    cat > "$multi_file" << 'ENTRIES'
{"timestamp":"2026-02-08T10:00:00Z","scenario":"add-feature","score":6.0,"max_score":10,"criteria":{"task_tracking":{"points":1,"max":1},"confidence":{"points":1,"max":1},"plan_mode_outline":{"points":1,"max":1},"plan_mode_tool":{"points":0,"max":1},"tdd_red":{"points":1,"max":2},"tdd_green_ran":{"points":1,"max":1},"tdd_green_pass":{"points":0,"max":1},"self_review":{"points":1,"max":1},"clean_code":{"points":0,"max":1}}}
{"timestamp":"2026-02-09T10:00:00Z","scenario":"fix-bug","score":8.0,"max_score":10,"criteria":{"task_tracking":{"points":1,"max":1},"confidence":{"points":1,"max":1},"plan_mode_outline":{"points":1,"max":1},"plan_mode_tool":{"points":1,"max":1},"tdd_red":{"points":2,"max":2},"tdd_green_ran":{"points":1,"max":1},"tdd_green_pass":{"points":0,"max":1},"self_review":{"points":1,"max":1},"clean_code":{"points":0,"max":1}}}
{"timestamp":"2026-02-10T10:00:00Z","scenario":"refactor","score":7.0,"max_score":10,"criteria":{"task_tracking":{"points":1,"max":1},"confidence":{"points":1,"max":1},"plan_mode_outline":{"points":1,"max":1},"plan_mode_tool":{"points":1,"max":1},"tdd_red":{"points":1,"max":2},"tdd_green_ran":{"points":1,"max":1},"tdd_green_pass":{"points":0,"max":1},"self_review":{"points":1,"max":1},"clean_code":{"points":0,"max":1}}}
ENTRIES
    local output
    output=$("$ANALYTICS" --history "$multi_file" 2>&1)
    # Average of 6+8+7 = 21/3 = 7.0
    if echo "$output" | grep -q "7.0\|7\.0"; then
        pass "Multiple entries: shows overall average (7.0)"
    else
        fail "Multiple entries: expected average 7.0, got: $output"
    fi
}

# --- Test 5: Per-criterion breakdown appears ---
test_criterion_breakdown() {
    local multi_file="$TMPDIR/multi.jsonl"
    # Reuse file from test 4
    local output
    output=$("$ANALYTICS" --history "$multi_file" 2>&1)
    if echo "$output" | grep -qi "plan_mode\|tdd_red\|confidence\|criterion\|criteria"; then
        pass "Multiple entries: shows per-criterion breakdown"
    else
        fail "Multiple entries: expected criterion names in output, got: $output"
    fi
}

# --- Test 6: Scenario difficulty ranking ---
test_scenario_ranking() {
    local multi_file="$TMPDIR/multi.jsonl"
    local output
    output=$("$ANALYTICS" --history "$multi_file" 2>&1)
    if echo "$output" | grep -qi "scenario\|difficulty\|ranking\|add-feature\|fix-bug\|refactor"; then
        pass "Multiple entries: shows scenario information"
    else
        fail "Multiple entries: expected scenario names in output, got: $output"
    fi
}

# --- Test 7: --report flag generates markdown ---
test_report_flag() {
    local multi_file="$TMPDIR/multi.jsonl"
    local output
    output=$("$ANALYTICS" --history "$multi_file" --report 2>&1)
    if echo "$output" | grep -q "^#\|^|"; then
        pass "--report flag: generates markdown (headers or tables)"
    else
        fail "--report flag: expected markdown output, got: ${output:0:200}"
    fi
}

# --- Test 8: Trend calculation with enough data ---
test_trend_calculation() {
    local trend_file="$TMPDIR/trend.jsonl"
    # Create 10 entries with improving scores
    for i in $(seq 1 10); do
        score=$(echo "5.0 + $i * 0.3" | bc -l)
        printf '{"timestamp":"2026-02-%02dT10:00:00Z","scenario":"add-feature","score":%s,"max_score":10,"criteria":{"task_tracking":{"points":1,"max":1},"confidence":{"points":1,"max":1},"plan_mode_outline":{"points":1,"max":1},"plan_mode_tool":{"points":0,"max":1},"tdd_red":{"points":1,"max":2},"tdd_green_ran":{"points":1,"max":1},"tdd_green_pass":{"points":0,"max":1},"self_review":{"points":1,"max":1},"clean_code":{"points":0,"max":1}}}\n' "$i" "$score" >> "$trend_file"
    done
    local output
    output=$("$ANALYTICS" --history "$trend_file" 2>&1)
    if echo "$output" | grep -qi "trend\|improving\|declining\|stable\|direction"; then
        pass "Trend: shows trend information with sufficient data"
    else
        fail "Trend: expected trend info, got: $output"
    fi
}

# --- Test 9: Handles malformed JSON lines gracefully ---
test_malformed_json() {
    local bad_file="$TMPDIR/bad.jsonl"
    echo "not json at all" > "$bad_file"
    echo '{"timestamp":"2026-02-10T10:00:00Z","scenario":"add-feature","score":7.0,"max_score":10,"criteria":{}}' >> "$bad_file"
    local output exit_code=0
    output=$("$ANALYTICS" --history "$bad_file" 2>&1) || exit_code=$?
    # Should not crash — either skip bad lines or warn
    if [ $exit_code -eq 0 ] || echo "$output" | grep -qi "skip\|warn\|ignore\|error\|1 entries\|1 valid"; then
        pass "Malformed JSON: handled gracefully (no crash)"
    else
        fail "Malformed JSON: crashed with exit $exit_code"
    fi
}

# --- Test 10: Report output includes last-updated timestamp ---
test_report_timestamp() {
    local multi_file="$TMPDIR/multi.jsonl"
    local output
    output=$("$ANALYTICS" --history "$multi_file" --report 2>&1)
    if echo "$output" | grep -qi "updated\|generated\|date\|202[0-9]"; then
        pass "--report: includes timestamp/date"
    else
        fail "--report: expected date/timestamp in output, got: ${output:0:200}"
    fi
}

# --- Test 11: Score distribution appears in output ---
test_score_distribution() {
    local trend_file="$TMPDIR/trend.jsonl"
    # Reuse file from test 8
    local output
    output=$("$ANALYTICS" --history "$trend_file" 2>&1)
    if echo "$output" | grep -qi "distribution\|range\|min\|max\|median\|histogram"; then
        pass "Shows score distribution information"
    else
        fail "Expected distribution info, got: $output"
    fi
}

# --- Test 12: Weakest criterion identification ---
test_weakest_criterion() {
    local multi_file="$TMPDIR/multi.jsonl"
    local output
    output=$("$ANALYTICS" --history "$multi_file" 2>&1)
    # clean_code has 0/1 in all entries — should be identified as weakest
    if echo "$output" | grep -qi "weak\|lowest\|clean_code\|improve"; then
        pass "Identifies weakest criterion"
    else
        fail "Expected weakest criterion identification, got: $output"
    fi
}

# Run all tests
test_script_exists
test_empty_history
test_single_entry
test_multiple_entries_average
test_criterion_breakdown
test_scenario_ranking
test_report_flag
test_trend_calculation
test_malformed_json
test_report_timestamp
test_score_distribution
test_weakest_criterion

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All score analytics tests passed!"
