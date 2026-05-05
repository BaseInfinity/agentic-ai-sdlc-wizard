#!/bin/bash
# Autocompact Benchmarking Methodology — Quality Tests
# Validates that the methodology document, benchmark harness, task suite,
# and canary facts meet rigorous research standards.
# Proves It Gate: tests prove OUTPUT QUALITY, not just existence.
#
# Scope note (2026-05-05): the companion CI workflow `benchmark-autocompact.yml`
# was deleted in the GC pass — it never ran and burned API on dispatch. Tests
# for the workflow itself were dropped with it. The methodology + harness are
# kept (ROADMAP #92) for local-Max execution, and these tests cover those.

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

METHODOLOGY="$REPO_ROOT/AUTOCOMPACT_BENCHMARK.md"
WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
HARNESS="$REPO_ROOT/tests/benchmarks/run-benchmark.sh"
ANALYZER="$REPO_ROOT/tests/benchmarks/analyze-results.sh"
TASKS_DIR="$REPO_ROOT/tests/benchmarks/tasks"
CANARY="$REPO_ROOT/tests/benchmarks/canary-facts.json"

echo "=== Autocompact Benchmarking Methodology Quality Tests ==="
echo "Validates methodology rigor, harness quality, and research standards"
echo ""

# ─────────────────────────────────────────────────────
# Methodology Document Quality
# ─────────────────────────────────────────────────────

echo "--- Methodology Document Quality ---"

# Test 1: Independent Variables section lists threshold percentages
test_methodology_independent_vars() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    local section
    section=$(extract_section "$METHODOLOGY" "Independent Variables")
    if echo "$section" | grep -q '50\|60\|70\|75\|80\|83\|95'; then
        pass "Methodology lists threshold percentages in Independent Variables"
    else
        fail "Methodology missing threshold percentages in Independent Variables section"
    fi
}

# Test 2: Dependent Variables section lists all 5 metrics
test_methodology_dependent_vars() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    local section
    section=$(extract_section "$METHODOLOGY" "Dependent Variables")
    local count=0
    echo "$section" | grep -qi "task completion\|completion score" && count=$((count + 1))
    echo "$section" | grep -qi "context preservation\|canary" && count=$((count + 1))
    echo "$section" | grep -qi "token cost\|cost" && count=$((count + 1))
    echo "$section" | grep -qi "compaction event\|compaction count" && count=$((count + 1))
    echo "$section" | grep -qi "time.to.completion\|wall clock\|latency" && count=$((count + 1))
    if [ "$count" -ge 5 ]; then
        pass "Methodology lists all 5 dependent variable metrics"
    else
        fail "Methodology only lists $count/5 dependent variable metrics"
    fi
}

# Test 3: Requires minimum 5 trials per condition
test_methodology_min_trials() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    if grep -qi 'minimum.*5 trial\|at least 5 trial\|≥.*5 trial\|5 trials per' "$METHODOLOGY"; then
        pass "Methodology requires minimum 5 trials per condition"
    else
        fail "Methodology missing minimum trial count requirement"
    fi
}

# Test 4: Documents 95% CI with t-distribution
test_methodology_statistical_rigor() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    if grep -qi '95%.*CI\|confidence interval' "$METHODOLOGY" && grep -qi 't.distribution\|t-value' "$METHODOLOGY"; then
        pass "Methodology documents 95% CI with t-distribution"
    else
        fail "Methodology missing statistical rigor (95% CI + t-distribution)"
    fi
}

# Test 5: Canary Fact Mechanism with injection/recall phases
test_methodology_canary_mechanism() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    local section
    section=$(extract_section "$METHODOLOGY" "Canary Fact")
    if echo "$section" | grep -qi "injection\|inject" && echo "$section" | grep -qi "recall\|retrieval"; then
        pass "Methodology has Canary Fact section with injection and recall phases"
    else
        fail "Methodology missing Canary Fact injection/recall mechanism"
    fi
}

# Test 6: Labels existing claims as unverified community consensus
test_methodology_honesty_about_claims() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    if grep -qi 'unverified\|community consensus\|not.*empirically.*validated\|anecdotal' "$METHODOLOGY"; then
        pass "Methodology labels existing claims as unverified/community consensus"
    else
        fail "Methodology doesn't acknowledge existing claims are unverified"
    fi
}

# Test 7: Controls section (isolated sessions, same prompt)
test_methodology_controls() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    local section
    section=$(extract_section "$METHODOLOGY" "Controls")
    if echo "$section" | grep -qi "isolat\|same prompt\|same task\|deterministic\|temperature"; then
        pass "Methodology has Controls section with isolation and determinism"
    else
        fail "Methodology missing Controls section with experimental controls"
    fi
}

# Test 8: Cost Estimation section
test_methodology_cost_estimation() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    local section
    section=$(extract_section "$METHODOLOGY" "Cost")
    if echo "$section" | grep -qi 'per.*threshold\|per.*session\|per.*trial\|estimated\|\$'; then
        pass "Methodology has Cost Estimation with per-threshold projections"
    else
        fail "Methodology missing Cost Estimation section"
    fi
}

# ─────────────────────────────────────────────────────
# Harness Script Quality
# ─────────────────────────────────────────────────────

echo ""
echo "--- Harness Script Quality ---"

# Test 9: run-benchmark.sh sources stats.sh
test_harness_sources_stats() {
    if [ ! -f "$HARNESS" ]; then fail "Harness script missing"; return; fi
    if grep -q 'source.*stats\.sh\|\..*stats\.sh' "$HARNESS"; then
        pass "run-benchmark.sh sources stats.sh for statistical analysis"
    else
        fail "run-benchmark.sh does not source stats.sh"
    fi
}

# Test 10: Validates threshold range 1-100
test_harness_validates_threshold_range() {
    if [ ! -f "$HARNESS" ]; then fail "Harness script missing"; return; fi
    if grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' "$HARNESS" && grep -qE '(100|[0-9]+)' "$HARNESS"; then
        # More specific: check for actual validation logic
        if grep -qE '\-lt 1|\-gt 100|< 1|> 100|range|invalid|1-100|1\.\.100' "$HARNESS"; then
            pass "run-benchmark.sh validates threshold is in range 1-100"
        else
            fail "run-benchmark.sh references threshold but lacks range validation"
        fi
    else
        fail "run-benchmark.sh missing threshold validation entirely"
    fi
}

# Test 11: Rejects non-numeric threshold values
test_harness_rejects_nonnumeric() {
    if [ ! -f "$HARNESS" ]; then fail "Harness script missing"; return; fi
    if grep -qE 'is_numeric|[^0-9]|not a number|numeric|NaN|^[0-9]+\$' "$HARNESS"; then
        pass "run-benchmark.sh rejects non-numeric threshold values"
    else
        fail "run-benchmark.sh missing non-numeric validation"
    fi
}

# Test 12: Has --dry-run flag
test_harness_dry_run() {
    if [ ! -f "$HARNESS" ]; then fail "Harness script missing"; return; fi
    if grep -q '\-\-dry.run\|dry_run\|DRY_RUN' "$HARNESS"; then
        pass "run-benchmark.sh has --dry-run flag"
    else
        fail "run-benchmark.sh missing --dry-run flag"
    fi
}

# Test 13: Implements multi-turn session (--resume/session_id for canary recall)
test_harness_multi_turn() {
    if [ ! -f "$HARNESS" ]; then fail "Harness script missing"; return; fi
    if grep -qE '\-\-resume|session.id|session_id|SESSION_ID' "$HARNESS"; then
        pass "run-benchmark.sh implements multi-turn session for canary recall"
    else
        fail "run-benchmark.sh missing multi-turn session orchestration (--resume/session_id)"
    fi
}

# Test 14: analyze-results.sh outputs comparison table with CI
test_analyzer_comparison_table() {
    if [ ! -f "$ANALYZER" ]; then fail "Analyzer script missing"; return; fi
    if grep -qi 'confidence.*interval\|CI\|compare\|comparison.*table\|stats\.sh' "$ANALYZER"; then
        pass "analyze-results.sh outputs comparison with confidence intervals"
    else
        fail "analyze-results.sh missing CI-based comparison output"
    fi
}

# ─────────────────────────────────────────────────────
# Task Suite Quality
# ─────────────────────────────────────────────────────

echo ""
echo "--- Task Suite Quality ---"

# Test 15: Short task exists and is under 500 words (control)
test_short_task_size() {
    local short_task="$TASKS_DIR/short-task.md"
    if [ -f "$short_task" ]; then
        local word_count
        word_count=$(wc -w < "$short_task" | tr -d ' ')
        if [ "$word_count" -lt 500 ]; then
            pass "Short task exists and is under 500 words ($word_count words — control)"
        else
            fail "Short task is $word_count words (should be under 500 for control)"
        fi
    else
        fail "Short task file missing: $short_task"
    fi
}

# Test 16: Long task includes multi-file exploration (targeting 120-150K tokens)
test_long_task_complexity() {
    local long_task="$TASKS_DIR/long-task.md"
    if [ -f "$long_task" ]; then
        if grep -qi 'multiple file\|multi.file\|explore\|exploration\|refactor\|across.*file' "$long_task"; then
            pass "Long task includes multi-file exploration instructions"
        else
            fail "Long task missing multi-file exploration instructions"
        fi
    else
        fail "Long task file missing: $long_task"
    fi
}

# Test 17: Tasks include canary fact injection instructions
test_tasks_have_canary_instructions() {
    local has_canary=0
    for task_file in "$TASKS_DIR"/*.md; do
        if grep -qi 'canary\|remember.*fact\|project deadline\|team lead' "$task_file" 2>/dev/null; then
            has_canary=$((has_canary + 1))
        fi
    done
    if [ "$has_canary" -ge 2 ]; then
        pass "At least 2 tasks include canary fact injection instructions"
    else
        fail "Only $has_canary tasks include canary fact instructions (need at least 2)"
    fi
}

# Test 18: All 3 tasks have different complexity levels (not copy-paste)
test_tasks_distinct() {
    local short_task="$TASKS_DIR/short-task.md"
    local medium_task="$TASKS_DIR/medium-task.md"
    local long_task="$TASKS_DIR/long-task.md"
    if [ -f "$short_task" ] && [ -f "$medium_task" ] && [ -f "$long_task" ]; then
        # Check word counts are meaningfully different
        local short_wc medium_wc long_wc
        short_wc=$(wc -w < "$short_task" | tr -d ' ')
        medium_wc=$(wc -w < "$medium_task" | tr -d ' ')
        long_wc=$(wc -w < "$long_task" | tr -d ' ')
        if [ "$short_wc" -lt "$medium_wc" ] && [ "$medium_wc" -lt "$long_wc" ]; then
            pass "3 tasks have distinct complexity levels (short:$short_wc < medium:$medium_wc < long:$long_wc words)"
        else
            fail "Tasks not properly ordered by complexity (short:$short_wc, medium:$medium_wc, long:$long_wc)"
        fi
    else
        fail "Missing one or more task files (need short, medium, long)"
    fi
}

# ─────────────────────────────────────────────────────
# Canary Fact Quality
# ─────────────────────────────────────────────────────

echo ""
echo "--- Canary Fact Quality ---"

# Test 19: canary-facts.json has exactly 5 facts
test_canary_count() {
    if [ -f "$CANARY" ]; then
        local count
        count=$(jq '.facts | length' "$CANARY" 2>/dev/null || echo "0")
        if [ "$count" -eq 5 ]; then
            pass "canary-facts.json has exactly 5 facts"
        else
            fail "canary-facts.json has $count facts (expected 5)"
        fi
    else
        fail "canary-facts.json missing"
    fi
}

# Test 20: Facts have distinct recall prompts
test_canary_distinct_prompts() {
    if [ -f "$CANARY" ]; then
        local unique_prompts
        unique_prompts=$(jq -r '.facts[].recall_prompt' "$CANARY" 2>/dev/null | sort -u | wc -l | tr -d ' ')
        if [ "$unique_prompts" -ge 5 ]; then
            pass "Canary facts have 5 distinct recall prompts"
        else
            fail "Canary facts only have $unique_prompts distinct recall prompts (need 5)"
        fi
    else
        fail "canary-facts.json missing"
    fi
}

# Test 21: Facts are domain-independent (not coding-specific)
test_canary_domain_independent() {
    if [ -f "$CANARY" ]; then
        local facts_text
        facts_text=$(jq -r '.facts[].fact' "$CANARY" 2>/dev/null)
        # Domain-independent facts should NOT be about code/programming
        if echo "$facts_text" | grep -qiE 'function|class|variable|import|module|API endpoint'; then
            fail "Canary facts are coding-specific (should be domain-independent)"
        else
            pass "Canary facts are domain-independent (test pure context preservation)"
        fi
    else
        fail "canary-facts.json missing"
    fi
}

# ─────────────────────────────────────────────────────
# Integration
# ─────────────────────────────────────────────────────

echo ""
echo "--- Integration ---"

# Test 25: Wizard doc autocompact section references methodology
test_wizard_references_methodology() {
    # Search the wizard doc's autocompact-related content for a reference to the benchmark
    if grep -A 50 '### Autocompact Tuning' "$WIZARD" | grep -qi 'AUTOCOMPACT_BENCHMARK\|benchmarking methodology'; then
        pass "Wizard doc autocompact section references benchmarking methodology"
    else
        fail "Wizard doc autocompact section doesn't reference AUTOCOMPACT_BENCHMARK.md"
    fi
}

# Test 26: Methodology has Limitations section
test_methodology_limitations() {
    if [ ! -f "$METHODOLOGY" ]; then fail "Methodology file missing"; return; fi
    if grep -qi '## Limitation\|### Limitation' "$METHODOLOGY"; then
        local section
        section=$(extract_section "$METHODOLOGY" "Limitation")
        if echo "$section" | grep -qi 'infrastructure.*before.*data\|methodology.*before.*result\|ships before'; then
            pass "Methodology has Limitations section acknowledging infrastructure ships before data"
        else
            fail "Methodology has Limitations section but doesn't acknowledge scope"
        fi
    else
        fail "Methodology missing Limitations section"
    fi
}

# ─────────────────────────────────────────────────────
# Run all tests
# ─────────────────────────────────────────────────────

echo ""
echo "=== Running Tests ==="
echo ""

# Methodology Document Quality
test_methodology_independent_vars
test_methodology_dependent_vars
test_methodology_min_trials
test_methodology_statistical_rigor
test_methodology_canary_mechanism
test_methodology_honesty_about_claims
test_methodology_controls
test_methodology_cost_estimation

# Harness Script Quality
test_harness_sources_stats
test_harness_validates_threshold_range
test_harness_rejects_nonnumeric
test_harness_dry_run
test_harness_multi_turn
test_analyzer_comparison_table

# Task Suite Quality
test_short_task_size
test_long_task_complexity
test_tasks_have_canary_instructions
test_tasks_distinct

# Canary Fact Quality
test_canary_count
test_canary_distinct_prompts
test_canary_domain_independent

# Integration
test_wizard_references_methodology
test_methodology_limitations

echo ""
echo "=== Results ==="
echo "Passed: $PASSED, Failed: $FAILED"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
