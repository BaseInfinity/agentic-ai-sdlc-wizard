#!/bin/bash
# Unit tests for scripts/cc-drift-check.sh — version-delta logic
# isolated from GitHub API calls. Per Codex design review
# .reviews/176-followup-prio-codex.md #350.6, this is split from
# tests/test-cc-version-drift.sh which covers the workflow YAML.

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/cc-drift-check.sh"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------------
# Existence
# ----------------------------------------------------------------------

test_script_exists() {
    if [ -x "$SCRIPT" ]; then
        pass "scripts/cc-drift-check.sh exists and is executable"
    else
        fail "scripts/cc-drift-check.sh missing or not executable"
        return 1
    fi
}

# ----------------------------------------------------------------------
# Happy path: same major.minor line, patch deltas
# ----------------------------------------------------------------------

test_same_version() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.150)
    if echo "$out" | jq -e '.patch_delta == 0 and .alert == false and .threshold_exceeded == false and .component == "patch"' >/dev/null; then
        pass "same version: patch_delta=0, alert=false"
    else
        fail "same version: expected no alert, got: $out"
    fi
}

test_below_threshold() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.153)
    if echo "$out" | jq -e '.patch_delta == 3 and .alert == false and .threshold_exceeded == false' >/dev/null; then
        pass "below threshold: patch_delta=3 (default 5), alert=false"
    else
        fail "below threshold check failed: $out"
    fi
}

test_at_threshold_no_alert() {
    # Codex constraint: alert only when delta > threshold; exactly threshold does NOT alert.
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.155)
    if echo "$out" | jq -e '.patch_delta == 5 and .alert == false and .threshold_exceeded == false' >/dev/null; then
        pass "at threshold (delta=5, threshold=5): no alert (strict >)"
    else
        fail "at-threshold should NOT alert: $out"
    fi
}

test_above_threshold() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.180)
    if echo "$out" | jq -e '.patch_delta == 30 and .alert == true and .threshold_exceeded == true and .component == "patch"' >/dev/null; then
        pass "above threshold: patch_delta=30, alert=true"
    else
        fail "above threshold check failed: $out"
    fi
}

# ----------------------------------------------------------------------
# Cross-component jumps always alert regardless of threshold
# ----------------------------------------------------------------------

test_minor_jump_always_alerts() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.2.0)
    if echo "$out" | jq -e '.component == "minor" and .alert == true and .threshold_exceeded == true' >/dev/null; then
        pass "minor jump alerts (component=minor, alert=true regardless of threshold)"
    else
        fail "minor jump should alert: $out"
    fi
}

test_major_jump_always_alerts() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 3.0.0)
    if echo "$out" | jq -e '.component == "major" and .alert == true and .threshold_exceeded == true' >/dev/null; then
        pass "major jump alerts (component=major, alert=true regardless of threshold)"
    else
        fail "major jump should alert: $out"
    fi
}

# ----------------------------------------------------------------------
# 'v' prefix stripping — npm view returns '1.2.3', git tags use 'v1.2.3'
# ----------------------------------------------------------------------

test_v_prefix_baseline() {
    local out
    out=$("$SCRIPT" --baseline v2.1.150 --latest 2.1.180)
    if echo "$out" | jq -e '.baseline == "2.1.150" and .patch_delta == 30' >/dev/null; then
        pass "'v' prefix stripped from baseline"
    else
        fail "'v' prefix stripping failed: $out"
    fi
}

test_v_prefix_latest() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest v2.1.180)
    if echo "$out" | jq -e '.latest == "2.1.180" and .patch_delta == 30' >/dev/null; then
        pass "'v' prefix stripped from latest"
    else
        fail "'v' prefix stripping failed: $out"
    fi
}

# ----------------------------------------------------------------------
# Configurable threshold
# ----------------------------------------------------------------------

test_custom_threshold_above() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.155 --threshold 3)
    if echo "$out" | jq -e '.threshold == 3 and .alert == true' >/dev/null; then
        pass "custom threshold=3 with delta=5: alerts"
    else
        fail "custom threshold path failed: $out"
    fi
}

test_custom_threshold_below() {
    local out
    out=$("$SCRIPT" --baseline 2.1.150 --latest 2.1.157 --threshold 10)
    if echo "$out" | jq -e '.threshold == 10 and .alert == false' >/dev/null; then
        pass "custom threshold=10 with delta=7: no alert"
    else
        fail "custom threshold below path failed: $out"
    fi
}

# ----------------------------------------------------------------------
# Error paths — invalid input must exit 2, not silently default
# ----------------------------------------------------------------------

test_invalid_baseline() {
    if "$SCRIPT" --baseline foo --latest 2.1.150 >/dev/null 2>&1; then
        fail "invalid baseline should exit 2, got success"
    else
        local rc=$?
        if [ "$rc" -eq 2 ]; then
            pass "invalid baseline exits 2"
        else
            fail "invalid baseline should exit 2, got $rc"
        fi
    fi
}

test_invalid_latest() {
    if "$SCRIPT" --baseline 2.1.150 --latest bar >/dev/null 2>&1; then
        fail "invalid latest should exit 2, got success"
    else
        [ "$?" -eq 2 ] && pass "invalid latest exits 2" \
            || fail "invalid latest should exit 2"
    fi
}

test_missing_args() {
    if "$SCRIPT" >/dev/null 2>&1; then
        fail "no args should exit non-zero"
    else
        pass "no args exits non-zero"
    fi
}

test_invalid_threshold_negative() {
    if "$SCRIPT" --baseline 2.1.150 --latest 2.1.180 --threshold -3 >/dev/null 2>&1; then
        fail "negative threshold should exit 2"
    else
        [ "$?" -eq 2 ] && pass "negative threshold exits 2" \
            || fail "negative threshold should exit 2"
    fi
}

test_invalid_threshold_non_integer() {
    if "$SCRIPT" --baseline 2.1.150 --latest 2.1.180 --threshold "ten" >/dev/null 2>&1; then
        fail "non-integer threshold should exit 2"
    else
        [ "$?" -eq 2 ] && pass "non-integer threshold exits 2" \
            || fail "non-integer threshold should exit 2"
    fi
}

test_latest_older_than_baseline() {
    # Common misconfig: caller swapped --baseline and --latest. Must fail
    # loud rather than emit a misleading "negative gap is fine" payload.
    if "$SCRIPT" --baseline 2.1.180 --latest 2.1.150 >/dev/null 2>&1; then
        fail "regression (latest < baseline) should exit 2, got success"
    else
        [ "$?" -eq 2 ] && pass "latest < baseline exits 2 (caller error)" \
            || fail "latest < baseline should exit 2"
    fi
}

test_rejects_prerelease() {
    # CC ships clean SemVer to npm `latest`. Prerelease tags would
    # signal a custom-built CLI or pipeline bug — fail loud.
    if "$SCRIPT" --baseline 2.1.150 --latest 2.1.150-beta.1 >/dev/null 2>&1; then
        fail "prerelease tag should exit 2"
    else
        [ "$?" -eq 2 ] && pass "prerelease tag exits 2 (out of scope)" \
            || fail "prerelease should exit 2"
    fi
}

# ----------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------

test_script_exists
test_same_version
test_below_threshold
test_at_threshold_no_alert
test_above_threshold
test_minor_jump_always_alerts
test_major_jump_always_alerts
test_v_prefix_baseline
test_v_prefix_latest
test_custom_threshold_above
test_custom_threshold_below
test_invalid_baseline
test_invalid_latest
test_missing_args
test_invalid_threshold_negative
test_invalid_threshold_non_integer
test_latest_older_than_baseline
test_rejects_prerelease

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All cc-drift-check.sh unit tests passed!"
