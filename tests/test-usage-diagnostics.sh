#!/bin/bash
# Test usage diagnostics deliverables (v1.82.0)
# Verification checks from plan v3 (Opus + Fable reviewed)

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

WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
LANES="$REPO_ROOT/AI_SETUP_LANES.md"
SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
SDLC="$REPO_ROOT/SDLC.md"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

echo "=== Usage Diagnostics Tests (v1.82.0) ==="
echo ""

# ────────────────────────────────────────────
# Deliverable 1: /usage row is not stale
# ────────────────────────────────────────────

echo "--- Deliverable 1: /usage row accuracy ---"

test_usage_row_mentions_per_category_breakdown() {
    if grep -q "per-category breakdown" "$WIZARD"; then
        pass "/usage row mentions per-category breakdown"
    else
        fail "/usage row missing per-category breakdown description"
    fi
}

test_usage_row_mentions_plan_limits() {
    if grep -q "plan.*limit\|limit.*usage" "$WIZARD"; then
        pass "/usage row mentions plan/limits"
    else
        fail "/usage row missing plan limits description"
    fi
}

test_usage_row_not_stale() {
    # The stale description was "Session total: USD, API time, code changes"
    if grep -q "Session total: USD, API time, code changes" "$WIZARD"; then
        fail "/usage row still has stale description"
    else
        pass "/usage row no longer has stale description"
    fi
}

# ────────────────────────────────────────────
# Deliverable 2: Reading Usage Signals subsection
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 2: Reading Usage Signals ---"

test_signals_subsection_exists() {
    if grep -q "### Reading Usage Signals" "$WIZARD"; then
        pass "Reading Usage Signals subsection exists"
    else
        fail "Reading Usage Signals subsection missing"
    fi
}

test_signals_community_observed_caveat() {
    if grep -q "community-observed" "$WIZARD"; then
        pass "Signals section marked as community-observed"
    else
        fail "Signals section missing community-observed caveat"
    fi
}

test_signals_advisor_not_subagent() {
    # Fable P2 #6: advisor must be described as server-side consultation, NOT subagent
    # Check for patterns that equate the two (not just proximity on a table row)
    local signals_section
    signals_section=$(sed -n '/### Reading Usage Signals/,/### /p' "$WIZARD" | head -30)
    if echo "$signals_section" | grep -qiE "advisor (is a subagent|as a subagent|subagent)"; then
        fail "Signals section calls advisor a subagent (must be server-side consultation)"
    else
        pass "Advisor correctly NOT called a subagent in signals section"
    fi
}

# ────────────────────────────────────────────
# Deliverable 3: Autocompact cross-reference in lanes doc
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 3: Autocompact cross-reference ---"

test_lanes_autocompact_crossref_exists() {
    if grep -q "Autocompact Thresholds" "$LANES"; then
        pass "Autocompact Thresholds section exists in lanes doc"
    else
        fail "Autocompact Thresholds section missing from lanes doc"
    fi
}

test_lanes_autocompact_no_inline_numbers() {
    # Numbers-free: should NOT contain specific % values in the crossref section
    local crossref_section
    crossref_section=$(sed -n '/## Autocompact Thresholds/,/^## /p' "$LANES")
    if echo "$crossref_section" | grep -qE '[0-9]+%'; then
        fail "Autocompact cross-reference contains inline percentage numbers (should be numbers-free)"
    else
        pass "Autocompact cross-reference is numbers-free"
    fi
}

# ────────────────────────────────────────────
# Deliverable 4: SKILL.md /usage fold + char budget
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 4: SKILL.md /usage + char budget ---"

test_skill_usage_mention() {
    if grep -q '/usage' "$SKILL"; then
        pass "SKILL.md mentions /usage"
    else
        fail "SKILL.md missing /usage mention"
    fi
}

# ────────────────────────────────────────────
# Deliverable 5: REJECTED (no test)
# ────────────────────────────────────────────

# ────────────────────────────────────────────
# Deliverable 6: Advisor fallback in lanes doc
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 6: Advisor fallback procedure ---"

test_advisor_fallback_exists() {
    if grep -q "When the Advisor Is Unavailable" "$LANES"; then
        pass "Advisor fallback procedure exists in lanes doc"
    else
        fail "Advisor fallback procedure missing from lanes doc"
    fi
}

test_advisor_fallback_escalation_ladder() {
    # Must be a numbered step sequence, not a flat menu. As of the
    # 2026-07-24 correction (Fable-as-advisor is server-side rollout-gated,
    # not a transient incident), Step 1 is the immediate subagent fallback,
    # NOT a session restart — restarting doesn't fix a rollout gate.
    local fallback_section
    fallback_section=$(sed -n '/## When the Advisor Is Unavailable/,/^## /p' "$LANES")
    if echo "$fallback_section" | grep -q "Step 1" && echo "$fallback_section" | grep -q "Step 2"; then
        pass "Advisor fallback uses escalation ladder (Step 1, Step 2)"
    else
        fail "Advisor fallback missing escalation ladder structure"
    fi
}

# ────────────────────────────────────────────
# Deliverable 7: Fable effort guidance
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 7: Fable effort guidance ---"

test_fable_effort_guidance_exists() {
    if grep -qi "fable.*effort\|effort.*fable" "$LANES"; then
        pass "Fable effort guidance exists in lanes doc"
    else
        fail "Fable effort guidance missing from lanes doc"
    fi
}

# ────────────────────────────────────────────
# Deliverable 8: Version bump
# ────────────────────────────────────────────

echo ""
echo "--- Deliverable 8: Version bump ---"

test_sdlc_version_bump() {
    if grep -q "1.82.0" "$SDLC"; then
        pass "SDLC.md has version 1.82.0"
    else
        fail "SDLC.md missing version 1.82.0"
    fi
}

test_changelog_version_entry() {
    if grep -q '\[1.82.0\]' "$CHANGELOG"; then
        pass "CHANGELOG.md has 1.82.0 entry"
    else
        fail "CHANGELOG.md missing 1.82.0 entry"
    fi
}

# ────────────────────────────────────────────
# Cross-cutting: Fable P1 checks
# ────────────────────────────────────────────

echo ""
echo "--- Cross-cutting: Fable P1 verification ---"

test_no_status_as_usage_source() {
    # Fable P1 #1: /status is settings, NOT usage. No doc should attribute
    # usage/cost breakdown to /status
    if grep -qE '/status.*usage breakdown|/status.*cost.*breakdown|/status.*per-category' "$WIZARD"; then
        fail "/status incorrectly attributed as usage source"
    else
        pass "/status not misattributed as usage source"
    fi
}

test_correct_env_var_name() {
    # Fable P1 #2: it's CLAUDE_AUTOCOMPACT_PCT_OVERRIDE, not AUTOCOMPACT_PCT_OVERRIDE
    if grep -q 'AUTOCOMPACT_PCT_OVERRIDE' "$WIZARD"; then
        # Make sure ALL occurrences have the CLAUDE_ prefix
        local bad_refs
        bad_refs=$(grep -c 'AUTOCOMPACT_PCT_OVERRIDE' "$WIZARD")
        local good_refs
        good_refs=$(grep -c 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$WIZARD")
        if [ "$bad_refs" = "$good_refs" ]; then
            pass "All AUTOCOMPACT_PCT_OVERRIDE refs have CLAUDE_ prefix"
        else
            fail "Found AUTOCOMPACT_PCT_OVERRIDE without CLAUDE_ prefix ($bad_refs total, $good_refs with prefix)"
        fi
    else
        pass "No AUTOCOMPACT_PCT_OVERRIDE references to check"
    fi
}

# ────────────────────────────────────────────
# Run all tests
# ────────────────────────────────────────────

test_usage_row_mentions_per_category_breakdown
test_usage_row_mentions_plan_limits
test_usage_row_not_stale
test_signals_subsection_exists
test_signals_community_observed_caveat
test_signals_advisor_not_subagent
test_lanes_autocompact_crossref_exists
test_lanes_autocompact_no_inline_numbers
test_skill_usage_mention
test_advisor_fallback_exists
test_advisor_fallback_escalation_ladder
test_fable_effort_guidance_exists
test_sdlc_version_bump
test_changelog_version_entry
test_no_status_as_usage_source
test_correct_env_var_name

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
