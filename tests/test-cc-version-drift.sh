#!/bin/bash
# Quality tests for .github/workflows/cc-version-drift.yml and the
# associated SDLC.md anchor — ROADMAP #350.
#
# Each test asserts a Codex-design-review constraint (Prove-It Gate,
# .reviews/176-followup-prio-codex.md #350). Existence tests would
# pass trivially against a stub; these check BEHAVIOR.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF="$REPO_ROOT/.github/workflows/cc-version-drift.yml"
SDLC_MD="$REPO_ROOT/SDLC.md"
SCRIPT="$REPO_ROOT/scripts/cc-drift-check.sh"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------------
# 1. Files exist + YAML parses
# ----------------------------------------------------------------------

test_workflow_exists() {
    [ -f "$WF" ] && pass "cc-version-drift.yml exists" || { fail "missing"; return 1; }
}

test_yaml_valid() {
    python3 -c "import yaml; yaml.safe_load(open('$WF'))" 2>/dev/null \
        && pass "cc-version-drift.yml is valid YAML" \
        || fail "invalid YAML"
}

# ----------------------------------------------------------------------
# 2. Triggers — weekly cron + workflow_dispatch
# ----------------------------------------------------------------------

test_has_schedule() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
on = d.get(True, d.get('on'))
sched = on.get('schedule')
assert sched and len(sched) >= 1, 'no schedule entries'
" 2>/dev/null && pass "has schedule trigger" || fail "missing schedule trigger"
}

test_cron_is_staggered() {
    # Codex constraint: '30 9 * * 1' (Mon 09:30 UTC), staggered from
    # weekly-update.yml (09:00) and weekly-api-update.yml (10:00).
    if grep -qE "cron:[[:space:]]*'30 9 \\* \\* 1'" "$WF"; then
        pass "cron staggered at Mon 09:30 UTC (between 09:00 and 10:00 neighbors)"
    else
        fail "cron must be '30 9 * * 1' to stagger from existing weekly workflows"
    fi
}

test_has_workflow_dispatch() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
on = d.get(True, d.get('on'))
assert 'workflow_dispatch' in on
" 2>/dev/null && pass "has workflow_dispatch trigger" || fail "missing workflow_dispatch"
}

# ----------------------------------------------------------------------
# 3. Permissions — issues: write (required) + contents: read; NO id-token
# ----------------------------------------------------------------------

test_permissions_issues_write() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
p = d.get('permissions', {})
assert p.get('issues') == 'write', 'permissions.issues must be write'
assert p.get('contents') == 'read', 'permissions.contents must be read'
" 2>/dev/null && pass "permissions: issues: write + contents: read" \
        || fail "permissions must declare 'issues: write' and 'contents: read'"
}

test_no_id_token() {
    # Match active code only (allow explanatory comments).
    if grep -qE '^[[:space:]]*[^#[:space:]].*id-token:[[:space:]]*write' "$WF"; then
        fail "id-token: write must not be declared (no OIDC consumer)"
    else
        pass "no active id-token: write declaration"
    fi
}

test_no_pull_requests_write() {
    if grep -qE '^[[:space:]]*[^#[:space:]].*pull-requests:[[:space:]]*write' "$WF"; then
        fail "pull-requests: write should not be declared (this workflow doesn't open PRs)"
    else
        pass "no pull-requests: write (only opens issues)"
    fi
}

# ----------------------------------------------------------------------
# 4. NOT in weekly-update.yml — standalone (Codex constraint #350.1)
# ----------------------------------------------------------------------

test_not_in_weekly_update_yml() {
    local weekly="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if grep -qE 'cc-version-drift|cc-drift-check\.sh|Claude Code Baseline' "$weekly" 2>/dev/null; then
        fail "weekly-update.yml mentions CC drift logic — must stay standalone (#212/#231 guardrails)"
    else
        pass "drift detection lives in standalone workflow, not weekly-update.yml"
    fi
}

# ----------------------------------------------------------------------
# 5. No LLM / no Anthropic action — pure GH-API + curl
# ----------------------------------------------------------------------

test_no_claude_code_action() {
    if grep -qE '^[[:space:]]*[^#[:space:]].*anthropics/claude-code-action' "$WF"; then
        fail "must not use anthropics/claude-code-action (zero-API requirement, ROADMAP #231)"
    else
        pass "no anthropics/claude-code-action (zero-API)"
    fi
}

# ----------------------------------------------------------------------
# 6. SDLC.md baseline anchor (Codex constraint #350.2)
# ----------------------------------------------------------------------

test_sdlc_baseline_anchor_present() {
    if grep -qE '<!-- Claude Code Baseline: v?[0-9]+\.[0-9]+\.[0-9]+ -->' "$SDLC_MD"; then
        pass "SDLC.md has single-purpose '<!-- Claude Code Baseline: vX.Y.Z -->' anchor"
    else
        fail "SDLC.md must contain '<!-- Claude Code Baseline: vX.Y.Z -->' anchor for the cron to parse"
    fi
}

test_sdlc_baseline_exactly_once() {
    local count
    count=$(grep -cE '<!-- Claude Code Baseline: v?[0-9]+\.[0-9]+\.[0-9]+ -->' "$SDLC_MD")
    if [ "$count" = "1" ]; then
        pass "exactly one CC Baseline anchor in SDLC.md (unambiguous)"
    else
        fail "expected 1 CC Baseline anchor in SDLC.md, found $count"
    fi
}

test_baseline_matches_recommended_row() {
    # Codex constraint: anchor must match the first SemVer in the
    # "Claude Code Recommended" row so they don't drift internally.
    local anchor row
    anchor=$(grep -oE '<!-- Claude Code Baseline: v?[0-9]+\.[0-9]+\.[0-9]+ -->' "$SDLC_MD" | head -1 \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    row=$(grep -E '^\| Claude Code Recommended' "$SDLC_MD" | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
    if [ -n "$anchor" ] && [ -n "$row" ] && [ "$anchor" = "$row" ]; then
        pass "Baseline anchor (v${anchor}) matches Recommended row (v${row})"
    else
        fail "Baseline anchor (v${anchor:-MISSING}) must match Claude Code Recommended row (v${row:-MISSING})"
    fi
}

test_workflow_parses_anchor() {
    # Workflow must grep the anchor with the exact format we ship.
    if grep -qE 'Claude Code Baseline' "$WF"; then
        pass "workflow parses '<!-- Claude Code Baseline: ... -->' from SDLC.md"
    else
        fail "workflow must reference 'Claude Code Baseline' anchor name"
    fi
}

# ----------------------------------------------------------------------
# 7. Label + idempotency — edit existing, dedupe via label
# ----------------------------------------------------------------------

test_label_name() {
    # Match 'cc-version-drift' or "cc-version-drift" after REVIEW_LABEL:.
    # Use grep -F-style literal substring inside a wider grep -E to dodge
    # bash quote-escape interactions inside the alternation class.
    if grep -E "REVIEW_LABEL:[[:space:]]*['\"]cc-version-drift['\"]" "$WF" >/dev/null 2>&1; then
        pass "uses label 'cc-version-drift'"
    else
        fail "must declare REVIEW_LABEL: 'cc-version-drift'"
    fi
}

test_edit_existing_not_comment() {
    # If an open issue exists, edit it (do NOT post a comment). Comment-
    # spam pattern would be `gh issue comment`.
    if grep -qE 'gh issue edit' "$WF" && ! grep -qE 'gh issue comment' "$WF"; then
        pass "edits existing issue instead of comment-spamming"
    else
        fail "must use 'gh issue edit' on existing open issue; must NOT use 'gh issue comment'"
    fi
}

test_machine_readable_marker_in_body() {
    # Marker format from Codex pseudocode: cc-version-drift baseline=... latest=... delta=... threshold=... component=...
    if grep -qE 'cc-version-drift baseline=' "$WF"; then
        pass "issue body contains machine-readable marker (baseline=/latest=/delta=)"
    else
        fail "issue body must contain machine-readable marker for re-comparison on next cron"
    fi
}

# ----------------------------------------------------------------------
# 8. Threshold configurability
# ----------------------------------------------------------------------

test_threshold_default_5() {
    if grep -qE "CC_DRIFT_THRESHOLD:[[:space:]]*'5'" "$WF"; then
        pass "default threshold is 5 (env var, in-git policy)"
    else
        fail "must default CC_DRIFT_THRESHOLD to '5'"
    fi
}

test_threshold_input_override() {
    # Workflow_dispatch should allow ad-hoc threshold override.
    if grep -qE 'threshold:' "$WF" && grep -qE 'inputs\.threshold' "$WF"; then
        pass "workflow_dispatch accepts threshold input override"
    else
        fail "must allow workflow_dispatch input to override threshold"
    fi
}

# ----------------------------------------------------------------------
# 9. Script integration
# ----------------------------------------------------------------------

test_invokes_drift_script() {
    if grep -qE 'scripts/cc-drift-check\.sh' "$WF"; then
        pass "workflow invokes scripts/cc-drift-check.sh (logic is unit-tested in test-cc-drift-check.sh)"
    else
        fail "workflow must call scripts/cc-drift-check.sh for version-delta logic"
    fi
}

test_drift_script_exists_and_executable() {
    if [ -x "$SCRIPT" ]; then
        pass "scripts/cc-drift-check.sh exists and is executable"
    else
        fail "scripts/cc-drift-check.sh must exist and be executable"
    fi
}

# ----------------------------------------------------------------------
# 10. Fail loud — no `|| true` suppression
# ----------------------------------------------------------------------

test_no_silent_failures() {
    # Look for `|| true` or `|| echo` in ACTIVE code (not comments)
    # that would suppress gh/npm/jq failures. These are bug-magnets per
    # #231 lessons. Codex constraint #350.8 explicitly forbids them.
    # The workflow's HEADER comment names these patterns to explain WHY
    # they're absent — that documentation should not trip the test, so
    # we anchor on uncommented lines using the same pattern as
    # test_no_node_auth_token in tests/test-release-dry-run-workflow.sh.
    local hits
    hits=$(grep -E '^[[:space:]]*[^#[:space:]].*\|\|[[:space:]]*(true|echo)' "$WF" 2>/dev/null || true)
    if [ -z "$hits" ]; then
        pass "no active || true / || echo failure-suppression (comments allowed)"
        return
    fi
    # Allow sentinel exceptions: closed-issue marker parsing has
    # defaults that fall back when markers are missing (first cron
    # run or legacy issues). `|| echo '-1'` for CLOSED_DELTA,
    # `|| echo 'unknown'` for CLOSED_BASELINE.
    local non_sentinel
    non_sentinel=$(echo "$hits" | grep -vE "echo '-1'|echo 'unknown'" || true)
    if [ -z "$non_sentinel" ]; then
        pass "no active || true / || echo (sentinel echo '-1' and echo 'unknown' exceptions accepted)"
    else
        fail "found || true / || echo suppression in active code: $non_sentinel"
    fi
}

# ----------------------------------------------------------------------
# 11. Baseline-aware re-open after bump (bug fix 2026-06-27)
# ----------------------------------------------------------------------

test_baseline_aware_reopen() {
    # Bug: after bumping the SDLC.md baseline, the delta resets (e.g.
    # old: baseline=170, latest=185, delta=15 → closed issue has delta=15;
    # new: baseline=185, latest=195, delta=10). The workflow compared
    # 10 > 15 → false → stayed silent. Fix: also extract the baseline
    # version from the closed issue marker and re-alert when the baseline
    # has changed (meaning we bumped and the delta is fresh).
    if grep -qE 'baseline=' "$WF" \
        && grep -qE 'CLOSED_BASELINE' "$WF"; then
        pass "workflow extracts baseline from closed issue for baseline-aware comparison"
    else
        fail "workflow must extract CLOSED_BASELINE from closed issue marker — delta-only comparison is fooled by baseline bumps"
    fi
}

# ----------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------

test_workflow_exists
test_yaml_valid
test_has_schedule
test_cron_is_staggered
test_has_workflow_dispatch
test_permissions_issues_write
test_no_id_token
test_no_pull_requests_write
test_not_in_weekly_update_yml
test_no_claude_code_action
test_sdlc_baseline_anchor_present
test_sdlc_baseline_exactly_once
test_baseline_matches_recommended_row
test_workflow_parses_anchor
test_label_name
test_edit_existing_not_comment
test_machine_readable_marker_in_body
test_threshold_default_5
test_threshold_input_override
test_invokes_drift_script
test_drift_script_exists_and_executable
test_baseline_aware_reopen
test_no_silent_failures

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All cc-version-drift workflow tests passed!"
