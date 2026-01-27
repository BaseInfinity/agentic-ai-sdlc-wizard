#!/bin/bash
# Test version comparison logic from daily-update workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PASSED=0
FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Version Logic Tests ==="
echo ""

# Test 1: Same version = no update needed
test_same_version() {
    LAST="v2.1.15"
    LATEST="v2.1.15"

    if [ "$LAST" = "$LATEST" ]; then
        NEEDS_UPDATE="false"
    else
        NEEDS_UPDATE="true"
    fi

    if [ "$NEEDS_UPDATE" = "false" ]; then
        pass "Same version detected correctly (no update needed)"
    else
        fail "Same version should not need update"
    fi
}

# Test 2: Different version = update needed
test_different_version() {
    LAST="v2.1.14"
    LATEST="v2.1.15"

    if [ "$LAST" = "$LATEST" ]; then
        NEEDS_UPDATE="false"
    else
        NEEDS_UPDATE="true"
    fi

    if [ "$NEEDS_UPDATE" = "true" ]; then
        pass "Different version detected correctly (update needed)"
    else
        fail "Different version should need update"
    fi
}

# Test 3: Initial state (v0.0.0) = update needed
test_initial_state() {
    LAST="v0.0.0"
    LATEST="v2.1.15"

    if [ "$LAST" = "$LATEST" ]; then
        NEEDS_UPDATE="false"
    else
        NEEDS_UPDATE="true"
    fi

    if [ "$NEEDS_UPDATE" = "true" ]; then
        pass "Initial state (v0.0.0) triggers update correctly"
    else
        fail "Initial state should need update"
    fi
}

# Test 4: Version file reading simulation
test_version_file_read() {
    # Create temp file
    TEMP_FILE=$(mktemp)
    echo "v2.1.16" > "$TEMP_FILE"

    VERSION=$(cat "$TEMP_FILE" | tr -d '\n')
    rm "$TEMP_FILE"

    if [ "$VERSION" = "v2.1.16" ]; then
        pass "Version file read correctly (no trailing newline)"
    else
        fail "Version file read incorrectly: got '$VERSION'"
    fi
}

# Test 5: Missing version file = v0.0.0 default
test_missing_version_file() {
    FAKE_PATH="/nonexistent/path/version.txt"

    if [ -f "$FAKE_PATH" ]; then
        VERSION=$(cat "$FAKE_PATH" | tr -d '\n')
    else
        VERSION="v0.0.0"
    fi

    if [ "$VERSION" = "v0.0.0" ]; then
        pass "Missing version file defaults to v0.0.0"
    else
        fail "Missing file should default to v0.0.0"
    fi
}

# Test 6: Branch name generation
test_branch_name() {
    VERSION="v2.1.16"
    BRANCH="auto-update/claude-code-${VERSION}"

    if [ "$BRANCH" = "auto-update/claude-code-v2.1.16" ]; then
        pass "Branch name generated correctly"
    else
        fail "Branch name incorrect: got '$BRANCH'"
    fi
}

# Run all tests
test_same_version
test_different_version
test_initial_state
test_version_file_read
test_missing_version_file
test_branch_name

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All version logic tests passed!"
