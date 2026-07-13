#!/bin/bash
# Test cross-document consistency: hardcoded counts must match filesystem reality
# Roadmap #102: docs drift silently when counts are hardcoded
#
# Philosophy: targeted checks for known-drifting claims, NOT generic
# "grep all numbers" which would be too noisy and brittle.

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

# Strip fenced code blocks from a file before grepping for claims.
# Prevents false positives from example code like: "run 2 workflows"
strip_code_blocks() {
    sed '/^```/,/^```/d' "$1"
}

echo "=== Cross-Document Consistency Tests ==="
echo ""

# ────────────────────────────────────────────
# Workflow Count Consistency
# ────────────────────────────────────────────

echo "--- Workflow Count ---"

ACTUAL_WORKFLOWS=$(ls "$REPO_ROOT"/.github/workflows/*.yml 2>/dev/null | wc -l | tr -d ' ')

# Test 1: README should NOT hardcode workflow count (use count-free language)
test_readme_no_hardcoded_workflow_count() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    # Should say "All workflows" not "All 7 workflows" or "7 workflows"
    # Strip code blocks to avoid false positives from examples
    if strip_code_blocks "$README" | grep -qE '\b[0-9]+\s+workflows?\b'; then
        local found
        found=$(strip_code_blocks "$README" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1)
        fail "README.md hardcodes workflow count: '$found' (should use count-free language)"
    else
        pass "README.md does not hardcode workflow count"
    fi
}

# Test 2: No doc outside CHANGELOG/ROADMAP/plans claims wrong workflow count
test_no_stale_workflow_count() {
    local stale=""
    # Search for "N workflows" in active docs (not historical)
    for doc in "$REPO_ROOT"/README.md "$REPO_ROOT"/CI_CD.md "$REPO_ROOT"/ARCHITECTURE.md \
               "$REPO_ROOT"/CONTRIBUTING.md "$REPO_ROOT"/COMPETITIVE_AUDIT.md \
               "$REPO_ROOT"/CODE_REVIEW_EXCEPTIONS.md "$REPO_ROOT"/SDLC.md; do
        [ ! -f "$doc" ] && continue
        local basename
        basename=$(basename "$doc")
        # Find lines claiming N workflows where N is wrong (exclude code blocks)
        while IFS= read -r line; do
            local claimed
            claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1 | grep -oE '[0-9]+')
            if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_WORKFLOWS" ]; then
                stale="$stale\n  $basename: claims $claimed workflows (actual: $ACTUAL_WORKFLOWS)"
            fi
        done < <(strip_code_blocks "$doc" | grep -nE '\b[0-9]+\s+workflows?\b' 2>/dev/null || true)
    done
    if [ -z "$stale" ]; then
        pass "No stale workflow counts in active docs (actual: $ACTUAL_WORKFLOWS)"
    else
        fail "Stale workflow counts found:$stale"
    fi
}

test_readme_no_hardcoded_workflow_count
test_no_stale_workflow_count

# ────────────────────────────────────────────
# CLI File Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- CLI File Count ---"

# Count FILES entries in init.js (the source of truth)
# The full install output = FILES array entries + the wizard doc (CLAUDE_CODE_SDLC_WIZARD.md)
INIT_JS="$REPO_ROOT/cli/init.js"
FILES_COUNT=$(grep -c "src:.*dest:" "$INIT_JS" 2>/dev/null || echo "0")
# init.js also copies WIZARD_DOC (CLAUDE_CODE_SDLC_WIZARD.md) separately
ACTUAL_CLI_FILES=$((FILES_COUNT + 1))

# Test 3: CI_CD.md file count claims match init.js
test_ci_cd_file_count() {
    local CI_CD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CI_CD" ]; then fail "CI_CD.md not found"; return; fi
    # Look for "N files created" or "all N files" in install verification context
    local stale=""
    while IFS= read -r line; do
        local claimed
        claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+files?\b' | head -1 | grep -oE '[0-9]+')
        if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_CLI_FILES" ]; then
            stale="$stale\n  claims $claimed files (actual: $ACTUAL_CLI_FILES)"
        fi
    done < <(strip_code_blocks "$CI_CD" | grep -nE '\b[0-9]+\s+files?\s*(created|simulates)' 2>/dev/null || true)
    # Also check "all N files"
    while IFS= read -r line; do
        local claimed
        claimed=$(echo "$line" | grep -oE 'all\s+[0-9]+\s+files' | grep -oE '[0-9]+')
        if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_CLI_FILES" ]; then
            stale="$stale\n  claims 'all $claimed files' (actual: $ACTUAL_CLI_FILES)"
        fi
    done < <(strip_code_blocks "$CI_CD" | grep -niE 'all\s+[0-9]+\s+files' 2>/dev/null || true)
    if [ -z "$stale" ]; then
        pass "CI_CD.md CLI file counts match init.js ($ACTUAL_CLI_FILES files)"
    else
        fail "CI_CD.md stale CLI file counts:$stale"
    fi
}

# Test 4: CI_CD.md should prefer count-free language for CLI install verification
test_ci_cd_no_hardcoded_file_count() {
    local CI_CD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CI_CD" ]; then fail "CI_CD.md not found"; return; fi
    if strip_code_blocks "$CI_CD" | grep -qE '\b[0-9]+\s+files\s+created\b' || strip_code_blocks "$CI_CD" | grep -qiE 'all\s+[0-9]+\s+files'; then
        fail "CI_CD.md hardcodes CLI file count (should use count-free language like 'all CLI files')"
    else
        pass "CI_CD.md uses count-free language for CLI files"
    fi
}

test_ci_cd_file_count
test_ci_cd_no_hardcoded_file_count

# ────────────────────────────────────────────
# Skill Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Skill Count ---"

# Skills live at repo root skills/ (symlinked into .claude/skills/)
ACTUAL_SKILLS=$(ls "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')

# Test 5: COMPETITIVE_AUDIT.md skill count matches actual
test_competitive_audit_skill_count() {
    local AUDIT="$REPO_ROOT/COMPETITIVE_AUDIT.md"
    if [ ! -f "$AUDIT" ]; then fail "COMPETITIVE_AUDIT.md not found"; return; fi
    # Look for "N skills" in our column (not competitor column like "80+ skills")
    # The pattern is "| N skills" in a table row about us
    local our_claim
    our_claim=$(grep -i 'skill library' "$AUDIT" | grep -oE '\|\s*[0-9]+\s+skills' | tail -1 | grep -oE '[0-9]+' || echo "")
    if [ -z "$our_claim" ]; then
        pass "COMPETITIVE_AUDIT.md does not hardcode our skill count"
    elif [ "$our_claim" = "$ACTUAL_SKILLS" ]; then
        pass "COMPETITIVE_AUDIT.md skill count correct ($our_claim = $ACTUAL_SKILLS)"
    else
        fail "COMPETITIVE_AUDIT.md claims $our_claim skills (actual: $ACTUAL_SKILLS)"
    fi
}

test_competitive_audit_skill_count

# ────────────────────────────────────────────
# Scenario Count Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Scenario Count ---"

ACTUAL_SCENARIOS=$(ls "$REPO_ROOT"/tests/e2e/scenarios/*.md 2>/dev/null | wc -l | tr -d ' ')

# Test 6: No doc outside CHANGELOG/ROADMAP claims wrong scenario count
test_no_stale_scenario_count() {
    local stale=""
    for doc in "$REPO_ROOT"/README.md "$REPO_ROOT"/CI_CD.md "$REPO_ROOT"/TESTING.md \
               "$REPO_ROOT"/CONTRIBUTING.md "$REPO_ROOT"/COMPETITIVE_AUDIT.md; do
        [ ! -f "$doc" ] && continue
        local basename
        basename=$(basename "$doc")
        while IFS= read -r line; do
            local claimed
            claimed=$(echo "$line" | grep -oE '\b[0-9]+\s+scenarios\b' | head -1 | grep -oE '[0-9]+')
            if [ -n "$claimed" ] && [ "$claimed" != "$ACTUAL_SCENARIOS" ]; then
                stale="$stale\n  $basename: claims $claimed scenarios (actual: $ACTUAL_SCENARIOS)"
            fi
        done < <(strip_code_blocks "$doc" | grep -nE '\b[0-9]+\s+scenarios\b' 2>/dev/null || true)
    done
    if [ -z "$stale" ]; then
        pass "No stale scenario counts in active docs (actual: $ACTUAL_SCENARIOS)"
    else
        fail "Stale scenario counts found:$stale"
    fi
}

test_no_stale_scenario_count

# ────────────────────────────────────────────
# CODE_REVIEW_EXCEPTIONS Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Code Review Exceptions ---"

# Test 7: CODE_REVIEW_EXCEPTIONS.md should not hardcode workflow count
test_code_review_exceptions_no_hardcoded_count() {
    local EXCEPTIONS="$REPO_ROOT/CODE_REVIEW_EXCEPTIONS.md"
    if [ ! -f "$EXCEPTIONS" ]; then pass "CODE_REVIEW_EXCEPTIONS.md not found (OK)"; return; fi
    if strip_code_blocks "$EXCEPTIONS" | grep -qE '\b[0-9]+\s+workflows?\b'; then
        local found
        found=$(strip_code_blocks "$EXCEPTIONS" | grep -oE '\b[0-9]+\s+workflows?\b' | head -1)
        fail "CODE_REVIEW_EXCEPTIONS.md hardcodes workflow count: '$found'"
    else
        pass "CODE_REVIEW_EXCEPTIONS.md does not hardcode workflow count"
    fi
}

test_code_review_exceptions_no_hardcoded_count

# ────────────────────────────────────────────
# Cross-Check: init.js FILES vs filesystem
# ────────────────────────────────────────────

echo ""
echo "--- Init.js Source-of-Truth ---"

# Test 8: Every file in init.js FILES actually exists
test_init_js_files_exist() {
    if [ ! -f "$INIT_JS" ]; then fail "cli/init.js not found"; return; fi
    local missing=""
    # Extract src paths from FILES array (lines with both src: and dest:)
    while IFS= read -r src_path; do
        # Check both REPO_ROOT and TEMPLATES_DIR locations
        if [ ! -f "$REPO_ROOT/$src_path" ] && [ ! -f "$REPO_ROOT/cli/templates/$src_path" ]; then
            missing="$missing $src_path"
        fi
    done < <(grep "src:.*dest:" "$INIT_JS" | sed "s/.*src: *['\"]//;s/['\"].*//" )
    if [ -z "$missing" ]; then
        pass "All init.js FILES entries exist on disk ($ACTUAL_CLI_FILES files)"
    else
        fail "init.js references missing files:$missing"
    fi
}

test_init_js_files_exist

# Test 9: Every skill in init.js FILES has a matching SKILL.md on disk
test_init_js_skills_match_disk() {
    if [ ! -f "$INIT_JS" ]; then fail "cli/init.js not found"; return; fi
    local init_skills disk_skills
    # Extract skill paths from FILES array (lines with src: and dest:)
    init_skills=$(grep "src:.*dest:" "$INIT_JS" | sed "s/.*src: *['\"]//;s/['\"].*//" | grep 'skills/' | sort)
    # Get skills from disk (repo root skills/, same path format as init.js)
    disk_skills=$(ls "$REPO_ROOT"/skills/*/SKILL.md 2>/dev/null | \
        sed "s|$REPO_ROOT/||" | sort)
    if [ "$init_skills" = "$disk_skills" ]; then
        pass "init.js skill list matches disk ($(echo "$init_skills" | wc -l | tr -d ' ') skills)"
    else
        local only_init only_disk
        only_init=$(comm -23 <(echo "$init_skills") <(echo "$disk_skills"))
        only_disk=$(comm -13 <(echo "$init_skills") <(echo "$disk_skills"))
        fail "init.js skills != disk skills. Only in init.js: [$only_init] Only on disk: [$only_disk]"
    fi
}

test_init_js_skills_match_disk

# ────────────────────────────────────────────
# Scoring Rubric Consistency
# ────────────────────────────────────────────

echo ""
echo "--- Scoring Rubric ---"

# Test 10: README should not hardcode criteria count (it drifts when rubric changes)
test_readme_no_hardcoded_criteria_count() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if strip_code_blocks "$README" | grep -qE '\b[0-9]+\s+criteria\b'; then
        local found
        found=$(strip_code_blocks "$README" | grep -oE '\b[0-9]+\s+criteria\b' | head -1)
        fail "README.md hardcodes criteria count: '$found' (should use count-free language)"
    else
        pass "README.md does not hardcode criteria count"
    fi
}

test_readme_no_hardcoded_criteria_count

# ────────────────────────────────────────────
# Recommended Model Consistency (opus[1m] — opt-in per issue #198)
# ────────────────────────────────────────────

echo ""
echo "--- Recommended Model (opus[1m], opt-in) ---"

# Wizard recommends opus[1m] for power users but does NOT pin it by default
# (issue #198: a top-level model disables Claude Code auto-mode). These tests
# ensure the recommendation is surfaced in docs for discovery, while the CLI
# template and repo settings leave the pin opt-in via setup Step 9.5.

test_wizard_doc_recommends_opus_1m() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE 'opus\[1m\]' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md references opus[1m]"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md missing opus[1m] recommendation"
    fi
}

# After #198, the wizard doc must frame opus[1m] as opt-in (not "default").
# Guard against regression: someone re-writes the doc to call it the default again.
test_wizard_doc_frames_opus_1m_as_opt_in() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Must mention opt-in / auto-mode / #198 somewhere in the 1M section.
    if grep -qiE 'opt.?in.*opus\[1m\]|opus\[1m\].*opt.?in|issue.*198|auto.?mode.*disable|disable.*auto.?mode' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md frames opus[1m] as opt-in (not silent default)"
    else
        fail "Wizard doc must frame opus[1m] as opt-in + mention auto-mode impact (issue #198)"
    fi
}

# Regression guard (Codex round 1 finding #1): the doc must NOT contain any
# live phrase that calls opus[1m] the SDLC default. The prior test was too
# loose — it only required opt-in language to exist somewhere in the doc,
# so a contradictory "SDLC default (opus[1m])" table row slipped through.
# This test greps for the anti-pattern directly.
test_wizard_doc_no_default_opus_1m_wording() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Anti-patterns: assertions that opus[1m] IS the default.
    # - "SDLC default (opus[1m])"  — table cell format
    # - "default (opus[1m])" or "default (`opus[1m]`)"
    # - "opus[1m] as (the/our) default"
    # - "opus[1m] is (the/our) default"
    # - "opus[1m] as default" (no article)
    # Allowed: "default No", "default autocompact", "its default", where
    # "default" refers to something other than opus[1m].
    local hits
    hits=$(grep -nE 'SDLC default[[:space:]]*\(`?opus\[1m\]|default[[:space:]]+\(`?opus\[1m\]`?\)|`?opus\[1m\]`?[[:space:]]+(as|is)([[:space:]]+(the|our|a))?[[:space:]]+default' "$DOC" || true)
    if [ -z "$hits" ]; then
        pass "Wizard doc has no live 'default opus[1m]' phrasing (issue #198)"
    else
        fail "Wizard doc contains contradictory 'default opus[1m]' language: $hits"
    fi
}

test_sdlc_skill_recommends_opus_or_opusplan() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'opusplan|claude-opus-4-[0-9]+' "$SKILL"; then
        pass "skills/sdlc/SKILL.md references opusplan or Opus model pin"
    else
        fail "skills/sdlc/SKILL.md missing opusplan or claude-opus-4-X recommendation"
    fi
}

# #236(c): "no default model pin" / "no default env" for
# cli/templates/settings.json were tested identically here and in
# test-cli.sh (which pairs them with follow-on behavioral tests —
# test_fresh_init_does_not_write_model, merge/--force preservation) — kept
# test-cli.sh's, removed the duplicate here.

# Setup skill Step 9.5 must reference an Opus model alias (either the
# `opus[1m]` generic alias or an explicit `claude-opus-4-X[1m]` id) so users
# can discover the pin during the opt-in prompt — just without calling it the
# default. v1.80.0 flipped to explicit model ids for the recommended flagship.
test_setup_skill_mentions_model_pin_in_optin_prompt() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qE 'opusplan|claude-opus-4-[0-9]+' "$SKILL"; then
        pass "skills/setup/SKILL.md references opusplan or Opus model pin (Step 9.5)"
    else
        fail "skills/setup/SKILL.md must reference opusplan or claude-opus-4-X in Step 9.5"
    fi
}

# Repo's tracked .claude/settings.json must have advisorModel=fable and
# NO model pin (pin = 200K; omitting = 1M default on Max per feedback_model_pin_1m).
test_repo_settings_dogfood_setup_a() {
    local SETTINGS="$REPO_ROOT/.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then fail ".claude/settings.json not found"; return; fi
    local model advisor
    model=$(jq -r '.model // ""' "$SETTINGS" 2>/dev/null)
    advisor=$(jq -r '.advisorModel // ""' "$SETTINGS" 2>/dev/null)
    if [ "$model" = "" ] && [ "$advisor" = "fable" ]; then
        pass ".claude/settings.json dogfoods Setup A (no model pin + Fable advisor)"
    else
        fail ".claude/settings.json should have no model pin and advisorModel=fable (model=$model advisorModel=$advisor)"
    fi
}

# Hook must recommend a model pin (plain or opusplan — no [1m] since #390).
test_hooks_recommend_model() {
    local H1="$REPO_ROOT/hooks/model-effort-check.sh"
    if [ ! -f "$H1" ]; then fail "$H1 not found"; return; fi
    if ! grep -qE 'RECOMMENDED_MODELS=.*opusplan' "$H1"; then
        fail "model-effort-check.sh should set RECOMMENDED_MODELS including opusplan (#403)"
        return
    fi
    # instructions-loaded-check.sh must NOT re-declare the variable (would
    # reintroduce the #217 duplicate-nudge bug).
    local H2="$REPO_ROOT/hooks/instructions-loaded-check.sh"
    if [ -f "$H2" ] && grep -qE 'RECOMMENDED_MODEL=' "$H2"; then
        fail "instructions-loaded-check.sh declares RECOMMENDED_MODEL — must delegate to model-effort-check.sh per #217"
        return
    fi
    pass "model-effort-check.sh is single source of truth for Opus model recommendation (#217)"
}

# Setup skill must point users at /less-permission-prompts so they can
# auto-tune their allowlist without enabling auto mode. This is a native CC
# skill (ships with the CLI), so we just reference it — we don't reimplement.
test_setup_skill_mentions_less_permission_prompts() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qF '/less-permission-prompts' "$SKILL"; then
        pass "skills/setup/SKILL.md mentions /less-permission-prompts"
    else
        fail "skills/setup/SKILL.md should recommend /less-permission-prompts post-setup"
    fi
}

# Wizard doc must surface /less-permission-prompts in a Further Reading /
# complementary-tools section so readers know it's native CC, not wizard-owned.
test_wizard_doc_mentions_less_permission_prompts() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qF '/less-permission-prompts' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md mentions /less-permission-prompts"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md should reference /less-permission-prompts as a complementary native skill"
    fi
}

# Pin the second row of the "Complementary native skills" table too —
# otherwise a future edit could silently drop /permissions and no test catches it.
test_wizard_doc_mentions_permissions_command() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE '\| `/permissions` \|' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md pins /permissions row in complementary-skills table"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md should keep /permissions in the complementary-skills table"
    fi
}

# Test (#207): the wizard doc must explicitly warn that PCT_OVERRIDE and
# AUTO_COMPACT_WINDOW are ALTERNATIVES, not complementary. Setting both
# compounds (30% × 400K = 120K trigger = ~12% of 1M) — the consumer hit
# this in practice and autocompact fired at 12% context.
test_wizard_doc_warns_against_compound_autocompact_config() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE '(do not set both|don.t set both|alternatives.*not|pick one.*not both|either.*PCT_OVERRIDE.*or.*AUTO_COMPACT_WINDOW|setting both.*compound)' "$DOC"; then
        pass "wizard doc explicitly marks PCT_OVERRIDE / AUTO_COMPACT_WINDOW as alternatives (#207)"
    else
        fail "wizard doc must warn against setting both PCT_OVERRIDE AND AUTO_COMPACT_WINDOW (compound trigger footgun, #207)"
    fi
}

# Test (#207, Codex round 1 finding 2): the SHIPPED `/sdlc` skill must not
# repeat the ambiguous "30 or AUTO_COMPACT_WINDOW=400000" wording. This file
# is distributed via npm to consumers' .claude/skills/sdlc/, so doc drift
# here puts the same footgun back in front of every user.
test_sdlc_skill_warns_against_compound_autocompact_config() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qiE '(do not set (both|this)|don.t set both|pick one|alternatives.*not)' "$SKILL"; then
        pass "skills/sdlc/SKILL.md warns against autocompact compound config (#207)"
    else
        fail "skills/sdlc/SKILL.md must warn against PCT_OVERRIDE + AUTO_COMPACT_WINDOW compound (#207)"
    fi
}

# Test (#207, Codex round 1 finding 2; updated #434 for Sonnet 5): the shipped
# `/sdlc` skill must frame the model pin as a recommendation, not a silent
# default. v1.80.0 flipped opus[1m] -> claude-opus-4-6[1m]; #434 (2026-07-04)
# made Sonnet 5 the new recommended driver. Any of the three is acceptable —
# what matters is the section explicitly frames it as "Recommended:".
test_sdlc_skill_frames_model_as_recommendation() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'Recommended:.*claude-opus|Recommended:.*opusplan|Recommended:.*Sonnet|opusplan.*claude-opus' "$SKILL"; then
        pass "skills/sdlc/SKILL.md frames model pin as recommendation"
    else
        fail "skills/sdlc/SKILL.md must recommend Sonnet 5, opusplan, or claude-opus-4-X"
    fi
}

# Tests (#251 + #225): Browser Tooling Policy section.
# Greps run INSIDE the policy section, not against the whole doc — otherwise
# claims could be satisfied by unrelated mentions elsewhere (Codex round 1
# finding 3).

# Extract the Browser Tooling Policy section: from `### Browser Tooling Policy`
# heading to the next `###` or `##` heading. Echoes the section content.
extract_browser_tooling_policy_section() {
    local DOC="$1"
    awk '
        /^### Browser Tooling Policy/ { in_section = 1; print; next }
        in_section && /^##[#]?[^#]/ { in_section = 0 }
        in_section { print }
    ' "$DOC"
}

test_wizard_doc_has_browser_tooling_policy_section() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qE '^### Browser Tooling Policy[[:space:]]*$' "$DOC"; then
        pass "wizard doc has 'Browser Tooling Policy' section heading (#225, #251)"
    else
        fail "wizard doc must have a 'Browser Tooling Policy' section (#225, #251)"
    fi
}

# #225: 3-way split — all 3 tools must be named INSIDE the policy section
test_wizard_doc_browser_policy_covers_three_way_split() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if [ -z "$section" ]; then fail "Browser Tooling Policy section is empty/missing"; return; fi
    local ok=true
    echo "$section" | grep -qE 'Playwright tests' || ok=false
    echo "$section" | grep -qE 'Playwright MCP' || ok=false
    echo "$section" | grep -qiE 'browser-use|real.browser tooling' || ok=false
    if [ "$ok" = true ]; then
        pass "policy section covers 3-way browser-tooling split (tests / MCP / real-browser, #225)"
    else
        fail "policy section must cover all 3 browser tooling approaches (#225)"
    fi
}

# #251: profile isolation for concurrent agents — INSIDE the policy section
test_wizard_doc_mcp_profile_isolation_for_concurrent_agents() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE 'concurrent.*(agent|MCP client)|multiple (agent|MCP client)|profile.lock|--user-data-dir|--isolated' ; then
        pass "policy section covers MCP profile-isolation for concurrent agent workflows (#251)"
    else
        fail "policy section must explain MCP profile isolation for concurrent agents (#251)"
    fi
}

# #251: upstream Playwright rejection — INSIDE the policy section
test_wizard_doc_notes_playwright_default_isolation_rejected() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE '(playwright/issues/40419|playwright/pull/40420|upstream.*rejected|very breaking)'; then
        pass "policy section notes upstream Playwright rejected default-isolated (#251)"
    else
        fail "policy section must explain that upstream Playwright rejected default-isolated (#251)"
    fi
}

# #225: trigger examples for real-browser tooling — INSIDE the policy section
test_wizard_doc_real_browser_trigger_examples() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(extract_browser_tooling_policy_section "$DOC")
    if echo "$section" | grep -qiE 'registrar|DNS setup|wallet|Web3|auth.heavy|profile.dependent|stateful operator|admin panel'; then
        pass "policy section includes real-browser trigger examples (#225)"
    else
        fail "policy section must include trigger examples for real-browser tooling (#225)"
    fi
}

test_wizard_doc_recommends_opus_1m
test_wizard_doc_frames_opus_1m_as_opt_in
test_wizard_doc_no_default_opus_1m_wording
test_wizard_doc_warns_against_compound_autocompact_config
test_sdlc_skill_warns_against_compound_autocompact_config
test_sdlc_skill_frames_model_as_recommendation
test_wizard_doc_has_browser_tooling_policy_section
test_wizard_doc_browser_policy_covers_three_way_split
test_wizard_doc_mcp_profile_isolation_for_concurrent_agents
test_wizard_doc_notes_playwright_default_isolation_rejected
test_wizard_doc_real_browser_trigger_examples
test_sdlc_skill_recommends_opus_or_opusplan
test_setup_skill_mentions_model_pin_in_optin_prompt
test_repo_settings_dogfood_setup_a
test_hooks_recommend_model
test_setup_skill_mentions_less_permission_prompts
test_wizard_doc_mentions_less_permission_prompts
test_wizard_doc_mentions_permissions_command

# ────────────────────────────────────────────
# XDLC Ecosystem Cross-References
# ────────────────────────────────────────────
#
# This repo is one of three published siblings:
#   - agentic-sdlc-wizard (this repo, npm) — Claude Code SDLC
#   - codex-sdlc-wizard (npm) — Codex SDLC adapter
#   - claude-gdlc-wizard (npm) — Game Development Life Cycle sibling
#
# Each package's README and primary docs should cross-reference the others
# so users landing on one package can discover the family. Without this,
# discoverability across the 3 packages is weak.

echo ""
echo "--- XDLC Ecosystem Cross-Refs ---"

# README must reference all 3 sibling packages by name so users on npm/GH
# can discover the family. Codex sibling = `codex-sdlc-wizard`,
# GDLC sibling = `claude-gdlc-wizard`. This repo's npm name is
# `agentic-sdlc-wizard` (already implicit in install commands, but the
# Ecosystem section should make all three explicit).
test_readme_references_all_siblings() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    local missing=()
    grep -q 'codex-sdlc-wizard' "$README" || missing+=("codex-sdlc-wizard")
    grep -q 'claude-gdlc-wizard' "$README" || missing+=("claude-gdlc-wizard")
    if [ ${#missing[@]} -gt 0 ]; then
        fail "README.md missing sibling refs: ${missing[*]}"
    else
        pass "README.md references both sibling packages (codex-sdlc-wizard, claude-gdlc-wizard)"
    fi
}

# README should have a discoverable Ecosystem/Family section heading so
# users skimming the TOC find the cross-references, not just inline mentions.
test_readme_has_ecosystem_section() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if grep -qiE '^##+ (XDLC )?(Ecosystem|Family|Sibling|Related Projects)' "$README"; then
        pass "README.md has an Ecosystem/Family section heading"
    else
        fail "README.md missing an Ecosystem/Family/Siblings section heading"
    fi
}

# Wizard doc already mentions Codex sibling (line 501); GDLC was added to
# the family 2026-04-26 and should be referenced wherever Codex is.
test_wizard_doc_mentions_gdlc_sibling() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -q 'claude-gdlc-wizard' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md references claude-gdlc-wizard sibling"
    else
        fail "Wizard doc missing claude-gdlc-wizard sibling reference"
    fi
}

# Codex sibling must surface near the top of README + wizard doc so users
# landing on either entry point see the alternative-agent option without
# scrolling 250+ lines to the Ecosystem section. (User feedback
# 2026-05-04: "mention codex-sdlc-wizard towards the top after mentioning
# this is for claude — 'this is for Claude but check out codex for
# alternatives'.")
test_readme_mentions_codex_near_top() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi
    if head -30 "$README" | grep -q 'codex-sdlc-wizard'; then
        pass "README.md mentions codex-sdlc-wizard within first 30 lines"
    else
        fail "README.md does not mention codex-sdlc-wizard near top (first 30 lines)"
    fi
}

test_wizard_doc_mentions_codex_near_top() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if head -50 "$DOC" | grep -q 'codex-sdlc-wizard'; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md mentions codex-sdlc-wizard within first 50 lines"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md does not mention codex-sdlc-wizard near top (first 50 lines)"
    fi
}

test_readme_references_all_siblings
test_readme_has_ecosystem_section
test_wizard_doc_mentions_gdlc_sibling
test_readme_mentions_codex_near_top
test_wizard_doc_mentions_codex_near_top

# Setup skill must point users at /insights with the explicit qualitative-only
# caveat (ROADMAP #235a, original research #206). Without the caveat, the doc
# risks drifting into "we have token-spike detection via /insights" — which
# would be wrong; /insights is qualitative friction surfacing only, NOT a
# substitute for #220's raw-JSONL token instrumentation.
test_setup_skill_mentions_insights_with_caveat() {
    local SKILL="$REPO_ROOT/skills/setup/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/setup/SKILL.md not found"; return; fi
    if grep -qF '/insights' "$SKILL" && \
       grep -qE 'friction|qualitative' "$SKILL" && \
       grep -qE '#220|token-spike|raw.*session.*JSONL|does NOT replace' "$SKILL"; then
        pass "skills/setup/SKILL.md mentions /insights with qualitative-only caveat (#235a)"
    else
        fail "skills/setup/SKILL.md must reference /insights + friction/qualitative + the #220 non-replacement caveat"
    fi
}

# Wizard doc must list /insights in the "Complementary native skills" table
# (next to /less-permission-prompts and /permissions) AND carry the
# qualitative-only caveat as a paragraph below the table. Same anti-overclaim
# protection as the setup-skill test above.
test_wizard_doc_lists_insights_with_caveat() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # Extract the Complementary native skills section
    local section
    section=$(awk '/Complementary native skills/,/### When Claude Code Improves/' "$DOC")
    if echo "$section" | grep -qF '/insights' && \
       echo "$section" | grep -qE 'friction|qualitative' && \
       echo "$section" | grep -qE '#220|token-spike|raw.*session.*JSONL|not a substitute'; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md lists /insights with qualitative-only caveat (#235a)"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md 'Complementary native skills' section must list /insights with the #220 non-replacement caveat"
    fi
}

# SDLC skill must carry the skill-source-and-precedence preamble (ROADMAP
# #338). Prevents user confusion when both repo-local .claude/skills/sdlc/
# and global ~/.claude/skills/sdlc/ exist with the same name.
test_sdlc_skill_has_precedence_preamble() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE '^## Skill source & precedence' "$SKILL" && \
       grep -qF 'repo-local' "$SKILL" && \
       grep -qF 'head -5' "$SKILL"; then
        pass "skills/sdlc/SKILL.md carries 'Skill source & precedence' preamble (#338)"
    else
        fail "skills/sdlc/SKILL.md must include '## Skill source & precedence' section with repo-local-wins guidance + head -5 verification one-liner"
    fi
}

# Codex stdin-hang fix: every documented multi-line `codex exec` block must
# append `< /dev/null` so callers don't hit the codex stdin-read hang from
# non-interactive parents (background, hooks, CI, CC Bash tool). Validated
# on codex-cli 0.130.0 / macOS 14, 2026-05-15.
#
# Matcher covers BOTH multi-line shapes:
#   1. `codex exec \`                (bare, args on continuation lines)
#   2. `codex exec -c '...' -s ... \` (flags on the first line, continuing)
# Both end the first line with a trailing backslash. False positives are
# limited to lines containing the literal word "codex exec" followed by a
# trailing-backslash continuation, which is exactly what we want to enforce.
test_codex_exec_blocks_redirect_stdin() {
    local missing=0
    for f in "$REPO_ROOT/README.md" "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" "$REPO_ROOT/skills/sdlc/SKILL.md"; do
        if [ ! -f "$f" ]; then continue; fi
        local total stdin_redirected
        total=$(grep -cE '^[[:space:]]*codex exec( .*)? \\$' "$f" || true)
        stdin_redirected=$(awk '
            /^[[:space:]]*codex exec( .*)? \\$/ { in_block=1; depth=0; next }
            in_block {
                depth++
                if (/<[[:space:]]*\/dev\/null/) { count++; in_block=0; next }
                if (depth > 25) { in_block=0 }
            }
            END { print count+0 }
        ' "$f")
        if [ "$total" -gt 0 ] && [ "$stdin_redirected" -lt "$total" ]; then
            fail "$f: $stdin_redirected of $total multi-line codex exec blocks redirect stdin (need all $total to append '< /dev/null'). Matcher covers both 'codex exec \\' and 'codex exec -c ... \\' shapes."
            missing=$((missing+1))
        fi
    done
    if [ "$missing" -eq 0 ]; then
        pass "All documented multi-line codex exec blocks append '< /dev/null' (stdin-hang fix)"
    fi
}

# SDLC skill must carry the /goal wrapper with all 5 quality elements
# (#347 corrected 2026-05-24). Existence-only would let drift remove the
# safety guidance — each item below is a load-bearing claim from the
# corrected research doc (.reviews/347-goal-mode-research-CORRECTED.md).
test_sdlc_skill_has_goal_wrapper() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    local missing=""
    grep -qE '^## Long-Running Goals \(`?/goal`?\)' "$SKILL" || missing+=" section-header"
    grep -qF 'v2.1.143' "$SKILL" || missing+=" version-floor-2.1.143"
    grep -qiE 'trusted|untrusted' "$SKILL" || missing+=" trusted-workspace-preflight"
    grep -qF 'disableAllHooks' "$SKILL" || missing+=" disableAllHooks-preflight"
    grep -qiE 'turn(/| )?time bound|hard.*bound|stop after' "$SKILL" || missing+=" hard-bound-guidance"
    grep -qiE 'cannot call tools|can.t call tools|transcript[ -]only' "$SKILL" || missing+=" anti-pattern-off-transcript"
    grep -qiE 'resume.*reset|--resume.*counters|counters.*reset' "$SKILL" || missing+=" resume-caveat"
    # PR-D additions: 95% confidence gate + DLC binding in condition.
    # Without these, /goal becomes "20 turns of flailing" — the evaluator
    # has no anchor for correctness, only for completion.
    grep -qiE 'confidence gate|HIGH 95%|below.*95%|95%.*confidence' "$SKILL" || missing+=" 95-percent-confidence-gate"
    grep -qiE 'DLC binding|name the (active )?DLC|condition MUST name' "$SKILL" || missing+=" DLC-binding-rule"
    if [ -z "$missing" ]; then
        pass "skills/sdlc/SKILL.md /goal wrapper has all required quality elements (#347 + PR-D)"
    else
        fail "skills/sdlc/SKILL.md /goal wrapper missing:$missing"
    fi
}

# Cross-model review guidance must teach background-mode (issue #364, 2026-05-27).
# Bash tool clamps `timeout` to 600000 ms; foreground codex gets force-killed at
# the wall. Without this guidance, sessions burn 60+ minutes on 7-minute reviews
# (incident: 70 min + 9 Stop-hook re-invocations before harness safeguard fired).
test_codex_review_guidance_teaches_background_mode() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local missing=""
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if [ ! -f "$WIZARD" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    # SKILL.md must teach background-mode + cite the 10-min cap reason
    grep -qF 'run_in_background: true' "$SKILL" || missing+=" SKILL.md:run_in_background"
    grep -qiE '600000|10 min|10-min' "$SKILL" || missing+=" SKILL.md:10-min-cap-reason"
    # Wizard doc must carry the same guidance (verified in at least one of the
    # two Cross-Model Review sections — both edits land in the same release).
    grep -qF 'run_in_background: true' "$WIZARD" || missing+=" WIZARD.md:run_in_background"
    grep -qiE '600000|10 min|10-min' "$WIZARD" || missing+=" WIZARD.md:10-min-cap-reason"
    if [ -z "$missing" ]; then
        pass "Cross-model review guidance teaches background-mode + cites 10-min cap (#364)"
    else
        fail "Cross-model review background-mode guidance missing:$missing"
    fi
}

test_setup_skill_mentions_insights_with_caveat
test_wizard_doc_lists_insights_with_caveat
test_sdlc_skill_has_precedence_preamble
test_codex_exec_blocks_redirect_stdin
test_sdlc_skill_has_goal_wrapper
test_codex_review_guidance_teaches_background_mode

# #372: Cross-model review is REQUIRED for high-stakes, not opt-in
test_cross_model_review_required_not_optional() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local ok=true
    grep -q '## Cross-Model Review (REQUIRED' "$SKILL" || ok=false
    grep -q 'REQUIRED' "$WIZARD" || ok=false
    grep -q 'If Configured' "$SKILL" && ok=false
    grep -q 'log justification' "$SKILL" || ok=false
    if [ "$ok" = true ]; then
        pass "#372: Cross-model review REQUIRED in skill + wizard, skip requires justification"
    else
        fail "#372: Cross-model review heading must say REQUIRED, not 'If Configured', with log justification"
    fi
}

test_cross_model_review_required_not_optional

# ────────────────────────────────────────────
# AI Setup Lanes — Sonnet 5 + model-aware effort (July 2026 update)
# ────────────────────────────────────────────

echo ""
echo "--- AI Setup Lanes ---"

test_setup_lanes_references_sonnet_5() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$LANES"; then
        pass "AI_SETUP_LANES.md references Sonnet 5"
    else
        fail "AI_SETUP_LANES.md must reference Sonnet 5 (launched June 30, replaces Sonnet 4.6)"
    fi
}

test_setup_lanes_has_model_aware_effort() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'xhigh.*Opus 4\.8|Opus 4\.8.*xhigh' "$LANES" \
        && grep -qE 'high.*Sonnet 5|Sonnet 5.*high' "$LANES"; then
        pass "AI_SETUP_LANES.md has model-aware effort (xhigh for Opus 4.8, high for Sonnet 5)"
    else
        fail "AI_SETUP_LANES.md must recommend effort per model (xhigh for Opus 4.8, high for Sonnet 5)"
    fi
}

test_setup_lanes_no_blanket_max() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qE 'max.*all models|always.*max|max.*every' "$LANES"; then
        fail "AI_SETUP_LANES.md must NOT recommend blanket max for all models (max overthinks on Opus 4.8 and Sonnet 5)"
    else
        pass "AI_SETUP_LANES.md does not blanket-recommend max for all models"
    fi
}

test_setup_lanes_effort_escalation_ladder() {
    local LANES="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$LANES" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    if grep -qiE 'escalat|ramp|bump.*effort|raise.*effort|ladder' "$LANES"; then
        pass "AI_SETUP_LANES.md documents effort escalation (start at default, raise when needed)"
    else
        fail "AI_SETUP_LANES.md must document effort escalation strategy"
    fi
}

test_setup_lanes_references_sonnet_5
test_setup_lanes_has_model_aware_effort
test_setup_lanes_no_blanket_max
test_setup_lanes_effort_escalation_ladder

# The /sdlc skill's "Recommended Model" section is read on every /sdlc
# invocation — it must not enshrine the same blanket-max bug the hook had.
# Real incident: a user's ~/.zshrc had CLAUDE_CODE_EFFORT_LEVEL=max from
# this exact advice, and it silently overrode /effort xhigh after they
# switched to Sonnet 5 (2026-07-04).
test_sdlc_skill_recommended_model_is_model_aware() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'CLAUDE_CODE_EFFORT_LEVEL.?=.?max.? in (settings )?env block' "$SKILL"; then
        fail "skills/sdlc/SKILL.md must not blanket-recommend persisting max via env var (bit a real user, 2026-07-04)"
    else
        pass "skills/sdlc/SKILL.md does not blanket-recommend persisting max via env var"
    fi
}

test_sdlc_skill_recommended_model_mentions_sonnet_5() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$SKILL"; then
        pass "skills/sdlc/SKILL.md Recommended Model section mentions Sonnet 5"
    else
        fail "skills/sdlc/SKILL.md must mention Sonnet 5 in Recommended Model section"
    fi
}

test_sdlc_skill_recommended_model_is_model_aware
test_sdlc_skill_recommended_model_mentions_sonnet_5

# This repo's own dogfooded SDLC.md has the identical table/callout pattern
# as skills/sdlc/SKILL.md had — same blanket-max bug, same stale opus-4-6
# recommendation. It also already has a "Lessons Learned" entry (added
# 2026-07-04) explaining why blanket max is wrong, which the table
# contradicted until fixed. Found while shipping #436/#437, 2026-07-05.
test_sdlc_config_recommended_effort_is_model_aware() {
    local CONFIG="$REPO_ROOT/SDLC.md"
    if [ ! -f "$CONFIG" ]; then fail "SDLC.md not found"; return; fi
    if grep -qE 'CLAUDE_CODE_EFFORT_LEVEL.?=.?max.? in (settings )?env block' "$CONFIG"; then
        fail "SDLC.md must not blanket-recommend persisting max via env var (contradicts its own Lessons Learned entry)"
    else
        pass "SDLC.md does not blanket-recommend persisting max via env var"
    fi
}

test_sdlc_config_recommended_model_mentions_sonnet_5() {
    local CONFIG="$REPO_ROOT/SDLC.md"
    if [ ! -f "$CONFIG" ]; then fail "SDLC.md not found"; return; fi
    if grep -qE 'Sonnet 5|claude-sonnet-5' "$CONFIG"; then
        pass "SDLC.md Recommended Model row mentions Sonnet 5"
    else
        fail "SDLC.md must mention Sonnet 5 in its Recommended Model row"
    fi
}

test_sdlc_config_recommended_effort_is_model_aware
test_sdlc_config_recommended_model_mentions_sonnet_5

# Cowork plugin (cowork/) shipped in PR #410 (ROADMAP #424) with working
# skills + prompt-based hooks and its own README, but was never
# cross-referenced from the main wizard doc — invisible to anyone who
# only reads CLAUDE_CODE_SDLC_WIZARD.md. Found 2026-07-05.
test_wizard_doc_has_cowork_section() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if grep -qiE '^#+ .*Cowork' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md has a Cowork section"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md must have a Cowork section cross-referencing cowork/README.md"
    fi
}

test_wizard_doc_has_cowork_section

# Autocompact Tuning table previously blanket-recommended 30% for "any 1M
# model" — this was Opus-specific (opus[1m] needed an opt-in pin for
# extended context). Sonnet 5 always runs 1M natively with its own
# proactive-compaction default (~967K, per code.claude.com/docs/en/
# model-config#sonnet-5-context-window) — the 30% figure was never
# re-derived for it and doesn't apply. Verified via live research
# 2026-07-05, not carried over from the Opus-era table unexamined.
test_wizard_doc_autocompact_mentions_sonnet_5() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local section
    section=$(awk '/^### Autocompact Tuning/{f=1} f && /^###[^#]/ && !/^### Autocompact Tuning/{f=0} f' "$DOC")
    if echo "$section" | grep -qE 'Sonnet 5'; then
        pass "Autocompact Tuning section addresses Sonnet 5 specifically"
    else
        fail "Autocompact Tuning section must address Sonnet 5's native 1M/967K default, not just Opus-era guidance"
    fi
}

test_wizard_doc_autocompact_mentions_sonnet_5

# ROADMAP #437: the wizard doc has 2 separate copies of the cross-model
# review protocol (a condensed summary section and a fuller tutorial
# section), each with its own prose instruction AND its own flow diagram —
# 3 prose "If CERTIFIED" lines plus 4 diagram terminal states (2 per
# section), 7 decision points total. The v1.86.0 codex-gate-check.sh fix
# requires every one of them to write commit_sha into handoff.json.
#
# Codex round 1 caught 2 of 3 prose lines fixed (1 missed); a global-count
# comparison (commit_sha mentions >= "If CERTIFIED" mentions) briefly
# replaced it but round 2's mutation testing proved that heuristic has slack
# — extra commit_sha mentions elsewhere in the doc could mask an individual
# line silently losing its own instruction, and it never covered the
# diagram terminal states at all (round 2 also found a 3rd, entirely
# separate diagram — the first section's own flow chart at lines ~2515/2526
# — that neither the prose fix nor the original test had ever touched).
#
# Per-line check instead: every line matching one of the 3 known decision-
# point shapes (prose "If CERTIFIED", diagram "CERTIFIED? ", or diagram
# "→ CERTIFIED") must contain "commit_sha" on that SAME line — no aggregate
# slack possible. Verified the exact pattern below matches all 7 real
# decision-point lines and none of the ~13 other CERTIFIED mentions in the
# doc (explanatory prose, reviewer-prompt "End with CERTIFIED or NOT
# CERTIFIED" text, unrelated "implicit CERTIFIED" references).
test_wizard_doc_certified_paths_all_mention_commit_sha() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local decision_lines total missing offenders
    decision_lines=$(grep -nE "If CERTIFIED|CERTIFIED\? |→ CERTIFIED" "$DOC" 2>/dev/null || true)
    total=$(echo "$decision_lines" | { grep -c . || true; })
    offenders=$(echo "$decision_lines" | { grep -v "commit_sha" || true; })
    missing=$(echo "$offenders" | { grep -c . || true; })
    if [ "$total" -gt 0 ] && [ "$missing" -eq 0 ]; then
        pass "every CERTIFIED decision point in the wizard doc mentions commit_sha on the same line ($total checked)"
    else
        fail "$missing of $total CERTIFIED decision points in the wizard doc are missing a same-line commit_sha mention — at least one path silently skips the ROADMAP #437 staleness-fix instruction. Offending lines:
$offenders"
    fi
}

test_wizard_doc_certified_paths_all_mention_commit_sha

# #236(c): relocated from the dissolved tests/test-degradation-detection.sh
# (5 of that file's 14 tests, the only non-stub non-duplicate survivors —
# doc-hardening checks belong here with the rest of the wizard-doc consistency
# suite, not in a file named for CI score-persistence/degradation-detection).

# Wizard doc effort section must explain WHY effort matters — not just how to
# set it — by naming "adaptive thinking" as the degradation mechanism.
test_wizard_doc_effort_section_cites_adaptive_thinking() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -iq "adaptive thinking"; then
        pass "wizard doc effort section references adaptive thinking as root cause"
    else
        fail "wizard doc effort section must reference 'adaptive thinking' as degradation root cause"
    fi
}

# Must scope "medium is the default" to Pro/Max plans specifically (API/Team/
# Enterprise default to high) rather than a blanket claim.
test_wizard_doc_medium_default_scoped_to_pro_max() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -iE "Pro.*Max|Max.*Pro|Pro/Max|Pro and Max"; then
        if echo "$effort_section" | grep -iE "medium.*(default|defaults)" | grep -iqE "Pro|Max|plan"; then
            pass "wizard doc medium-default claim scoped to Pro/Max plans"
        elif ! echo "$effort_section" | grep -iqE "medium.*(default|defaults)"; then
            pass "wizard doc medium-default scoped to Pro/Max plans (no blanket claim)"
        else
            fail "wizard doc has a medium-default claim not scoped to Pro/Max"
        fi
    else
        fail "wizard doc effort section must reference Pro/Max plans for medium-default scope"
    fi
}

test_wizard_doc_cites_live_effort_docs_url() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -q "code.claude.com"; then
        pass "wizard doc effort section cites code.claude.com docs"
    else
        fail "wizard doc effort section must cite code.claude.com docs (not memory files or vague references)"
    fi
}

# CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING is a "nuclear option" — must be
# documented as opt-in, never shipped as a default in the CLI template.
test_wizard_doc_disable_adaptive_thinking_is_optin() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local SETTINGS="$REPO_ROOT/cli/templates/settings.json"
    local effort_section
    effort_section=$(sed -n '/## Recommended Effort Level/,/^## /p' "$DOC")
    if echo "$effort_section" | grep -q "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING"; then
        if jq -e '.env.CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING' "$SETTINGS" > /dev/null 2>&1; then
            fail "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING should be opt-in, not in default settings.json"
        else
            pass "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING documented as opt-in (not in default template)"
        fi
    else
        fail "wizard doc must document CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING env var"
    fi
}

# Anti-laziness guidance must name at least 2 specific mechanisms, not a vague
# "be thorough" — otherwise it reads as unenforceable advice.
test_wizard_doc_anti_laziness_names_specific_mechanisms() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    local wizard_content
    wizard_content=$(cat "$DOC")
    local mechanism_count=0
    echo "$wizard_content" | grep -iq "adaptive thinking" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "effort.level\|effort:.*high\|effort.*level" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "thinking budget\|reasoning.*budget\|reasoning.*allocat" && mechanism_count=$((mechanism_count + 1))
    echo "$wizard_content" | grep -iq "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING" && mechanism_count=$((mechanism_count + 1))
    if [ "$mechanism_count" -ge 2 ]; then
        pass "wizard doc anti-laziness guidance references $mechanism_count specific mechanisms"
    else
        fail "anti-laziness guidance must reference specific mechanisms (adaptive thinking, effort levels, etc.), found $mechanism_count"
    fi
}

test_wizard_doc_effort_section_cites_adaptive_thinking
test_wizard_doc_medium_default_scoped_to_pro_max
test_wizard_doc_cites_live_effort_docs_url
test_wizard_doc_disable_adaptive_thinking_is_optin
test_wizard_doc_anti_laziness_names_specific_mechanisms

# ────────────────────────────────────────────
# ROADMAP archive split (#236(f), 2026-07-06)
# ────────────────────────────────────────────

# A row number must never appear in both the active table and the archive —
# that would mean a row was copied instead of moved, or edited independently
# in both places after the split.
test_roadmap_no_duplicate_row_numbers_across_files() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    local ARCHIVE="$REPO_ROOT/ROADMAP_ARCHIVE.md"
    if [ ! -f "$ROADMAP" ] || [ ! -f "$ARCHIVE" ]; then
        fail "ROADMAP.md or ROADMAP_ARCHIVE.md not found"
        return
    fi
    local active_nums archive_nums dupes
    active_nums=$(grep -oE '^\| *[0-9]+ *\|' "$ROADMAP" | grep -oE '[0-9]+' | sort -un)
    archive_nums=$(grep -oE '^\| *[0-9]+ *\|' "$ARCHIVE" | grep -oE '[0-9]+' | sort -un)
    # NOTE: avoid `comm <(...) <(...)` here — BSD comm on macOS silently
    # returns empty output when both inputs are process substitutions
    # (verified: two real files behave correctly, two /dev/fd fifos don't).
    # Concatenating two already-deduped lists and taking uniq -d is
    # portable and gives the same "appears in both" answer.
    dupes=$(printf '%s\n%s\n' "$active_nums" "$archive_nums" | sort -n | uniq -d)
    if [ -z "$dupes" ]; then
        pass "no row number appears in both ROADMAP.md and ROADMAP_ARCHIVE.md"
    else
        fail "row number(s) present in BOTH ROADMAP.md and ROADMAP_ARCHIVE.md (should be moved, not copied): $dupes"
    fi
}

# Spot-check a sample of rows known to still be open as of the 2026-07-06
# split — proves the split didn't silently archive an active item.
test_roadmap_key_open_items_present() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    if [ ! -f "$ROADMAP" ]; then fail "ROADMAP.md not found"; return; fi
    local missing=""
    for n in 19 89 236 424 434 438; do
        if ! grep -qE "^\| *$n *\|" "$ROADMAP"; then
            missing="$missing $n"
        fi
    done
    if [ -z "$missing" ]; then
        pass "known-open ROADMAP rows (19/89/236/424/434/438) all present in ROADMAP.md"
    else
        fail "known-open ROADMAP row(s) missing from ROADMAP.md:$missing"
    fi
}

# Spot-check a sample of rows known to be fully resolved as of the 2026-07-06
# split — proves the split actually moved them out of the active table.
test_roadmap_archive_has_key_archived_items() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    local ARCHIVE="$REPO_ROOT/ROADMAP_ARCHIVE.md"
    if [ ! -f "$ROADMAP" ] || [ ! -f "$ARCHIVE" ]; then
        fail "ROADMAP.md or ROADMAP_ARCHIVE.md not found"
        return
    fi
    local bad=""
    for n in 1 14 20 231; do
        if ! grep -qE "^\| *$n *\|" "$ARCHIVE"; then
            bad="$bad $n(missing-from-archive)"
        fi
        if grep -qE "^\| *$n *\|" "$ROADMAP"; then
            bad="$bad $n(still-in-active-table)"
        fi
    done
    if [ -z "$bad" ]; then
        pass "known-resolved ROADMAP rows (1/14/20/231) all archived, none left in active table"
    else
        fail "archive split issue(s):$bad"
    fi
}

test_roadmap_no_duplicate_row_numbers_across_files
test_roadmap_key_open_items_present
test_roadmap_archive_has_key_archived_items

# ────────────────────────────────────────────
# ROADMAP #439: GPT-5.6 (Sol) supersedes GPT-5.5 as cross-model reviewer
# Per-location checks, not whole-file counts (per #437's CHANGELOG lesson:
# aggregate checks have slack that lets one unfixed line hide behind an
# unrelated match elsewhere in the same file). Each line must both GAIN
# "5.6" and LOSE "5.5" (and "5.4" on fallback-chain lines) — a half-applied
# edit (mentions 5.6 nearby but leaves the old 5.5/5.4 name in place) fails.
# ────────────────────────────────────────────

# Checks one line of a file both contains a required substring and does NOT
# contain any of the forbidden substrings. Echoes a descriptive failure (or
# nothing on success) for the caller to collect via command substitution,
# rather than calling fail() directly, so one test function can report every
# stale line in one message. (bash 3.x on macOS has no namerefs.)
_check_line_has_and_lacks() {
    local file="$1" line_num="$2" must_have_csv="$3"
    shift 3
    local content
    content="$(sed -n "${line_num}p" "$file")"
    if [ -z "$content" ]; then
        echo "${file}:${line_num}(line-missing)"
        return
    fi
    local required
    for required in ${must_have_csv//,/ }; do
        if ! printf '%s' "$content" | grep -qi "$required"; then
            echo "${file}:${line_num}(missing '$required')"
            return
        fi
    done
    for forbidden in "$@"; do
        if printf '%s' "$content" | grep -qi "$forbidden"; then
            echo "${file}:${line_num}(stale '$forbidden')"
            return
        fi
    done
}

test_ai_setup_lanes_reviewer_is_gpt56() {
    local F="$REPO_ROOT/AI_SETUP_LANES.md"
    if [ ! -f "$F" ]; then fail "AI_SETUP_LANES.md not found"; return; fi
    local bad=""
    # "5\.6" AND "Sol" (not just one or the other) so a Sol->Terra swap, or a
    # future GPT-5.7 Sol rename, both fail.
    # (Line numbers re-pinned +4 after the 2026-07-13 Setup A clarity insertion.)
    for n in 13 16 32 45 47 123 168 172 210 211 214; do
        bad="$bad$(_check_line_has_and_lacks "$F" "$n" "5\.6,Sol" "5\.5")"
    done
    # L127 is the fallback-chain line: must name "5\.6" AND BOTH Sol (primary)
    # and Terra (fallback target) so a Terra->Luna swap also fails.
    bad="$bad$(_check_line_has_and_lacks "$F" 127 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    if [ -z "$bad" ]; then
        pass "AI_SETUP_LANES.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "AI_SETUP_LANES.md stale reviewer-model reference(s):$bad"
    fi
}

test_readme_reviewer_is_gpt56() {
    local F="$REPO_ROOT/README.md"
    if [ ! -f "$F" ]; then fail "README.md not found"; return; fi
    local bad=""
    # L126 is the fallback-chain line: must name "5\.6" AND BOTH Sol and Terra.
    bad="$bad$(_check_line_has_and_lacks "$F" 126 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    for n in 186 187 188; do
        bad="$bad$(_check_line_has_and_lacks "$F" "$n" "5\.6,Sol" "5\.5")"
    done
    if [ -z "$bad" ]; then
        pass "README.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "README.md stale reviewer-model reference(s):$bad"
    fi
}

# L151 is a historical eval citation (Andon Labs Vending-Bench actually used
# GPT-5.5 at the time) — must NOT be rewritten, or the citation becomes
# factually wrong about what model that benchmark run used.
test_readme_vending_bench_citation_untouched() {
    local F="$REPO_ROOT/README.md"
    if [ ! -f "$F" ]; then fail "README.md not found"; return; fi
    if sed -n '151p' "$F" | grep -q "GPT-5\.5"; then
        pass "README.md L151 vending-bench citation still names GPT-5.5 (historical, untouched)"
    else
        fail "README.md L151 vending-bench citation no longer names GPT-5.5 — historical citation was rewritten"
    fi
}

test_wizard_doc_reviewer_is_gpt56() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    local bad=""
    bad="$bad$(_check_line_has_and_lacks "$F" 1090 "5\.6,Sol" "5\.5")"
    bad="$bad$(_check_line_has_and_lacks "$F" 1113 "5\.6,Sol" "5\.5")"
    # L3855 and L3860 are fallback-chain lines: must name "5\.6" AND BOTH Sol
    # and Terra.
    bad="$bad$(_check_line_has_and_lacks "$F" 3855 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    bad="$bad$(_check_line_has_and_lacks "$F" 3860 "5\.6,Sol,Terra" "5\.5" "5\.4")"
    if [ -z "$bad" ]; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md: all reviewer-model lines reference GPT-5.6 Sol/Terra, none reference stale GPT-5.5/5.4"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md stale reviewer-model reference(s):$bad"
    fi
}

# L113 is a historical audit citation (the E2E benchmark critique actually
# ran on GPT-5.4 at the time) — must NOT be rewritten.
test_wizard_doc_e2e_audit_citation_untouched() {
    local F="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$F" ]; then fail "CLAUDE_CODE_SDLC_WIZARD.md not found"; return; fi
    if sed -n '113p' "$F" | grep -q "GPT-5\.4"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md L113 E2E-audit citation still names GPT-5.4 (historical, untouched)"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md L113 E2E-audit citation no longer names GPT-5.4 — historical citation was rewritten"
    fi
}

# Both copies (canonical + cowork) must move together — this is the exact
# doc-duplication-drift risk documented in project memory (v1.85.0: a
# protocol documented twice, fixed in only one copy).
test_skill_files_reviewer_is_gpt56() {
    local bad=""
    bad="$bad$(_check_line_has_and_lacks "$REPO_ROOT/skills/sdlc/SKILL.md" 140 "5\.6,sol" "5\.5")"
    bad="$bad$(_check_line_has_and_lacks "$REPO_ROOT/cowork/skills/sdlc/SKILL.md" 140 "5\.6,sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "skills/sdlc/SKILL.md and cowork/skills/sdlc/SKILL.md both reference GPT-5.6 Sol reviewer"
    else
        fail "skill file(s) stale reviewer-model reference(s):$bad"
    fi
}

test_agents_md_reviewer_is_gpt56() {
    local bad=""
    bad="$bad$(_check_line_has_and_lacks "$REPO_ROOT/AGENTS.md" 16 "5\.6,Sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "AGENTS.md: lane summary references GPT-5.6 Sol reviewer"
    else
        fail "AGENTS.md stale reviewer-model reference(s):$bad"
    fi
}

test_claude_md_reviewer_is_gpt56() {
    local bad=""
    bad="$bad$(_check_line_has_and_lacks "$REPO_ROOT/CLAUDE.md" 75 "5\.6,Sol" "5\.5")"
    if [ -z "$bad" ]; then
        pass "CLAUDE.md: cross-model safety check references GPT-5.6 Sol reviewer"
    else
        fail "CLAUDE.md stale reviewer-model reference(s):$bad"
    fi
}

test_ai_setup_lanes_reviewer_is_gpt56
test_readme_reviewer_is_gpt56
test_readme_vending_bench_citation_untouched
test_wizard_doc_reviewer_is_gpt56
test_wizard_doc_e2e_audit_citation_untouched
test_skill_files_reviewer_is_gpt56
test_agents_md_reviewer_is_gpt56
test_claude_md_reviewer_is_gpt56

# ────────────────────────────────────────────
# ROADMAP #440: unbacked "~5x less quota" claim removed; Sonnet 5 default
# effort is medium (CodeRabbit-tested), not the unsupported "high sweet spot"
# ────────────────────────────────────────────

# The "~5x less Max quota" figure was traced to commit ab6fc9c with zero
# supporting measurement (no source in the commit, CHANGELOG, ROADMAP, or
# review artifacts). It must not appear anywhere in live guidance — repo-wide
# sweep (Fable round-1 root-cause: a fixed file list misses stragglers), with
# variant phrasings ("5x less/lighter/fewer/lower") all caught.
# ROADMAP*.md/CHANGELOG.md/.reviews/ are historical record, intentionally
# excluded.
test_no_unbacked_5x_quota_claim() {
    # Codex round-1 catch: the claim also survives as rewordings — "fraction
    # of the quota cost", "far less quota" — not just the literal "5x". Ban
    # the whole unqualified-multiplier class.
    local hits
    hits=$(grep -rliE "5x (less|lighter|fewer|lower)|fraction of (Setup B's |the )?quota|far less quota" \
        "$REPO_ROOT" \
        --include="*.md" \
        --exclude="ROADMAP.md" --exclude="ROADMAP_ARCHIVE.md" \
        --exclude="CHANGELOG.md" \
        --exclude-dir=".reviews" --exclude-dir="node_modules" \
        --exclude-dir=".git" 2>/dev/null || true)
    if [ -z "$hits" ]; then
        pass "#440: no live-guidance file carries an unqualified quota-multiplier claim (repo-wide)"
    else
        fail "#440: unqualified quota-multiplier claim still present in: $(echo "$hits" | tr '\n' ' ')"
    fi
}

# Sonnet 5's documented default effort is medium — per CodeRabbit's testing
# (the same source already cited for the max-doubles-cost claim), confirmed
# independently by Fable + Codex xhigh 2026-07-12. Each live-guidance file
# must state the medium default in its own idiom.
test_sonnet5_default_effort_is_medium() {
    local bad=""
    grep -q 'medium` default' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md(driver-row)"
    grep -q 'Start at `medium`' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md(ladder)"
    grep -q 'Sonnet 5 at `medium` effort' "$REPO_ROOT/README.md" \
        || bad="$bad README.md(default-line)"
    grep -q 'Sonnet 5: `medium` default' "$REPO_ROOT/README.md" \
        || bad="$bad README.md(effort-line)"
    grep -q 'Sonnet 5: `medium` default' "$REPO_ROOT/SDLC.md" \
        || bad="$bad SDLC.md"
    grep -q 'Sonnet 5 `medium`' "$REPO_ROOT/skills/sdlc/SKILL.md" \
        || bad="$bad skills/sdlc/SKILL.md"
    grep -q 'Sonnet 5 `medium`' "$REPO_ROOT/cowork/skills/sdlc/SKILL.md" \
        || bad="$bad cowork/skills/sdlc/SKILL.md"
    grep -q 'Effort: `medium`' "$REPO_ROOT/skills/setup/SKILL.md" \
        || bad="$bad skills/setup/SKILL.md"
    grep -q 'Sonnet 5 (recommended default) | `medium`' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" \
        || bad="$bad CLAUDE_CODE_SDLC_WIZARD.md(effort-table)"
    # Codex round-1 catch: presence-of-medium alone false-greens while a
    # contradictory high-default ladder survives elsewhere in the same repo
    # (README.md's lane table said "Sonnet 5, `high`→`xhigh`"). Repo-wide
    # absence check for the stale ladder shape.
    local stale
    stale=$(grep -rlE 'Sonnet 5,? .?high.?→' "$REPO_ROOT" \
        --include="*.md" \
        --exclude="ROADMAP.md" --exclude="ROADMAP_ARCHIVE.md" \
        --exclude="CHANGELOG.md" \
        --exclude-dir=".reviews" --exclude-dir="node_modules" \
        --exclude-dir=".git" 2>/dev/null || true)
    [ -n "$stale" ] && bad="$bad stale-high-ladder-in:$(echo "$stale" | tr '\n' ',')"
    if [ -z "$bad" ]; then
        pass "#440: Sonnet 5 default effort is medium in all live-guidance files (no stale high-ladder anywhere)"
    else
        fail "#440: Sonnet 5 medium default missing in:$bad"
    fi
}

# The "high is Sonnet 5's sweet spot" framing had no measurement behind it —
# CodeRabbit (the cited source) actually recommends medium. The two stale
# phrasings must be gone.
test_no_unsupported_sonnet5_sweet_spot() {
    local bad=""
    grep -q 'default and sweet spot' "$REPO_ROOT/AI_SETUP_LANES.md" \
        && bad="$bad AI_SETUP_LANES.md"
    grep -q 'is the tested sweet spot' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" \
        && bad="$bad CLAUDE_CODE_SDLC_WIZARD.md"
    if [ -z "$bad" ]; then
        pass "#440: unsupported 'high sweet spot' framing removed"
    else
        fail "#440: unsupported 'high sweet spot' framing still present in:$bad"
    fi
}

# Guard: Opus 4.6's max-is-the-sweet-spot claim is a DIFFERENT, community-
# supported claim and must survive the #440 cleanup untouched.
test_opus46_max_sweet_spot_guard() {
    if grep -q '4\.6 is the only Opus where `max`' "$REPO_ROOT/AI_SETUP_LANES.md"; then
        pass "#440 guard: Opus 4.6 max sweet-spot claim survives (separate, supported claim)"
    else
        fail "#440 guard: Opus 4.6 max sweet-spot claim was collaterally removed from AI_SETUP_LANES.md"
    fi
}

test_no_unbacked_5x_quota_claim
test_sonnet5_default_effort_is_medium
test_no_unsupported_sonnet5_sweet_spot
test_opus46_max_sweet_spot_guard

# #440 follow-up (maintainer ask 2026-07-13): Setup A's two escalation axes and
# the advisor-failure fallback kept getting re-confused ("sonnet 5 xhigh? or
# high?" / "sometimes advisor fails then we need a sub agent remember").
# Both README and AI_SETUP_LANES must state, explicitly:
#   (a) model escalation SWAPS THE DRIVER (Opus 4.8 xhigh takes over) — it is
#       not a higher rung on Sonnet's effort ladder;
#   (b) when advisor() errors, the fallback is spawning a Fable subagent — the
#       check is never skipped (same rule the /sdlc skill already carries).
test_setup_a_escalation_and_advisor_fallback_explicit() {
    local bad=""
    grep -q 'takes over as driver' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md:driver-swap"
    grep -q 'spawn a Fable subagent' "$REPO_ROOT/AI_SETUP_LANES.md" \
        || bad="$bad AI_SETUP_LANES.md:advisor-fallback"
    grep -q 'takes over as driver' "$REPO_ROOT/README.md" \
        || bad="$bad README.md:driver-swap"
    grep -q 'spawn a Fable subagent' "$REPO_ROOT/README.md" \
        || bad="$bad README.md:advisor-fallback"
    # Negative half (Codex round-1 P1-3): positive assertions alone false-green
    # while the advisor-outage procedure still offers a "no advisor" path. The
    # outage section must route to the subagent fallback, never to skipping.
    local outage
    outage="$(sed -n '/^## When the Advisor Is Unavailable/,/^## [^W]/p' "$REPO_ROOT/AI_SETUP_LANES.md")"
    if [ -z "$outage" ]; then
        bad="$bad AI_SETUP_LANES.md:outage-section-missing"
    else
        printf '%s' "$outage" | grep -qiE 'no advisor|without the advisor' \
            && bad="$bad AI_SETUP_LANES.md:outage-still-offers-skip-path"
        printf '%s' "$outage" | grep -q 'Fable subagent' \
            || bad="$bad AI_SETUP_LANES.md:outage-missing-subagent-fallback"
    fi
    if [ -z "$bad" ]; then
        pass "Setup A: driver-swap escalation + advisor subagent fallback explicit in README and AI_SETUP_LANES"
    else
        fail "Setup A clarity missing:$bad"
    fi
}

test_setup_a_escalation_and_advisor_fallback_explicit

# ────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All cross-document consistency tests passed!"
