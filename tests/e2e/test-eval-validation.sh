#!/bin/bash
# Test eval pipeline validation: schema checks, bounds checks, prompt versioning
#
# Tests the hardening functions added to evaluate.sh:
#   - validate_eval_schema: required JSON fields exist with correct types
#   - validate_criteria_bounds: 0 <= points <= max for every criterion
#   - validate_max_total: sum of .max equals expected total (10 or 11)
#
# These functions are in lib/eval-validation.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/eval-validation.sh"

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

# -----------------------------------------------
# Shared test fixtures
# -----------------------------------------------

VALID_STANDARD='{
    "criteria": {
        "plan_mode_outline": {"points": 1, "max": 1, "evidence": "Outlined steps"},
        "plan_mode_tool": {"points": 1, "max": 1, "evidence": "Used plan mode tool"},
        "tdd_green_ran": {"points": 1, "max": 1, "evidence": "Tests ran"},
        "tdd_green_pass": {"points": 0, "max": 1, "evidence": "Tests not all passing"},
        "self_review": {"points": 1, "max": 1, "evidence": "Reviewed"},
        "clean_code": {"points": 1, "max": 1, "evidence": "Clean"}
    },
    "summary": "Good SDLC compliance.",
    "improvements": ["Run tests earlier"]
}'

VALID_UI='{
    "criteria": {
        "plan_mode_outline": {"points": 1, "max": 1, "evidence": "Outlined steps"},
        "plan_mode_tool": {"points": 1, "max": 1, "evidence": "Used plan mode tool"},
        "tdd_green_ran": {"points": 1, "max": 1, "evidence": "Tests ran"},
        "tdd_green_pass": {"points": 1, "max": 1, "evidence": "Tests pass"},
        "self_review": {"points": 1, "max": 1, "evidence": "Reviewed"},
        "clean_code": {"points": 1, "max": 1, "evidence": "Clean"},
        "design_system": {"points": 1, "max": 1, "evidence": "Checked DESIGN_SYSTEM.md"}
    },
    "summary": "Full UI compliance.",
    "improvements": []
}'

VALID_FULL_STANDARD='{
    "criteria": {
        "plan_mode_outline": {"points": 1, "max": 1, "evidence": "Outlined steps"},
        "plan_mode_tool": {"points": 1, "max": 1, "evidence": "Used plan mode tool"},
        "tdd_green_ran": {"points": 1, "max": 1, "evidence": "Tests ran"},
        "tdd_green_pass": {"points": 0, "max": 1, "evidence": "Tests pass late"},
        "self_review": {"points": 0, "max": 1, "evidence": "Brief"},
        "clean_code": {"points": 1, "max": 1, "evidence": "Clean"},
        "task_tracking": {"points": 1, "max": 1, "evidence": "Found TaskCreate"},
        "confidence": {"points": 1, "max": 1, "evidence": "Stated HIGH"},
        "tdd_red": {"points": 2, "max": 2, "evidence": "Test before impl"}
    },
    "summary": "Good SDLC compliance overall.",
    "improvements": ["Run tests immediately", "More thorough review"]
}'

VALID_FULL_UI='{
    "criteria": {
        "plan_mode_outline": {"points": 1, "max": 1, "evidence": "ok"},
        "plan_mode_tool": {"points": 1, "max": 1, "evidence": "ok"},
        "tdd_green_ran": {"points": 1, "max": 1, "evidence": "ok"},
        "tdd_green_pass": {"points": 1, "max": 1, "evidence": "ok"},
        "self_review": {"points": 1, "max": 1, "evidence": "ok"},
        "clean_code": {"points": 1, "max": 1, "evidence": "ok"},
        "design_system": {"points": 1, "max": 1, "evidence": "ok"},
        "task_tracking": {"points": 1, "max": 1, "evidence": "ok"},
        "confidence": {"points": 1, "max": 1, "evidence": "ok"},
        "tdd_red": {"points": 2, "max": 2, "evidence": "ok"}
    },
    "summary": "Full compliance.",
    "improvements": []
}'

echo "=== Eval Validation Tests ==="
echo ""

# -----------------------------------------------
# validate_eval_schema tests
# -----------------------------------------------

echo "--- validate_eval_schema ---"

test_schema_valid_standard() {
    if validate_eval_schema "$VALID_STANDARD"; then
        pass "Valid standard schema accepted"
    else
        fail "Valid standard schema should be accepted"
    fi
}

test_schema_valid_ui() {
    if validate_eval_schema "$VALID_UI"; then
        pass "Valid UI schema accepted"
    else
        fail "Valid UI schema should be accepted"
    fi
}

test_schema_missing_criteria() {
    local json='{
        "summary": "Missing criteria.",
        "improvements": ["Add criteria"]
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Missing .criteria should be rejected"
    else
        pass "Missing .criteria rejected"
    fi
}

test_schema_missing_summary() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 2, "evidence": "ok"}
        },
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Missing .summary should be rejected"
    else
        pass "Missing .summary rejected"
    fi
}

test_schema_missing_improvements() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 2, "evidence": "ok"}
        },
        "summary": "ok"
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Missing .improvements should be rejected"
    else
        pass "Missing .improvements rejected"
    fi
}

test_schema_improvements_not_array() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 2, "evidence": "ok"}
        },
        "summary": "ok",
        "improvements": "not an array"
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail ".improvements as string should be rejected"
    else
        pass ".improvements as string rejected"
    fi
}

test_schema_criterion_missing_points() {
    local json='{
        "criteria": {
            "plan_mode": {"max": 2, "evidence": "ok"}
        },
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Criterion missing .points should be rejected"
    else
        pass "Criterion missing .points rejected"
    fi
}

test_schema_criterion_missing_max() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "evidence": "ok"}
        },
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Criterion missing .max should be rejected"
    else
        pass "Criterion missing .max rejected"
    fi
}

test_schema_criterion_missing_evidence() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 2}
        },
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Criterion missing .evidence should be rejected"
    else
        pass "Criterion missing .evidence rejected"
    fi
}

test_schema_empty_criteria() {
    local json='{
        "criteria": {},
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Empty .criteria should be rejected"
    else
        pass "Empty .criteria rejected"
    fi
}

# -----------------------------------------------
# validate_criteria_bounds tests
# -----------------------------------------------

echo ""
echo "--- validate_criteria_bounds ---"

test_bounds_valid() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 1, "max": 2, "evidence": "ok"},
            "tdd_green": {"points": 2, "max": 2, "evidence": "ok"},
            "self_review": {"points": 0, "max": 1, "evidence": "none"},
            "clean_code": {"points": 0.5, "max": 1, "evidence": "ok"}
        }
    }'
    if validate_criteria_bounds "$json"; then
        pass "All points within bounds"
    else
        fail "Valid bounds should be accepted"
    fi
}

test_bounds_negative_points() {
    local json='{
        "criteria": {
            "plan_mode": {"points": -1, "max": 2, "evidence": "penalized"}
        }
    }'
    local result
    result=$(validate_criteria_bounds "$json" 2>&1) || true
    if echo "$result" | grep -q "plan_mode"; then
        pass "Negative points detected for plan_mode"
    else
        fail "Negative points should be detected"
    fi
}

test_bounds_exceeds_max() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 3, "max": 2, "evidence": "too generous"}
        }
    }'
    local result
    result=$(validate_criteria_bounds "$json" 2>&1) || true
    if echo "$result" | grep -q "plan_mode"; then
        pass "Points exceeding max detected for plan_mode"
    else
        fail "Points exceeding max should be detected"
    fi
}

test_bounds_exact_max() {
    local json='{
        "criteria": {
            "tdd_red": {"points": 2, "max": 2, "evidence": "full marks"}
        }
    }'
    if validate_criteria_bounds "$json"; then
        pass "Points exactly at max accepted"
    else
        fail "Points exactly at max should be accepted"
    fi
}

test_bounds_zero_points() {
    local json='{
        "criteria": {
            "self_review": {"points": 0, "max": 1, "evidence": "none"}
        }
    }'
    if validate_criteria_bounds "$json"; then
        pass "Zero points accepted"
    else
        fail "Zero points should be accepted"
    fi
}

test_bounds_fractional_valid() {
    local json='{
        "criteria": {
            "self_review": {"points": 0.5, "max": 1, "evidence": "partial"}
        }
    }'
    if validate_criteria_bounds "$json"; then
        pass "Fractional points (0.5/1) accepted"
    else
        fail "Fractional points within range should be accepted"
    fi
}

# -----------------------------------------------
# validate_max_total tests
# -----------------------------------------------

echo ""
echo "--- validate_max_total ---"

test_max_total_standard_valid() {
    if validate_max_total "$VALID_FULL_STANDARD" 10; then
        pass "Standard total (10) accepted"
    else
        fail "Standard total of 10 should be accepted"
    fi
}

test_max_total_ui_valid() {
    if validate_max_total "$VALID_FULL_UI" 11; then
        pass "UI total (11) accepted"
    else
        fail "UI total of 11 should be accepted"
    fi
}

test_max_total_wrong() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 5, "evidence": "inflated"},
            "tdd_green": {"points": 2, "max": 3, "evidence": "inflated"}
        }
    }'
    if validate_max_total "$json" 10 2>/dev/null; then
        fail "Wrong max total should be rejected (sum is 8, expected 10)"
    else
        pass "Wrong max total detected"
    fi
}

# -----------------------------------------------
# clamp_criteria_bounds tests
# -----------------------------------------------

echo ""
echo "--- clamp_criteria_bounds ---"

test_clamp_exceeds_max() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 5, "max": 2, "evidence": "too generous"}
        }
    }'
    local result
    result=$(clamp_criteria_bounds "$json")
    local clamped
    clamped=$(echo "$result" | jq '.criteria.plan_mode.points')
    if [ "$clamped" = "2" ]; then
        pass "Points clamped to max (5 -> 2)"
    else
        fail "Points should be clamped to 2, got $clamped"
    fi
}

test_clamp_negative() {
    local json='{
        "criteria": {
            "self_review": {"points": -1, "max": 1, "evidence": "penalized"}
        }
    }'
    local result
    result=$(clamp_criteria_bounds "$json")
    local clamped
    clamped=$(echo "$result" | jq '.criteria.self_review.points')
    if [ "$clamped" = "0" ]; then
        pass "Negative points clamped to 0 (-1 -> 0)"
    else
        fail "Negative points should be clamped to 0, got $clamped"
    fi
}

test_clamp_valid_unchanged() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 1.5, "max": 2, "evidence": "partial"}
        }
    }'
    local result
    result=$(clamp_criteria_bounds "$json")
    local clamped
    clamped=$(echo "$result" | jq '.criteria.plan_mode.points')
    if [ "$clamped" = "1.5" ]; then
        pass "Valid points unchanged (1.5 stays 1.5)"
    else
        fail "Valid points should be unchanged, got $clamped"
    fi
}

# -----------------------------------------------
# Prompt version tests
# -----------------------------------------------

echo ""
echo "--- prompt versioning ---"

test_prompt_version_defined() {
    # Source evaluate.sh indirectly - check the constant is defined
    # in eval-validation.sh
    if [ -n "$EVAL_PROMPT_VERSION" ]; then
        pass "EVAL_PROMPT_VERSION is defined: $EVAL_PROMPT_VERSION"
    else
        fail "EVAL_PROMPT_VERSION should be defined"
    fi
}

test_prompt_version_format() {
    if echo "$EVAL_PROMPT_VERSION" | grep -qE '^v[0-9]+$'; then
        pass "EVAL_PROMPT_VERSION has correct format: $EVAL_PROMPT_VERSION"
    else
        fail "EVAL_PROMPT_VERSION should match v<N>, got: $EVAL_PROMPT_VERSION"
    fi
}

# -----------------------------------------------
# Integration: full pipeline validation
# -----------------------------------------------

echo ""
echo "--- Integration: validate full eval result ---"

test_valid_full_result() {
    local errors=0

    if ! validate_eval_schema "$VALID_FULL_STANDARD"; then
        echo "  schema validation failed"
        errors=$((errors + 1))
    fi

    if ! validate_criteria_bounds "$VALID_FULL_STANDARD"; then
        echo "  bounds validation failed"
        errors=$((errors + 1))
    fi

    if ! validate_max_total "$VALID_FULL_STANDARD" 10; then
        echo "  max total validation failed"
        errors=$((errors + 1))
    fi

    if [ "$errors" -eq 0 ]; then
        pass "Full valid result passes all validations"
    else
        fail "Full valid result had $errors validation errors"
    fi
}

test_invalid_full_result() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 5, "max": 2, "evidence": "inflated"},
            "tdd_green": {"points": -1, "max": 2, "evidence": "negative"}
        },
        "summary": "Bad result."
    }'
    local errors=0

    # Missing improvements
    if validate_eval_schema "$json" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    # Out of bounds
    if validate_criteria_bounds "$json" 2>/dev/null; then
        errors=$((errors + 1))
    fi

    if [ "$errors" -eq 0 ]; then
        pass "Invalid result correctly caught by validations"
    else
        fail "Invalid result should fail validations ($errors passed unexpectedly)"
    fi
}

# -----------------------------------------------
# Malformed LLM response tests
# -----------------------------------------------

echo ""
echo "--- Malformed LLM response handling ---"

test_malformed_not_json() {
    local raw="This is not JSON at all, just a plain text response from the LLM."
    if validate_eval_schema "$raw" 2>/dev/null; then
        fail "Plain text should be rejected"
    else
        pass "Plain text rejected"
    fi
}

test_malformed_wrong_structure() {
    local json='{"answer": "The score is 8/10", "reasoning": "Good work"}'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Wrong JSON structure should be rejected"
    else
        pass "Wrong JSON structure rejected (no criteria/summary/improvements)"
    fi
}

test_malformed_criteria_as_array() {
    local json='{
        "criteria": [
            {"name": "plan_mode", "points": 2, "max": 2}
        ],
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Criteria as array should be rejected (must be object)"
    else
        pass "Criteria as array rejected"
    fi
}

test_malformed_partial_criteria() {
    local json='{
        "criteria": {
            "plan_mode": {"points": 2, "max": 2, "evidence": "ok"},
            "tdd_green": {"score": 1, "total": 2}
        },
        "summary": "ok",
        "improvements": []
    }'
    if validate_eval_schema "$json" 2>/dev/null; then
        fail "Criteria with wrong field names should be rejected"
    else
        pass "Criteria with wrong field names rejected (score/total instead of points/max/evidence)"
    fi
}

test_malformed_clamped_then_valid() {
    # Simulate: LLM returns out-of-range scores, we clamp, then validate bounds
    local json='{
        "criteria": {
            "plan_mode": {"points": 10, "max": 2, "evidence": "very inflated"},
            "tdd_green": {"points": -5, "max": 2, "evidence": "very negative"},
            "self_review": {"points": 0.5, "max": 1, "evidence": "ok"},
            "clean_code": {"points": 1, "max": 1, "evidence": "ok"}
        },
        "summary": "LLM hallucinated scores.",
        "improvements": ["Be more careful"]
    }'

    # Before clamping, bounds should fail
    if validate_criteria_bounds "$json" 2>/dev/null; then
        fail "Pre-clamp bounds should fail"
        return
    fi

    # After clamping, bounds should pass
    local clamped
    clamped=$(clamp_criteria_bounds "$json" 2>/dev/null)

    if validate_criteria_bounds "$clamped"; then
        # Verify clamped values are correct
        local pm_pts tg_pts
        pm_pts=$(echo "$clamped" | jq '.criteria.plan_mode.points')
        tg_pts=$(echo "$clamped" | jq '.criteria.tdd_green.points')
        if [ "$pm_pts" = "2" ] && [ "$tg_pts" = "0" ]; then
            pass "Malformed scores clamped correctly (10->2, -5->0) and pass bounds"
        else
            fail "Clamped values wrong: plan_mode=$pm_pts (expected 2), tdd_green=$tg_pts (expected 0)"
        fi
    else
        fail "Post-clamp bounds should pass"
    fi
}

# -----------------------------------------------
# Run all tests
# -----------------------------------------------

test_schema_valid_standard
test_schema_valid_ui
test_schema_missing_criteria
test_schema_missing_summary
test_schema_missing_improvements
test_schema_improvements_not_array
test_schema_criterion_missing_points
test_schema_criterion_missing_max
test_schema_criterion_missing_evidence
test_schema_empty_criteria

test_bounds_valid
test_bounds_negative_points
test_bounds_exceeds_max
test_bounds_exact_max
test_bounds_zero_points
test_bounds_fractional_valid

test_max_total_standard_valid
test_max_total_ui_valid
test_max_total_wrong

test_clamp_exceeds_max
test_clamp_negative
test_clamp_valid_unchanged

test_prompt_version_defined
test_prompt_version_format

test_malformed_not_json
test_malformed_wrong_structure
test_malformed_criteria_as_array
test_malformed_partial_criteria
test_malformed_clamped_then_valid

test_valid_full_result
test_invalid_full_result

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All eval validation tests passed!"
