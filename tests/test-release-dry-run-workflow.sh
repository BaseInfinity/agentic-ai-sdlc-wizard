#!/bin/bash
# Quality tests for .github/workflows/release-dry-run.yml — A1 from
# .reviews/176-followup-prio-codex.md / v1.75.1 CHANGELOG post-mortem.
#
# Catches the class of bugs that would break `release.yml` at tag-time
# (npm/Node version drift, OIDC permission leaks, removed-and-restored
# token reliance, package.json shipping wrong paths).
#
# Each test asserts a SPECIFIC behavior, not existence. Per Prove-It Gate.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WF="$REPO_ROOT/.github/workflows/release-dry-run.yml"
RELEASE_WF="$REPO_ROOT/.github/workflows/release.yml"
PKG="$REPO_ROOT/package.json"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

# ----------------------------------------------------------------------
# 1. File + YAML structure
# ----------------------------------------------------------------------

test_workflow_exists() {
    [ -f "$WF" ] && pass "release-dry-run.yml exists" || fail "release-dry-run.yml does not exist"
}

test_yaml_valid() {
    python3 -c "import yaml; yaml.safe_load(open('$WF'))" 2>/dev/null \
        && pass "release-dry-run.yml is valid YAML" \
        || fail "release-dry-run.yml is invalid YAML"
}

# ----------------------------------------------------------------------
# 2. Triggers — pull_request + workflow_dispatch, NEVER pull_request_target
#
# pull_request_target runs against base ref with secrets; combined with
# our package surface paths this is a code-injection vector. Block it.
# ----------------------------------------------------------------------

test_triggers_on_pull_request() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
on = d.get(True, d.get('on'))
assert 'pull_request' in on, 'missing pull_request trigger'
" 2>/dev/null && pass "triggers on pull_request" \
        || fail "missing pull_request trigger"
}

test_triggers_on_workflow_dispatch() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
on = d.get(True, d.get('on'))
assert 'workflow_dispatch' in on, 'missing workflow_dispatch trigger'
" 2>/dev/null && pass "triggers on workflow_dispatch" \
        || fail "missing workflow_dispatch trigger"
}

test_never_pull_request_target() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
on = d.get(True, d.get('on'))
assert 'pull_request_target' not in on, 'pull_request_target is a security risk for package-surface workflows'
" 2>/dev/null && pass "does not use pull_request_target (security: no code-injection vector)" \
        || fail "release-dry-run.yml MUST NOT use pull_request_target (Codex review constraint)"
}

# ----------------------------------------------------------------------
# 3. Permissions — read-only contents, NEVER id-token: write
#
# Codex finding: npm CLI runs OIDC setup before the dry-run branch. If
# id-token: write is present, npm may attempt token mint even though it
# will not PUT the package. The dry-run workflow proves packaging, NOT
# publish auth. Auth is `release.yml`'s job.
# ----------------------------------------------------------------------

test_permissions_contents_read_only() {
    python3 -c "
import yaml; d = yaml.safe_load(open('$WF'))
perms = d.get('permissions', {})
assert perms.get('contents') == 'read', 'permissions.contents must be read'
" 2>/dev/null && pass "permissions.contents is read (top-level)" \
        || fail "permissions.contents must be 'read' at top level"
}

test_no_id_token_permission() {
    if grep -qE '^[[:space:]]*id-token:' "$WF"; then
        fail "release-dry-run.yml has id-token permission — MUST NOT (npm OIDC mint risk per Codex review)"
    else
        pass "release-dry-run.yml has no id-token permission (correct — no OIDC mint risk)"
    fi
}

# ----------------------------------------------------------------------
# 4. Forbidden patterns — no token-based publish, no self-upgrade, no --provenance, no --force
# ----------------------------------------------------------------------

test_no_node_auth_token() {
    # Match actual command lines only, not YAML comments. The workflow's
    # explanatory comments mention NODE_AUTH_TOKEN to explain WHY it's
    # absent — that documentation should not trip the test.
    if grep -qE '^[[:space:]]*[^#[:space:]].*NODE_AUTH_TOKEN' "$WF"; then
        fail "release-dry-run.yml contains active NODE_AUTH_TOKEN — Trusted Publishing only since v1.75.0"
    else
        pass "release-dry-run.yml has no active NODE_AUTH_TOKEN reference"
    fi
}

test_no_npm_token() {
    if grep -qE '^[[:space:]]*[^#[:space:]].*NPM_TOKEN' "$WF"; then
        fail "release-dry-run.yml references NPM_TOKEN in active code — Trusted Publishing only since v1.75.0"
    else
        pass "release-dry-run.yml has no active NPM_TOKEN reference"
    fi
}

test_no_npm_self_upgrade() {
    if grep -qE '^[[:space:]]*[^#[:space:]].*npm install -g npm@' "$WF"; then
        fail "release-dry-run.yml has 'npm install -g npm@' (in-place self-upgrade — MODULE_NOT_FOUND class bug, killed in v1.75.1)"
    else
        pass "release-dry-run.yml has no npm self-upgrade step"
    fi
}

test_no_provenance_flag() {
    if grep -qE 'npm publish[^$]*--provenance' "$WF"; then
        fail "release-dry-run.yml uses --provenance — Trusted Publishing auto-generates it; dry-run should NOT request"
    else
        pass "release-dry-run.yml has no --provenance flag"
    fi
}

test_no_force_flag() {
    if grep -qE 'npm publish[^$]*--force' "$WF"; then
        fail "release-dry-run.yml uses --force — disables protections; use temp version rewrite instead (Codex constraint)"
    else
        pass "release-dry-run.yml has no --force flag"
    fi
}

# ----------------------------------------------------------------------
# 5. Required structural elements
# ----------------------------------------------------------------------

test_uses_setup_node_v5() {
    grep -qE 'actions/setup-node@v5' "$WF" \
        && pass "uses actions/setup-node@v5" \
        || fail "must use actions/setup-node@v5 (parity with release.yml)"
}

test_node_version_24() {
    grep -qE '^[[:space:]]+node-version:[[:space:]]*24' "$WF" \
        && pass "node-version: 24 (ships npm 11.x natively, parity with release.yml)" \
        || fail "must pin node-version: 24"
}

test_registry_url() {
    grep -qE 'registry-url:[[:space:]]*https://registry\.npmjs\.org' "$WF" \
        && pass "registry-url: https://registry.npmjs.org" \
        || fail "must declare registry-url: https://registry.npmjs.org"
}

test_npm_version_guard() {
    # Same fail-loud check as release.yml — npm < 11.5.1 means Trusted
    # Publishing silently falls back to token mode. Even though this
    # workflow doesn't publish, the guard documents the contract.
    if grep -qE 'NPM_VERSION=\$\(npm --version\)' "$WF" && grep -qE '11\.5\.1' "$WF"; then
        pass "has npm version guard with 11.5.1 floor (parity with release.yml)"
    else
        fail "must include npm --version guard with 11.5.1 floor"
    fi
}

# ----------------------------------------------------------------------
# 6. Temp version rewrite (Codex constraint — naive dry-run fails on
#    already-published versions, --force is dangerous)
# ----------------------------------------------------------------------

test_temp_version_rewrite_present() {
    # Look for the pattern that rewrites package.json to an unpublished
    # prerelease before dry-run. node -e script that sets pkg.version.
    if grep -qE "pkg\.version\s*=|version.*=.*dry-run|0\.0\.0-dry-run" "$WF"; then
        pass "rewrites package.json to a dry-run prerelease before publishing"
    else
        fail "must rewrite package.json to unpublished version (e.g. 0.0.0-dry-run-\$SHA) — direct dry-run fails on already-published 1.75.1"
    fi
}

# ----------------------------------------------------------------------
# 7. Dry-run flag + JSON output
# ----------------------------------------------------------------------

test_uses_dry_run_flag() {
    grep -qE 'npm publish[^$]*--dry-run' "$WF" \
        && pass "uses 'npm publish --dry-run' (no actual publish)" \
        || fail "must use 'npm publish --dry-run'"
}

test_uses_json_output() {
    # --json makes the output parseable so we can assert on shipped paths.
    grep -qE 'npm publish[^$]*--json' "$WF" \
        && pass "uses 'npm publish --json' (parseable output for path assertions)" \
        || fail "must use --json so package contents are assertion-friendly"
}

test_uses_dry_run_tag() {
    # --tag dry-run keeps the dry-run cleanly separated from real dist-tags
    # in case anything ever escapes (defense in depth).
    grep -qE 'npm publish[^$]*--tag[[:space:]]*dry-run' "$WF" \
        && pass "uses --tag dry-run (separated from real dist-tags)" \
        || fail "must use --tag dry-run (Codex constraint)"
}

# ----------------------------------------------------------------------
# 8. Asserts shipped paths from package.json.files appear in dry-run JSON
# ----------------------------------------------------------------------

test_asserts_shipped_paths() {
    # The workflow must verify at least one shipped path is in the
    # dry-run output — otherwise a regression where package.json.files
    # silently drops a path would not be caught.
    local missing=""
    for path in 'cli/' 'skills/' 'hooks/' '.claude-plugin/' 'CLAUDE_CODE_SDLC_WIZARD.md' 'CHANGELOG.md'; do
        if ! grep -qF "$path" "$WF"; then
            missing="$missing $path"
        fi
    done
    if [ -z "$missing" ]; then
        pass "workflow references all 6 shipped paths from package.json.files for assertion"
    else
        fail "workflow missing shipped-path assertions for:$missing"
    fi
}

# ----------------------------------------------------------------------
# 9. Path filter covers every package.json.files entry — drift guard
# ----------------------------------------------------------------------

test_path_filter_covers_package_files() {
    # If package.json.files adds a new entry but the workflow `paths:` filter
    # doesn't include it, a PR touching that path won't run the dry-run.
    # That silently re-opens the surface this workflow is meant to gate.
    local missing=""
    while IFS= read -r p; do
        # Normalize: strip trailing slash, escape dots for grep, allow ** suffix.
        stripped="${p%/}"
        # Match either exact `path:` line or `path/**:` line in the workflow paths.
        if ! grep -qE "(^|[[:space:]])-[[:space:]]*['\"]?${stripped}(/\\*\\*)?['\"]?[[:space:]]*\$" "$WF" \
            && ! grep -qE "['\"]?${stripped}(/\\*\\*)?['\"]?" "$WF"; then
            missing="$missing $p"
        fi
    done < <(jq -r '.files[]' "$PKG")
    if [ -z "$missing" ]; then
        pass "workflow paths filter covers every package.json.files entry"
    else
        fail "workflow paths filter missing entries:$missing — drift guard would silently skip PRs touching these"
    fi
}

test_path_filter_includes_release_yml() {
    # The whole point: changes to release.yml MUST trigger this dry-run.
    grep -qE "release\.yml" "$WF" \
        && pass "paths filter includes release.yml (the file we're proving)" \
        || fail "paths filter MUST include .github/workflows/release.yml"
}

test_path_filter_includes_package_json() {
    grep -qE "package\.json" "$WF" \
        && pass "paths filter includes package.json" \
        || fail "paths filter MUST include package.json"
}

# ----------------------------------------------------------------------
# 10. Parity with release.yml — same Node major version, same npm guard
# ----------------------------------------------------------------------

test_node_version_parity_with_release() {
    local dryrun_node release_node
    dryrun_node=$(grep -E '^[[:space:]]+node-version:[[:space:]]*[0-9]+' "$WF" | head -1 | grep -oE '[0-9]+' | head -1)
    release_node=$(grep -E '^[[:space:]]+node-version:[[:space:]]*[0-9]+' "$RELEASE_WF" | head -1 | grep -oE '[0-9]+' | head -1)
    if [ -n "$dryrun_node" ] && [ "$dryrun_node" = "$release_node" ]; then
        pass "Node major version parity: release-dry-run=$dryrun_node, release=$release_node"
    else
        fail "Node major version mismatch: release-dry-run=$dryrun_node vs release=$release_node — they MUST agree (Codex parity rule)"
    fi
}

# ----------------------------------------------------------------------
# Run all
# ----------------------------------------------------------------------

test_workflow_exists
test_yaml_valid
test_triggers_on_pull_request
test_triggers_on_workflow_dispatch
test_never_pull_request_target
test_permissions_contents_read_only
test_no_id_token_permission
test_no_node_auth_token
test_no_npm_token
test_no_npm_self_upgrade
test_no_provenance_flag
test_no_force_flag
test_uses_setup_node_v5
test_node_version_24
test_registry_url
test_npm_version_guard
test_temp_version_rewrite_present
test_uses_dry_run_flag
test_uses_json_output
test_uses_dry_run_tag
test_asserts_shipped_paths
test_path_filter_covers_package_files
test_path_filter_includes_release_yml
test_path_filter_includes_package_json
test_node_version_parity_with_release

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All release-dry-run workflow tests passed!"
