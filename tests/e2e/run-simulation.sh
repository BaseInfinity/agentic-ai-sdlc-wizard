#!/bin/bash
# E2E Simulation Runner for SDLC Wizard
#
# This script:
# 1. Sets up a test repo from fixtures
# 2. Installs the wizard
# 3. Runs Claude with a test scenario
# 4. Checks SDLC compliance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check for required tools
check_requirements() {
    log_info "Checking requirements..."

    if ! command -v claude &> /dev/null; then
        log_warn "Claude CLI not found - skipping live simulation"
        log_info "To run full E2E tests, install Claude Code CLI"
        return 1
    fi

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        log_warn "ANTHROPIC_API_KEY not set - skipping live simulation"
        log_info "Set ANTHROPIC_API_KEY to run full E2E tests"
        return 1
    fi

    return 0
}

# Setup test environment
setup_test_repo() {
    local test_dir="$1"

    log_info "Setting up test repo at $test_dir"

    # Copy template
    cp -r "$FIXTURES_DIR/test-repo" "$test_dir"

    # Initialize git (needed for some SDLC features)
    cd "$test_dir"
    git init -q
    git add .
    git commit -q -m "Initial commit"

    # Install wizard (copy key files)
    mkdir -p .claude/hooks .claude/skills/sdlc .claude/skills/testing

    # Copy wizard if it exists (would be installed by wizard setup)
    if [ -f "$REPO_ROOT/CLAUDE.md" ]; then
        cp "$REPO_ROOT/CLAUDE.md" .
    fi

    if [ -d "$REPO_ROOT/.claude/hooks" ]; then
        cp -r "$REPO_ROOT/.claude/hooks/"* .claude/hooks/ 2>/dev/null || true
    fi

    if [ -d "$REPO_ROOT/.claude/skills" ]; then
        cp -r "$REPO_ROOT/.claude/skills/"* .claude/skills/ 2>/dev/null || true
    fi

    if [ -f "$REPO_ROOT/.claude/settings.json" ]; then
        cp "$REPO_ROOT/.claude/settings.json" .claude/
    fi

    log_info "Test repo ready"
}

# Run a scenario
run_scenario() {
    local scenario_file="$1"
    local test_dir="$2"
    local scenario_name=$(basename "$scenario_file" .md)

    log_info "Running scenario: $scenario_name"

    # Extract task from scenario (between ## Task and next ##)
    TASK=$(sed -n '/^## Task$/,/^## /p' "$scenario_file" | grep -v '^##' | head -20)

    if [ -z "$TASK" ]; then
        log_error "Could not extract task from scenario"
        return 1
    fi

    cd "$test_dir"

    # Run Claude with the task (capture output for compliance check)
    # Using --print to get full output
    log_info "Executing task with Claude..."

    # Store output for compliance checking
    OUTPUT_FILE="$test_dir/claude_output.txt"

    # Run claude with task (this is where the actual simulation happens)
    # Note: In CI, this would use claude-code-action instead
    claude --print "$TASK" > "$OUTPUT_FILE" 2>&1 || true

    log_info "Scenario execution complete"
    return 0
}

# Check SDLC compliance (calls separate script)
check_compliance() {
    local test_dir="$1"
    local scenario_file="$2"

    "$SCRIPT_DIR/check-compliance.sh" "$test_dir" "$scenario_file"
}

# Cleanup
cleanup() {
    local test_dir="$1"

    if [ -d "$test_dir" ]; then
        rm -rf "$test_dir"
        log_info "Cleaned up test directory"
    fi
}

# Main execution
main() {
    local scenario="${1:-all}"

    echo ""
    echo "=========================================="
    echo "  SDLC Wizard E2E Simulation"
    echo "=========================================="
    echo ""

    # Check if we can run live simulations
    if ! check_requirements; then
        log_info "Running in validation-only mode"
        log_info "Validating scenario files and fixtures..."

        # Just validate that files exist and are readable
        for scenario_file in "$SCENARIOS_DIR"/*.md; do
            if [ -f "$scenario_file" ]; then
                scenario_name=$(basename "$scenario_file" .md)
                if grep -q "## Task" "$scenario_file" && grep -q "## Success Criteria" "$scenario_file"; then
                    log_info "Validated: $scenario_name"
                else
                    log_error "Invalid scenario: $scenario_name (missing required sections)"
                    exit 1
                fi
            fi
        done

        # Validate test repo fixture
        if [ -f "$FIXTURES_DIR/test-repo/src/app.js" ] && \
           [ -f "$FIXTURES_DIR/test-repo/tests/app.test.js" ] && \
           [ -f "$FIXTURES_DIR/test-repo/package.json" ]; then
            log_info "Test repo fixture is complete"
        else
            log_error "Test repo fixture is incomplete"
            exit 1
        fi

        echo ""
        log_info "Validation complete - all fixtures and scenarios are valid"
        log_info "To run full E2E tests, set ANTHROPIC_API_KEY and install Claude CLI"
        exit 0
    fi

    # Full simulation mode
    TEST_DIR=$(mktemp -d)
    trap "cleanup '$TEST_DIR'" EXIT

    setup_test_repo "$TEST_DIR"

    if [ "$scenario" = "all" ]; then
        for scenario_file in "$SCENARIOS_DIR"/*.md; do
            run_scenario "$scenario_file" "$TEST_DIR"
            check_compliance "$TEST_DIR" "$scenario_file"
        done
    else
        scenario_file="$SCENARIOS_DIR/$scenario.md"
        if [ ! -f "$scenario_file" ]; then
            log_error "Scenario not found: $scenario"
            exit 1
        fi
        run_scenario "$scenario_file" "$TEST_DIR"
        check_compliance "$TEST_DIR" "$scenario_file"
    fi

    echo ""
    log_info "All E2E simulations complete!"
}

main "$@"
