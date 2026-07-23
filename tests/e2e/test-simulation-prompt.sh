#!/bin/bash
# Test simulation prompt requirements in ci.yml
#
# Verifies that the CI simulation prompts instruct Claude to use
# scoreable SDLC practices, and that supporting infrastructure
# (output limits, fixture size) is adequate.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
EVALUATE_FILE="$SCRIPT_DIR/evaluate.sh"
FIXTURE_DIR="$SCRIPT_DIR/fixtures/test-repo"

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

echo "=== Simulation Prompt Requirements Tests ==="
echo ""

# -----------------------------------------------
# Prompt content tests (check ci.yml prompts)
# -----------------------------------------------

echo "--- Prompt instructs scoreable SDLC criteria ---"

test_prompt_mentions_task_tracking() { pass "test_prompt_mentions_task_tracking n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_mentions_confidence() { pass "test_prompt_mentions_confidence n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_mentions_tdd() { pass "test_prompt_mentions_tdd n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_mentions_plan_mode() { pass "test_prompt_mentions_plan_mode n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_mentions_self_review() { pass "test_prompt_mentions_self_review n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_self_review_explains_how() { pass "test_prompt_self_review_explains_how n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_prompt_self_review_marked_scored() { pass "test_prompt_self_review_marked_scored n/a per #212 Option 1 (ci.yml prompt removed; shepherd prompt verified in test-local-shepherd.sh::test_shepherd_prompt_has_required_signatures)"; }

test_all_structured_simulation_prompts_have_self_review() {
    # Every individual prompt block in workflows with structured prompts must have
    # self-review in both STEPS and IMPORTANT. Counts occurrences to ensure each
    # prompt block is individually covered (ci.yml has 4 blocks, benchmark has 1).
    local missing=""
    for wf in "$REPO_ROOT"/.github/workflows/*.yml; do
        [ ! -f "$wf" ] && continue
        grep -q 'STEPS:' "$wf" || continue
        grep -q 'IMPORTANT:' "$wf" || continue
        local basename
        basename=$(basename "$wf")
        # Count prompt blocks (each "STEPS:" starts a new prompt)
        local prompt_count step_review_count important_review_count
        prompt_count=$(grep -c 'STEPS:' "$wf")
        # Count self-review in step 7 (Read back files)
        step_review_count=$(grep -ciE 'Self-review:.*Read.*back.*files|Read.*back.*files.*modified|Read.*files.*modified' "$wf")
        # Count self-review in IMPORTANT (MUST + scored)
        important_review_count=$(grep -ciE 'MUST self.review.*scored|self.review.*MUST.*scored' "$wf")
        if [ "$step_review_count" -lt "$prompt_count" ]; then
            missing="$missing $basename(STEPS:$step_review_count/$prompt_count)"
        fi
        if [ "$important_review_count" -lt "$prompt_count" ]; then
            missing="$missing $basename(IMPORTANT:$important_review_count/$prompt_count)"
        fi
    done
    if [ -z "$missing" ]; then
        pass "All structured simulation prompts have self-review in STEPS + IMPORTANT"
    else
        fail "Missing self-review in structured simulation prompts:$missing"
    fi
}

# -----------------------------------------------
# Infrastructure tests
# -----------------------------------------------

echo ""
echo "--- Infrastructure adequacy ---"

test_output_limit_adequate() {
    # evaluate.sh should not truncate at 50KB - need at least 100KB
    local limit
    limit=$(grep -o 'head -c [0-9]*' "$EVALUATE_FILE" | head -1 | grep -o '[0-9]*')
    if [ -n "$limit" ] && [ "$limit" -ge 100000 ]; then
        pass "Output limit is >= 100KB (${limit} bytes)"
    else
        fail "Output limit should be >= 100KB, got ${limit:-unknown} bytes"
    fi
}

test_fixture_app_size() {
    local app_file="$FIXTURE_DIR/src/app.js"
    if [ ! -f "$app_file" ]; then
        fail "Fixture app.js not found at $app_file"
        return
    fi
    local line_count
    line_count=$(wc -l < "$app_file" | tr -d ' ')
    if [ "$line_count" -ge 40 ]; then
        pass "Fixture app.js has >= 40 lines ($line_count lines)"
    else
        fail "Fixture app.js should have >= 40 lines, has $line_count"
    fi
}

test_fixture_has_multiple_source_files() {
    local src_count
    src_count=$(find "$FIXTURE_DIR/src" -name "*.js" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$src_count" -ge 2 ]; then
        pass "Fixture has >= 2 source files ($src_count files)"
    else
        fail "Fixture should have >= 2 source files, has $src_count"
    fi
}

test_evaluate_has_no_curl_transport() {
    # The curl-based transport (and its -d @file argument-length mitigation)
    # was deleted 2026-07-21 — evaluate.sh's only judge transport is now
    # `claude --print`, which takes the prompt directly (not via curl at all).
    #
    # Codex round 1 P2 API-005: `^\s*curl` only matches curl as the line's
    # first token, missing forms like `response=$(curl ...)`. Match `curl`
    # as a word anywhere on a non-comment line instead (same pattern as
    # tests/test-evaluate-cli-mode.sh's equivalent check).
    if grep -E '\bcurl\b' "$EVALUATE_FILE" | grep -qvE '^\s*#'; then
        fail "evaluate.sh has curl invocations — the curl transport should stay deleted"
    else
        pass "evaluate.sh has no curl transport (claude --print only, #228)"
    fi
}

# Run all tests
test_prompt_mentions_task_tracking
test_prompt_mentions_confidence
test_prompt_mentions_tdd
test_prompt_mentions_plan_mode
test_prompt_mentions_self_review
test_prompt_self_review_explains_how
test_prompt_self_review_marked_scored
test_all_structured_simulation_prompts_have_self_review
test_output_limit_adequate
test_fixture_app_size
test_fixture_has_multiple_source_files
test_evaluate_has_no_curl_transport

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All simulation prompt tests passed!"
