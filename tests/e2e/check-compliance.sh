#!/bin/bash
# SDLC Compliance Checker
#
# Verifies that Claude's execution followed SDLC workflow

set -e

TEST_DIR="$1"
SCENARIO_FILE="$2"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASSED=0
FAILED=0
WARNINGS=0

pass() {
    echo -e "  ${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "  ${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo -e "  ${YELLOW}WARN${NC}: $1"
    WARNINGS=$((WARNINGS + 1))
}

check_output() {
    local pattern="$1"
    local message="$2"
    local required="${3:-true}"

    if [ -f "$TEST_DIR/claude_output.txt" ]; then
        if grep -qi "$pattern" "$TEST_DIR/claude_output.txt"; then
            pass "$message"
            return 0
        fi
    fi

    if [ "$required" = "true" ]; then
        fail "$message"
    else
        warn "$message"
    fi
    return 1
}

check_file_exists() {
    local file="$1"
    local message="$2"

    if [ -f "$TEST_DIR/$file" ]; then
        pass "$message"
        return 0
    fi

    fail "$message"
    return 1
}

echo ""
echo "=== SDLC Compliance Check ==="
echo "Scenario: $(basename "$SCENARIO_FILE" .md)"
echo ""

# Extract complexity from scenario
COMPLEXITY=$(grep -A1 "^## Complexity" "$SCENARIO_FILE" | tail -1 | awk '{print tolower($1)}')
echo "Complexity: $COMPLEXITY"
echo ""

# Basic checks for all scenarios
echo "--- Basic SDLC Checks ---"

# Check if files were read before editing
check_output "Read\|reading\|read the file" "Files read before modification" false

# Check if task was acknowledged
check_output "task\|plan\|approach" "Task/plan acknowledged" false

# Complexity-specific checks
case "$COMPLEXITY" in
    simple)
        echo ""
        echo "--- Simple Scenario Checks ---"
        check_output "fix\|update\|change" "Identified the change to make" false
        ;;

    medium)
        echo ""
        echo "--- Medium Scenario Checks ---"
        # TDD checks
        check_output "test\|failing\|fail first" "TDD approach mentioned" false
        # Confidence check
        check_output "confidence\|HIGH\|MEDIUM\|LOW" "Confidence level stated" false
        # Task tracking
        check_output "task\|todo\|TodoWrite\|TaskCreate" "Task tracking used" false
        ;;

    hard)
        echo ""
        echo "--- Hard Scenario Checks ---"
        # Plan mode check
        check_output "plan\|planning\|EnterPlanMode" "Planning phase used" false
        # Multiple tasks
        check_output "task\|todo\|TodoWrite\|TaskCreate" "Task list created" false
        # Confidence
        check_output "confidence\|HIGH\|MEDIUM\|LOW" "Confidence level stated" false
        # TDD
        check_output "test\|TDD\|failing" "TDD approach followed" false
        ;;
esac

# Self-review check (all scenarios)
echo ""
echo "--- Self-Review Check ---"
check_output "review\|verify\|check\|confirm" "Self-review performed" false

echo ""
echo "=== Compliance Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Warnings: $WARNINGS"

if [ $FAILED -gt 0 ]; then
    echo ""
    echo -e "${RED}SDLC compliance check failed${NC}"
    exit 1
fi

if [ $WARNINGS -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Compliance check passed with warnings${NC}"
fi

echo ""
echo -e "${GREEN}SDLC compliance check passed${NC}"
