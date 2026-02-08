#!/bin/bash
# Test deterministic pre-checks for SDLC evaluation
#
# Tests the grep-based checks that run BEFORE the LLM judge,
# providing free, reproducible scoring for objective criteria.
#
# Criteria checked deterministically:
#   - task_tracking: TodoWrite or TaskCreate usage (1 pt)
#   - confidence: HIGH/MEDIUM/LOW stated (1 pt)
#   - tdd_red: test file written before implementation (2 pt)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/deterministic-checks.sh"

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

echo "=== Deterministic Pre-Check Tests ==="
echo ""

# -----------------------------------------------
# check_task_tracking tests
# -----------------------------------------------

echo "--- check_task_tracking ---"

test_task_tracking_with_todowrite() {
    local output="I'll create a task list.
TodoWrite: Add validation function
Now let me start implementing..."
    local result
    result=$(check_task_tracking "$output")
    if [ "$result" = "1" ]; then
        pass "TodoWrite detected"
    else
        fail "TodoWrite should score 1, got $result"
    fi
}

test_task_tracking_with_taskcreate() {
    local output="Let me track this work.
Using TaskCreate to organize.
Starting implementation."
    local result
    result=$(check_task_tracking "$output")
    if [ "$result" = "1" ]; then
        pass "TaskCreate detected"
    else
        fail "TaskCreate should score 1, got $result"
    fi
}

test_task_tracking_missing() {
    local output="Let me just start coding.
I'll add a function to validate emails.
Done!"
    local result
    result=$(check_task_tracking "$output")
    if [ "$result" = "0" ]; then
        pass "No task tracking detected"
    else
        fail "Missing task tracking should score 0, got $result"
    fi
}

test_task_tracking_case_sensitive() {
    local output="I used todowrite to track things."
    local result
    result=$(check_task_tracking "$output")
    if [ "$result" = "0" ]; then
        pass "Case-sensitive: todowrite (lowercase) not matched"
    else
        fail "todowrite (lowercase) should not match, got $result"
    fi
}

# -----------------------------------------------
# check_confidence tests
# -----------------------------------------------

echo ""
echo "--- check_confidence ---"

test_confidence_high() {
    local output="Confidence: HIGH
I'm very confident in this approach."
    local result
    result=$(check_confidence "$output")
    if [ "$result" = "1" ]; then
        pass "HIGH confidence detected"
    else
        fail "HIGH confidence should score 1, got $result"
    fi
}

test_confidence_medium() {
    local output="I'd rate my confidence as MEDIUM for this task."
    local result
    result=$(check_confidence "$output")
    if [ "$result" = "1" ]; then
        pass "MEDIUM confidence detected"
    else
        fail "MEDIUM confidence should score 1, got $result"
    fi
}

test_confidence_low() {
    local output="Confidence: LOW - this is a complex area."
    local result
    result=$(check_confidence "$output")
    if [ "$result" = "1" ]; then
        pass "LOW confidence detected"
    else
        fail "LOW confidence should score 1, got $result"
    fi
}

test_confidence_missing() {
    local output="Let me start coding right away.
This should be straightforward."
    local result
    result=$(check_confidence "$output")
    if [ "$result" = "0" ]; then
        pass "No confidence statement detected"
    else
        fail "Missing confidence should score 0, got $result"
    fi
}

test_confidence_lowercase_ignored() {
    local output="I have high confidence in this."
    local result
    result=$(check_confidence "$output")
    if [ "$result" = "0" ]; then
        pass "Lowercase 'high' not matched (requires uppercase)"
    else
        fail "lowercase 'high' should not match, got $result"
    fi
}

# -----------------------------------------------
# check_tdd_red tests
# -----------------------------------------------

echo ""
echo "--- check_tdd_red ---"

test_tdd_red_test_before_impl() {
    local output="First I'll write the test.
Write file: tests/validate.test.js
Now let me run the test to see it fail.
FAIL: validateEmail is not defined
Now I'll implement the function.
Write file: src/validate.js"
    local result
    result=$(check_tdd_red "$output")
    if [ "$result" = "2" ]; then
        pass "TDD RED: test file before implementation file"
    else
        fail "TDD RED should score 2, got $result"
    fi
}

test_tdd_red_impl_before_test() {
    local output="Let me implement the function first.
Write file: src/validate.js
Now I'll add a test.
Write file: tests/validate.test.js"
    local result
    result=$(check_tdd_red "$output")
    if [ "$result" = "0" ]; then
        pass "TDD RED: implementation before test scores 0"
    else
        fail "Impl before test should score 0, got $result"
    fi
}

test_tdd_red_no_test_file() {
    local output="Let me implement the function.
Write file: src/validate.js
Done! The function works."
    local result
    result=$(check_tdd_red "$output")
    if [ "$result" = "0" ]; then
        pass "TDD RED: no test file at all scores 0"
    else
        fail "No test file should score 0, got $result"
    fi
}

test_tdd_red_edit_test_before_edit_impl() {
    local output="Let me add a test first.
Edit file: tests/app.test.js
Now run the test... it fails.
Edit file: src/app.js"
    local result
    result=$(check_tdd_red "$output")
    if [ "$result" = "2" ]; then
        pass "TDD RED: Edit test before Edit impl detected"
    else
        fail "Edit test before Edit impl should score 2, got $result"
    fi
}

test_tdd_red_spec_file() {
    local output="Writing the spec first.
Write file: spec/validate.spec.ts
Now implement.
Write file: src/validate.ts"
    local result
    result=$(check_tdd_red "$output")
    if [ "$result" = "2" ]; then
        pass "TDD RED: .spec file detected as test"
    else
        fail ".spec file should be detected as test, got $result"
    fi
}

# -----------------------------------------------
# run_deterministic_checks integration tests
# -----------------------------------------------

echo ""
echo "--- run_deterministic_checks (integration) ---"

test_full_compliance() {
    local output="TaskCreate: Add email validation
Confidence: HIGH

First, write the test:
Write file: tests/validate.test.js
Run tests... FAIL
Now implement:
Write file: src/validate.js
Run tests... PASS"
    local result
    result=$(run_deterministic_checks "$output")

    local task_score confidence_score tdd_score total
    task_score=$(echo "$result" | jq -r '.task_tracking.points')
    confidence_score=$(echo "$result" | jq -r '.confidence.points')
    tdd_score=$(echo "$result" | jq -r '.tdd_red.points')
    total=$(echo "$result" | jq -r '.total')

    if [ "$task_score" = "1" ] && [ "$confidence_score" = "1" ] && [ "$tdd_score" = "2" ] && [ "$total" = "4" ]; then
        pass "Full compliance: task=1, confidence=1, tdd=2, total=4"
    else
        fail "Full compliance expected 1,1,2,4 got $task_score,$confidence_score,$tdd_score,$total"
    fi
}

test_zero_compliance() {
    local output="Let me just code this up quickly.
Write file: src/validate.js
Done, it works."
    local result
    result=$(run_deterministic_checks "$output")

    local total
    total=$(echo "$result" | jq -r '.total')

    if [ "$total" = "0" ]; then
        pass "Zero compliance: total=0"
    else
        fail "Zero compliance expected total=0, got $total"
    fi
}

test_partial_compliance() {
    local output="TodoWrite: Add feature
Let me start coding.
Write file: src/validate.js
Write file: tests/validate.test.js"
    local result
    result=$(run_deterministic_checks "$output")

    local task_score confidence_score tdd_score total
    task_score=$(echo "$result" | jq -r '.task_tracking.points')
    confidence_score=$(echo "$result" | jq -r '.confidence.points')
    tdd_score=$(echo "$result" | jq -r '.tdd_red.points')
    total=$(echo "$result" | jq -r '.total')

    if [ "$task_score" = "1" ] && [ "$confidence_score" = "0" ] && [ "$tdd_score" = "0" ] && [ "$total" = "1" ]; then
        pass "Partial compliance: task=1, confidence=0, tdd=0, total=1"
    else
        fail "Partial expected 1,0,0,1 got $task_score,$confidence_score,$tdd_score,$total"
    fi
}

test_json_structure() {
    local output="TaskCreate: something
Confidence: MEDIUM"
    local result
    result=$(run_deterministic_checks "$output")

    # Validate JSON structure has all expected fields
    local has_task has_conf has_tdd has_total has_max
    has_task=$(echo "$result" | jq -r 'has("task_tracking")')
    has_conf=$(echo "$result" | jq -r 'has("confidence")')
    has_tdd=$(echo "$result" | jq -r 'has("tdd_red")')
    has_total=$(echo "$result" | jq -r 'has("total")')
    has_max=$(echo "$result" | jq -r 'has("max")')

    if [ "$has_task" = "true" ] && [ "$has_conf" = "true" ] && [ "$has_tdd" = "true" ] && [ "$has_total" = "true" ] && [ "$has_max" = "true" ]; then
        pass "JSON structure has all required fields"
    else
        fail "Missing fields: task=$has_task conf=$has_conf tdd=$has_tdd total=$has_total max=$has_max"
    fi
}

test_max_score() {
    local output="anything"
    local result
    result=$(run_deterministic_checks "$output")

    local max
    max=$(echo "$result" | jq -r '.max')

    if [ "$max" = "4" ]; then
        pass "Max deterministic score is 4"
    else
        fail "Max should be 4, got $max"
    fi
}

test_evidence_fields() {
    local output="TodoWrite: Track work
Confidence: HIGH"
    local result
    result=$(run_deterministic_checks "$output")

    local task_evidence conf_evidence
    task_evidence=$(echo "$result" | jq -r '.task_tracking.evidence')
    conf_evidence=$(echo "$result" | jq -r '.confidence.evidence')

    if [ "$task_evidence" != "null" ] && [ "$task_evidence" != "" ] && \
       [ "$conf_evidence" != "null" ] && [ "$conf_evidence" != "" ]; then
        pass "Evidence fields populated for matched criteria"
    else
        fail "Evidence fields should be populated: task='$task_evidence' conf='$conf_evidence'"
    fi
}

# Run all tests
test_task_tracking_with_todowrite
test_task_tracking_with_taskcreate
test_task_tracking_missing
test_task_tracking_case_sensitive

test_confidence_high
test_confidence_medium
test_confidence_low
test_confidence_missing
test_confidence_lowercase_ignored

test_tdd_red_test_before_impl
test_tdd_red_impl_before_test
test_tdd_red_no_test_file
test_tdd_red_edit_test_before_edit_impl
test_tdd_red_spec_file

test_full_compliance
test_zero_compliance
test_partial_compliance
test_json_structure
test_max_score
test_evidence_fields

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All deterministic pre-check tests passed!"
