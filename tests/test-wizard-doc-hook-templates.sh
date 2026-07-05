#!/bin/bash
# Guards against wizard-doc tutorial hooks drifting from the real hooks/*.sh
# they're modeled on. Post-mortem (SDLC.md Lessons Learned, 2026-07-04):
# round 8 of the v1.84.0 Codex review found the Step 5 TDD hook tutorial
# still showed the pre-#436 advisory-only version (no exit 2) after the
# real hook had already been fixed to block. The fix for that itself
# reintroduced a second, independently-known bug (absolute-only /src/
# path pattern), caught again in round 9. Mechanical checks here replace
# needing a human/reviewer to re-read prose each release.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"

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

# Extracts the first ```bash ... ``` fence following the given
# "Create `.claude/hooks/X.sh`" marker line.
extract_tutorial_block() {
    local hook="$1"
    awk -v marker="Create \`.claude/hooks/$hook\`" '
        found_marker && /^```bash/ { in_block=1; next }
        in_block && /^```/ { exit }
        in_block { print }
        index($0, marker) { found_marker=1 }
    ' "$DOC"
}

echo "=== Wizard Doc Hook Template Drift Tests ==="
echo ""

if [ ! -f "$DOC" ]; then
    fail "CLAUDE_CODE_SDLC_WIZARD.md not found"
    echo ""
    echo "=== Results: $PASSED passed, $FAILED failed ==="
    exit 1
fi

HOOK_NAMES=$(grep -oE 'Create `\.claude/hooks/[a-zA-Z0-9_-]+\.sh`' "$DOC" \
    | sed -E 's#Create `\.claude/hooks/([a-zA-Z0-9_-]+\.sh)`#\1#' | sort -u)

if [ -z "$HOOK_NAMES" ]; then
    fail "No 'Create .claude/hooks/X.sh' tutorial markers found — extraction pattern may be broken"
fi

for hook in $HOOK_NAMES; do
    real_hook="$REPO_ROOT/hooks/$hook"

    if [ ! -f "$real_hook" ]; then
        fail "Wizard doc templates '$hook' but hooks/$hook does not exist in this repo"
        continue
    fi

    tutorial_block=$(extract_tutorial_block "$hook")

    if [ -z "$tutorial_block" ]; then
        fail "Could not extract tutorial bash code block for $hook"
        continue
    fi

    if grep -q 'exit 2' "$real_hook"; then
        if echo "$tutorial_block" | grep -q 'exit 2'; then
            pass "$hook: real hook blocks via exit 2 and the tutorial block matches"
        else
            fail "$hook: real hooks/$hook blocks via exit 2, but the wizard doc's tutorial template never exits 2 — a reader following the doc builds a non-blocking, advisory-only hook"
        fi
    else
        pass "$hook: real hook does not block — no exit 2 required in tutorial"
    fi
done

# Targeted regression test: the TDD hook's src/ pattern must match both the
# absolute (*/src/*) and cwd-relative (src/*) forms. A leading-slash-only
# pattern silently no-ops on relative file_paths like "src/app.js" — found
# by Codex in #436 round 1, fixed in the real hook, independently
# reintroduced into this doc's tutorial copy, and caught again in the
# v1.84.0 review (round 9). Locking this shut as its own case, not just
# folded into the generic exit-2 check above, since it's the specific bug
# that recurred.
test_tdd_hook_tutorial_matches_relative_paths() {
    local hook="tdd-pretool-check.sh"
    local tutorial_block
    tutorial_block=$(extract_tutorial_block "$hook")

    if [ -z "$tutorial_block" ]; then
        fail "Could not extract tutorial code block for $hook (relative-path check)"
        return
    fi

    if echo "$tutorial_block" | grep -qF '"src/"*'; then
        pass "$hook tutorial matches cwd-relative src/ paths, not just absolute */src/*"
    else
        fail "$hook tutorial only matches absolute */src/* paths — silently no-ops on relative file_paths like 'src/app.js' (the #436 round-1 bug, reintroduced and caught again in v1.84.0 round 9)"
    fi
}

test_tdd_hook_tutorial_matches_relative_paths

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All wizard doc hook template drift tests passed!"
