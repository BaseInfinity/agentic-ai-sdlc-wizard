#!/bin/bash
# Tests for "Prove It's Better" library (tests/e2e/lib/prove-it.sh)
# Validates: path allowlist, fixture stripping, overlap signal parsing

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

echo "=== Prove It's Better Tests ==="
echo ""

# Source the library under test
PROVE_IT="$REPO_ROOT/tests/e2e/lib/prove-it.sh"
if [ ! -f "$PROVE_IT" ]; then
    fail "Library not found: $PROVE_IT"
    echo "=== Results: $PASSED passed, $FAILED failed ==="
    exit 1
fi
source "$PROVE_IT"

# ============================================
# validate_removable_paths() Tests
# ============================================

# Test 1: Accepts known hook path
test_validate_accepts_hook() {
    local INPUT='[".claude/hooks/sdlc-prompt-check.sh"]'
    local RESULT
    RESULT=$(validate_removable_paths "$INPUT" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -q "sdlc-prompt-check.sh"; then
        pass "validate_removable_paths accepts known hook path"
    else
        fail "validate_removable_paths should accept sdlc-prompt-check.sh, got: $RESULT"
    fi
}
test_validate_accepts_hook

# Test 2: Accepts known skill path
test_validate_accepts_skill() {
    local INPUT='[".claude/skills/sdlc/SKILL.md"]'
    local RESULT
    RESULT=$(validate_removable_paths "$INPUT" 2>/dev/null || echo "")

    if echo "$RESULT" | grep -q "sdlc/SKILL.md"; then
        pass "validate_removable_paths accepts known skill path"
    else
        fail "validate_removable_paths should accept sdlc/SKILL.md, got: $RESULT"
    fi
}
test_validate_accepts_skill

# Test 3: Rejects unknown path (security: prevents LLM hallucination)
test_validate_rejects_unknown() {
    local INPUT='["/etc/passwd"]'
    local RESULT
    RESULT=$(validate_removable_paths "$INPUT" 2>/dev/null || echo "")

    if [ -z "$RESULT" ]; then
        pass "validate_removable_paths rejects unknown path"
    else
        fail "validate_removable_paths should reject /etc/passwd, got: $RESULT"
    fi
}
test_validate_rejects_unknown

# Test 4: Handles empty array
test_validate_empty_array() {
    local INPUT='[]'
    local RESULT
    RESULT=$(validate_removable_paths "$INPUT" 2>/dev/null || echo "")

    if [ -z "$RESULT" ]; then
        pass "validate_removable_paths handles empty array"
    else
        fail "validate_removable_paths should return empty for [], got: $RESULT"
    fi
}
test_validate_empty_array

# Test 5: Mixed valid and invalid — only returns valid
test_validate_mixed() {
    local INPUT='[".claude/hooks/tdd-pretool-check.sh", "/etc/shadow", ".claude/skills/setup/SKILL.md"]'
    local RESULT
    RESULT=$(validate_removable_paths "$INPUT" 2>/dev/null || echo "")

    local VALID_COUNT
    VALID_COUNT=$(echo "$RESULT" | grep -c '\.claude/' || true)

    if [ "$VALID_COUNT" -eq 2 ]; then
        pass "validate_removable_paths returns only valid paths from mixed input"
    else
        fail "Expected 2 valid paths, got $VALID_COUNT. Result: $RESULT"
    fi
}
test_validate_mixed

# ============================================
# create_stripped_fixture() Tests
# ============================================

# Test 6: Removes target file from fixture copy
test_strip_removes_file() {
    local TEMP_SRC
    TEMP_SRC=$(mktemp -d)
    local TEMP_DST
    TEMP_DST=$(mktemp -d)

    # Create a minimal fixture
    mkdir -p "$TEMP_SRC/.claude/hooks"
    echo '#!/bin/bash' > "$TEMP_SRC/.claude/hooks/sdlc-prompt-check.sh"
    echo '{"hooks":{}}' > "$TEMP_SRC/.claude/settings.json"
    echo "keep me" > "$TEMP_SRC/README.md"

    create_stripped_fixture "$TEMP_SRC" "$TEMP_DST" '[".claude/hooks/sdlc-prompt-check.sh"]' 2>/dev/null || true

    # Must have copied something AND removed the target
    if [ -f "$TEMP_DST/README.md" ] && [ ! -f "$TEMP_DST/.claude/hooks/sdlc-prompt-check.sh" ]; then
        pass "create_stripped_fixture removes target file"
    else
        fail "create_stripped_fixture should copy fixture and remove sdlc-prompt-check.sh"
    fi

    rm -rf "$TEMP_SRC" "$TEMP_DST"
}
test_strip_removes_file

# Test 7: Keeps unrelated files
test_strip_keeps_unrelated() {
    local TEMP_SRC
    TEMP_SRC=$(mktemp -d)
    local TEMP_DST
    TEMP_DST=$(mktemp -d)

    # Create fixture with target and unrelated files
    mkdir -p "$TEMP_SRC/.claude/hooks"
    echo '#!/bin/bash' > "$TEMP_SRC/.claude/hooks/sdlc-prompt-check.sh"
    echo '#!/bin/bash' > "$TEMP_SRC/.claude/hooks/tdd-pretool-check.sh"
    echo '{"hooks":{}}' > "$TEMP_SRC/.claude/settings.json"
    echo "keep me" > "$TEMP_SRC/README.md"

    create_stripped_fixture "$TEMP_SRC" "$TEMP_DST" '[".claude/hooks/sdlc-prompt-check.sh"]' 2>/dev/null || true

    if [ -f "$TEMP_DST/.claude/hooks/tdd-pretool-check.sh" ] && [ -f "$TEMP_DST/README.md" ]; then
        pass "create_stripped_fixture keeps unrelated files"
    else
        fail "create_stripped_fixture removed files it shouldn't have"
    fi

    rm -rf "$TEMP_SRC" "$TEMP_DST"
}
test_strip_keeps_unrelated

# Test 8: Updates settings.json — removes hook entry for removed hook file
test_strip_updates_settings() {
    local TEMP_SRC
    TEMP_SRC=$(mktemp -d)
    local TEMP_DST
    TEMP_DST=$(mktemp -d)

    # Create fixture with real settings.json structure
    mkdir -p "$TEMP_SRC/.claude/hooks"
    echo '#!/bin/bash' > "$TEMP_SRC/.claude/hooks/sdlc-prompt-check.sh"
    echo '#!/bin/bash' > "$TEMP_SRC/.claude/hooks/tdd-pretool-check.sh"
    cat > "$TEMP_SRC/.claude/settings.json" << 'SETTINGS'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/sdlc-prompt-check.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/tdd-pretool-check.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS

    create_stripped_fixture "$TEMP_SRC" "$TEMP_DST" '[".claude/hooks/sdlc-prompt-check.sh"]' 2>/dev/null || true

    # UserPromptSubmit should be gone, PreToolUse should remain
    local HAS_USER_PROMPT HAS_PRE_TOOL
    HAS_USER_PROMPT=$(jq 'has("hooks") and (.hooks | has("UserPromptSubmit"))' "$TEMP_DST/.claude/settings.json" 2>/dev/null || echo "error")
    HAS_PRE_TOOL=$(jq 'has("hooks") and (.hooks | has("PreToolUse"))' "$TEMP_DST/.claude/settings.json" 2>/dev/null || echo "error")

    if [ "$HAS_USER_PROMPT" = "false" ] && [ "$HAS_PRE_TOOL" = "true" ]; then
        pass "create_stripped_fixture updates settings.json (removes hook entry)"
    else
        fail "settings.json not updated correctly. UserPromptSubmit=$HAS_USER_PROMPT (want false), PreToolUse=$HAS_PRE_TOOL (want true)"
    fi

    rm -rf "$TEMP_SRC" "$TEMP_DST"
}
test_strip_updates_settings

# ============================================
# Overlap Signal Parsing Tests
# ============================================

# Test 9: Non-empty replaces_custom → has_overlap=true
test_overlap_detected() {
    local FIXTURE="$REPO_ROOT/tests/fixtures/releases/v99.0.0-overlap.json"

    if [ ! -f "$FIXTURE" ]; then
        fail "Fixture v99.0.0-overlap.json not found (create it first)"
    else
        local REPLACES
        REPLACES=$(jq -r '.plugin_check.replaces_custom | length' "$FIXTURE" 2>/dev/null || echo "0")

        if [ "$REPLACES" -gt 0 ]; then
            pass "Non-empty replaces_custom detected as overlap"
        else
            fail "v99.0.0-overlap.json should have non-empty replaces_custom, got length $REPLACES"
        fi
    fi
}
test_overlap_detected

# Test 10: Empty replaces_custom → has_overlap=false
test_no_overlap() {
    local FIXTURE="$REPO_ROOT/tests/fixtures/releases/v2.1.16-tasks.json"

    if [ ! -f "$FIXTURE" ]; then
        fail "Fixture v2.1.16-tasks.json not found (create it first)"
    else
        local REPLACES
        REPLACES=$(jq -r '.plugin_check.replaces_custom | length' "$FIXTURE" 2>/dev/null || echo "0")

        if [ "$REPLACES" -eq 0 ]; then
            pass "Empty replaces_custom detected as no overlap"
        else
            fail "v2.1.16-tasks.json should have empty replaces_custom, got length $REPLACES"
        fi
    fi
}
test_no_overlap

# ============================================
# Local Runner Integration Tests (ROADMAP #231 Phase 2)
# Replaces the prove-it-test job in weekly-update.yml — that job was deleted
# when the burning-money cron migrated to a local-Max workflow. The pattern
# now lives in `local-shepherd.sh --compare-baseline --strip-paths`.
# ============================================

# Test 11: local-shepherd.sh exposes --strip-paths flag
test_shepherd_has_strip_paths_flag() {
    local SHEPHERD="$REPO_ROOT/tests/e2e/local-shepherd.sh"

    if grep -qE '\-\-strip-paths' "$SHEPHERD" 2>/dev/null; then
        pass "local-shepherd.sh exposes --strip-paths flag"
    else
        fail "local-shepherd.sh missing --strip-paths flag (Phase 2 migration)"
    fi
}
test_shepherd_has_strip_paths_flag

# Test 12: shepherd sources prove-it.sh (single source of truth for allowlist)
test_shepherd_uses_prove_it_lib() {
    local SHEPHERD="$REPO_ROOT/tests/e2e/local-shepherd.sh"

    if grep -qE 'lib/prove-it\.sh' "$SHEPHERD" 2>/dev/null \
       && grep -qE 'validate_removable_paths|create_stripped_fixture' "$SHEPHERD" 2>/dev/null; then
        pass "shepherd sources tests/e2e/lib/prove-it.sh and uses its functions"
    else
        fail "shepherd must reuse prove-it.sh allowlist (no parallel allowlists)"
    fi
}
test_shepherd_uses_prove_it_lib

# Test 13: weekly-update.yml does NOT have the prove-it-test job anymore
# (Phase 2 migration deleted it. Keeping this test ensures it doesn't sneak
# back in via merge.)
test_weekly_update_no_prove_it_job() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ -f "$WORKFLOW" ] && ! grep -qE '^\s*prove-it-test:' "$WORKFLOW" 2>/dev/null; then
        pass "weekly-update.yml does not contain prove-it-test job (Phase 2 migration)"
    else
        fail "weekly-update.yml still has prove-it-test job — Phase 2 migration incomplete"
    fi
}
test_weekly_update_no_prove_it_job

# Test 14: YAML validation of weekly-update.yml (still valid after job removal)
test_yaml_valid() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        pass "weekly-update.yml is valid YAML"
    else
        fail "weekly-update.yml has invalid YAML"
    fi
}
test_yaml_valid

# ============================================
# compare_ci Integration Tests
# Prove the pipeline can detect real differences
# ============================================

# Source stats.sh for compare_ci
STATS_LIB="$REPO_ROOT/tests/e2e/lib/stats.sh"
if [ ! -f "$STATS_LIB" ]; then
    fail "stats.sh library not found"
else
    source "$STATS_LIB"

    # #236(c): the REGRESSION/STABLE/IMPROVED classification tests that used
    # to live here duplicated test-stats.sh's unit coverage of the same
    # compare_ci behavior classes exactly — removed. Kept: the 2-point-gap
    # sensitivity test below, the only prove-it-specific semantic (that a
    # real signal separates cleanly from noise), not covered elsewhere.

    # Test 17: Pipeline distinguishes 2-point mean shift (not STABLE)
    test_compare_ci_sensitivity() {
        local result
        result=$(compare_ci "6 6 6 6 6" "8 8 8 8 8")
        if [ "$result" != "STABLE" ]; then
            pass "compare_ci distinguishes 2-point gap (result: $result)"
        else
            fail "compare_ci should distinguish a 2-point mean shift, got STABLE"
        fi
    }
    test_compare_ci_sensitivity
fi

# ============================================
# Competitive Watchlist Tests
# ============================================

# Test 18: analyze-community.md still contains the competitive watchlist
# (post-#231 Phase 3c the prompt is invoked manually via `claude --print`
# instead of the deleted scan-community CI job — the prompt content itself
# remains the single source of truth for the watchlist).
test_weekly_has_competitive_watchlist() {
    local COMMUNITY_PROMPT="$REPO_ROOT/.github/prompts/analyze-community.md"

    if [ -f "$COMMUNITY_PROMPT" ] && grep -qi "everything-claude-code\|competitive.*watchlist\|competitor" "$COMMUNITY_PROMPT" 2>/dev/null; then
        pass "analyze-community.md retains competitive watchlist (manual on-Max scan uses this prompt)"
    else
        fail "analyze-community.md should retain the competitive watchlist for manual on-Max scans"
    fi
}
test_weekly_has_competitive_watchlist

# Test 19: README has positioning/comparison section
test_readme_has_positioning() {
    local README="$REPO_ROOT/README.md"

    if grep -qi "how.*compares\|comparison\|positioning\|community.*landscape\|competitive" "$README" 2>/dev/null; then
        pass "README has positioning/comparison section"
    else
        fail "README should have a section comparing SDLC Wizard to community alternatives"
    fi
}
test_readme_has_positioning

# ============================================
# Results
# ============================================

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
