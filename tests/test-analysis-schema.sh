#!/bin/bash
# Test that analysis response fixtures match expected schema

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/releases"
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

echo "=== Analysis Schema Tests ==="
echo ""

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "ERROR: jq is required but not installed"
    exit 1
fi

# Required fields in analysis response
REQUIRED_FIELDS=("version" "relevance" "summary" "wizard_impact" "plugin_check" "reasoning")
VALID_RELEVANCE=("HIGH" "MEDIUM" "LOW")

validate_fixture() {
    local file="$1"
    local filename=$(basename "$file")

    # Check file is valid JSON
    if ! jq empty "$file" 2>/dev/null; then
        fail "$filename: Invalid JSON"
        return
    fi

    # Check required fields exist
    for field in "${REQUIRED_FIELDS[@]}"; do
        if ! jq -e ".$field" "$file" > /dev/null 2>&1; then
            fail "$filename: Missing required field '$field'"
            return
        fi
    done

    # Check relevance is valid
    RELEVANCE=$(jq -r '.relevance' "$file")
    VALID=false
    for valid_val in "${VALID_RELEVANCE[@]}"; do
        if [ "$RELEVANCE" = "$valid_val" ]; then
            VALID=true
            break
        fi
    done

    if [ "$VALID" = "false" ]; then
        fail "$filename: Invalid relevance '$RELEVANCE' (must be HIGH, MEDIUM, or LOW)"
        return
    fi

    # Check wizard_impact is array
    if ! jq -e '.wizard_impact | type == "array"' "$file" > /dev/null 2>&1; then
        fail "$filename: wizard_impact must be an array"
        return
    fi

    # Check plugin_check has required subfields
    if ! jq -e '.plugin_check.new_official_plugins | type == "array"' "$file" > /dev/null 2>&1; then
        fail "$filename: plugin_check.new_official_plugins must be an array"
        return
    fi

    if ! jq -e '.plugin_check.replaces_custom | type == "array"' "$file" > /dev/null 2>&1; then
        fail "$filename: plugin_check.replaces_custom must be an array"
        return
    fi

    # All checks passed
    pass "$filename: Valid schema"
}

# Validate each fixture
for fixture in "$FIXTURES_DIR"/*.json; do
    if [ -f "$fixture" ]; then
        validate_fixture "$fixture"
    fi
done

# Test relevance filtering logic (simulates workflow decision)
echo ""
echo "=== Relevance Filtering Tests ==="

test_relevance_filter() {
    local file="$1"
    local expected_action="$2"  # "pr" or "skip"
    local filename=$(basename "$file")

    RELEVANCE=$(jq -r '.relevance' "$file")

    if [ "$RELEVANCE" = "HIGH" ] || [ "$RELEVANCE" = "MEDIUM" ]; then
        ACTUAL_ACTION="pr"
    else
        ACTUAL_ACTION="skip"
    fi

    if [ "$ACTUAL_ACTION" = "$expected_action" ]; then
        pass "$filename: $RELEVANCE relevance correctly triggers $expected_action"
    else
        fail "$filename: $RELEVANCE should trigger $expected_action, got $ACTUAL_ACTION"
    fi
}

# Test each fixture with expected outcomes
test_relevance_filter "$FIXTURES_DIR/v2.1.16-tasks.json" "pr"      # HIGH -> PR
test_relevance_filter "$FIXTURES_DIR/v2.1.17-bugfix.json" "skip"   # LOW -> skip
test_relevance_filter "$FIXTURES_DIR/v2.1.19-arguments.json" "pr"  # MEDIUM -> PR
test_relevance_filter "$FIXTURES_DIR/v2.1.20-ui-polish.json" "skip" # LOW -> skip

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All schema tests passed!"
