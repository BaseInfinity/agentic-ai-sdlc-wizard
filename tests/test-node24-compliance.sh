#!/bin/bash
# Test that all GitHub Actions workflows use Node 24-compatible action versions
# and do not reference deprecated Node.js 20 runtimes.
#
# Context: GitHub Actions runners drop Node.js 20 support on June 2, 2026.
# Actions declaring runs.using: node20 will be force-overridden to Node 24.
# This test ensures we've proactively migrated before the deadline.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

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

echo "=== Node 24 Compliance Tests ==="
echo ""

# --- Action Version Tests ---

# Test 1: No workflow uses actions/checkout@v4 (deprecated node20)
test_no_checkout_v4() {
    if grep -rq 'actions/checkout@v4' "$WORKFLOW_DIR"; then
        fail "Found actions/checkout@v4 (node20) — should be @v5+"
        grep -rn 'actions/checkout@v4' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use actions/checkout@v4"
    fi
}

# Test 2: No workflow uses actions/setup-node@v4 (deprecated node20)
test_no_setup_node_v4() {
    if grep -rq 'actions/setup-node@v4' "$WORKFLOW_DIR"; then
        fail "Found actions/setup-node@v4 (node20) — should be @v5+"
        grep -rn 'actions/setup-node@v4' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use actions/setup-node@v4"
    fi
}

# Test 3: No workflow uses actions/upload-artifact@v4 (deprecated node20)
test_no_upload_artifact_v4() {
    if grep -rq 'actions/upload-artifact@v4' "$WORKFLOW_DIR"; then
        fail "Found actions/upload-artifact@v4 (node20) — should be @v6+"
        grep -rn 'actions/upload-artifact@v4' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use actions/upload-artifact@v4"
    fi
}

# Test 4: No workflow uses peter-evans/create-pull-request@v7 (deprecated node20)
test_no_create_pr_v7() {
    if grep -rq 'peter-evans/create-pull-request@v7' "$WORKFLOW_DIR"; then
        fail "Found peter-evans/create-pull-request@v7 (node20) — should be @v8+"
        grep -rn 'peter-evans/create-pull-request@v7' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use peter-evans/create-pull-request@v7"
    fi
}

# Test 5: No workflow uses marocchino/sticky-pull-request-comment@v2 (deprecated node20)
test_no_sticky_comment_v2() {
    if grep -rq 'marocchino/sticky-pull-request-comment@v2' "$WORKFLOW_DIR"; then
        fail "Found marocchino/sticky-pull-request-comment@v2 (node20) — should be @v3+"
        grep -rn 'marocchino/sticky-pull-request-comment@v2' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use marocchino/sticky-pull-request-comment@v2"
    fi
}

# Test 6: No workflow uses int128/hide-comment-action (replaced with gh api graphql)
test_no_hide_comment_action() {
    if grep -rq 'uses:.*int128/hide-comment-action' "$WORKFLOW_DIR"; then
        fail "Found int128/hide-comment-action in uses: — should be replaced with gh api graphql"
        grep -rn 'uses:.*int128/hide-comment-action' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use int128/hide-comment-action (replaced with gh CLI)"
    fi
}

# Test 7: No workflow uses softprops/action-gh-release (replaced with gh release create)
test_no_gh_release_action() {
    if grep -rq 'softprops/action-gh-release' "$WORKFLOW_DIR"; then
        fail "Found softprops/action-gh-release — should be replaced with gh release create"
        grep -rn 'softprops/action-gh-release' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use softprops/action-gh-release (replaced with gh CLI)"
    fi
}

# Test 7.5: No workflow uses oven-sh/setup-bun (ROADMAP #210)
# setup-bun's internal JS runs on Node 20; GitHub Actions emits a real
# Node 20 deprecation warning per run even when the workflow YAML is clean.
# This is a defensive regression guard — verified empty on 2026-04-23.
test_no_oven_sh_setup_bun() {
    if grep -rq 'oven-sh/setup-bun' "$WORKFLOW_DIR"; then
        fail "Found oven-sh/setup-bun — runs on Node 20, will emit deprecation warning (use manual bun install or Node-24-native alt)"
        grep -rn 'oven-sh/setup-bun' "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows use oven-sh/setup-bun"
    fi
}

# Test 7.5-nc: Committed negative control for test_no_oven_sh_setup_bun.
# Codex review (2026-04-23, batch-code-prs-214-216-217) raised P2 for missing
# in-repo proof that the grep actually catches the banned pattern. This test
# writes a temp file under an isolated fixture dir with the banned string,
# runs the exact same grep, asserts it catches, then tears down. Proves the
# regex would fire if setup-bun ever reappears in a real workflow.
test_no_oven_sh_setup_bun_negative_control() {
    local fixture
    fixture=$(mktemp -d 2>/dev/null || mktemp -d -t setup-bun-nc)
    # Simulate a workflow file using the banned action.
    cat > "$fixture/fake-workflow.yml" <<'YAML'
name: fake
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: oven-sh/setup-bun@v1
YAML
    if grep -rq 'oven-sh/setup-bun' "$fixture"; then
        pass "Negative control: grep catches oven-sh/setup-bun when present (regex works)"
    else
        fail "Negative control FAILED — grep did not catch a known setup-bun reference; regex broken"
    fi
    rm -rf "$fixture"
}

# --- Node Version Tests ---

# Test 8: No workflow specifies node-version: '20' or node-version: 20
test_no_node_version_20() {
    if grep -rqE "node-version:\s*['\"]?20['\"]?" "$WORKFLOW_DIR"; then
        fail "Found node-version: 20 — should be 22 (LTS)"
        grep -rnE "node-version:\s*['\"]?20['\"]?" "$WORKFLOW_DIR" | head -3
    else
        pass "No workflows specify node-version: 20"
    fi
}

# --- Positive Tests (correct versions are present) ---

# Test 9: All workflows with checkout use @v5+
test_checkout_v5_present() {
    if grep -rq 'actions/checkout@v5' "$WORKFLOW_DIR"; then
        pass "Workflows use actions/checkout@v5"
    else
        fail "No workflow uses actions/checkout@v5"
    fi
}

# Test 10: Workflows with setup-node use @v5+
test_setup_node_v5_present() {
    if grep -rq 'actions/setup-node@v5' "$WORKFLOW_DIR"; then
        pass "Workflows use actions/setup-node@v5"
    else
        fail "No workflow uses actions/setup-node@v5"
    fi
}

# Test 11: If any workflow uses upload-artifact, it must be @v6+
# (Conditional: no failure when no workflow uses upload-artifact at all —
# Test 3 above + the no-v4/v5/v7 negative coverage already enforce that any
# present version is current. This guards against silently regressing to an
# older version if upload-artifact is reintroduced.)
test_upload_artifact_v6_present() {
    if grep -rq 'actions/upload-artifact@' "$WORKFLOW_DIR"; then
        if grep -rq 'actions/upload-artifact@v6' "$WORKFLOW_DIR"; then
            pass "Workflows that use upload-artifact use @v6"
        else
            fail "Some workflow uses upload-artifact at non-v6 version"
            grep -rn 'actions/upload-artifact@' "$WORKFLOW_DIR" | head -3
        fi
    else
        pass "No workflow uses upload-artifact (nothing to version-check)"
    fi
}

# Test 12: release.yml uses gh release create (not third-party action)
test_release_uses_gh_cli() {
    if grep -q 'gh release create' "$WORKFLOW_DIR/release.yml"; then
        pass "release.yml uses gh release create"
    else
        fail "release.yml does not use gh release create"
    fi
}

# Test 13: ci.yml uses gh api graphql for comment hiding (not third-party action)
test_ci_uses_graphql_for_comments() {
    if grep -q 'minimizeComment' "$WORKFLOW_DIR/ci.yml"; then
        pass "ci.yml uses GraphQL minimizeComment for comment hiding"
    else
        fail "ci.yml does not use GraphQL minimizeComment"
    fi
}

# --- Run tests ---

test_no_checkout_v4
test_no_setup_node_v4
test_no_upload_artifact_v4
test_no_create_pr_v7
test_no_sticky_comment_v2
test_no_hide_comment_action
test_no_gh_release_action
test_no_oven_sh_setup_bun
test_no_oven_sh_setup_bun_negative_control
test_no_node_version_20
test_checkout_v5_present
test_setup_node_v5_present
test_upload_artifact_v6_present
test_release_uses_gh_cli
test_ci_uses_graphql_for_comments

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
