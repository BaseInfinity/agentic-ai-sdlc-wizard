#!/bin/bash
# Quality test: /claude-update-wizard must detect stale local CLI before in-session file updates.
#
# ROADMAP #232: previously /claude-update-wizard fetched the latest wizard files from GitHub raw
# and patched in-session, but the user's local npx-cached CLI (the thing that runs `check`,
# `init`, etc.) could remain on an old version forever. Symptom: user sees "you're up to
# date" on wizard files, but their `npx agentic-sdlc-wizard ...` is still 1.30.0 missing
# the latest drift heuristics. v1.40.0 adds a dedicated CLI version step that fetches the
# npm registry latest, compares to whatever is actually installed locally, and offers a
# one-shot upgrade BEFORE running drift detection or per-file updates.

set -e

SKILL="${SKILL:-skills/update/SKILL.md}"
CHANGELOG="${CHANGELOG:-CHANGELOG.md}"
PASSED=0
FAILED=0

pass() { echo "PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$SKILL" ]; then
    echo "FAIL: $SKILL not found"
    exit 1
fi

# Extract the CLI Version step BLOCK first — every body assertion below must scope to
# this block, not the whole skill, to prevent CHANGELOG-sample false-greens (AUDIT-001).
cli_step_block=$(awk '
  /^### Step [0-9]+(\.[0-9]+)?: .*CLI Version/ { flag=1; next }
  /^### Step [0-9]/ && flag { flag=0 }
  flag { print }
' "$SKILL")

# ---------------------------------------------------------------------------
# Test 1: A dedicated CLI version step exists.
# ---------------------------------------------------------------------------
if grep -qE "^### Step [0-9]+(\.[0-9]+)?: .*CLI Version" "$SKILL"; then
    pass "Skill has a CLI Version check step"
else
    fail "Skill missing dedicated CLI version check step"
fi

# ---------------------------------------------------------------------------
# Test 2: Step body references the npm registry latest endpoint.
# Scoped to the Step 1.5 block (AUDIT-001 fix).
# ---------------------------------------------------------------------------
if [ -n "$cli_step_block" ] && echo "$cli_step_block" | grep -qE "registry\.npmjs\.org/agentic-sdlc-wizard"; then
    pass "CLI step body references npm registry latest endpoint"
else
    fail "CLI step body must fetch registry version from registry.npmjs.org/agentic-sdlc-wizard"
fi

# ---------------------------------------------------------------------------
# Test 3: Step body describes BOTH detection paths (npm ls + npx cache).
# Scoped to the Step 1.5 block.
# ---------------------------------------------------------------------------
has_npm_ls=$(echo "$cli_step_block" | grep -cE "npm ls.*agentic-sdlc-wizard" || true)
has_npx_cache=$(echo "$cli_step_block" | grep -cE "_npx" || true)
if [ "$has_npm_ls" -gt 0 ] && [ "$has_npx_cache" -gt 0 ]; then
    pass "CLI step body describes both detection paths (npm ls + npx cache)"
else
    fail "CLI step body must describe both 'npm ls' (global install) AND '_npx' cache inspection (npx users)"
fi

# ---------------------------------------------------------------------------
# Test 4: Step body recommends the one-shot upgrade command.
# Scoped to the Step 1.5 block (AUDIT-001 fix).
# ---------------------------------------------------------------------------
if echo "$cli_step_block" | grep -qE "npx.*-y.*agentic-sdlc-wizard@latest"; then
    pass "CLI step body recommends one-shot upgrade with npx -y agentic-sdlc-wizard@latest"
else
    fail "CLI step body must recommend 'npx -y agentic-sdlc-wizard@latest' as part of the upgrade path"
fi

# ---------------------------------------------------------------------------
# Test 5: CLI version check runs BEFORE the per-file update plan, by ACTUAL
# LINE NUMBER (AUDIT-002 fix — numeric step parsing alone is insufficient).
# Verify Step 1.5 line number sits strictly between Step 1 and Step 2 lines.
# ---------------------------------------------------------------------------
cli_line=$(grep -nE "^### Step [0-9]+(\.[0-9]+)?: .*CLI Version" "$SKILL" | head -1 | cut -d: -f1)
step1_line=$(grep -nE "^### Step 1: " "$SKILL" | head -1 | cut -d: -f1)
step2_line=$(grep -nE "^### Step 2: " "$SKILL" | head -1 | cut -d: -f1)
step6_line=$(grep -nE "^### Step 6: " "$SKILL" | head -1 | cut -d: -f1)
if [ -n "$cli_line" ] && [ -n "$step1_line" ] && [ -n "$step2_line" ] && [ -n "$step6_line" ] \
    && [ "$cli_line" -gt "$step1_line" ] \
    && [ "$cli_line" -lt "$step2_line" ] \
    && [ "$cli_line" -lt "$step6_line" ]; then
    pass "CLI step at line $cli_line sits between Step 1 (line $step1_line) and Step 2 (line $step2_line) and well before Step 6 (line $step6_line)"
else
    fail "CLI step ordering wrong by line number — must be between Step 1 and Step 2 (and well before Step 6 / per-file plan)"
fi

# ---------------------------------------------------------------------------
# Test 6: Step honors check-only — must NOT execute the upgrade automatically;
# must just report the gap when check-only is set.
# ---------------------------------------------------------------------------
if echo "$cli_step_block" | grep -qE "check-only"; then
    pass "CLI step honors check-only flag (no auto-upgrade)"
else
    fail "CLI step must explicitly honor check-only (report-only, no automatic init --force)"
fi

# ---------------------------------------------------------------------------
# Test 7: Step warns/notes when the CLI cannot be detected (offline, custom install).
# Otherwise a missing detection silently turns into "you're current" — false negative.
# ---------------------------------------------------------------------------
if echo "$cli_step_block" | grep -qiE "cannot detect|detection fail|unknown|skip|fallback"; then
    pass "CLI step has graceful fallback for undetectable installs"
else
    fail "CLI step must describe what to do when local CLI version cannot be detected (graceful fallback)"
fi

# ---------------------------------------------------------------------------
# Test 8: CHANGELOG [1.40.0] entry documents the CLI version detection feature.
# ---------------------------------------------------------------------------
if grep -qE "^## \[1\.40\.0\]" "$CHANGELOG"; then
    cl_entry=$(awk '/^## \[1\.40\.0\]/,/^## \[1\.39\.1\]/' "$CHANGELOG" | sed '$d')
    if echo "$cl_entry" | grep -qiE "CLI version|stale CLI|npx cache|registry\.npmjs"; then
        pass "CHANGELOG [1.40.0] documents CLI version detection"
    else
        fail "CHANGELOG [1.40.0] must mention the CLI version detection (CLI version / npx cache / registry)"
    fi
else
    fail "CHANGELOG must have a [1.40.0] entry"
fi

# Negative control: removing the CLI step from a temp copy must fail tests 1, 2, 3, 4, 5, 6, 7.
# Mutation test runs in cross-model review.

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
