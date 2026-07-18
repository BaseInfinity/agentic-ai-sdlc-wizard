#!/bin/bash
# test-release-drift.sh — ROADMAP #449: release-drift gate.
#
# Tests scripts/release-drift-check.sh, the pure-computation half of the
# "main must not silently outrun the published npm package" watcher.
# Mirrors tests/test-cc-version-drift.sh's pattern: the workflow fetches
# real data (git log, npm view); this script/test operates on synthetic
# counts/epochs so it needs no live git repo or network.
#
# bash 3-compatible (macOS default ships bash 3.x).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO_ROOT/scripts/release-drift-check.sh"

PASSED=0
FAILED=0

pass() { echo -e "\033[0;32mPASS\033[0m: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31mFAIL\033[0m: $1"; FAILED=$((FAILED + 1)); }

# ────────────────────────────────────────────
# Below-threshold: no alert
# ────────────────────────────────────────────

test_below_both_thresholds_no_alert() {
    local out
    out=$(bash "$CHECK" --commit-count 2 --oldest-commit-epoch "$(($(date +%s) - 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    if [ "$alert" = "false" ]; then
        pass "2 commits / 1 day old, thresholds 5/7 — no alert"
    else
        fail "expected no alert, got: $out"
    fi
}

test_at_count_threshold_no_alert() {
    # Strict greater-than, matching cc-drift-check.sh's convention:
    # exactly N does NOT alert.
    local out
    out=$(bash "$CHECK" --commit-count 5 --oldest-commit-epoch "$(($(date +%s) - 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    if [ "$alert" = "false" ]; then
        pass "commit_count exactly at threshold (5) — no alert (strict >)"
    else
        fail "expected no alert at exact threshold, got: $out"
    fi
}

# ────────────────────────────────────────────
# Above-threshold: alert
# ────────────────────────────────────────────

test_count_exceeded_alerts() {
    local out
    out=$(bash "$CHECK" --commit-count 6 --oldest-commit-epoch "$(($(date +%s) - 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert count_exceeded
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    count_exceeded=$(echo "$out" | grep -oE '"count_exceeded":(true|false)' | cut -d: -f2)
    if [ "$alert" = "true" ] && [ "$count_exceeded" = "true" ]; then
        pass "commit_count 6 > threshold 5 — alerts, count_exceeded true"
    else
        fail "expected alert+count_exceeded, got: $out"
    fi
}

test_age_exceeded_alerts() {
    local out
    out=$(bash "$CHECK" --commit-count 1 --oldest-commit-epoch "$(($(date +%s) - 8 * 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert age_exceeded
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    age_exceeded=$(echo "$out" | grep -oE '"age_exceeded":(true|false)' | cut -d: -f2)
    if [ "$alert" = "true" ] && [ "$age_exceeded" = "true" ]; then
        pass "oldest commit 8 days old > threshold 7 — alerts, age_exceeded true"
    else
        fail "expected alert+age_exceeded, got: $out"
    fi
}

test_at_age_threshold_no_alert() {
    local out
    out=$(bash "$CHECK" --commit-count 1 --oldest-commit-epoch "$(($(date +%s) - 7 * 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    if [ "$alert" = "false" ]; then
        pass "oldest commit exactly 7 days old, threshold 7 — no alert (strict >)"
    else
        fail "expected no alert at exact age threshold, got: $out"
    fi
}

test_zero_commits_no_alert() {
    # No consumer-path commits since last tag at all — nothing pending,
    # oldest-commit-epoch is meaningless; script must not crash or alert.
    local out
    out=$(bash "$CHECK" --commit-count 0 --oldest-commit-epoch 0 \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local alert
    alert=$(echo "$out" | grep -oE '"alert":(true|false)' | cut -d: -f2)
    if [ "$alert" = "false" ]; then
        pass "commit_count 0 — no alert regardless of oldest-commit-epoch"
    else
        fail "expected no alert with zero commits, got: $out"
    fi
}

test_both_exceeded_alerts_with_both_flags() {
    local out
    out=$(bash "$CHECK" --commit-count 9 --oldest-commit-epoch "$(($(date +%s) - 10 * 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local count_exceeded age_exceeded
    count_exceeded=$(echo "$out" | grep -oE '"count_exceeded":(true|false)' | cut -d: -f2)
    age_exceeded=$(echo "$out" | grep -oE '"age_exceeded":(true|false)' | cut -d: -f2)
    if [ "$count_exceeded" = "true" ] && [ "$age_exceeded" = "true" ]; then
        pass "both count and age exceeded — both flags true independently"
    else
        fail "expected both flags true, got: $out"
    fi
}

# ────────────────────────────────────────────
# Output shape
# ────────────────────────────────────────────

test_json_shape_has_all_fields() {
    local out
    out=$(bash "$CHECK" --commit-count 3 --oldest-commit-epoch "$(($(date +%s) - 86400))" \
        --now-epoch "$(date +%s)" --count-threshold 5 --age-threshold-days 7)
    local ok=true
    for field in commit_count oldest_age_days count_threshold age_threshold_days count_exceeded age_exceeded alert; do
        echo "$out" | grep -q "\"$field\"" || ok=false
    done
    if [ "$ok" = true ]; then
        pass "JSON output contains all 7 expected fields"
    else
        fail "JSON output missing a field: $out"
    fi
}

test_default_thresholds_applied_when_omitted() {
    # Defaults per ROADMAP #449 scope: count=5, age=7 days.
    local out
    out=$(bash "$CHECK" --commit-count 6 --oldest-commit-epoch "$(($(date +%s) - 86400))" \
        --now-epoch "$(date +%s)")
    local threshold
    threshold=$(echo "$out" | grep -oE '"count_threshold":[0-9]+' | cut -d: -f2)
    if [ "$threshold" = "5" ]; then
        pass "count-threshold defaults to 5 when omitted"
    else
        fail "expected default count_threshold=5, got: $out"
    fi
}

# ────────────────────────────────────────────
# Invalid input — fail loud (per #350's "no silent failure" philosophy,
# reused here per #449's own root-cause: nothing must silently swallow
# a broken check).
# ────────────────────────────────────────────

test_missing_required_arg_exits_nonzero() {
    if bash "$CHECK" --commit-count 3 --now-epoch "$(date +%s)" > /dev/null 2>&1; then
        fail "missing --oldest-commit-epoch should exit non-zero, but succeeded"
    else
        pass "missing --oldest-commit-epoch exits non-zero"
    fi
}

test_non_numeric_commit_count_exits_nonzero() {
    if bash "$CHECK" --commit-count "abc" --oldest-commit-epoch 0 --now-epoch "$(date +%s)" > /dev/null 2>&1; then
        fail "non-numeric --commit-count should exit non-zero, but succeeded"
    else
        pass "non-numeric --commit-count exits non-zero"
    fi
}

test_negative_threshold_exits_nonzero() {
    if bash "$CHECK" --commit-count 3 --oldest-commit-epoch 0 --now-epoch "$(date +%s)" \
        --count-threshold "-1" > /dev/null 2>&1; then
        fail "negative --count-threshold should exit non-zero, but succeeded"
    else
        pass "negative --count-threshold exits non-zero"
    fi
}

test_now_before_oldest_exits_nonzero() {
    # now-epoch < oldest-commit-epoch means the caller passed bad data
    # (a commit from the future) — fail loud rather than emit a
    # misleading negative age.
    if bash "$CHECK" --commit-count 3 --oldest-commit-epoch "$(date +%s)" \
        --now-epoch "$(($(date +%s) - 86400))" > /dev/null 2>&1; then
        fail "now-epoch before oldest-commit-epoch should exit non-zero, but succeeded"
    else
        pass "now-epoch before oldest-commit-epoch exits non-zero"
    fi
}

# ────────────────────────────────────────────
# Workflow file existence + design-constraint guards (mirrors
# test-cc-version-drift.sh's approach of asserting on the YAML itself,
# not just the script — these catch someone editing the workflow
# in ways that violate #449's stated scope without touching the script).
# ────────────────────────────────────────────

test_workflow_file_exists() {
    if [ -f "$REPO_ROOT/.github/workflows/release-drift.yml" ]; then
        pass "release-drift.yml workflow file exists"
    else
        fail "release-drift.yml workflow file missing"
    fi
}

test_workflow_is_standalone_not_extending_weekly_update() {
    # Same design constraint as cc-version-drift.yml (#350.1), and the
    # same check tests/test-cc-version-drift.sh already runs: the
    # standalone-ness requirement is that weekly-update.yml itself
    # doesn't grow release-drift logic (deliberate #212/#231
    # guardrails — its cron is commented out, no issues: write). It's
    # fine for release-drift.yml's own header prose to mention
    # weekly-update.yml as rationale, same as cc-version-drift.yml's
    # header does.
    local weekly="$REPO_ROOT/.github/workflows/weekly-update.yml"
    if [ -f "$weekly" ] && grep -qi "release-drift\|release_drift" "$weekly"; then
        fail "weekly-update.yml mentions release-drift logic — must stay standalone (#212/#231 guardrails)"
    else
        pass "release-drift detection lives in standalone workflow, not weekly-update.yml"
    fi
}

test_workflow_checks_consumer_distributed_paths() {
    # Anchor on the CONSUMER_PATHS env line specifically — a naive
    # whole-file grep would still find these words in the header
    # prose even if someone drops one from the actual operative
    # env var (caught live via mutation test: removing cowork/ from
    # CONSUMER_PATHS still passed a whole-file grep, since the header
    # comment restates the same path list).
    local line
    line=$(grep "^  CONSUMER_PATHS:" "$REPO_ROOT/.github/workflows/release-drift.yml" 2>/dev/null)
    local ok=true
    for path in "skills/" "hooks/" "cli/" "CLAUDE_CODE_SDLC_WIZARD.md" "cowork/"; do
        echo "$line" | grep -qF -- "$path" || ok=false
    done
    if [ -n "$line" ] && [ "$ok" = true ]; then
        pass "release-drift.yml's CONSUMER_PATHS env includes all 5 consumer-distributed paths"
    else
        fail "release-drift.yml's CONSUMER_PATHS env is missing a consumer-distributed path: $line"
    fi
}

test_workflow_uses_release_drift_check_script() {
    # Anchor on the actual invocation (a `./scripts/...sh` call), not
    # any mention of the filename — a comment referencing the script
    # (e.g. the permissions block's rationale) would otherwise let a
    # mutated/renamed invocation still pass. Caught live via mutation
    # test on the CONSUMER_PATHS check above; applying the same
    # anchoring discipline here preemptively.
    if grep -qE '^\s*\./scripts/release-drift-check\.sh\s*\\?$' "$REPO_ROOT/.github/workflows/release-drift.yml" 2>/dev/null; then
        pass "release-drift.yml actually invokes ./scripts/release-drift-check.sh"
    else
        fail "release-drift.yml does not invoke ./scripts/release-drift-check.sh"
    fi
}

test_workflow_has_no_failure_suppression() {
    # #350's design constraint 5, reused verbatim for #449: no || true /
    # || echo silently swallowing a broken check. Anchor on
    # uncommented lines only — the header comment names these patterns
    # to explain why they're absent, same convention as
    # tests/test-cc-version-drift.sh's test_no_silent_failures.
    local hits
    hits=$(grep -E '^[[:space:]]*[^#[:space:]].*\|\|[[:space:]]*(true|echo)' \
        "$REPO_ROOT/.github/workflows/release-drift.yml" 2>/dev/null || true)
    if [ -z "$hits" ]; then
        pass "release-drift.yml has no active failure-suppression pattern (comments allowed)"
    else
        fail "release-drift.yml contains failure-suppressing || true or || echo: $hits"
    fi
}

test_workflow_cron_staggered_from_siblings() {
    # weekly-update.yml: 09:00 UTC Mon (disabled); weekly-api-update.yml:
    # 10:00 UTC Mon; cc-version-drift.yml: 09:30 UTC Mon. Must not
    # collide with any of those three.
    local cron_line
    cron_line=$(grep -oE "cron: '[0-9]+ [0-9]+ \* \* [0-9]+'" "$REPO_ROOT/.github/workflows/release-drift.yml" 2>/dev/null | head -1)
    if [ -n "$cron_line" ] && ! echo "$cron_line" | grep -qE "'30 9 \* \* 1'|'0 9 \* \* 1'|'0 10 \* \* 1'"; then
        pass "release-drift.yml cron is staggered from sibling workflows"
    else
        fail "release-drift.yml cron missing or collides with a sibling workflow: $cron_line"
    fi
}

# ────────────────────────────────────────────
# #449 round-1 Codex catch: counting commits since the last git tag
# only proves main outran the TAG, not npm — a tag pushed whose
# release.yml publish step then failed silently would report "no
# drift" without an explicit npm-vs-tag check.
# ────────────────────────────────────────────

test_workflow_verifies_npm_publish_matches_tag() {
    # Codex round-3 catch: without asserting the TAG_VERSION="${LAST_TAG#v}"
    # normalization specifically, mutating it to drop the #v strip
    # (TAG_VERSION="${LAST_TAG}") still passed 21/21 — every vX.Y.Z tag
    # would then falsely mismatch npm's bare X.Y.Z version and spam a
    # tracking issue on every single run, the opposite failure mode
    # from what this check exists to catch.
    local wf="$REPO_ROOT/.github/workflows/release-drift.yml"
    local ok=true
    grep -qE '^\s*NPM_VERSION=\$\(npm view agentic-sdlc-wizard version\)' "$wf" || ok=false
    grep -qF 'TAG_VERSION="${LAST_TAG#v}"' "$wf" || ok=false
    grep -qE '^\s*if \[ "\$NPM_VERSION" != "\$TAG_VERSION" \]' "$wf" || ok=false
    if [ "$ok" = true ]; then
        pass "release-drift.yml verifies npm's published version against the v-stripped last tag"
    else
        fail "release-drift.yml is missing the npm-vs-tag publish-mismatch check or its v-prefix normalization"
    fi
}

test_workflow_issue_step_triggers_on_publish_mismatch_too() {
    # The issue-opening step's `if:` must fire on EITHER commit drift
    # OR a publish mismatch — a mismatch with 0 stranded commits
    # (publish failed right after tagging, before new commits landed)
    # would otherwise never surface. Codex round-2 catch: checking only
    # for the SUBSTRING "npmcheck.outputs.mismatch" passed even when
    # the connecting operator was mutated from || (OR) to && (AND) —
    # AND would only fire when BOTH conditions are true simultaneously,
    # exactly missing the edge case this check exists for. Anchor on
    # the literal `alert == 'true' || steps.npmcheck.outputs.mismatch`
    # sequence so the operator itself is part of the match.
    local wf="$REPO_ROOT/.github/workflows/release-drift.yml"
    local if_line
    if_line=$(grep -A1 "name: Open or update tracking issue" "$wf" | grep "^\s*if:")
    if echo "$if_line" | grep -qF "alert == 'true' || steps.npmcheck.outputs.mismatch == 'true'"; then
        pass "issue-opening step's if: condition ORs commit-drift with the publish-mismatch check"
    else
        fail "issue-opening step's if: condition doesn't OR in the publish-mismatch check: $if_line"
    fi
}

# ────────────────────────────────────────────
# Run all tests
# ────────────────────────────────────────────

test_below_both_thresholds_no_alert
test_at_count_threshold_no_alert
test_count_exceeded_alerts
test_age_exceeded_alerts
test_at_age_threshold_no_alert
test_zero_commits_no_alert
test_both_exceeded_alerts_with_both_flags
test_json_shape_has_all_fields
test_default_thresholds_applied_when_omitted
test_missing_required_arg_exits_nonzero
test_non_numeric_commit_count_exits_nonzero
test_negative_threshold_exits_nonzero
test_now_before_oldest_exits_nonzero
test_workflow_file_exists
test_workflow_is_standalone_not_extending_weekly_update
test_workflow_checks_consumer_distributed_paths
test_workflow_uses_release_drift_check_script
test_workflow_has_no_failure_suppression
test_workflow_cron_staggered_from_siblings
test_workflow_verifies_npm_publish_matches_tag
test_workflow_issue_step_triggers_on_publish_mismatch_too

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All release-drift gate tests passed!"
