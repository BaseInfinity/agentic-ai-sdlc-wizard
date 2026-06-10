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

test_sdlc_skill_recommends_opus_1m() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    # v1.80.0: accept either the opus[1m] alias OR an explicit
    # claude-opus-4-X[1m] model id (flagship default flipped to 4.6 max).
    if grep -qE 'opus\[1m\]|claude-opus-4-[0-9]+\[1m\]' "$SKILL"; then
        pass "skills/sdlc/SKILL.md references an Opus pin (alias or explicit)"
    else
        fail "skills/sdlc/SKILL.md missing opus[1m] or claude-opus-4-X[1m] recommendation"
    fi
}

# Template settings.json must NOT pin model (issue #198 — opt-in via setup skill)
test_cli_template_has_no_default_model_pin() {
    local TPL="$REPO_ROOT/cli/templates/settings.json"
    if [ ! -f "$TPL" ]; then fail "cli/templates/settings.json not found"; return; fi
    local has_model
    has_model=$(jq 'has("model")' "$TPL" 2>/dev/null)
    if [ "$has_model" = "false" ]; then
        pass "cli/templates/settings.json has no default model pin (issue #198 — opt-in)"
    else
        fail "cli/templates/settings.json must not pin a default model (disables auto-mode)"
    fi
}

# Template must NOT ship a default autocompact value either — paired with the
# model pin since 30% is 1M-tuned. Users opt into both together in Step 9.5.
test_cli_template_has_no_default_autocompact() {
    local TPL="$REPO_ROOT/cli/templates/settings.json"
    if [ ! -f "$TPL" ]; then fail "cli/templates/settings.json not found"; return; fi
    local has_env
    has_env=$(jq 'has("env")' "$TPL" 2>/dev/null)
    if [ "$has_env" = "false" ]; then
        pass "cli/templates/settings.json has no default env (paired opt-in with model pin)"
    else
        fail "cli/templates/settings.json must not ship a default env block (issue #198)"
    fi
}

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

# Repo's tracked .claude/settings.json must match the template it ships —
# after #198, neither should contain a model or env block.
test_repo_settings_match_template_no_model_pin() {
    local SETTINGS="$REPO_ROOT/.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then fail ".claude/settings.json not found"; return; fi
    local has_model has_env
    has_model=$(jq 'has("model")' "$SETTINGS" 2>/dev/null)
    has_env=$(jq 'has("env")' "$SETTINGS" 2>/dev/null)
    if [ "$has_model" = "false" ] && [ "$has_env" = "false" ]; then
        pass ".claude/settings.json matches template (no model pin, no default env)"
    else
        fail ".claude/settings.json must not pin model/env (has_model=$has_model has_env=$has_env)"
    fi
}

# Hooks must nudge users toward the recommended Opus alias or explicit id,
# not raw "claude-opus-4-6" without [1m] suffix (we want the 1M context).
# Regression guard against Codex round-1 finding #3.
# Post-#217 (2026-04-24): the effort/model nudge is centralized in
# model-effort-check.sh — instructions-loaded-check.sh no longer duplicates it.
# v1.80.0 flipped RECOMMENDED_MODEL from `opus[1m]` to explicit
# `claude-opus-4-6[1m]`, so the wizard's flagship recommendation names the
# version not the alias.
test_hooks_recommend_opus_1m_alias() {
    local H1="$REPO_ROOT/hooks/model-effort-check.sh"
    if [ ! -f "$H1" ]; then fail "$H1 not found"; return; fi
    if ! grep -qE 'RECOMMENDED_MODEL="(opus\[1m\]|claude-opus-4-[0-9]+\[1m\])"' "$H1"; then
        fail "model-effort-check.sh should set RECOMMENDED_MODEL to opus[1m] or claude-opus-4-X[1m]"
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
    if grep -qE '(do not set both|don.t set both|do NOT set both|pick one|alternatives.*not)' "$SKILL"; then
        pass "skills/sdlc/SKILL.md warns against autocompact compound config (#207)"
    else
        fail "skills/sdlc/SKILL.md must warn against PCT_OVERRIDE + AUTO_COMPACT_WINDOW compound (#207)"
    fi
}

# Test (#207, Codex round 1 finding 2): the shipped `/sdlc` skill must frame
# the Opus pin as opt-in (matching the wizard doc post-#198), not default.
# v1.80.0 flipped from opus[1m] alias to explicit claude-opus-4-6[1m] —
# both forms are acceptable references to the opt-in pin.
test_sdlc_skill_frames_opus_1m_as_opt_in() {
    local SKILL="$REPO_ROOT/skills/sdlc/SKILL.md"
    if [ ! -f "$SKILL" ]; then fail "skills/sdlc/SKILL.md not found"; return; fi
    # Must explicitly say "opt-in" or "issue #198" in the Recommended Model section.
    if grep -qE 'Opt-in:.*opus\[1m\]|opt-in.*opus\[1m\]|opus\[1m\].*opt-in|Opt-in:.*claude-opus-4-[0-9]+\[1m\]|opt-in.*claude-opus-4-[0-9]+\[1m\]|claude-opus-4-[0-9]+\[1m\].*opt-in|issue #198' "$SKILL"; then
        pass "skills/sdlc/SKILL.md frames Opus pin as opt-in (#198, #207 round 1)"
    else
        fail "skills/sdlc/SKILL.md must frame Opus pin as opt-in, not default (#198)"
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
test_sdlc_skill_frames_opus_1m_as_opt_in
test_wizard_doc_has_browser_tooling_policy_section
test_wizard_doc_browser_policy_covers_three_way_split
test_wizard_doc_mcp_profile_isolation_for_concurrent_agents
test_wizard_doc_notes_playwright_default_isolation_rejected
test_wizard_doc_real_browser_trigger_examples
test_sdlc_skill_recommends_opus_1m
test_cli_template_has_no_default_model_pin
test_cli_template_has_no_default_autocompact
test_setup_skill_mentions_model_pin_in_optin_prompt
test_repo_settings_match_template_no_model_pin
test_hooks_recommend_opus_1m_alias
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
# Summary
# ────────────────────────────────────────────

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All cross-document consistency tests passed!"
