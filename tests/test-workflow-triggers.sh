#!/bin/bash
# Test workflow trigger configurations and state file handling

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

echo "=== Workflow Trigger Tests ==="
echo ""

# Test 1: Weekly-update workflow has workflow_dispatch trigger
test_weekly_update_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml file not found"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "weekly-update.yml has workflow_dispatch trigger"
    else
        fail "weekly-update.yml missing workflow_dispatch trigger"
    fi
}

# Test 2: daily-update.yml must NOT exist (consolidated into weekly-update.yml)
test_daily_update_deleted() {
    WORKFLOW="$REPO_ROOT/.github/workflows/daily-update.yml"

    if [ -f "$WORKFLOW" ]; then
        fail "daily-update.yml still exists (should be deleted — consolidated into weekly-update.yml)"
    else
        pass "daily-update.yml does not exist (consolidated into weekly-update.yml)"
    fi
}

# Test 3: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_dispatch() { pass "test_monthly_dispatch n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 4: Weekly-update workflow has active schedule trigger
test_weekly_update_has_schedule() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # ROADMAP #212 Option 1: cron is intentionally commented out — workflow
    # still burns API credits (9 claude-code-action blocks), migration is
    # ROADMAP #231. Manual via workflow_dispatch is the current policy.
    if grep -qE '^\s*#\s*- cron:' "$WORKFLOW"; then
        pass "weekly-update.yml cron is disabled (ROADMAP #212 Option 1, migration tracked as #231)"
    elif grep -qE '^\s*- cron:' "$WORKFLOW"; then
        fail "weekly-update.yml cron is ENABLED — either intentionally re-enable with API budget confirmed, or keep disabled per #212"
    else
        pass "weekly-update.yml has no cron trigger"
    fi
}

# Test 35: weekly-community.yml must NOT exist (consolidated into weekly-update.yml)
test_weekly_community_deleted() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-community.yml"

    if [ -f "$WORKFLOW" ]; then
        fail "weekly-community.yml still exists (should be deleted — consolidated into weekly-update.yml)"
    else
        pass "weekly-community.yml does not exist (consolidated into weekly-update.yml)"
    fi
}

# Test 36: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_has_schedule() { pass "test_monthly_has_schedule n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 5: State file path is valid in weekly-update workflow
test_state_file_path() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    if grep -q "last-checked-version.txt" "$WORKFLOW"; then
        pass "weekly-update.yml references state file correctly"
    else
        fail "weekly-update.yml missing state file reference"
    fi
}

# Test 6: State file round-trip (write then read)
test_state_file_roundtrip() {
    TEMP_DIR=$(mktemp -d)
    STATE_FILE="$TEMP_DIR/last-checked-version.txt"
    TEST_VERSION="v2.1.20"

    # Write
    echo "$TEST_VERSION" > "$STATE_FILE"

    # Read back (same logic as workflow)
    if [ -f "$STATE_FILE" ]; then
        READ_VERSION=$(cat "$STATE_FILE" | tr -d '\n')
    else
        READ_VERSION="v0.0.0"
    fi

    rm -rf "$TEMP_DIR"

    if [ "$READ_VERSION" = "$TEST_VERSION" ]; then
        pass "State file round-trip works correctly"
    else
        fail "State file round-trip failed: wrote '$TEST_VERSION', read '$READ_VERSION'"
    fi
}

# Test 7: Workflow has proper permissions
test_workflow_permissions() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    if grep -q "permissions:" "$WORKFLOW"; then
        pass "weekly-update.yml declares permissions"
    else
        fail "weekly-update.yml missing permissions declaration"
    fi
}

# Test 8: Workflow uses checkout action
test_workflow_checkout() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    if grep -q "actions/checkout" "$WORKFLOW"; then
        pass "weekly-update.yml uses checkout action"
    else
        fail "weekly-update.yml missing checkout action"
    fi
}

# Test 9: Error handling - jq fallback for missing release
test_error_handling_pattern() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # Check for error handling pattern (|| echo for fallback)
    if grep -q '|| echo' "$WORKFLOW" || grep -q '2>/dev/null' "$WORKFLOW"; then
        pass "weekly-update.yml has error handling patterns"
    else
        fail "weekly-update.yml missing error handling"
    fi
}

# Test 10: All workflows are valid YAML (basic check)
test_yaml_validity() {
    WORKFLOWS="$REPO_ROOT/.github/workflows"
    ALL_VALID=true

    for workflow in "$WORKFLOWS"/*.yml; do
        # Basic check: file starts with valid YAML (name: or on:)
        FIRST_LINE=$(head -n 1 "$workflow")
        if [[ ! "$FIRST_LINE" =~ ^(name:|on:|\#) ]]; then
            fail "Workflow $(basename "$workflow") may have invalid YAML"
            ALL_VALID=false
        fi
    done

    if [ "$ALL_VALID" = true ]; then
        pass "All workflow files have valid YAML structure"
    fi
}

# ============================================
# E2E Bootstrapping Detection Regression Tests
# ============================================
# These tests ensure the bootstrapping logic in ci.yml
# is not accidentally removed or broken.

# Tests 11-13: DELETED — bootstrapping/baseline logic lived in ci.yml's
# e2e-quick-check + e2e-full-evaluation jobs, removed as part of ROADMAP #212
# Option 1. See ROADMAP #230 for shepherd baseline/candidate follow-up.
test_e2e_bootstrapping_detection() { pass "e2e-bootstrapping test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }
test_e2e_conditional_baseline() { pass "e2e-conditional-baseline test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }
test_e2e_bootstrapping_handling() { pass "e2e-bootstrapping-handling test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }

# ============================================
# CI Label Trigger Tests
# ============================================
# These tests ensure the CI workflow properly handles
# the `labeled` event for merge-ready label triggering.

# Test 14: CI pull_request trigger includes 'labeled' type
test_ci_labeled_trigger() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    if grep -q "labeled" "$WORKFLOW"; then
        pass "CI pull_request trigger includes 'labeled' type"
    else
        fail "CI pull_request trigger missing 'labeled' type"
    fi
}

# Test 15: DELETED — e2e-quick-check job removed per ROADMAP #212 Option 1.
test_quick_check_labeled_guard() { pass "quick-check-labeled-guard test n/a (e2e-quick-check job removed per #212 Option 1)"; }

# Test 16: cleanup-old-comments is guarded from labeled events
test_cleanup_labeled_guard() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    # The cleanup-old-comments job should skip on labeled events
    if sed -n '/cleanup-old-comments:/,/steps:/p' "$WORKFLOW" | grep -q "labeled"; then
        pass "cleanup-old-comments is guarded from labeled events"
    else
        fail "cleanup-old-comments missing guard for labeled events"
    fi
}

# Test 17: Weekly-update workflow checks for existing PR before creating.
# Phase 4 (#231) consolidated the dedicated `existing-pr` step into the
# combined `detect` step. The check now greps for the actual pattern
# (`gh pr list --head` + `skip` output write) rather than a step ID.
test_weekly_existing_pr_check() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    if grep -q 'gh pr list --head' "$WORKFLOW" && grep -q 'skip=true' "$WORKFLOW"; then
        pass "weekly-update.yml checks for existing PR before creating"
    else
        fail "weekly-update.yml missing existing PR check (gh pr list --head + skip output)"
    fi
}

# ============================================
# PR Review Re-trigger Tests
# ============================================
# These tests ensure the PR review workflow re-runs
# on each push (synchronize event), not just on open.

# Test 18: PR review triggers on synchronize (re-review on push)
test_pr_review_synchronize_trigger() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "PR review workflow file not found"
        return
    fi

    # Check the types: line specifically includes synchronize
    if grep "types:" "$WORKFLOW" | grep -q "synchronize"; then
        pass "PR review workflow triggers on synchronize"
    else
        fail "PR review workflow missing synchronize trigger (reviews only run once per PR)"
    fi
}

# Test 19: PR review if-condition allows synchronize events through
test_pr_review_synchronize_condition() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "PR review workflow file not found"
        return
    fi

    # The job-level if condition must include synchronize
    if grep -A 5 "if:" "$WORKFLOW" | grep -q "synchronize"; then
        pass "PR review if-condition handles synchronize events"
    else
        fail "PR review if-condition does not handle synchronize events (reviews won't run on push)"
    fi
}

# ============================================
# E2E AllowedTools Coverage Tests
# ============================================
# These tests ensure Claude simulations have access
# to the tools that scenarios actually need.

# Tests 20-21: DELETED — ci.yml no longer has claude-code-action calls per
# ROADMAP #212 Option 1. allowedTools parity is now enforced on the local
# shepherd (tests/test-local-shepherd.sh::test_shepherd_calls_claude_with_parity_flags).
test_ci_allowed_tools_no_plan_mode() { pass "ci-allowedTools-no-plan-mode test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }
test_ci_allowed_tools_task_tracking() { pass "ci-allowedTools-task-tracking test n/a (parity enforced on shepherd instead)"; }

# Test 30: ci.yml has workflow_dispatch trigger
test_ci_workflow_dispatch() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for dispatch test)"
        return
    fi

    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "ci.yml has workflow_dispatch trigger"
    else
        fail "ci.yml missing workflow_dispatch trigger"
    fi
}

# Test 34: ci.yml max-turns is >= 35 for all simulations
test_ci_max_turns_sufficient() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found (needed for max-turns test)"
        return
    fi

    # Extract all --max-turns values and check they're all >= 35
    ALL_SUFFICIENT=true
    while IFS= read -r line; do
        TURNS=$(echo "$line" | grep -oE '[0-9]+')
        if [ "$TURNS" -lt 35 ]; then
            fail "ci.yml has --max-turns $TURNS (need >= 35 to avoid error_max_turns flakiness)"
            ALL_SUFFICIENT=false
            break
        fi
    done < <(grep -- "--max-turns" "$WORKFLOW")

    if [ "$ALL_SUFFICIENT" = true ]; then
        pass "ci.yml max-turns is >= 35 for all simulations"
    fi
}

# Run all tests
test_weekly_update_dispatch
test_daily_update_deleted
test_monthly_dispatch
test_weekly_update_has_schedule
test_weekly_community_deleted
test_monthly_has_schedule
test_state_file_path
test_state_file_roundtrip
test_workflow_permissions
test_workflow_checkout
test_error_handling_pattern
test_yaml_validity
test_e2e_bootstrapping_detection
test_e2e_conditional_baseline
test_e2e_bootstrapping_handling
test_ci_labeled_trigger
test_quick_check_labeled_guard
test_cleanup_labeled_guard
test_weekly_existing_pr_check
test_pr_review_synchronize_trigger
test_pr_review_synchronize_condition
test_ci_allowed_tools_no_plan_mode
test_ci_allowed_tools_task_tracking
test_ci_workflow_dispatch
test_ci_max_turns_sufficient

# ============================================
# CI Cosmetic Step Resilience Tests
# ============================================
# These tests ensure cosmetic CI steps (PR comments)
# don't fail the build, while the real quality gate does.

# Tests 42-45: DELETED — ci.yml no longer has quick-check comment steps or
# Fail-on-regression steps per ROADMAP #212 Option 1 (e2e jobs removed).
# Shepherd has its own continue-on-error behavior (tests in test-local-shepherd.sh).
test_quick_check_comment_continue_on_error() { pass "quick-check-comment-continue-on-error test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }
test_quick_check_post_comment_continue_on_error() { pass "quick-check-post-comment-continue-on-error test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }
test_fail_on_regression_no_continue_on_error() { pass "fail-on-regression test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }

# Tests 45-46: DELETED — CRITERIA safety tested inline when ci.yml had LLM
# evidence output. ci.yml no longer passes LLM output to bash; shepherd
# handles its own comment safety.
test_criteria_not_inline_expanded() { pass "criteria-not-inline-expanded test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }

test_comment_steps_use_env_block() { pass "comment-steps-use-env-block test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }

test_criteria_not_inline_expanded
test_comment_steps_use_env_block

test_quick_check_comment_continue_on_error
test_quick_check_post_comment_continue_on_error
test_fail_on_regression_no_continue_on_error

# ============================================
# Full E2E Dependency Compatibility Tests
# ============================================
# These tests ensure the e2e-full-evaluation job can actually run
# when triggered by the 'labeled' event (merge-ready label).

# Test 47: e2e-full-evaluation must not depend on jobs that skip on 'labeled' events
test_full_eval_deps_run_on_labeled() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # Parse the workflow to check that every job in e2e-full-evaluation's 'needs'
    # does NOT have a condition that excludes 'labeled' events
    python3 -c "
import yaml, sys
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
jobs = wf.get('jobs', {})
full_eval = jobs.get('e2e-full-evaluation', {})
needs = full_eval.get('needs', [])
if isinstance(needs, str):
    needs = [needs]

blocked = []
for dep in needs:
    dep_job = jobs.get(dep, {})
    condition = str(dep_job.get('if', ''))
    # If the dependency skips on 'labeled' events, full-eval can never run
    if \"event.action != 'labeled'\" in condition:
        blocked.append(dep)

if blocked:
    print('BLOCKED_BY:' + ','.join(blocked))
else:
    print('DEPS_OK')
" > /tmp/full_eval_deps.txt 2>&1

    if grep -q "DEPS_OK" /tmp/full_eval_deps.txt; then
        pass "e2e-full-evaluation dependencies all run on 'labeled' events"
    else
        BLOCKERS=$(grep "BLOCKED_BY:" /tmp/full_eval_deps.txt | sed 's/BLOCKED_BY://')
        fail "e2e-full-evaluation depends on jobs that skip on 'labeled': $BLOCKERS (full eval can never run)"
    fi
}

test_full_eval_deps_run_on_labeled

# ============================================
# PR Review Prompt Hygiene Tests
# ============================================
# Ensure the review prompt doesn't contain shell
# constructs that won't expand in YAML strings.

# Test 48: pr-review prompt must not use $(cat ...) in YAML prompt field
test_review_prompt_no_shell_subst() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml file not found"
        return
    fi

    # $(cat ...) in a YAML 'prompt: |' field is dead code —
    # YAML strings don't execute shell commands.
    # claude-code-action provides comments through its own mechanism.
    if grep -E '\$\(cat ' "$WORKFLOW"; then
        fail "pr-review.yml prompt contains \$(cat ...) — won't expand in YAML string (dead code)"
    else
        pass "pr-review.yml prompt has no shell command substitution in YAML strings"
    fi
}

test_review_prompt_no_shell_subst

# Test 91: pr-review prompt references CODE_REVIEW_EXCEPTIONS.md
test_review_prompt_has_exceptions_ref() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml file not found"
        return
    fi

    if grep -q "CODE_REVIEW_EXCEPTIONS.md" "$WORKFLOW"; then
        pass "pr-review.yml prompt references CODE_REVIEW_EXCEPTIONS.md"
    else
        fail "pr-review.yml prompt does not reference CODE_REVIEW_EXCEPTIONS.md"
    fi
}

# Test 92: CODE_REVIEW_EXCEPTIONS.md exists
test_review_exceptions_file_exists() {
    if [ -f "$REPO_ROOT/CODE_REVIEW_EXCEPTIONS.md" ]; then
        pass "CODE_REVIEW_EXCEPTIONS.md exists"
    else
        fail "CODE_REVIEW_EXCEPTIONS.md not found in repo root"
    fi
}

test_review_prompt_has_exceptions_ref
test_review_exceptions_file_exists

# Test 93: ci.yml has concurrency group (cancel stale runs)
test_ci_has_concurrency() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "ci.yml file not found"
        return
    fi

    if grep -q "cancel-in-progress: true" "$WORKFLOW"; then
        pass "ci.yml has concurrency cancel-in-progress"
    else
        fail "ci.yml missing concurrency cancel-in-progress"
    fi
}

# Test 94: pr-review.yml has concurrency group (cancel stale runs)
test_pr_review_has_concurrency() {
    WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml file not found"
        return
    fi

    if grep -q "cancel-in-progress: true" "$WORKFLOW"; then
        pass "pr-review.yml has concurrency cancel-in-progress"
    else
        fail "pr-review.yml missing concurrency cancel-in-progress"
    fi
}

test_ci_has_concurrency
test_pr_review_has_concurrency

# ============================================
# Weekly-Update Workflow Input Validation Tests
# ============================================
# Ensure claude-code-action steps use valid inputs only.
# (Consolidates former daily-update + weekly-community tests)

# Test 49: weekly-update must NOT use 'prompt_file' (not a valid action input)
test_weekly_update_no_prompt_file_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # claude-code-action@v1 does not accept 'prompt_file' — use 'prompt' instead
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'prompt_file' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/prompt_file_check.txt 2>&1

    if grep -q "FOUND:" /tmp/prompt_file_check.txt; then
        STEP=$(grep "FOUND:" /tmp/prompt_file_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-update uses 'prompt_file' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "weekly-update does not use invalid 'prompt_file' input"
    fi
}

# Test 50: weekly-update must NOT use 'direct_prompt' (not a valid action input)
test_weekly_update_no_direct_prompt_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'direct_prompt' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/direct_prompt_check.txt 2>&1

    if grep -q "FOUND:" /tmp/direct_prompt_check.txt; then
        STEP=$(grep "FOUND:" /tmp/direct_prompt_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-update uses 'direct_prompt' input in step '$STEP' — not a valid claude-code-action input"
    else
        pass "weekly-update does not use invalid 'direct_prompt' input"
    fi
}

# Test 51: weekly-update must NOT use 'model' as a top-level action input
test_weekly_update_no_model_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        uses = step.get('uses', '')
        with_block = step.get('with', {})
        if 'claude-code-action' in uses and 'model' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/model_input_check.txt 2>&1

    if grep -q "FOUND:" /tmp/model_input_check.txt; then
        STEP=$(grep "FOUND:" /tmp/model_input_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-update uses 'model' as action input in step '$STEP' — use claude_args --model instead"
    else
        pass "weekly-update does not use invalid 'model' action input"
    fi
}

# Test 52: weekly-update evaluate.sh calls must NOT use 2>&1 (stderr corruption)
test_weekly_update_no_stderr_mixing_in_eval() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # evaluate.sh calls with 2>&1 corrupt JSON output with stderr messages.
    python3 -c "
import yaml, re
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        if 'evaluate.sh' in run and '2>&1' in run:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/stderr_mix_check.txt 2>&1

    if grep -q "FOUND:" /tmp/stderr_mix_check.txt; then
        STEP=$(grep "FOUND:" /tmp/stderr_mix_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-update step '$STEP' pipes evaluate.sh stderr to stdout (2>&1) — causes jq parse failures"
    else
        pass "weekly-update.yml does not mix stderr into evaluate.sh output"
    fi
}

test_weekly_update_no_prompt_file_input
test_weekly_update_no_direct_prompt_input
test_weekly_update_no_model_input
test_weekly_update_no_stderr_mixing_in_eval

# Test 53: weekly-update must NOT reference outputs.response (doesn't exist in claude-code-action@v1)
test_weekly_update_no_outputs_response() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    content = f.read()
if 'outputs.response' in content:
    print('FOUND')
" > /tmp/outputs_response_check.txt 2>&1

    if grep -q "FOUND" /tmp/outputs_response_check.txt; then
        fail "weekly-update references 'outputs.response' — claude-code-action@v1 has no response output"
    else
        pass "weekly-update does not reference non-existent 'outputs.response'"
    fi
}

# Test 54: n/a per #231 Phase 3d — Claude-ranker step deleted, no execution
# output file to extract from. Replaced with regression check that the
# placeholder analysis step writes /tmp/analysis.json.
test_weekly_update_extracts_from_output_file() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # Regression: no `uses: anthropics/claude-code-action` directive should
    # remain (Phase 3d removed it). Comments mentioning the old action are OK.
    # Two YAML step forms must both be caught:
    #   "      - uses: anthropics/claude-code-action@v1"  (compact form)
    #   "      uses: anthropics/claude-code-action@v1"   (continuation under -name:)
    # Use Python YAML parsing to catch both reliably (Codex round 1 P1).
    USES_CHECK=$(python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        uses = step.get('uses', '')
        if 'anthropics/claude-code-action' in uses:
            print('RESURRECTED:' + job_name + '/' + (step.get('name') or step.get('id') or 'unnamed'))
print('OK')
" 2>&1)
    if echo "$USES_CHECK" | grep -q "RESURRECTED:"; then
        DETAIL=$(echo "$USES_CHECK" | grep "RESURRECTED:" | sed 's/RESURRECTED://')
        fail "weekly-update.yml has RESURRECTED claude-code-action step: $DETAIL — Phase 3d removed all API spend"
    else
        # Phase 4 (#231) eliminated the /tmp/analysis.json placeholder (it was
        # consumed by nothing once the relevance label became hardcoded
        # UNKNOWN). Regression check is now just: no claude-code-action@v1
        # directive resurrects.
        pass "weekly-update.yml has no claude-code-action@v1 directive (Phase 3d/4 zero-API-spend)"
    fi
}

test_weekly_update_no_outputs_response
test_weekly_update_extracts_from_output_file

# ============================================
# Weekly-Update Workflow Input Validation Tests (continued)
# ============================================
# Tests 55-60: These previously tested weekly-community.yml separately.
# Now consolidated — they also check weekly-update.yml (same file as 49-54).

# Test 55: weekly-update must NOT use 'allowed_tools' as action input (use claude_args)
test_weekly_update_no_allowed_tools_input() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        with_block = step.get('with', {})
        if 'allowed_tools' in with_block:
            print('FOUND:' + step.get('name', 'unnamed'))
" > /tmp/weekly_allowed_tools_check.txt 2>&1

    if grep -q "FOUND:" /tmp/weekly_allowed_tools_check.txt; then
        STEP=$(grep "FOUND:" /tmp/weekly_allowed_tools_check.txt | head -1 | sed 's/FOUND://')
        fail "weekly-update uses 'allowed_tools' input in step '$STEP' — use claude_args --allowedTools instead"
    else
        pass "weekly-update does not use invalid 'allowed_tools' input"
    fi
}

# Test 56: n/a per #231 Phase 3c — scan-community deleted, no execution-output extraction step remains.
test_weekly_update_extracts_scan_from_output_file() {
    pass "test_weekly_update_extracts_scan_from_output_file n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 57: n/a per #231 Phase 3c — scan-community job deleted (state file no longer used in CI).
# The maintainer can still maintain `.github/last-community-scan.txt` manually for local scans.
test_weekly_update_community_state_file() {
    pass "test_weekly_update_community_state_file n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 58: n/a per #231 Phase 3c — digest issue creation step was inside scan-community (deleted).
test_weekly_update_creates_issues() {
    pass "test_weekly_update_creates_issues n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 59: weekly-update uses peter-evans/create-pull-request for version update PRs
test_weekly_update_uses_create_pr() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    if grep -q "peter-evans/create-pull-request" "$WORKFLOW"; then
        pass "weekly-update uses peter-evans/create-pull-request"
    else
        fail "weekly-update missing peter-evans/create-pull-request"
    fi
}

test_weekly_update_no_allowed_tools_input
test_weekly_update_extracts_scan_from_output_file
test_weekly_update_community_state_file
test_weekly_update_creates_issues
test_weekly_update_uses_create_pr

# ============================================
# Monthly-Research Workflow Input Validation Tests — DELETED
# ============================================
# Tests 61-66: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1.
# Keep function names as stubs so any external callers referencing them pass.
test_monthly_no_prompt_file_input()   { pass "test_monthly_no_prompt_file_input n/a per #231 Phase 1 (monthly-research.yml deleted)"; }
test_monthly_no_direct_prompt_input() { pass "test_monthly_no_direct_prompt_input n/a per #231 Phase 1 (monthly-research.yml deleted)"; }
test_monthly_no_model_input()         { pass "test_monthly_no_model_input n/a per #231 Phase 1 (monthly-research.yml deleted)"; }
test_monthly_no_allowed_tools_input() { pass "test_monthly_no_allowed_tools_input n/a per #231 Phase 1 (monthly-research.yml deleted)"; }
test_monthly_no_outputs_response()    { pass "test_monthly_no_outputs_response n/a per #231 Phase 1 (monthly-research.yml deleted)"; }
test_monthly_extracts_from_output_file() { pass "test_monthly_extracts_from_output_file n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

test_monthly_no_prompt_file_input
test_monthly_no_direct_prompt_input
test_monthly_no_model_input
test_monthly_no_allowed_tools_input
test_monthly_no_outputs_response
test_monthly_extracts_from_output_file

# ============================================
# Silent Workflow Failure Regression Tests
# ============================================
# These tests ensure previously-identified silent failures
# remain fixed after the post-audit cleanup.

# Test 67: ci.yml has no dead token extraction showing N/A
test_ci_no_dead_token_extraction() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # The execution output file from claude-code-action@v1 does NOT contain
    # .usage.input_tokens, .token_usage, .total_tokens, etc.
    # Any jq paths extracting these are dead code producing N/A values.
    if grep -q '\.usage\.input_tokens\|\.token_usage\|\.total_tokens' "$WORKFLOW"; then
        fail "ci.yml still has dead token extraction code (all values show N/A)"
    else
        pass "ci.yml has no dead token extraction code"
    fi
}

# Test 68: ci.yml uploads score data as artifact (not git commit/push)
# Score commits pushed via GITHUB_TOKEN don't trigger CI, blocking auto-merge.
# Artifacts preserve data without polluting PR branches.
test_ci_score_history_uploaded_as_artifact() { pass "test_ci_score_history_uploaded_as_artifact n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 70: n/a per #231 Phase 3b — community-e2e-test job deleted
# (replaced by manual review of scan-community digest issues + maintainer
# applies findings + runs `tests/e2e/local-shepherd.sh <PR> --compare-baseline`)
test_weekly_e2e_triggers_on_findings() {
    pass "test_weekly_e2e_triggers_on_findings n/a per #231 Phase 3b (community-e2e-test deleted)"
}

# Test 70b: n/a per #231 Phase 3c — scan-community job deleted entirely.
# Replaced by manual `claude --print` invocation when the maintainer wants
# a community scan, with `.github/prompts/analyze-community.md` as the prompt.
test_scan_community_has_typed_outputs() {
    pass "test_scan_community_has_typed_outputs n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 70c: n/a per #231 Phase 3c — scan-community job deleted entirely.
test_scan_community_no_count_only_gate() {
    pass "test_scan_community_no_count_only_gate n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 70d: n/a per #231 Phase 3c — digest issue creation step gone with scan-community job.
test_digest_gates_on_total_findings() {
    pass "test_digest_gates_on_total_findings n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 70e: n/a per #231 Phase 3b — community-e2e-test deleted
test_e2e_receives_scan_payload() {
    pass "test_e2e_receives_scan_payload n/a per #231 Phase 3b (community-e2e-test deleted)"
}

# Test 70f: n/a per #231 Phase 3c — parse step gone with scan-community job.
test_origin_fallback_in_parse() {
    pass "test_origin_fallback_in_parse n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 71: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_e2e_triggers_on_notable() { pass "test_monthly_e2e_triggers_on_notable n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 72: ci.yml uses upload-artifact for score data in both tiers
test_ci_score_upload_artifact_both_tiers() { pass "test_ci_score_upload_artifact_both_tiers n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 74: ci.yml initializes git in workspace root before claude-code-action
test_ci_workspace_git_init() { pass "test_ci_workspace_git_init n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 75: DELETED — ci.yml no longer has max-turns (e2e jobs removed per #212).
# Shepherd max-turns validated in test-local-shepherd.sh.
test_ci_max_turns_sufficient() { pass "ci-max-turns test n/a per #212 Option 1 (ci.yml e2e jobs removed; shepherd enforces max-turns=55)"; }
_unused_test_ci_max_turns_sufficient() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # Hard scenarios (refactor) need more than 45 turns.
    # error_max_turns causes action failure even with is_error: false.
    MAX_TURNS=$(grep 'max-turns' "$WORKFLOW" | head -1 | sed 's/.*max-turns //' | sed 's/[^0-9].*//')
    if [ -z "$MAX_TURNS" ]; then
        fail "Could not find max-turns in ci.yml"
        return
    fi

    if [ "$MAX_TURNS" -ge 50 ]; then
        pass "ci.yml max-turns ($MAX_TURNS) is sufficient for hard scenarios"
    else
        fail "ci.yml max-turns ($MAX_TURNS) is too low for hard scenarios (need >= 50)"
    fi
}

# Test 76: DELETED — ci.yml no longer has Tier 1 regression compare step per
# ROADMAP #212 Option 1. Regression detection is now advisory via shepherd.
test_tier1_regression_threshold() { pass "tier1-regression-threshold test n/a (ci.yml e2e jobs removed per #212 Option 1)"; }

# ============================================
# Monthly-Research Permission Tests — DELETED
# ============================================
# Test 77: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_has_pr_write_permission() { pass "test_monthly_has_pr_write_permission n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

test_monthly_has_pr_write_permission
test_tier1_regression_threshold
test_ci_no_dead_token_extraction
test_ci_score_history_uploaded_as_artifact
test_weekly_e2e_triggers_on_findings
test_monthly_e2e_triggers_on_notable
test_ci_score_upload_artifact_both_tiers
test_ci_workspace_git_init
test_ci_max_turns_sufficient

# Test 81: ci.yml workspace git init adds origin remote (trusted file restore needs it)
test_ci_workspace_git_init_has_origin() { pass "test_ci_workspace_git_init_has_origin n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 82: ci.yml shellcheck step name accurately describes what it does
test_ci_shellcheck_step_name_accurate() {
    WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "CI workflow file not found"
        return
    fi

    # The step previously said "Shellcheck scripts in workflows" but only runs a grep.
    # Step name must not claim to run shellcheck when it doesn't.
    if grep -q 'name: Shellcheck' "$WORKFLOW"; then
        fail "ci.yml has step named 'Shellcheck' but doesn't actually run shellcheck (misleading)"
    else
        pass "ci.yml shell validation step name is accurate (no false shellcheck claim)"
    fi
}

test_ci_workspace_git_init_has_origin
test_ci_shellcheck_step_name_accurate

# Test 83: weekly-update schedule is weekly (Monday only)
test_weekly_update_monday_schedule() { pass "test_weekly_update_monday_schedule n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 84: All auto-update schedules are uncommented (active)
test_all_schedules_active() { pass "test_all_schedules_active n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 85: ci.yml score artifact upload uses retention-days
test_ci_score_artifact_has_retention() { pass "test_ci_score_artifact_has_retention n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

test_weekly_update_monday_schedule
test_all_schedules_active
test_ci_score_artifact_has_retention

# ============================================
# Weekly-Update Consolidation Structure Tests
# ============================================
# These tests verify the consolidated weekly-update.yml has the
# expected jobs after #231 Phase 3a + 3b + 3c (1 active job; version-test,
# community-e2e-test, and scan-community all deleted).

# Test 86: weekly-update.yml has only check-updates after Phase 3a/3b/3c.
# Asserts NONE of the deleted jobs reappear.
test_weekly_update_has_one_job_post_phase_3c() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
jobs = list(wf.get('jobs', {}).keys())
# Phase 3a (#231) deleted version-test, 3b deleted community-e2e-test,
# 3c deleted scan-community → 1 active job remains.
expected = ['check-updates']
missing = [j for j in expected if j not in jobs]
deleted = [j for j in ('version-test', 'community-e2e-test', 'scan-community') if j in jobs]
if not missing and not deleted:
    print('ALL_PRESENT')
elif deleted:
    print('RESURRECTED:' + ','.join(deleted))
else:
    print('MISSING:' + ','.join(missing))
" > /tmp/weekly_jobs_check.txt 2>&1

    if grep -q "ALL_PRESENT" /tmp/weekly_jobs_check.txt; then
        pass "weekly-update.yml has 1 active job (version-test + community-e2e-test + scan-community deleted per Phase 3a/3b/3c)"
    elif grep -q "RESURRECTED" /tmp/weekly_jobs_check.txt; then
        RESURRECTED=$(grep "RESURRECTED:" /tmp/weekly_jobs_check.txt | sed 's/RESURRECTED://')
        fail "weekly-update.yml has resurrected deleted job(s): $RESURRECTED"
    else
        MISSING=$(grep "MISSING:" /tmp/weekly_jobs_check.txt | sed 's/MISSING://')
        fail "weekly-update.yml missing jobs: $MISSING"
    fi
}

# Test 87: n/a per #231 Phase 3a (version-test deleted, no dependency to check).
# Stub keeps the test count stable so harness counters/CI summaries don't shift.
test_weekly_update_version_test_needs_check_updates() {
    pass "n/a per #231 Phase 3a — version-test deleted (manual local-shepherd replaces it)"
}

# Test 88: n/a per #231 Phase 3b — community-e2e-test deleted, no dependency to check.
test_weekly_update_community_e2e_needs_scan() {
    pass "test_weekly_update_community_e2e_needs_scan n/a per #231 Phase 3b (community-e2e-test deleted)"
}

# Test 89: n/a per #231 Phase 3c — issues: write permission dropped along with
# the digest-issue-creating scan-community job. Regression test: ensure the
# permission stays REMOVED so we don't silently re-grant it.
test_weekly_update_has_issues_permission() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # Per Phase 3c, issues: write must NOT be in the permissions block.
    # Extract just the permissions block: lines BETWEEN `permissions:` and the
    # next top-level key. The naive awk range `/^permissions:/,/^[a-z]/` ends
    # on the `permissions:` line itself (since it matches `^[a-z]`); use a
    # flag-based scan instead.
    PERM_BLOCK=$(awk '/^permissions:/{flag=1; next} flag && /^[a-zA-Z]/{flag=0} flag' "$WORKFLOW")
    if echo "$PERM_BLOCK" | grep -qE "^\s*issues:\s*write\s*$"; then
        fail "weekly-update.yml has resurrected 'issues: write' permission (#231 Phase 3c removed it)"
    else
        pass "weekly-update.yml has no issues: write permission (Phase 3c regression check)"
    fi
}

# Test 90: DELETED — weekly-update.yml cron intentionally disabled per #212.
test_weekly_update_single_cron() { pass "weekly-update-single-cron test n/a per #212 Option 1 (cron disabled; migration tracked #231)"; }

# Test 91: CI Tier 2 comment matches actual trial count (5x, not 3x)
test_tier2_comment_matches_trial_count() { pass "test_tier2_comment_matches_trial_count n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 92: CI Tier 2 cleans stale output between baseline and candidate sims
test_tier2_cleans_stale_output() { pass "test_tier2_cleans_stale_output n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

test_weekly_update_has_one_job_post_phase_3c
test_weekly_update_version_test_needs_check_updates
test_weekly_update_community_e2e_needs_scan
test_weekly_update_has_issues_permission
test_weekly_update_single_cron

# ============================================
# #231 Phase 4: weekly-update.yml shrink regression checks
# ============================================
# After Phase 3d, several leftovers were dead-weight: the VERSION_SCENARIO
# env var (used by the deleted version-test job), and the has_overlap /
# overlap_paths job-level outputs (set by the now-deleted analysis chain
# but consumed by nobody). Phase 4 deletes these. Tests here are
# regression checks — they fail if the dead code resurrects.

# Test 92a: VERSION_SCENARIO env block must NOT exist (dead since Phase 3a)
test_weekly_update_no_dead_version_scenario_env() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    # Use Python YAML so we look at the actual top-level env, not a comment
    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
env = wf.get('env', {}) or {}
if 'VERSION_SCENARIO' in env:
    print('FOUND')
" > /tmp/version_scenario_check.txt 2>&1

    if grep -q "FOUND" /tmp/version_scenario_check.txt; then
        fail "weekly-update.yml still has VERSION_SCENARIO env var (#231 Phase 4: dead since version-test deleted)"
    else
        pass "weekly-update.yml has no dead VERSION_SCENARIO env (Phase 4)"
    fi
}

# Test 92b: has_overlap job output must NOT exist (consumed by nothing post-3d)
test_weekly_update_no_has_overlap_output() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    outputs = job.get('outputs', {}) or {}
    if 'has_overlap' in outputs:
        print('FOUND:' + job_name)
" > /tmp/has_overlap_check.txt 2>&1

    if grep -q "FOUND:" /tmp/has_overlap_check.txt; then
        fail "weekly-update.yml still has has_overlap job output (#231 Phase 4: dead since prove-it-test deleted)"
    else
        pass "weekly-update.yml has no dead has_overlap output (Phase 4)"
    fi
}

# Test 92c: overlap_paths job output must NOT exist (same reason as has_overlap)
test_weekly_update_no_overlap_paths_output() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi

    python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
for job_name, job in wf.get('jobs', {}).items():
    outputs = job.get('outputs', {}) or {}
    if 'overlap_paths' in outputs:
        print('FOUND:' + job_name)
" > /tmp/overlap_paths_check.txt 2>&1

    if grep -q "FOUND:" /tmp/overlap_paths_check.txt; then
        fail "weekly-update.yml still has overlap_paths job output (#231 Phase 4: dead since prove-it-test deleted)"
    else
        pass "weekly-update.yml has no dead overlap_paths output (Phase 4)"
    fi
}

test_weekly_update_no_dead_version_scenario_env
test_weekly_update_no_has_overlap_output
test_weekly_update_no_overlap_paths_output
test_tier2_comment_matches_trial_count
test_tier2_cleans_stale_output

# ============================================
# Full System Audit (#25) — Apply Step Bug Tests
# ============================================
# The "apply" step in auto-update workflows modifies repo root files,
# but candidate simulations run in the test fixture. Without copying
# applied changes into the fixture, baseline == candidate (useless).

# Test 93: n/a per #231 Phase 3a — version-test job deleted (Phase A/B no longer in CI)
test_weekly_update_copies_wizard_after_apply() {
    pass "test_weekly_update_copies_wizard_after_apply n/a per #231 Phase 3a (version-test deleted)"
}

# Test 94: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_copies_wizard_after_apply() { pass "test_monthly_copies_wizard_after_apply n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 95: n/a per #231 Phase 3a — version-test (Phase A/B) deleted from CI
test_weekly_update_cleans_output_before_phase_b() {
    pass "test_weekly_update_cleans_output_before_phase_b n/a per #231 Phase 3a (version-test deleted)"
}

# Test 96: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_cleans_output_before_candidate() { pass "test_monthly_cleans_output_before_candidate n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 97: README uses count-free workflow language (hardcoded counts drift — #102)
test_readme_workflow_count_accurate() {
    README="$REPO_ROOT/README.md"

    if [ ! -f "$README" ]; then
        fail "README.md not found"
        return
    fi

    # README should say "All workflows" not "All N workflows"
    # Hardcoded counts drift silently (#102 — doc consistency enforcement)
    if grep -q "All workflows" "$README" && ! grep -qE 'All [0-9]+ workflows' "$README"; then
        pass "README uses count-free workflow language"
    else
        fail "README should use 'All workflows' not a hardcoded count (see #102)"
    fi
}

test_weekly_update_copies_wizard_after_apply
test_monthly_copies_wizard_after_apply
test_weekly_update_cleans_output_before_phase_b
test_monthly_cleans_output_before_candidate
test_readme_workflow_count_accurate

# Test 98: e2e-quick-check must not skip on workflow_dispatch
# Bug: PR #75 blocked because gh workflow run (dispatch) caused e2e-quick-check to be skipped.
# Branch protection requires e2e-quick-check. Skipped result overwrites previous pass → PR blocked.
test_quick_check_accepts_workflow_dispatch() { pass "test_quick_check_accepts_workflow_dispatch n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 99: cleanup-old-comments must not skip on workflow_dispatch
# Same bug pattern as e2e-quick-check — both are PR-conditional and required (or in needs chain).
test_cleanup_accepts_workflow_dispatch() {
    CI="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$CI" ]; then
        fail "ci.yml not found"
        return
    fi

    local condition
    condition=$(awk '/^ *cleanup-old-comments:/{found=1} found && /^ *if:/{print; exit}' "$CI")

    if echo "$condition" | grep -q "workflow_dispatch"; then
        pass "cleanup-old-comments condition allows workflow_dispatch"
    else
        fail "cleanup-old-comments condition must allow workflow_dispatch (same bug as e2e-quick-check)"
    fi
}

# Test 100: All jobs required by branch protection must run on workflow_dispatch
# Branch protection requires: validate, e2e-quick-check
# validate has no condition (always runs). e2e-quick-check needs dispatch support.
# This test ensures no required job has a pull_request-only condition.
test_required_checks_run_on_dispatch() {
    CI="$REPO_ROOT/.github/workflows/ci.yml"

    if [ ! -f "$CI" ]; then
        fail "ci.yml not found"
        return
    fi

    local all_pass=true

    # Required checks: validate and e2e-quick-check
    for job in validate e2e-quick-check; do
        # Extract the if: line for this job (between job name and its steps/needs)
        local condition
        condition=$(sed -n "/^  ${job}:/,/^  [a-z]/{ /if:/p; }" "$CI" | head -1)

        # No condition means always runs (good)
        if [ -z "$condition" ]; then
            continue
        fi

        # Has a condition — must not be pull_request-only (must include workflow_dispatch)
        if echo "$condition" | grep -q "workflow_dispatch"; then
            continue
        fi

        # If it only checks for pull_request, it will skip on dispatch
        if echo "$condition" | grep -q "pull_request"; then
            all_pass=false
        fi
    done

    if [ "$all_pass" = true ]; then
        pass "All branch-protection-required jobs (validate, e2e-quick-check) run on workflow_dispatch"
    else
        fail "Some required jobs skip on workflow_dispatch — will block auto-merge after self-heal re-trigger"
    fi
}

test_quick_check_accepts_workflow_dispatch
test_cleanup_accepts_workflow_dispatch
test_required_checks_run_on_dispatch

# Test 101: weekly-update fetches release list (not just /releases/latest)
test_weekly_update_multi_release_fetch() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if grep -q 'releases?per_page=' "$WORKFLOW"; then
        pass "weekly-update.yml fetches release list (not just /releases/latest)"
    else
        fail "weekly-update.yml should use releases?per_page= instead of releases/latest"
    fi
}

# Test 102: analyze-release.md handles multiple releases
test_analyze_release_handles_multi() {
    local PROMPT="$REPO_ROOT/.github/prompts/analyze-release.md"

    if grep -qi "one or more.*release\|multiple release\|releases are provided" "$PROMPT"; then
        pass "analyze-release.md handles multiple releases"
    else
        fail "analyze-release.md should mention handling multiple releases"
    fi
}

test_weekly_update_multi_release_fetch
test_analyze_release_handles_multi

# --- --bare flag tests (non-E2E steps should use --bare, E2E simulations should NOT) ---

# Test 107: pr-review.yml uses --bare in claude_args
test_bare_pr_review() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if grep -A2 'claude_args:' "$WORKFLOW" | grep -q '\-\-bare'; then
        pass "pr-review.yml uses --bare in claude_args"
    else
        fail "pr-review.yml should use --bare (non-E2E analysis step)"
    fi
}

# Test 109: n/a per #231 Phase 3d — "Analyze release with Claude" step deleted.
test_bare_weekly_update_analysis() {
    pass "test_bare_weekly_update_analysis n/a per #231 Phase 3d (Claude-ranker step deleted)"
}

# Test 110: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_bare_monthly_research() { pass "test_bare_monthly_research n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 111: ci.yml E2E simulation steps do NOT use --bare (negative test)
test_no_bare_ci_simulations() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

    # ci.yml has ONLY E2E simulation steps — none should have --bare
    if grep -A3 'claude_args:' "$WORKFLOW" | grep -q '\-\-bare'; then
        fail "ci.yml should NOT use --bare (all steps are E2E simulations)"
    else
        pass "ci.yml correctly does NOT use --bare in any step"
    fi
}

# Test 112: weekly-update.yml simulation steps do NOT use --bare (negative test)
test_no_bare_weekly_simulations() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    # Simulation steps have claude_args with --allowedTools but should NOT have --bare
    # Check that simulation step names don't have --bare in their claude_args blocks
    local bare_in_sim=false
    for sim_name in "Run scenario simulation with Claude" "Run baseline simulation with Claude" "Run candidate simulation with Claude"; do
        if sed -n "/name: ${sim_name}/,/name:/p" "$WORKFLOW" | grep -q '\-\-bare'; then
            bare_in_sim=true
            break
        fi
    done

    if [ "$bare_in_sim" = "false" ]; then
        pass "weekly-update.yml simulation steps correctly do NOT use --bare"
    else
        fail "weekly-update.yml simulation steps should NOT use --bare"
    fi
}

# Test 122: pr-review.yml uses --effort xhigh for deep reasoning on reviews
test_pr_review_effort_xhigh() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if grep -A4 'claude_args:' "$WORKFLOW" | grep -q '\-\-effort xhigh'; then
        pass "pr-review.yml uses --effort xhigh in claude_args"
    else
        fail "pr-review.yml should use --effort xhigh for deeper review reasoning"
    fi
}

# Test 123: pr-review.yml uses claude-opus-4-7 model
test_pr_review_opus_model() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"

    if grep -A4 'claude_args:' "$WORKFLOW" | grep -q 'claude-opus-4-7'; then
        pass "pr-review.yml uses claude-opus-4-7 model"
    else
        fail "pr-review.yml should use claude-opus-4-7 for maximum review quality"
    fi
}

test_bare_pr_review
test_bare_weekly_update_analysis
test_bare_monthly_research
test_no_bare_ci_simulations
test_no_bare_weekly_simulations
test_pr_review_effort_xhigh
test_pr_review_opus_model

# --- Bug fix tests (weekly-update/monthly-research workflow issues) ---

# Test 113: n/a per #231 Phase 3c — scan-community job deleted (no git push step left).
test_scan_community_push_nonblocking() {
    pass "test_scan_community_push_nonblocking n/a per #231 Phase 3c (scan-community job deleted)"
}

# Test 114: No working_directory input in weekly-update (not a valid claude-code-action input)
test_no_working_directory_weekly() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"

    if grep -q 'working_directory:' "$WORKFLOW"; then
        fail "weekly-update.yml should not use working_directory (invalid claude-code-action input)"
    else
        pass "weekly-update.yml has no invalid working_directory input"
    fi
}

# Test 115: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_no_working_directory_monthly() { pass "test_no_working_directory_monthly n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 116: Simulation max-turns >= 35 in weekly-update (was 30, ci.yml uses 55)
test_weekly_sim_max_turns() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    local min_turns=35
    local all_ok=true

    while IFS= read -r line; do
        local turns
        turns=$(echo "$line" | grep -oE '[0-9]+')
        if [ -n "$turns" ] && [ "$turns" -lt "$min_turns" ]; then
            all_ok=false
            break
        fi
    done < <(grep 'max-turns' "$WORKFLOW")

    if [ "$all_ok" = "true" ]; then
        pass "weekly-update.yml simulation --max-turns >= $min_turns"
    else
        fail "weekly-update.yml has --max-turns < $min_turns (too low, causes error_max_turns)"
    fi
}

# Test 117: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_sim_max_turns() { pass "test_monthly_sim_max_turns n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

test_scan_community_push_nonblocking
test_no_working_directory_weekly
test_no_working_directory_monthly
test_weekly_sim_max_turns
test_monthly_sim_max_turns

# ============================================
# .gitignore Tests
# ============================================
# Workflows create node_modules and cache artifacts.
# Without .gitignore, peter-evans/create-pull-request commits them.

# Test 118: .gitignore exists at repo root
test_gitignore_exists() {
    if [ -f "$REPO_ROOT/.gitignore" ]; then
        pass ".gitignore exists at repo root"
    else
        fail ".gitignore missing — workflow PRs will commit node_modules and cache artifacts"
    fi
}

# Test 119: .gitignore ignores node_modules
test_gitignore_node_modules() {
    if [ ! -f "$REPO_ROOT/.gitignore" ]; then
        fail ".gitignore missing (can't check node_modules pattern)"
        return
    fi

    if grep -q 'node_modules' "$REPO_ROOT/.gitignore"; then
        pass ".gitignore ignores node_modules"
    else
        fail ".gitignore missing node_modules pattern"
    fi
}

# Test 120: .gitignore ignores e2e cache
test_gitignore_e2e_cache() {
    if [ ! -f "$REPO_ROOT/.gitignore" ]; then
        fail ".gitignore missing (can't check e2e cache pattern)"
        return
    fi

    if grep -q '.cache' "$REPO_ROOT/.gitignore"; then
        pass ".gitignore ignores e2e cache files"
    else
        fail ".gitignore missing e2e cache pattern"
    fi
}

test_gitignore_exists
test_gitignore_node_modules
test_gitignore_e2e_cache

# ============================================
# CI Coverage Tests
# ============================================
# Every test-*.sh script should be wired into ci.yml validate job.
# Catches orphaned test scripts that run locally but not in CI.

# Test 121: All test-*.sh scripts are referenced in ci.yml validate job
test_no_orphaned_test_scripts() {
    local CI="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$CI" ]; then
        fail "ci.yml not found"
        return
    fi

    local orphans=""
    # Check tests/ (top-level test scripts)
    for script in "$REPO_ROOT"/tests/test-*.sh; do
        local name
        name=$(basename "$script")
        if ! grep -q "tests/$name" "$CI"; then
            orphans="$orphans $name"
        fi
    done
    # Check tests/e2e/ (e2e test scripts)
    for script in "$REPO_ROOT"/tests/e2e/test-*.sh; do
        local name
        name=$(basename "$script")
        if ! grep -q "tests/e2e/$name" "$CI"; then
            orphans="$orphans $name"
        fi
    done

    if [ -z "$orphans" ]; then
        pass "All test-*.sh scripts are wired into ci.yml"
    else
        fail "Orphaned test scripts not in ci.yml:$orphans"
    fi
}

test_no_orphaned_test_scripts

# Test 122: All test-*.sh scripts are executable (ci.yml invokes them as
# ./tests/foo.sh, not `bash tests/foo.sh` — a script committed without the
# executable bit passes locally (bash tests/foo.sh doesn't need it) but
# fails CI with "Permission denied", exit 126.
test_all_test_scripts_executable() {
    local non_exec=""
    for script in "$REPO_ROOT"/tests/test-*.sh "$REPO_ROOT"/tests/e2e/test-*.sh; do
        [ -f "$script" ] || continue
        if [ ! -x "$script" ]; then
            non_exec="$non_exec $(basename "$script")"
        fi
    done

    if [ -z "$non_exec" ]; then
        pass "All test-*.sh scripts have the executable bit"
    else
        fail "Scripts missing executable bit (chmod +x):$non_exec"
    fi
}

test_all_test_scripts_executable

# ============================================
# Codex Cross-Model Review Findings (Tests 124-130)
# Validates fixes for issues found by independent Codex audit
# ============================================

# Test 124: pr-review.yml checkout specifies explicit ref for PR head
# Without explicit ref, pull_request_target checks out main instead of PR code
test_pr_review_checkout_explicit_ref() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml not found"
        return
    fi

    if grep -A 5 'actions/checkout@v5' "$WORKFLOW" | grep -q 'ref:'; then
        pass "pr-review.yml checkout specifies explicit ref (pull_request_target safe)"
    else
        fail "pr-review.yml checkout missing explicit ref (pull_request_target checks out base branch)"
    fi
}

# Test 125: pr-review.yml concurrency group uses PR number, not github.ref
# github.ref on pull_request_target = refs/heads/main for ALL PRs (collision)
test_pr_review_concurrency_uses_pr_number() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml not found"
        return
    fi

    if grep -A 4 'concurrency:' "$WORKFLOW" | grep -q 'pull_request.number'; then
        pass "pr-review.yml concurrency group uses PR number (no cross-PR collision)"
    else
        fail "pr-review.yml concurrency group doesn't use PR number (pull_request_target collision risk)"
    fi
}

# Test 126: ci.yml does not use head.ref directly in run: blocks (injection risk)
# head.ref should be passed via env: block, not interpolated inline in shell
test_ci_head_ref_not_in_run_blocks() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "ci.yml not found"
        return
    fi

    # Use YAML parser to check run: block content for direct head.ref interpolation
    local result
    result=$(python3 -c "
import yaml, sys
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
found = False
for job_name, job in wf.get('jobs', {}).items():
    for step in job.get('steps', []):
        run = step.get('run', '')
        if 'pull_request.head.ref' in run:
            found = True
print('CLEAN' if not found else 'FOUND')
" 2>/dev/null) || true
    if [ "$result" = "CLEAN" ]; then
        pass "ci.yml: head.ref passed via env: blocks, not inline in run: blocks"
    else
        fail "ci.yml: head.ref used directly in run: blocks (injection risk — use env: block)"
    fi
}

# Test 127: pr-review.yml trivial detection excludes execution-critical paths
# .github/workflows/*.yml and tests/** should never be "trivial" in this meta-repo
test_trivial_pr_excludes_critical_paths() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml not found"
        return
    fi

    if grep -A 40 'Check if trivial PR' "$WORKFLOW" | grep -q 'github\|\.github'; then
        pass "pr-review.yml trivial detection excludes .github/ paths"
    else
        fail "pr-review.yml trivial detection doesn't exclude .github/ paths (workflow changes skip review)"
    fi
}

# Test 128: INVERTED per ROADMAP #212 Option 1 — pr-review.yml now gates ONLY
# on validate (e2e is advisory, no longer required). Test asserts the old wait
# loop is GONE, not present.
test_ci_wait_includes_e2e() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "pr-review.yml not found"
        return
    fi
    # The WAIT LOOP (not the explanatory comment) must not gate on e2e-quick-check.
    # We look for the actual failure branch: `if [ "$E2E" = "failure" ]` or
    # a success/empty check containing E2E. Both were removed.
    if grep -qE '\$E2E.*failure|E2E.*success.*empty' "$WORKFLOW"; then
        fail "pr-review.yml wait loop STILL checks e2e — should only check validate per #212 Option 1"
    else
        pass "pr-review.yml wait loop only checks validate (e2e is advisory per #212 Option 1)"
    fi
}

# Test 129: CONTRIBUTING.md lists all test scripts that CI validate runs
test_contributing_matches_ci_scripts() {
    local CI="$REPO_ROOT/.github/workflows/ci.yml"
    local CONTRIB="$REPO_ROOT/CONTRIBUTING.md"
    if [ ! -f "$CI" ] || [ ! -f "$CONTRIB" ]; then
        fail "ci.yml or CONTRIBUTING.md not found"
        return
    fi

    # Extract test runner scripts (test-*.sh and run-simulation.sh) from both files
    # Exclude helper scripts like evaluate.sh, score-analytics.sh (not test runners)
    local result
    result=$(python3 -c "
import re
with open('$CONTRIB') as f:
    contrib_scripts = set(re.findall(r'\./tests/(?:e2e/)?(?:test-[^\s\\\\]+\.sh|run-simulation\.sh)', f.read()))
with open('$CI') as f:
    ci_scripts = set(re.findall(r'\./tests/(?:e2e/)?(?:test-[^\s\\\\]+\.sh|run-simulation\.sh)', f.read()))
missing = ci_scripts - contrib_scripts
if missing:
    print('MISSING:' + ','.join(sorted(missing)))
else:
    print('OK')
" 2>/dev/null) || true
    if [ "$result" = "OK" ]; then
        pass "CONTRIBUTING.md lists all test scripts from CI"
    else
        fail "CONTRIBUTING.md missing test scripts that CI validate runs"
    fi
}

# Test 130: /testing skill consolidated into /sdlc (#28)
test_no_testing_skill() {
    if [ -d "$REPO_ROOT/.claude/skills/testing" ]; then
        fail "/testing skill directory still exists — should be consolidated into /sdlc"
    else
        pass "/testing skill consolidated into /sdlc (#28)"
    fi
}

test_pr_review_checkout_explicit_ref
test_pr_review_concurrency_uses_pr_number
test_ci_head_ref_not_in_run_blocks
test_trivial_pr_excludes_critical_paths
test_ci_wait_includes_e2e
test_contributing_matches_ci_scripts
test_no_testing_skill

# --- Round 2: Codex cross-model review findings (2026-03-27) ---

# Test 131: README install URL references correct repo name
test_readme_raw_url_matches_remote() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then
        fail "README.md not found"
        return
    fi

    # Post-npm-distribution: verify GitHub install shorthand uses correct repo name
    if grep -q 'github:BaseInfinity/claude-sdlc-wizard' "$README"; then
        pass "README install URL uses correct repo name"
    else
        fail "README install URL does not reference claude-sdlc-wizard"
    fi
}

# Test 132: No stale "daily" cadence references in key docs
# Weekly + monthly exist, daily was removed. Check broadly — not just specific phrases.
test_no_stale_daily_cadence() {
    local ERRORS=0

    # README.md should not describe daily cadence anywhere (table, summary, etc.)
    # Exclude changelog/historical lines by checking current-tense descriptions
    if grep -qiE 'Daily[/ ].*workflow|Daily.*Claude Code|Daily/weekly/monthly' "$REPO_ROOT/README.md" 2>/dev/null; then
        ERRORS=$((ERRORS + 1))
    fi

    # CLAUDE.md should not say "Daily workflow"
    if grep -qi 'Daily workflow checks Claude Code' "$REPO_ROOT/CLAUDE.md" 2>/dev/null; then
        ERRORS=$((ERRORS + 1))
    fi

    # CLAUDE_CODE_SDLC_WIZARD.md should not say "Daily workflow"
    if grep -qi 'Daily workflow tests new Claude Code' "$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md" 2>/dev/null; then
        ERRORS=$((ERRORS + 1))
    fi

    if [ "$ERRORS" -eq 0 ]; then
        pass "No stale 'daily' cadence references in key docs"
    else
        fail "Found $ERRORS stale 'daily' cadence reference(s) — only weekly/monthly exist"
    fi
}

# Test 134: Wizard does not recommend `act` for workflow testing
# TESTING.md and CI_CD.md say act doesn't work with claude-code-action@v1
test_wizard_no_act_recommendation() {
    local WIZARD="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$WIZARD" ]; then
        fail "CLAUDE_CODE_SDLC_WIZARD.md not found"
        return
    fi

    # Should NOT have act install instructions or recommend act for testing
    if grep -qi 'brew install act\|Use `act` locally\|Local testing with `act`' "$WIZARD"; then
        fail "Wizard still recommends 'act' for workflow testing (contradicts TESTING.md)"
    else
        pass "Wizard does not recommend 'act' for workflow testing"
    fi
}

# Test 135: COMPETITIVE_AUDIT.md does not hardcode stale test script counts
test_competitive_audit_no_stale_counts() {
    local AUDIT="$REPO_ROOT/COMPETITIVE_AUDIT.md"
    if [ ! -f "$AUDIT" ]; then
        fail "COMPETITIVE_AUDIT.md not found"
        return
    fi

    # Should NOT hardcode a specific number of scripts (goes stale)
    if grep -qE '[0-9]+ scripts' "$AUDIT"; then
        fail "COMPETITIVE_AUDIT.md hardcodes a script count (will go stale)"
    else
        pass "COMPETITIVE_AUDIT.md does not hardcode test script count"
    fi
}

# Test 136: AUTO_SELF_UPDATE.md "Who Gets What" section uses current cadence
# History items mention "daily" in past tense (DONE items) — that's fine.
# Monthly was removed per ROADMAP #231 Phase 1; active section should mention weekly-update only.
test_auto_self_update_no_daily() {
    local PLAN="$REPO_ROOT/plans/AUTO_SELF_UPDATE.md"
    if [ ! -f "$PLAN" ]; then
        fail "plans/AUTO_SELF_UPDATE.md not found"
        return
    fi

    # After #231 Phase 1: monthly-research removed. Live "Who Gets What" must not
    # describe monthly as active (no bare "weekly/monthly" cadence pair) and must
    # reference "weekly-update" explicitly.
    if grep -q 'auto-workflows.*weekly-update' "$PLAN" && ! grep -q 'auto-workflows.*(weekly/monthly)' "$PLAN"; then
        pass "AUTO_SELF_UPDATE.md 'Who Gets What' uses current cadence (weekly-update only post #231 Phase 1)"
    else
        fail "AUTO_SELF_UPDATE.md 'Who Gets What' stale — should reference weekly-update only (monthly-research removed per #231 Phase 1)"
    fi
}

test_readme_raw_url_matches_remote
test_no_stale_daily_cadence
test_wizard_no_act_recommendation
test_competitive_audit_no_stale_counts
test_auto_self_update_no_daily

# --- Round 3: Codex main-branch audit findings (2026-03-27) ---

# Test 137: PR review extraction uses robust array detection
test_pr_review_extraction_uses_array_detection() {
    local WF="$REPO_ROOT/.github/workflows/pr-review.yml"
    if [ ! -f "$WF" ]; then fail "pr-review.yml not found"; return; fi

    if grep -q 'type == "array"' "$WF"; then
        pass "pr-review.yml uses robust array/object extraction pattern"
    else
        fail "pr-review.yml missing array detection — still using fragile .result // .output only"
    fi
}

# Test 138: No hook recommends act for workflow testing
test_no_hook_recommends_act() {
    local HOOKS_DIR="$REPO_ROOT/hooks"
    if [ ! -d "$HOOKS_DIR" ]; then fail "hooks/ directory not found"; return; fi

    if grep -rq 'act workflow_dispatch' "$HOOKS_DIR"/ 2>/dev/null; then
        fail "Hook(s) still recommend 'act' for workflow testing — contradicts repo policy"
    else
        pass "No hooks recommend 'act' for workflow testing"
    fi
}

# Test 139: No workflow declares unused id-token: write
# release.yml is excluded — it legitimately uses id-token for npm Trusted
# Publishing (OIDC). Match active code lines only, NOT YAML comments —
# workflows like release-dry-run.yml legitimately mention "id-token: write"
# in their explanatory comments to document WHY they DO NOT request it.
test_no_unused_id_token_permission() {
    local WF_DIR="$REPO_ROOT/.github/workflows"
    local ERRORS=0
    local OFFENDERS=""

    for wf in "$WF_DIR"/*.yml; do
        local name
        name=$(basename "$wf")
        # release.yml legitimately uses id-token: write for npm provenance
        if [ "$name" = "release.yml" ]; then
            continue
        fi
        # Anchor on uncommented lines: optional leading whitespace, then a
        # non-`#` non-whitespace char before the match. A bare `# ...` comment
        # is excluded; an inline trailing comment on an active line still
        # counts (the active code is what matters).
        if grep -qE '^[[:space:]]*[^#[:space:]].*id-token:[[:space:]]*write' "$wf" 2>/dev/null; then
            ERRORS=$((ERRORS + 1))
            OFFENDERS="$OFFENDERS $name"
        fi
    done

    if [ "$ERRORS" -eq 0 ]; then
        pass "No workflow declares unused id-token: write permission (active code, comments allowed)"
    else
        fail "$ERRORS workflow(s) still declare id-token: write in active code (no OIDC consumers exist):$OFFENDERS"
    fi
}

# Test 140: Third-party action tag pinning tradeoff is documented
test_action_pinning_tradeoff_documented() {
    local EXCEPTIONS="$REPO_ROOT/CODE_REVIEW_EXCEPTIONS.md"
    if [ ! -f "$EXCEPTIONS" ]; then fail "CODE_REVIEW_EXCEPTIONS.md not found"; return; fi

    if grep -qi 'pinned to major tags\|tag.pinning' "$EXCEPTIONS" 2>/dev/null; then
        pass "Third-party action tag-pinning tradeoff documented in CODE_REVIEW_EXCEPTIONS.md"
    else
        fail "CODE_REVIEW_EXCEPTIONS.md does not document the action tag-pinning tradeoff"
    fi
}

# Test 142: README does not contain brittle exact test counts
test_readme_no_brittle_test_count() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    # Should not contain "354+" or any specific "NNN+ automated tests" pattern
    if grep -qE '[0-9]{3}\+[[:space:]]+automated tests' "$README" 2>/dev/null; then
        fail "README.md still contains brittle exact test count"
    else
        pass "README.md uses resilient test count wording"
    fi
}

test_pr_review_extraction_uses_array_detection
test_no_hook_recommends_act
test_no_unused_id_token_permission
test_action_pinning_tradeoff_documented
test_readme_no_brittle_test_count

# --- Round 4: Codex pass-2 audit findings (2026-03-27) ---

# Test 143: ci.yml generates SCORE_TRENDS.md before uploading artifact (Tier 1)
test_score_trends_generated_before_upload() { pass "test_score_trends_generated_before_upload n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 144: ci.yml does NOT push score commits to PR branches
test_ci_no_score_git_push_to_pr_branch() {
    local CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$CI_FILE" ]; then fail "ci.yml not found"; return; fi

    # Score recording should NOT git push to PR branches — GITHUB_TOKEN pushes
    # don't trigger CI, creating a new HEAD with zero checks and blocking auto-merge.
    # Check the full score commit steps (both Tier 1 and Tier 2) for git push.
    if grep -B 2 -A 30 'Commit score history' "$CI_FILE" | grep -q 'git push'; then
        fail "ci.yml still pushes score commits to PR branches (blocks auto-merge)"
    else
        pass "ci.yml does not push score commits to PR branches"
    fi
}

# Test 145: SCORE_TRENDS.md does not falsely claim auto-update
test_score_trends_honest_footer() { pass "test_score_trends_honest_footer n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 146: README scoring table shows TDD GREEN as AI-judge
test_readme_tdd_green_is_ai_judge() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    if grep -E 'TDD GREEN.*AI-judge' "$README" >/dev/null 2>&1; then
        pass "README correctly shows TDD GREEN as AI-judge"
    else
        fail "README does not show TDD GREEN as AI-judge"
    fi
}

# Test 147: README scoring split says 40% deterministic (not 60%)
test_readme_scoring_split_accurate() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    if grep -q '40% deterministic' "$README" 2>/dev/null; then
        pass "README correctly says 40% deterministic"
    else
        fail "README does not say 40% deterministic (actual: 4/10 criteria are deterministic)"
    fi
}

# Test 148: CONTRIBUTING.md shows tdd_red at 2 points
test_contributing_tdd_red_points() {
    local CONTRIB="$REPO_ROOT/CONTRIBUTING.md"
    if [ ! -f "$CONTRIB" ]; then fail "CONTRIBUTING.md not found"; return; fi

    if grep -E 'tdd_red.*\| 2 \|' "$CONTRIB" >/dev/null 2>&1; then
        pass "CONTRIBUTING.md correctly shows tdd_red at 2 points"
    else
        fail "CONTRIBUTING.md does not show tdd_red at 2 points (actual max is 2 per deterministic-checks.sh)"
    fi
}

# Test 149: CONTRIBUTING.md task_tracking mentions TodoWrite
test_contributing_task_tracking_mentions_todowrite() {
    local CONTRIB="$REPO_ROOT/CONTRIBUTING.md"
    if [ ! -f "$CONTRIB" ]; then fail "CONTRIBUTING.md not found"; return; fi

    if grep -E 'task_tracking.*TodoWrite' "$CONTRIB" >/dev/null 2>&1; then
        pass "CONTRIBUTING.md task_tracking mentions TodoWrite"
    else
        fail "CONTRIBUTING.md task_tracking does not mention TodoWrite (evaluator checks TodoWrite|TaskCreate)"
    fi
}

# Test 150: ci.yml workflow-level permissions are read-only
test_ci_validate_read_only_permissions() {
    local CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$CI_FILE" ]; then fail "ci.yml not found"; return; fi

    # Check that workflow-level permissions use 'read' not 'write'
    # Extract the permissions block (between 'permissions:' and 'jobs:')
    local perms_section
    perms_section=$(sed -n '/^permissions:/,/^jobs:/p' "$CI_FILE" | head -10)

    if echo "$perms_section" | grep -q 'write' 2>/dev/null; then
        fail "ci.yml workflow-level permissions still grant write access"
    else
        pass "ci.yml workflow-level permissions are read-only"
    fi
}

# Test 151: CI_CD.md Tier 1 description doesn't mention "token metrics"
test_cicd_no_token_metrics_in_tier1() {
    local CICD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CICD" ]; then fail "CI_CD.md not found"; return; fi

    # Check first 40 lines (Tier 1 flow summary area) for "token metrics"
    if head -40 "$CICD" | grep -qi 'token metrics' 2>/dev/null; then
        fail "CI_CD.md still mentions 'token metrics' in Tier 1 flow description"
    else
        pass "CI_CD.md Tier 1 flow does not mention token metrics"
    fi
}

# Test 152: CI_CD.md overview table accurately describes push-to-main
test_cicd_push_main_validation_only() {
    local CICD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CICD" ]; then fail "CI_CD.md not found"; return; fi

    # The overview table should not lump "PR, push to main" in one row with "E2E evaluation"
    # Either split into separate rows or not claim push-to-main does E2E
    if head -15 "$CICD" | grep -i 'ci.yml' | grep -qi 'PR.*push to main.*E2E' 2>/dev/null; then
        fail "CI_CD.md overview table lumps PR and push-to-main together with E2E"
    else
        pass "CI_CD.md overview table accurately distinguishes PR vs push-to-main"
    fi
}

# Test 153: CI_CD.md may mention id-token: write ONLY in the context of an
# active OIDC consumer (npm Trusted Publishing per v1.75.0, or SLSA
# provenance). The original intent was to flag dead/unused declarations.
# With Trusted Publishing live in release.yml, the permission is legitimate;
# this test now ensures any mention is tied to its OIDC consumer.
test_cicd_permissions_no_id_token() {
    local CICD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CICD" ]; then fail "CI_CD.md not found"; return; fi

    # Find every line mentioning id-token: write; each must be co-mentioned
    # with an OIDC consumer (Trusted Publishing, OIDC, or provenance) within
    # the same surrounding paragraph.
    local lines
    lines=$(grep -nE 'id-token[ :_-]*write' "$CICD" 2>/dev/null || true)
    if [ -z "$lines" ]; then
        pass "CI_CD.md has no id-token: write mentions (acceptable when no OIDC consumer is documented)"
        return
    fi
    local bad=0
    while IFS= read -r entry; do
        local line_no="${entry%%:*}"
        # Scan ±5 lines of context for the OIDC-consumer keywords.
        local start=$((line_no > 5 ? line_no - 5 : 1))
        local context
        context=$(sed -n "${start},$((line_no+5))p" "$CICD")
        if echo "$context" | grep -qiE 'Trusted Publishing|OIDC|provenance'; then
            continue
        fi
        bad=$((bad+1))
    done <<< "$lines"
    if [ "$bad" -eq 0 ]; then
        pass "CI_CD.md id-token: write mentions are all tied to an OIDC consumer (Trusted Publishing / provenance)"
    else
        fail "CI_CD.md mentions id-token: write in $bad place(s) without an OIDC-consumer context — declarations must cite Trusted Publishing, OIDC, or provenance"
    fi
}

# Test 157: README setup claim references roadmap for cross-stack
test_readme_setup_mentions_roadmap() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    if grep -i 'auto-detect' "$README" | grep -qi 'roadmap'; then
        pass "README setup claim references roadmap"
    else
        fail "README setup claim does not reference roadmap"
    fi
}

# Test 160: ROADMAP.md has setup-path E2E item
test_roadmap_has_setup_path_e2e() {
    local ROADMAP="$REPO_ROOT/ROADMAP.md"
    if [ ! -f "$ROADMAP" ]; then fail "ROADMAP.md not found"; return; fi

    if grep -qi 'setup.path.*e2e\|setup.*e2e.*proof' "$ROADMAP"; then
        pass "ROADMAP.md has setup-path E2E item"
    else
        fail "ROADMAP.md missing setup-path E2E item"
    fi
}

# Test 163: README setup claim does not say "proven" (CI doesn't verify setup flow)
test_readme_setup_not_proven() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    if grep -i 'auto-detect' "$README" | grep -qi 'proven'; then
        fail "README setup claim says 'proven' but CI doesn't verify setup flow"
    else
        pass "README setup claim does not overstate CI proof"
    fi
}

# Test 164: Weekly community scan fetches open friction-signal issues
test_weekly_fetches_friction_issues() {
    pass "test_weekly_fetches_friction_issues n/a per #231 Phase 3c (scan-community job deleted; manual scan)"
}

# Test 165: README setup claim scopes to generated-asset validation (not setup flow)
test_readme_setup_scopes_generated_assets() {
    local README="$REPO_ROOT/README.md"
    if [ ! -f "$README" ]; then fail "README.md not found"; return; fi

    # The claim about auto-detection should clarify CI validates generated assets, not the setup flow
    if grep -i 'auto-detect' "$README" | grep -qi 'generated.*asset\|asset.*validat\|validates.*generated'; then
        pass "README setup claim scopes to generated-asset validation"
    else
        fail "README setup claim should clarify CI validates generated assets, not setup flow"
    fi
}

# Test 166: n/a per #231 Phase 3c — competitive watchlist now lives only in
# analyze-community.md (manual on-Max prompt), no longer in a weekly CI cron.
test_competitive_audit_says_weekly() {
    pass "test_competitive_audit_says_weekly n/a per #231 Phase 3c (watchlist is manual via analyze-community.md prompt)"
}

# Test 167: n/a per #231 Phase 3c — CI_CD.md weekly section no longer covers the watchlist
# (the watchlist moved to manual on-Max usage of analyze-community.md).
test_cicd_weekly_mentions_watchlist() {
    pass "test_cicd_weekly_mentions_watchlist n/a per #231 Phase 3c (watchlist moved to manual prompt)"
}

# Original test logic preserved here for reference if the watchlist ever returns to a CI workflow.
test_cicd_weekly_mentions_watchlist_DEPRECATED() {
    local CICD="$REPO_ROOT/CI_CD.md"
    if [ ! -f "$CICD" ]; then fail "CI_CD.md not found"; return; fi

    local section
    section=$(sed -n '/## Weekly Update/,/## Monthly/p' "$CICD")
    if [ -z "$section" ]; then
        fail "Could not extract Weekly Update section from CI_CD.md (heading may have changed)"
        return
    fi
    if echo "$section" | grep -qi 'competitive\|watchlist'; then
        pass "CI_CD.md weekly section mentions competitive watchlist"
    else
        fail "CI_CD.md weekly section should mention competitive watchlist"
    fi
}

test_score_trends_generated_before_upload
test_ci_no_score_git_push_to_pr_branch
test_score_trends_honest_footer
test_readme_tdd_green_is_ai_judge
test_readme_scoring_split_accurate
test_contributing_tdd_red_points
test_contributing_task_tracking_mentions_todowrite
test_ci_validate_read_only_permissions
test_cicd_no_token_metrics_in_tier1
test_cicd_push_main_validation_only
test_cicd_permissions_no_id_token
test_readme_setup_mentions_roadmap
test_roadmap_has_setup_path_e2e
test_readme_setup_not_proven
test_weekly_fetches_friction_issues
test_readme_setup_scopes_generated_assets
# Test 171: Tier 2 (e2e-full-evaluation) git init includes origin remote
# Without origin, claude-code-action@v1 fails on "git fetch origin main" trust check.
test_tier2_git_init_has_origin() { pass "test_tier2_git_init_has_origin n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

test_competitive_audit_says_weekly
test_cicd_weekly_mentions_watchlist
test_tier2_git_init_has_origin
test_scan_community_has_typed_outputs
test_scan_community_no_count_only_gate
test_digest_gates_on_total_findings
test_e2e_receives_scan_payload
test_origin_fallback_in_parse

# Test 172: ci.yml Compare step checks critical_miss (Bug 1 regression)
test_ci_verdict_checks_critical_miss() { pass "test_ci_verdict_checks_critical_miss n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 173: ci.yml eval-candidate extracts critical_miss to step output (Bug 1 regression)
test_ci_eval_extracts_critical_miss() { pass "test_ci_eval_extracts_critical_miss n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 174: ci.yml "Record score to history" does NOT silently swallow failures (Bug 3 regression)
test_ci_score_history_no_silent_fail() { pass "test_ci_score_history_no_silent_fail n/a per #212 Option 1 (ci.yml e2e jobs removed)"; }

# Test 175: ci.yml has NO "Commit score history" step (removed — caused auto-merge blocking)
test_ci_no_score_commit_step() {
    local CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$CI_FILE" ]; then fail "ci.yml not found"; return; fi

    # "Commit score history" steps were removed because GITHUB_TOKEN pushes
    # don't trigger CI, creating PR HEADs with zero checks (blocks auto-merge).
    # Score data is now uploaded as artifacts instead.
    if grep -q 'Commit score history' "$CI_FILE" 2>/dev/null; then
        fail "ci.yml still has 'Commit score history' step (should use artifacts instead)"
    else
        pass "ci.yml has no 'Commit score history' step (uses artifacts)"
    fi
}

test_ci_verdict_checks_critical_miss
test_ci_eval_extracts_critical_miss
test_ci_score_history_no_silent_fail
test_ci_no_score_commit_step

# Test 176: DELETED — Persist scores steps removed with e2e jobs per #212 Option 1.
# scripts/persist-score-history.sh still exists and is invoked by local-shepherd.sh.
test_ci_persist_steps_use_script_not_silent() { pass "ci-persist-steps test n/a per #212 Option 1 (persist now handled by shepherd)"; }

test_ci_persist_steps_use_script_not_silent

# --- Round 6: Review pipeline experiment (#27) ---

# Test 181: AGENTS.md exists at repo root (Codex review guidelines)
test_agents_md_exists() {
    if [ -f "$REPO_ROOT/AGENTS.md" ]; then
        pass "AGENTS.md exists (Codex review guidelines)"
    else
        fail "AGENTS.md should exist for Codex review guidelines"
    fi
}

# Test 182: AGENTS.md references CODE_REVIEW_EXCEPTIONS.md
test_agents_md_references_exceptions() {
    if [ ! -f "$REPO_ROOT/AGENTS.md" ]; then fail "AGENTS.md not found"; return; fi
    if grep -q "CODE_REVIEW_EXCEPTIONS" "$REPO_ROOT/AGENTS.md"; then
        pass "AGENTS.md references CODE_REVIEW_EXCEPTIONS.md"
    else
        fail "AGENTS.md should reference CODE_REVIEW_EXCEPTIONS.md"
    fi
}

# Test 183: Review experiment tracking file exists
test_review_experiment_tracking_exists() {
    if [ -f "$REPO_ROOT/.reviews/experiment-tracking.md" ]; then
        pass "Review experiment tracking file exists"
    else
        fail ".reviews/experiment-tracking.md should exist for the Claude vs Codex experiment"
    fi
}

test_agents_md_exists
test_agents_md_references_exceptions
test_review_experiment_tracking_exists

# ============================================
# Auto-Update CI Trigger Tests (#41)
# ============================================
# peter-evans/create-pull-request uses GITHUB_TOKEN which doesn't trigger
# pull_request events (GitHub anti-loop protection). We need to manually
# dispatch CI after PR creation so auto-update PRs get checked.

# Test 184: weekly-update.yml has actions: write permission
test_weekly_has_actions_write() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if grep -q 'actions: write' "$WORKFLOW"; then
        pass "weekly-update.yml has actions: write permission (needed for CI dispatch)"
    else
        fail "weekly-update.yml missing actions: write permission (gh workflow run returns 403)"
    fi
}

# Test 185: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_has_actions_write() { pass "test_monthly_has_actions_write n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

# Test 186: weekly-update.yml dispatches CI after auto-update PR creation
test_weekly_dispatches_ci_after_update_pr() {
    WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    # The check-updates job creates the auto-update PR. It must dispatch CI afterward.
    if grep -q 'gh workflow run ci.yml' "$WORKFLOW"; then
        pass "weekly-update.yml dispatches CI after PR creation"
    else
        fail "weekly-update.yml should dispatch CI after PR creation (GITHUB_TOKEN PRs don't trigger pull_request events)"
    fi
}

# Test 187: DELETED — monthly-research.yml removed per ROADMAP #231 Phase 1
test_monthly_dispatches_ci_after_pr() { pass "test_monthly_dispatches_ci_after_pr n/a per #231 Phase 1 (monthly-research.yml deleted)"; }

test_weekly_has_actions_write
test_monthly_has_actions_write
test_weekly_dispatches_ci_after_update_pr
test_monthly_dispatches_ci_after_pr

# --- Reviewer Severity Prompt Fix Tests (#34) ---

# Test 188: pr-review.yml prompt contains P0/P1/P2 severity rubric
test_review_prompt_has_severity_rubric() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if grep -q 'P0.*Critical' "$WORKFLOW" && grep -q 'P1.*Must' "$WORKFLOW" && grep -q 'P2.*Suggestion' "$WORKFLOW"; then
        pass "pr-review.yml prompt has P0/P1/P2 severity rubric"
    else
        fail "pr-review.yml prompt should have P0/P1/P2 severity rubric"
    fi
}

# Test 189: pr-review.yml prompt explicitly mentions "silent failures" as P0
test_review_prompt_has_silent_failure_escalation() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if grep -qi 'silent.*fail' "$WORKFLOW"; then
        pass "pr-review.yml prompt escalates silent failures"
    else
        fail "pr-review.yml prompt should explicitly escalate silent failures to P0"
    fi
}

# Test 190: pr-review.yml output format uses P0/P1/P2 sections
test_review_output_format_three_tier() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    if grep -q '#### P0' "$WORKFLOW" && grep -q '#### P1' "$WORKFLOW" && grep -q '#### P2' "$WORKFLOW"; then
        pass "pr-review.yml output format uses P0/P1/P2 sections"
    else
        fail "pr-review.yml output format should use P0/P1/P2 sections (not just Critical/Suggestions)"
    fi
}

# Test 191: pr-review.yml severity rubric matches AGENTS.md rubric
test_review_severity_matches_agents() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/pr-review.yml"
    local AGENTS="$REPO_ROOT/AGENTS.md"
    # Both should list the same P0 categories
    if grep -qi 'silent failures' "$WORKFLOW" && grep -qi 'silent failures' "$AGENTS"; then
        pass "pr-review.yml and AGENTS.md both classify silent failures as P0"
    else
        fail "pr-review.yml and AGENTS.md should have aligned severity definitions"
    fi
}

test_review_prompt_has_severity_rubric
test_review_prompt_has_silent_failure_escalation
test_review_output_format_three_tier
test_review_severity_matches_agents

# ============================================
# CI Self-Heal Deprecation Tests
# ============================================
# ci-self-heal.yml was removed — local shepherd is sufficient.
# These tests ensure it stays deleted and references are cleaned up.

# Test: ci-self-heal.yml must NOT exist (deprecated)
test_ci_self_heal_deleted() {
    if [ -f "$REPO_ROOT/.github/workflows/ci-self-heal.yml" ]; then
        fail "ci-self-heal.yml still exists (deprecated — local shepherd replaces it)"
    else
        pass "ci-self-heal.yml does not exist (deprecated)"
    fi
}

# Test: ci.yml does not run self-heal simulation tests
test_ci_no_self_heal_simulation_step() {
    local CI_FILE="$REPO_ROOT/.github/workflows/ci.yml"
    if grep -q 'test-self-heal-simulation' "$CI_FILE"; then
        fail "ci.yml still runs self-heal simulation tests (workflow deleted)"
    else
        pass "ci.yml has no self-heal simulation test step"
    fi
}

# Test: self-heal simulation test file must NOT exist
test_self_heal_simulation_deleted() {
    if [ -f "$REPO_ROOT/tests/e2e/test-self-heal-simulation.sh" ]; then
        fail "test-self-heal-simulation.sh still exists (deprecated)"
    else
        pass "test-self-heal-simulation.sh does not exist (deprecated)"
    fi
}

# Test: ARCHITECTURE.md does not list ci-self-heal.yml
test_architecture_no_self_heal() {
    if grep -q 'ci-self-heal' "$REPO_ROOT/ARCHITECTURE.md"; then
        fail "ARCHITECTURE.md still references ci-self-heal.yml"
    else
        pass "ARCHITECTURE.md has no ci-self-heal reference"
    fi
}

# Test: CI_CD.md does not document Tier 2 auto-fix bot
test_cicd_no_tier2_autofix() {
    if grep -q 'ci-self-heal' "$REPO_ROOT/CI_CD.md"; then
        fail "CI_CD.md still references ci-self-heal.yml"
    else
        pass "CI_CD.md has no ci-self-heal reference"
    fi
}

# Test: SKILL.md CI Feedback Loop does not mention auto-fix bot
test_skill_no_autofix_bot() {
    local SKILL="$REPO_ROOT/.claude/skills/sdlc/SKILL.md"
    if grep -qi 'auto-fix bot\|ci-autofix' "$SKILL"; then
        fail "SKILL.md still references CI auto-fix bot"
    else
        pass "SKILL.md has no auto-fix bot reference"
    fi
}

# Test: ci.yml must compute max_score from eval output, not hardcode it.
# Regresses ROADMAP #211 — UI scenarios score 11/11 but score-history.jsonl
# recorded max_score=10, causing PR comments to show "11/10" (confusing and
# breaks downstream analytics that rely on max_score being accurate).
test_ci_max_score_not_hardcoded() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
    local HARDCODED
    HARDCODED=$(grep -cE "argjson[[:space:]]+max_score[[:space:]]+[0-9]+" "$WORKFLOW" || true)
    if [ "$HARDCODED" -gt 0 ]; then
        fail "ci.yml hardcodes --argjson max_score to a literal number ($HARDCODED instance(s)) — should read from eval result"
    else
        pass "ci.yml does not hardcode --argjson max_score (reads from eval result)"
    fi
}

# Test: every steps.<id>.outputs.<name> reference in ci.yml points at a real output
# Regresses ROADMAP #215 — Tier 2 "Persist scores to PR branch" step gated on
# steps.check-baseline.outputs.should_simulate, but the Tier 2 check-baseline
# never emits should_simulate — so the step was silently dead (regression from #193).
test_ci_gated_expressions_reference_real_outputs() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "ci.yml not found"
        return
    fi

    if python3 - "$WORKFLOW" <<'PYEOF'
import re, sys, yaml

path = sys.argv[1]
with open(path) as fh:
    wf = yaml.safe_load(fh)

broken = []
OUT_RE = re.compile(r'echo\s+"?([A-Za-z_][A-Za-z0-9_]*)(=|<<)')
REF_RE = re.compile(r'steps\.([A-Za-z0-9_-]+)\.outputs\.([A-Za-z0-9_-]+)')

for job_name, job in (wf.get('jobs') or {}).items():
    steps = job.get('steps') or []
    emitted = {}
    for step in steps:
        sid = step.get('id')
        if not sid:
            continue
        run = step.get('run') or ''
        names = set()
        # If the step writes to $GITHUB_OUTPUT anywhere, scan every `echo "name=..."`
        # or `echo "name<<EOF"` in the run block — they're outputs (possibly inside
        # a { ... } >> $GITHUB_OUTPUT block, possibly direct redirect).
        if '$GITHUB_OUTPUT' in run:
            for line in run.splitlines():
                m = OUT_RE.search(line)
                if m:
                    names.add(m.group(1))
        # Multiple steps can share the same id across branches of conditional setup;
        # union the outputs so a later emitter counts.
        emitted.setdefault(sid, set()).update(names)

    def scan(val, where):
        if isinstance(val, str):
            for sid, name in REF_RE.findall(val):
                if sid in emitted and name not in emitted[sid]:
                    broken.append(f"{job_name}:{where} -> steps.{sid}.outputs.{name} (step emits: {sorted(emitted[sid]) or 'nothing'})")
        elif isinstance(val, dict):
            for k, v in val.items():
                scan(v, f"{where}.{k}")
        elif isinstance(val, list):
            for i, v in enumerate(val):
                scan(v, f"{where}[{i}]")

    for idx, step in enumerate(steps):
        scan(step, f"step[{idx}]({step.get('name') or step.get('id') or '?'})")

if broken:
    print("Dead-gate or mismatched output references in ci.yml:", file=sys.stderr)
    for b in broken:
        print(f"  - {b}", file=sys.stderr)
    sys.exit(1)
PYEOF
    then
        pass "All ci.yml steps.<id>.outputs.<name> refs resolve to real outputs"
    else
        fail "ci.yml has dead-gate steps.<id>.outputs.<name> refs"
    fi
}

test_ci_self_heal_deleted
test_ci_no_self_heal_simulation_step
test_self_heal_simulation_deleted
test_architecture_no_self_heal
test_cicd_no_tier2_autofix
test_skill_no_autofix_bot
test_ci_max_score_not_hardcoded
test_ci_gated_expressions_reference_real_outputs

# Test (#227): weekly-update.yml must NOT call `cusum.sh --add` because it
# appends to legacy score-history.txt, creating PR noise on every run
# (per Codex finding PR213-02). The canonical history is score-history.jsonl
# written elsewhere via --add-json.
test_weekly_update_does_not_call_legacy_cusum_add() {
    local WORKFLOW="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if [ ! -f "$WORKFLOW" ]; then
        fail "weekly-update.yml not found"
        return
    fi
    # Match `cusum.sh --add ` (with space, NOT --add-json — that's the new path)
    # The legacy --add writes to .txt; --add-json writes to .jsonl (canonical).
    if grep -nE 'cusum\.sh[[:space:]]+--add[[:space:]]' "$WORKFLOW"; then
        fail "#227: weekly-update.yml still calls 'cusum.sh --add' (legacy .txt write — PR-noise source)"
    else
        pass "#227: weekly-update.yml does not call legacy 'cusum.sh --add' (no PR noise from score-history.txt)"
    fi
}

test_weekly_update_does_not_call_legacy_cusum_add

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All workflow trigger tests passed!"
