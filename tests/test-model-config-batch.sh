#!/bin/bash
# Test model-config batch (#403, #391, #405, #384) — v1.83.0
# TDD RED: written BEFORE implementation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0

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

HOOK="$REPO_ROOT/hooks/model-effort-check.sh"
SETUP_SKILL="$REPO_ROOT/skills/setup/SKILL.md"
UPDATE_SKILL="$REPO_ROOT/skills/update/SKILL.md"

echo "=== Model Config Batch Tests ==="
echo ""

# ────────────────────────────────────────────
# #403: Hook should list multiple models, not just claude-opus-4-6
# ────────────────────────────────────────────

echo "--- #403: Hook multi-model recommendation ---"

test_hook_recommendation_not_single_model() {
    if grep -q "opusplan" "$HOOK"; then
        pass "Hook recommendation mentions opusplan"
    else
        fail "Hook recommendation does not mention opusplan (only lists single model)"
    fi
}

test_hook_no_hardcoded_single_model_nudge() {
    # The output should NOT tell users to run /model for one specific model
    # It should offer choices or point to /model without a single hardcoded value
    if grep -q 'run: /model \$RECOMMENDED_MODEL' "$HOOK"; then
        fail "Hook still nudges users to a single hardcoded model via \$RECOMMENDED_MODEL"
    else
        pass "Hook does not nudge to single hardcoded model"
    fi
}

# ────────────────────────────────────────────
# #391: Setup skill should detect global [1m] pin
# ────────────────────────────────────────────

echo ""
echo "--- #391: Global [1m] pin detection in setup ---"

test_setup_skill_checks_global_1m_pin() {
    # Step 9.5 should specifically detect [1m] pins in global settings
    local step95_section
    step95_section=$(sed -n '/### Step 9.5/,/### Step [0-9]/p' "$SETUP_SKILL")
    if echo "$step95_section" | grep -qi '\[1m\].*global\|global.*\[1m\]\|global.*model.*pin'; then
        pass "Step 9.5 detects [1m] pins in global settings"
    else
        fail "Step 9.5 does not detect [1m] pins in global settings"
    fi
}

test_setup_skill_warns_1m_pin() {
    local step95_section
    step95_section=$(sed -n '/### Step 9.5/,/### Step [0-9]/p' "$SETUP_SKILL")
    if echo "$step95_section" | grep -qi '\[1m\].*warn\|warn.*\[1m\]\|API.*bill\|billing.*trap'; then
        pass "Step 9.5 warns about [1m] billing implications"
    else
        fail "Step 9.5 does not warn about [1m] billing trap"
    fi
}

# ────────────────────────────────────────────
# #405: Update skill version race — use npm as authoritative
# ────────────────────────────────────────────

echo ""
echo "--- #405: Version race — npm as authoritative ---"

test_update_step3_uses_npm_version() {
    # Step 3 should reference npm registry version, not just CHANGELOG
    local step3_section
    step3_section=$(sed -n '/### Step 3/,/### Step [0-9]/p' "$UPDATE_SKILL")
    if echo "$step3_section" | grep -qi 'npm.*registry\|npm.*latest\|Step 1.5\|installable'; then
        pass "Step 3 references npm registry version as authoritative"
    else
        fail "Step 3 does not reference npm registry version (uses CHANGELOG only)"
    fi
}

test_update_step3_handles_publish_window() {
    local step3_section
    step3_section=$(sed -n '/### Step 3/,/### Step [0-9]/p' "$UPDATE_SKILL")
    if echo "$step3_section" | grep -qi 'publish.*window\|not yet published\|CHANGELOG.*ahead\|min.*npm'; then
        pass "Step 3 handles CHANGELOG-ahead-of-npm publish window"
    else
        fail "Step 3 does not handle the publish window race condition"
    fi
}

# ────────────────────────────────────────────
# #384: Update skill effort config check
# ────────────────────────────────────────────

echo ""
echo "--- #384: Effort config check in update skill ---"

test_update_has_effort_check_step() {
    if grep -q 'Step 7.9' "$UPDATE_SKILL"; then
        pass "Update skill has Step 7.9 (effort config check)"
    else
        fail "Update skill missing Step 7.9"
    fi
}

test_update_effort_step_checks_env_var() {
    local step79_section
    step79_section=$(sed -n '/### Step 7.9/,/### Step [0-9]/p' "$UPDATE_SKILL")
    if echo "$step79_section" | grep -q 'CLAUDE_CODE_EFFORT_LEVEL'; then
        pass "Step 7.9 checks CLAUDE_CODE_EFFORT_LEVEL env var"
    else
        fail "Step 7.9 does not check CLAUDE_CODE_EFFORT_LEVEL"
    fi
}

test_update_effort_step_warns_settings_only_max() {
    local step79_section
    step79_section=$(sed -n '/### Step 7.9/,/### Step [0-9]/p' "$UPDATE_SKILL")
    if echo "$step79_section" | grep -qi 'settings.*only\|session.*only\|ignores'; then
        pass "Step 7.9 warns about settings-only max being ignored"
    else
        fail "Step 7.9 does not warn about settings-only max"
    fi
}

# ────────────────────────────────────────────
# Run all tests
# ────────────────────────────────────────────

test_hook_recommendation_not_single_model
test_hook_no_hardcoded_single_model_nudge
test_setup_skill_checks_global_1m_pin
test_setup_skill_warns_1m_pin
test_update_step3_uses_npm_version
test_update_step3_handles_publish_window
test_update_has_effort_check_step
test_update_effort_step_checks_env_var
test_update_effort_step_warns_settings_only_max

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
