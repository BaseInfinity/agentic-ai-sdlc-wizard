#!/bin/bash
# Domain-Adaptive Testing Diamond — Quality Tests
# Validates that wizard doc and setup skill generate domain-specific
# TESTING.md guidance (not just web-focused). Proves It Gate: every test
# checks OUTPUT QUALITY, not just existence.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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

# Helper: extract a section from a markdown file (between headings or bold markers)
extract_section() {
    awk -v section="$2" '
        /^##+ / || /^\*\*[A-Z]/ { if (found) exit; if (index($0, section)) found=1 }
        found { print }
    ' "$1"
}

WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
SETUP_SKILL="$REPO_ROOT/skills/setup/SKILL.md"
FIXTURES="$REPO_ROOT/tests/e2e/fixtures"

echo "=== Domain-Adaptive Testing Diamond Tests ==="
echo "Validates domain detection patterns and domain-specific testing guidance"
echo ""

# ─────────────────────────────────────────────────────
# Wizard Doc Content Quality
# ─────────────────────────────────────────────────────

echo "--- Wizard Doc Content Quality ---"

# Test 1: Wizard doc has firmware testing layers with SIL and HIL
test_wizard_firmware_sil_hil() {
    if grep -q "SIL" "$WIZARD" && grep -q "HIL" "$WIZARD"; then
        pass "Wizard doc has SIL and HIL testing layers"
    else
        fail "Wizard doc missing SIL/HIL testing layers for firmware domain"
    fi
}
test_wizard_firmware_sil_hil

# Test 2: Wizard doc has data science testing layers with model evaluation
test_wizard_datascience_model_eval() {
    if grep -qi "model evaluation\|model eval" "$WIZARD"; then
        pass "Wizard doc has model evaluation testing layer"
    else
        fail "Wizard doc missing model evaluation layer for data science domain"
    fi
}
test_wizard_datascience_model_eval

# Test 3: Wizard doc has CLI testing layers with CLI integration
test_wizard_cli_integration() {
    if grep -qi "CLI integration\|CLI invocation" "$WIZARD"; then
        pass "Wizard doc has CLI integration testing layer"
    else
        fail "Wizard doc missing CLI integration layer for CLI domain"
    fi
}
test_wizard_cli_integration

# Test 4: Firmware section does NOT recommend Playwright/Cypress/browser testing
test_wizard_firmware_no_browser() {
    local firmware_section
    firmware_section=$(extract_section "$WIZARD" "Firmware")
    if [ -z "$firmware_section" ]; then
        fail "Wizard doc has no Firmware section to check"
        return
    fi
    # Filter out negation lines (NO browser, not browser) before checking
    if echo "$firmware_section" | grep -vi "NO browser\|no.*browser\|not.*browser" | grep -qi "playwright\|cypress\|browser test"; then
        fail "Wizard doc firmware section recommends browser testing (should not)"
    else
        pass "Wizard doc firmware section correctly omits browser testing"
    fi
}
test_wizard_firmware_no_browser

# Test 5: Data science section does NOT mention database mocking
test_wizard_datascience_no_db_mock() {
    local ds_section
    ds_section=$(extract_section "$WIZARD" "Data Science")
    if [ -z "$ds_section" ]; then
        fail "Wizard doc has no Data Science section to check"
        return
    fi
    if echo "$ds_section" | grep -qi "database.*mock\|mock.*database\|test DB\|in-memory DB"; then
        fail "Wizard doc data science section mentions database mocking (should not)"
    else
        pass "Wizard doc data science section correctly omits database mocking"
    fi
}
test_wizard_datascience_no_db_mock

# Test 6: CLI section does NOT recommend Playwright/Cypress/browser testing
test_wizard_cli_no_browser() {
    local cli_section
    cli_section=$(extract_section "$WIZARD" "CLI Tool")
    if [ -z "$cli_section" ]; then
        fail "Wizard doc has no CLI Tool section to check"
        return
    fi
    # Filter out negation lines (NO browser, not browser) before checking
    if echo "$cli_section" | grep -vi "NO browser\|no.*browser\|not.*browser" | grep -qi "playwright\|cypress\|browser test"; then
        fail "Wizard doc CLI section recommends browser testing (should not)"
    else
        pass "Wizard doc CLI section correctly omits browser testing"
    fi
}
test_wizard_cli_no_browser

# Test 7: Each domain has different testing layer names (no copy-paste)
test_wizard_distinct_layers() {
    local has_sil has_model_eval has_cli_int
    has_sil=$(grep -c "Software-in-the-Loop\|SIL" "$WIZARD" || true)
    has_model_eval=$(grep -c "Model Evaluation\|Model evaluation" "$WIZARD" || true)
    has_cli_int=$(grep -c "CLI [Ii]ntegration" "$WIZARD" || true)
    if [ "$has_sil" -gt 0 ] && [ "$has_model_eval" -gt 0 ] && [ "$has_cli_int" -gt 0 ]; then
        pass "Each domain has distinct testing layer names"
    else
        fail "Domains missing distinct layers (SIL=$has_sil, ModelEval=$has_model_eval, CLIInt=$has_cli_int)"
    fi
}
test_wizard_distinct_layers

# Test 8: Web/API Testing Diamond still present (regression check)
test_wizard_web_diamond_regression() {
    if grep -q "Testing Diamond" "$WIZARD" && grep -q "Integration.*90%" "$WIZARD"; then
        pass "Web/API Testing Diamond still present (regression check)"
    else
        fail "Web/API Testing Diamond missing or altered (regression)"
    fi
}
test_wizard_web_diamond_regression

# ─────────────────────────────────────────────────────
# Setup Skill Domain Awareness
# ─────────────────────────────────────────────────────

echo ""
echo "--- Setup Skill Domain Awareness ---"

# Test 9: Step 1 scan mentions domain detection
test_skill_step1_domain_detection() {
    if grep -qi "domain.*detect\|detect.*domain\|project domain\|domain indicator" "$SETUP_SKILL"; then
        pass "Setup skill mentions domain detection"
    else
        fail "Setup skill missing domain detection in scan"
    fi
}
test_skill_step1_domain_detection

# Test 10: Step 1 lists firmware indicators
test_skill_firmware_indicators() {
    if grep -qi "\.cfg\|/sys/\|flash" "$SETUP_SKILL"; then
        pass "Setup skill lists firmware indicators (.cfg, /sys/, flash)"
    else
        fail "Setup skill missing firmware detection indicators"
    fi
}
test_skill_firmware_indicators

# Test 11: Step 1 lists data science indicators
test_skill_datascience_indicators() {
    if grep -qi "\.ipynb\|notebook\|pandas\|sklearn\|tensorflow\|torch" "$SETUP_SKILL"; then
        pass "Setup skill lists data science indicators (.ipynb, ML libs)"
    else
        fail "Setup skill missing data science detection indicators"
    fi
}
test_skill_datascience_indicators

# Test 12: Step 1 lists CLI indicators
test_skill_cli_indicators() {
    if grep -qi '"bin"' "$SETUP_SKILL" || grep -qi "bin.*field\|cli.*tool\|no.*UI" "$SETUP_SKILL"; then
        pass "Setup skill lists CLI tool indicators (bin field, no UI)"
    else
        fail "Setup skill missing CLI tool detection indicators"
    fi
}
test_skill_cli_indicators

# Test 13: Step 2 has "Project domain" in confidence map
test_skill_step2_domain_datapoint() {
    if grep -qi "project domain\|domain.*data.*point\|domain.*detect" "$SETUP_SKILL"; then
        pass "Setup skill Step 2 has project domain data point"
    else
        fail "Setup skill Step 2 missing project domain data point"
    fi
}
test_skill_step2_domain_datapoint

# Test 14: Step 6 references domain-adaptive TESTING.md generation
test_skill_step6_domain_adaptive() {
    local step6
    step6=$(extract_section "$SETUP_SKILL" "Step 6")
    if [ -z "$step6" ]; then
        fail "Setup skill has no Step 6 section"
        return
    fi
    if echo "$step6" | grep -qi "domain\|firmware\|data science\|CLI"; then
        pass "Setup skill Step 6 references domain-adaptive generation"
    else
        fail "Setup skill Step 6 missing domain-adaptive TESTING.md guidance"
    fi
}
test_skill_step6_domain_adaptive

# ─────────────────────────────────────────────────────
# Detection Pattern Quality
# ─────────────────────────────────────────────────────

echo ""
echo "--- Detection Pattern Quality ---"

# Test 15: Firmware patterns include Makefile with flash/burn
test_pattern_firmware_makefile() {
    if grep -qi "Makefile.*flash\|flash.*Makefile\|burn\|flash target" "$WIZARD"; then
        pass "Firmware detection includes Makefile flash/burn targets"
    else
        fail "Firmware detection missing Makefile flash/burn pattern"
    fi
}
test_pattern_firmware_makefile

# Test 16: Firmware patterns include device config files
test_pattern_firmware_device_cfg() {
    if grep -qi "device.*config\|\.cfg\|platformio" "$WIZARD"; then
        pass "Firmware detection includes device config patterns"
    else
        fail "Firmware detection missing device config patterns"
    fi
}
test_pattern_firmware_device_cfg

# Test 17: Data science patterns include .ipynb
test_pattern_datascience_ipynb() {
    if grep -qi "\.ipynb\|notebook" "$WIZARD"; then
        pass "Data science detection includes .ipynb/notebook pattern"
    else
        fail "Data science detection missing .ipynb pattern"
    fi
}
test_pattern_datascience_ipynb

# Test 18: Data science patterns include ML library names
test_pattern_datascience_ml_libs() {
    if grep -qi "pandas\|sklearn\|scikit-learn\|tensorflow\|torch\|pytorch" "$WIZARD"; then
        pass "Data science detection includes ML library names"
    else
        fail "Data science detection missing ML library names"
    fi
}
test_pattern_datascience_ml_libs

# Test 19: CLI patterns include package.json bin field
test_pattern_cli_bin_field() {
    if grep -qi 'bin.*field\|"bin".*package\|package.*"bin"' "$WIZARD"; then
        pass "CLI detection includes package.json bin field"
    else
        fail "CLI detection missing package.json bin field pattern"
    fi
}
test_pattern_cli_bin_field

# Test 20: Web remains default when no other domain matches
test_pattern_web_default() {
    if grep -qi "default\|fallback" "$WIZARD" && grep -qi "web.*default\|default.*web\|Web/API" "$WIZARD"; then
        pass "Web/API is the default domain when no other matches"
    else
        fail "Web/API not clearly established as the default domain"
    fi
}
test_pattern_web_default

# ─────────────────────────────────────────────────────
# Fixture Validation
# ─────────────────────────────────────────────────────

echo ""
echo "--- Fixture Validation ---"

# #236(c): the firmware-embedded Makefile/flash check that used to live here
# duplicated test-firmware-fixture.sh's identical check on the same file —
# removed; that file covers the same fixture with 12 deeper checks. The
# data-science/cli-tool fixture checks below have no such sibling, so stay.

# Test 22: data-science fixture has requirements.txt with pandas
test_fixture_datascience_requirements() {
    local req="$FIXTURES/data-science/requirements.txt"
    if [ -f "$req" ] && grep -q "pandas" "$req"; then
        pass "data-science fixture has requirements.txt with pandas"
    else
        fail "data-science fixture missing requirements.txt with pandas"
    fi
}
test_fixture_datascience_requirements

# Test 23: cli-tool fixture has package.json with bin field
test_fixture_cli_package() {
    local pkg="$FIXTURES/cli-tool/package.json"
    if [ -f "$pkg" ] && grep -q '"bin"' "$pkg"; then
        pass "cli-tool fixture has package.json with bin field"
    else
        fail "cli-tool fixture missing package.json with bin field"
    fi
}
test_fixture_cli_package

# ─────────────────────────────────────────────────────
# Cross-Domain Correctness
# ─────────────────────────────────────────────────────

echo ""
echo "--- Cross-Domain Correctness ---"

# Test 24: Firmware template mentions config validation layer
test_cross_firmware_config_validation() {
    if grep -qi "config validation\|config.*check\|device config.*test" "$WIZARD"; then
        pass "Firmware template includes config validation layer"
    else
        fail "Firmware template missing config validation layer"
    fi
}
test_cross_firmware_config_validation

# Test 25: Data science template mentions data validation layer
test_cross_datascience_data_validation() {
    if grep -qi "data validation\|schema check\|distribution drift" "$WIZARD"; then
        pass "Data science template includes data validation layer"
    else
        fail "Data science template missing data validation layer"
    fi
}
test_cross_datascience_data_validation

# ─────────────────────────────────────────────────────
# Results
# ─────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
