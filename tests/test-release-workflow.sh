#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/release.yml"

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

# --- Tests ---

test_workflow_exists() {
    if [ -f "$WORKFLOW" ]; then
        pass "release.yml exists"
    else
        fail "release.yml does not exist"
    fi
}

test_yaml_valid() {
    if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        pass "release.yml is valid YAML"
    else
        fail "release.yml is invalid YAML"
    fi
}

test_trigger_on_tag_push() {
    if grep -A2 'on:' "$WORKFLOW" | grep -q "tags:" && grep -q "'v\*'" "$WORKFLOW"; then
        pass "release.yml triggers on tag push (v*)"
    else
        fail "release.yml does not trigger on tag push (v*)"
    fi
}

test_has_contents_write_permission() {
    if grep -q 'contents: write' "$WORKFLOW"; then
        pass "release.yml has contents: write permission"
    else
        fail "release.yml missing contents: write permission"
    fi
}

test_uses_checkout_v5() {
    if grep -q 'actions/checkout@v5' "$WORKFLOW"; then
        pass "release.yml uses actions/checkout@v5"
    else
        fail "release.yml does not use actions/checkout@v5"
    fi
}

test_uses_setup_node_with_registry() {
    if grep -q 'actions/setup-node@v5' "$WORKFLOW" && grep -q 'registry-url' "$WORKFLOW"; then
        pass "release.yml uses setup-node@v5 with registry-url"
    else
        fail "release.yml missing setup-node@v5 with registry-url"
    fi
}

test_uses_gh_release_create() {
    if grep -q 'gh release create' "$WORKFLOW"; then
        pass "release.yml uses gh release create"
    else
        fail "release.yml does not use gh release create"
    fi
}

test_uses_trusted_publishing_not_token() {
    # ROADMAP: v1.75.0 migrated from long-lived NPM_TOKEN to npm Trusted
    # Publishing (OIDC). NODE_AUTH_TOKEN must NOT appear in the publish env
    # — the presence of any auth-token env variable means we slipped back
    # to token-based publishing.
    if grep -qE '^[[:space:]]*NODE_AUTH_TOKEN:' "$WORKFLOW"; then
        fail "release.yml still uses NODE_AUTH_TOKEN — must use npm Trusted Publishing (OIDC) instead. ROADMAP: drop NPM_TOKEN dependency."
    elif ! grep -q 'id-token: write' "$WORKFLOW"; then
        fail "release.yml is missing 'id-token: write' permission required for npm Trusted Publishing OIDC"
    else
        pass "release.yml uses npm Trusted Publishing (OIDC) — no long-lived token"
    fi
}

test_upgrades_npm_for_trusted_publishing() {
    # npm Trusted Publishing requires npm CLI 11.5.1+. Node 22 ships with
    # 10.9.x by default, so the workflow must explicitly bump the npm CLI
    # before the publish step. Without this, the publish silently falls
    # back to token mode and fails with the same E404 we saw on v1.74.0.
    if grep -qE 'npm install -g npm@(latest|1[1-9]\.)' "$WORKFLOW"; then
        pass "release.yml upgrades npm CLI to ≥11.5.1 (required for Trusted Publishing)"
    else
        fail "release.yml must run 'npm install -g npm@latest' (or pin >=11.5.1) before publish — Node 22 ships npm 10.9.x which lacks Trusted Publishing support"
    fi
}

test_generates_release_notes() {
    if grep -q '\-\-generate-notes' "$WORKFLOW"; then
        pass "release.yml generates release notes automatically"
    else
        fail "release.yml does not generate release notes"
    fi
}

test_npm_publish_step() {
    if grep -q 'npm publish' "$WORKFLOW"; then
        pass "release.yml has npm publish step"
    else
        fail "release.yml missing npm publish step"
    fi
}

test_verifies_tag_on_main() {
    if grep -q 'merge-base --is-ancestor' "$WORKFLOW"; then
        pass "release.yml verifies tag is on main branch"
    else
        fail "release.yml does not verify tag is on main branch"
    fi
}

test_npm_provenance() {
    # ROADMAP: v1.75.0 migrated to npm Trusted Publishing. Trusted publish
    # auto-generates provenance — the explicit --provenance flag is no
    # longer required (and is incompatible with the token-less mode in
    # some npm CLI versions). Test is now a no-op assertion that provenance
    # remains in force via the trusted-publish path (provenance is implicit
    # when id-token: write is set + publishing via OIDC).
    if grep -q 'id-token: write' "$WORKFLOW"; then
        pass "release.yml provides provenance via Trusted Publishing (id-token: write set)"
    else
        fail "release.yml missing id-token: write permission — required for OIDC + provenance"
    fi
}

test_has_id_token_permission() {
    if grep -q 'id-token: write' "$WORKFLOW"; then
        pass "release.yml has id-token: write permission (required for Trusted Publishing OIDC)"
    else
        fail "release.yml missing id-token: write permission"
    fi
}

test_verifies_version_tag_match() {
    if grep -q 'package.json' "$WORKFLOW" && grep -q 'GITHUB_REF' "$WORKFLOW"; then
        pass "release.yml verifies tag matches package.json version"
    else
        fail "release.yml does not verify tag-version consistency"
    fi
}

# --- Run tests ---

test_workflow_exists
test_yaml_valid
test_trigger_on_tag_push
test_has_contents_write_permission
test_uses_checkout_v5
test_uses_setup_node_with_registry
test_uses_gh_release_create
test_uses_trusted_publishing_not_token
test_upgrades_npm_for_trusted_publishing
test_generates_release_notes
test_npm_publish_step
test_verifies_tag_on_main
test_npm_provenance
test_has_id_token_permission
test_verifies_version_tag_match

# --- Results ---

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
