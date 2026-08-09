#!/bin/bash
# Test hook scripts
# Tests: output keywords, JSON handling, missing jq behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"
PASSED=0
FAILED=0

# The suite owns its environment (#520).
#
# instructions-loaded-check.sh reads the LIVE env before falling back to
# settings.json, which is correct — the env is what governs the session. But it
# means a developer who has these set for their own use silently poisons every
# fixture here: the hook reports their values instead of the fixture's, and
# assertions fail locally while passing in a clean CI runner. That is the same
# green-here-red-there class as #488, so clear them once, up front, and let the
# tests that care about env precedence set them explicitly and locally.
unset CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
unset CLAUDE_CODE_AUTO_COMPACT_WINDOW

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

echo "=== Hook Script Tests ==="
echo ""

# ---- sdlc-prompt-check.sh tests ----

# Test 1: Script exists and is executable
test_sdlc_hook_exists() {
    if [ -x "$HOOKS_DIR/sdlc-prompt-check.sh" ]; then
        pass "sdlc-prompt-check.sh exists and is executable"
    else
        fail "sdlc-prompt-check.sh not found or not executable"
    fi
}

# Test 2: Output contains SDLC keywords
test_sdlc_hook_keywords() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    local has_all=true
    for keyword in "TodoWrite" "CONFIDENCE" "TDD" "TESTS" "SDLC"; do
        if ! echo "$output" | grep -qi "$keyword"; then
            has_all=false
            break
        fi
    done
    if [ "$has_all" = "true" ]; then
        pass "sdlc-prompt-check.sh contains all required keywords"
    else
        fail "sdlc-prompt-check.sh missing expected keywords"
    fi
}

# Test 3: Output contains skill auto-invoke rules
test_sdlc_hook_auto_invoke() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "AUTO-INVOKE"; then
        pass "sdlc-prompt-check.sh contains AUTO-INVOKE rules"
    else
        fail "sdlc-prompt-check.sh should contain AUTO-INVOKE rules"
    fi
}

# Test 4: Output contains workflow phases
test_sdlc_hook_phases() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "Plan Mode" && echo "$output" | grep -q "Implementation"; then
        pass "sdlc-prompt-check.sh contains workflow phases"
    else
        fail "sdlc-prompt-check.sh should contain workflow phases"
    fi
}

# Test 5: Output is reasonably sized (< 1000 chars for token efficiency)
test_sdlc_hook_size() {
    # Isolate from ambient $HOME/.cache/sdlc-wizard so a seeded signals
    # log (possible in any session that hit LOW/FAILED phrases) doesn't
    # make the "baseline" test secretly exercise the bump block. Codex
    # PR #203 round 1 repro: 2 seeded signals made this test measure
    # 1045 chars instead of the true no-bump baseline.
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    local size
    size=$(echo "$output" | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$size" -lt 1000 ]; then
        pass "sdlc-prompt-check.sh output is token-efficient (${size} chars)"
    else
        fail "sdlc-prompt-check.sh output too large (${size} chars, should be <1000)"
    fi
}

# ---- Hook token-cost caps (ROADMAP #203) ----
# CC issue #50799 documents hidden SessionStart hook billing — hooks that
# emit unbounded output silently eat user tokens. Every hook that writes
# to stdout gets an explicit size cap here. A regression that grows a
# hook's output (unintentional echo loop, bloated nudge copy, duplicate
# warnings) must trip these tests rather than ship to consumers.

test_tdd_pretool_size_cap() {
    local size
    size=$(echo '{"tool_input":{"file_path":"/src/foo.ts"}}' | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null | wc -c | tr -d ' ')
    if [ "$size" -lt 500 ]; then
        pass "tdd-pretool-check output is bounded (${size} chars < 500)"
    else
        fail "tdd-pretool-check output exceeded cap (${size} chars ≥ 500)"
    fi
}

test_model_effort_size_cap() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # #440: probe BOTH warning paths — "low" (below the medium floor) and
    # settings-only "max" (the LONGEST variant: effort_display carries the
    # "(settings-only — CC ignores this)" suffix). "medium" is now silent and
    # would make this test vacuous (Codex round-1 catch: it passed on 0 bytes
    # while the real warning was 556 bytes).
    local size max_size=0
    for probe in low max; do
        echo "{\"effortLevel\":\"$probe\"}" > "$tmpdir/.claude/settings.json"
        size=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null | wc -c | tr -d ' ')
        [ "$size" -eq 0 ] && { rm -rf "$tmpdir"; fail "model-effort-check emitted nothing for '$probe' — cap probe is vacuous"; return; }
        [ "$size" -gt "$max_size" ] && max_size=$size
    done
    rm -rf "$tmpdir"
    if [ "$max_size" -lt 500 ]; then
        pass "model-effort-check output is bounded (worst case ${max_size} chars < 500 across low + settings-only max)"
    else
        fail "model-effort-check output exceeded cap (${max_size} chars ≥ 500)"
    fi
}

test_instructions_loaded_size_cap() {
    # Stacked fixture: every emission branch in instructions-loaded-check.sh
    # must fire simultaneously. Codex PR #203 round 1 pointed out the original
    # fixture only exercised the loud-staleness branch (measured 557 chars,
    # cap was 3000 — 50-line bloat at 1509 still passed). This rebuilt fixture
    # stacks: loud staleness + cross-model review staleness + effort upgrade +
    # autocompact compound misconfig (#207) + dual-install + API review +
    # CC release + CC version check.
    local tmpdir
    tmpdir=$(mktemp -d)
    local fakehome="$tmpdir/home"
    local proj="$tmpdir/proj"
    mkdir -p "$fakehome/.claude/plugins-local/sdlc-wizard-wrap"
    mkdir -p "$proj/.claude/skills/update"
    mkdir -p "$proj/.github/workflows"
    mkdir -p "$proj/.reviews"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    echo '<!-- SDLC Harness Version: 1.10.0 -->' > "$proj/SDLC.md"
    echo 'testing' > "$proj/TESTING.md"
    # Effort upgrade (jq + stale effort)
    echo '{"effortLevel":"high"}' > "$proj/.claude/settings.local.json"
    # #207: autocompact compound misconfig (both env vars set)
    cat > "$proj/.claude/settings.json" <<'STACKED_SETTINGS'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
STACKED_SETTINGS
    # API review nudge (weekly-api-update.yml + gh stub → 5 open)
    echo 'name: weekly-api-update' > "$proj/.github/workflows/weekly-api-update.yml"
    # CC release nudge (weekly-update.yml + gh stub → 5 open)
    echo 'name: weekly-update' > "$proj/.github/workflows/weekly-update.yml"
    # Cross-model review staleness (codex + .reviews/ + age>3d + commits>5)
    touch -t 202603010000 "$proj/.reviews/latest-review.md"
    (cd "$proj" && git init -q && git config user.email t@t.com && git config user.name t \
        && for i in 1 2 3 4 5 6; do echo "$i" > "f$i.txt" && git add . && git commit -qm "c$i"; done)
    # Stubs: npm (loud 24-minor nudge + CC version diff), gh (nudge counts),
    # codex (presence), claude (CC version)
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm" && chmod +x "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "5"\n' > "$tmpdir/bin/gh" && chmod +x "$tmpdir/bin/gh"
    printf '#!/bin/bash\ntrue\n' > "$tmpdir/bin/codex" && chmod +x "$tmpdir/bin/codex"
    printf '#!/bin/bash\necho "1.2.3"\n' > "$tmpdir/bin/claude" && chmod +x "$tmpdir/bin/claude"
    local size
    size=$(cd "$proj" && HOME="$fakehome" PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$proj" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    # Cap raised 1500 → 1700 to accommodate the autocompact compound-misconfig
    # branch added in v1.44.1 / #207. Each new diagnostic warning legitimately
    # earns its space — but keep the cap as a brevity gate so unbounded growth
    # gets caught.
    if [ "$size" -lt 1700 ]; then
        pass "instructions-loaded-check stacked worst-case (all 8 branches incl. #207) is bounded (${size} chars < 1700)"
    else
        fail "instructions-loaded-check stacked worst-case exceeded cap (${size} chars ≥ 1700)"
    fi
}

# ---- PreCompact seam-gate hook (ROADMAP #208) ----
# Blocks manual /compact when compacting would lose evidence the next
# cycle needs — specifically when a Codex review is PENDING or a git
# rebase/merge/cherry-pick is in flight. Auto-compact is NOT gated
# (matcher: "manual" only in settings.json) — blocking auto risks
# pushing past 100% context.

test_precompact_hook_exists() {
    if [ -x "$HOOKS_DIR/precompact-seam-check.sh" ]; then
        pass "precompact-seam-check.sh exists and is executable"
    else
        fail "precompact-seam-check.sh missing or not executable"
    fi
}

test_precompact_silent_without_handoff_or_git_op() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # No .reviews/handoff.json, no .git — should exit 0 silently
    local stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null)
    local rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "precompact hook silent when no handoff and no git ops"
    else
        fail "precompact hook should be silent (rc=$rc, stderr='$stderr_out')"
    fi
}




test_precompact_blocks_on_git_rebase_in_progress() {
    # .git/rebase-merge/ — interactive rebase / rebase with merge strategy
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-merge"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact hook blocks (rc=2) on in-progress rebase-merge"
    else
        fail "precompact should block on rebase-merge (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_git_rebase_apply_in_progress() {
    # .git/rebase-apply/ — non-interactive rebase / `git am` / patch-based rebase.
    # Distinct code path from rebase-merge in the hook. Codex R1 caught the miss.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-apply"
    echo "dummy" > "$tmpdir/.git/rebase-apply/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact hook blocks (rc=2) on in-progress rebase-apply"
    else
        fail "precompact should block on rebase-apply (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_git_merge_in_progress() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/MERGE_HEAD"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "precompact hook blocks (rc=2) on in-progress merge"
    else
        fail "precompact should block on merge (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_cherry_pick_in_progress() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/CHERRY_PICK_HEAD"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "cherry-pick"; then
        pass "precompact hook blocks (rc=2) on in-progress cherry-pick"
    else
        fail "precompact should block on cherry-pick (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_silent_on_stale_rebase_head_alone() {
    # Bug: .git/REBASE_HEAD can persist as a stale marker after a rebase
    # has finished cleanly. The authoritative "rebase in progress" signal
    # is .git/rebase-merge/ or .git/rebase-apply/ — REBASE_HEAD alone is
    # just a rebase-related ref (the stopped/replayed commit), not an
    # in-flight state. Hit live 2026-05-05: yesterday's clean rebase left
    # REBASE_HEAD behind and blocked the user's manual /compact for no real reason.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/REBASE_HEAD"
    # NO rebase-merge/ or rebase-apply/ — actual rebase has finished
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "precompact hook is silent on stale REBASE_HEAD without rebase-{merge,apply} dirs"
    else
        fail "precompact should be silent on stale REBASE_HEAD alone (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_rebase_head_with_rebase_merge_dir() {
    # Negative control: REBASE_HEAD + rebase-merge/ together = real rebase
    # in progress (git wrote REBASE_HEAD when it created the dir). MUST
    # still block. Distinguishes the stale-alone case above from a live one.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-merge"
    echo "abc123" > "$tmpdir/.git/REBASE_HEAD"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact still blocks on REBASE_HEAD + rebase-merge dir (real rebase)"
    else
        fail "precompact should block on REBASE_HEAD + rebase-merge dir (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_size_cap() {
    # Worst case: all 3 git-op blockers fire simultaneously (rebase + merge +
    # cherry-pick). Should still emit a token-efficient HOLD message.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-merge"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    echo "abc" > "$tmpdir/.git/MERGE_HEAD"
    echo "def" > "$tmpdir/.git/CHERRY_PICK_HEAD"
    local size stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    size=$(printf '%s' "$stderr_out" | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && [ "$size" -lt 1000 ]; then
        pass "precompact hook stacked worst-case is bounded (${size} chars < 1000, rc=2)"
    else
        fail "precompact hook stacked worst-case exceeded cap or wrong rc (${size} chars, rc=$rc)"
    fi
}

# ---- tdd-pretool-check.sh tests ----

# Test 6: Script exists and is executable
test_tdd_hook_exists() {
    if [ -x "$HOOKS_DIR/tdd-pretool-check.sh" ]; then
        pass "tdd-pretool-check.sh exists and is executable"
    else
        fail "tdd-pretool-check.sh not found or not executable"
    fi
}

# Test 7: Source file edit produces TDD warning JSON
test_tdd_hook_src_warning() {
    local input='{"tool_input": {"file_path": "/project/src/app.js"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "TDD CHECK"; then
        pass "tdd-pretool-check.sh warns on src/ file edits"
    else
        fail "Should warn when editing src/ files, got: $output"
    fi
}

# Test 8: Source file edit produces valid JSON output
test_tdd_hook_valid_json() {
    local input='{"tool_input": {"file_path": "/project/src/utils/helper.ts"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if echo "$output" | jq -e '.hookSpecificOutput' > /dev/null 2>&1; then
        pass "tdd-pretool-check.sh outputs valid JSON for src/ edits"
    else
        fail "Output should be valid JSON with hookSpecificOutput, got: $output"
    fi
}

# Test 9: Test file edit exits cleanly (no warning)
test_tdd_hook_test_file_ok() {
    local input='{"tool_input": {"file_path": "tests/test-something.sh"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "tdd-pretool-check.sh allows test file edits silently"
    else
        fail "Test file edits should produce no output, got: $output"
    fi
}

# Test 10: Non-workflow, non-test file produces no output
test_tdd_hook_other_file_ok() {
    local input='{"tool_input": {"file_path": "README.md"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "tdd-pretool-check.sh allows other file edits silently"
    else
        fail "Non-workflow edits should produce no output, got: $output"
    fi
}

# Test 11: Missing file_path in input handled gracefully
test_tdd_hook_missing_path() {
    local input='{"tool_input": {}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd-pretool-check.sh handles missing file_path gracefully"
    else
        fail "Should handle missing file_path without crashing, exit code: $exit_code"
    fi
}

# #436 P0 (matching codex-gate bug class): tdd-pretool-check.sh printed a TDD
# reminder but never exited 2 — pure prose despite tdd_red being CRITICAL in
# the SDLC scoring rubric. Fable's proposed mechanism: block writing to src/**
# unless a test file was touched earlier this session (edit-ordering gate,
# not full "does a failing test exist" verification — that's out of a bash
# hook's reach, but ordering is a real, checkable proxy).

test_tdd_gate_blocks_src_write_when_no_test_touched() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"session_id":"sess-block-1","tool_input":{"file_path":"/project/src/app.js"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "test"; then
        pass "tdd gate BLOCKS (exit 2) src/ write when no test touched yet this session"
    else
        fail "tdd gate should exit 2 mentioning test-first, got exit=$exit_code out: $out"
    fi
}

test_tdd_gate_allows_src_write_after_test_touched() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local sid="sess-block-2"
    # First: touch a test file (plants the sentinel)
    echo "{\"session_id\":\"$sid\",\"tool_input\":{\"file_path\":\"/project/src/__tests__/app.test.js\"}}" \
        | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" > /dev/null 2>&1
    # Then: write to src/ in the same session
    local out exit_code
    out=$(echo "{\"session_id\":\"$sid\",\"tool_input\":{\"file_path\":\"/project/src/app.js\"}}" \
        | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd gate allows src/ write after a test file was touched this session"
    else
        fail "tdd gate should exit 0 once a test file was touched, got exit=$exit_code out: $out"
    fi
}

test_tdd_gate_allows_test_file_writes_unconditionally() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"session_id":"sess-block-3","tool_input":{"file_path":"/project/src/__tests__/app.test.js"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd gate always allows writing test files themselves (exit 0)"
    else
        fail "tdd gate should never block a test-file write, got exit=$exit_code out: $out"
    fi
}

test_tdd_gate_recognizes_test_patterns() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fails=0
    for test_path in "/p/src/foo.test.js" "/p/src/foo.spec.ts" "/p/src/test_foo.py" "/p/src/__tests__/foo.js"; do
        local sid
        sid="sess-pattern-$(printf '%s' "$test_path" | tr -cd 'A-Za-z0-9')"
        echo "{\"session_id\":\"$sid\",\"tool_input\":{\"file_path\":\"$test_path\"}}" \
            | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" > /dev/null 2>&1
        local out exit_code
        out=$(echo "{\"session_id\":\"$sid\",\"tool_input\":{\"file_path\":\"/p/src/impl.js\"}}" \
            | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
        if [ "$exit_code" -ne 0 ]; then
            fails=$((fails+1))
            echo "  [$test_path] did not unlock src/ writes, exit=$exit_code out: $out" >&2
        fi
    done
    rm -rf "$tmpdir"
    if [ "$fails" -eq 0 ]; then
        pass "tdd gate recognizes .test./.spec./test_*/__tests__/ as test files"
    else
        fail "tdd gate missed $fails test-file naming conventions"
    fi
}

test_tdd_gate_no_block_without_session_id() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"tool_input":{"file_path":"/project/src/app.js"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd gate degrades gracefully (no block) without session_id — no way to track ordering"
    else
        fail "tdd gate should not block when session_id is absent (can't track state), got exit=$exit_code out: $out"
    fi
}

# Codex review finding (hook-enforcement-436, round 1): the src/ gate matches
# `*"/src/"*`, which requires a slash BEFORE "src". A relative path like
# "src/app.js" (no leading slash — a plausible cwd-relative file_path) never
# matches, so the entire gate silently no-ops for relative src/ paths.
test_tdd_gate_blocks_relative_src_path() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"session_id":"sess-relative-1","tool_input":{"file_path":"src/app.js"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "test"; then
        pass "tdd gate BLOCKS (exit 2) relative src/ path when no test touched yet"
    else
        fail "tdd gate should exit 2 for relative 'src/app.js' path, got exit=$exit_code out: $out"
    fi
}

# #236(b) BUG 2 fix: SDLC_TDD_SRC_PATTERN lets a project (e.g. this meta-repo,
# which has no src/ dir) override the gated path(s) via env var instead of
# editing the shared/distributed script. Fable-reviewed design (advisor was
# down): env var replaces the default /src/ pattern when set, so it doesn't
# leak a meta-repo-specific path into the generic template other repos get.
test_tdd_gate_respects_src_pattern_override() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"session_id":"sess-override-1","tool_input":{"file_path":"/project/hooks/foo.sh"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" SDLC_TDD_SRC_PATTERN='hooks/|cli/' "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "test"; then
        pass "tdd gate BLOCKS (exit 2) a path matching SDLC_TDD_SRC_PATTERN override when no test touched yet"
    else
        fail "tdd gate should exit 2 for 'hooks/foo.sh' with SDLC_TDD_SRC_PATTERN='hooks/|cli/' set, got exit=$exit_code out: $out"
    fi
}

test_tdd_gate_override_replaces_not_extends_default_pattern() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local input='{"session_id":"sess-override-2","tool_input":{"file_path":"/project/src/app.js"}}'
    local out exit_code
    out=$(echo "$input" | SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" SDLC_TDD_SRC_PATTERN='hooks/|cli/' "$HOOKS_DIR/tdd-pretool-check.sh" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd gate override REPLACES the default /src/ pattern (src/ path unblocked when override doesn't mention it)"
    else
        fail "with SDLC_TDD_SRC_PATTERN set, a plain src/ path not covered by the override should not be gated, got exit=$exit_code out: $out"
    fi
}

# ---- instructions-loaded-check.sh tests ----

# Test 12: Script exists and is executable
test_instructions_hook_exists() {
    if [ -x "$HOOKS_DIR/instructions-loaded-check.sh" ]; then
        pass "instructions-loaded-check.sh exists and is executable"
    else
        fail "instructions-loaded-check.sh not found or not executable"
    fi
}


# Test 15: Silent when neither file exists (not an SDLC project, #173)
test_instructions_hook_missing_both() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent when neither SDLC file exists (#173)"
    else
        fail "Should be silent when no SDLC project, got: $output"
    fi
}

# Test 16: No warning when both files exist
test_instructions_hook_all_present() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Mock claude + npm so CC version check doesn't produce output
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif [ "$1" = "--version" ]; then echo "2.1.90 (Claude Code)"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif [ "$1" = "view" ] && echo "$@" | grep -q "claude-code"; then echo "2.1.90"; elif [ "$1" = "view" ]; then echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent when all files present"
    else
        fail "Should produce no output when files exist, got: $output"
    fi
}

# Test 17: Exits cleanly (exit 0) regardless of missing files
test_instructions_hook_exit_code() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh") > /dev/null 2>&1
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "instructions-loaded-check.sh exits cleanly even with missing files"
    else
        fail "Should exit 0 even when files missing, got exit code: $exit_code"
    fi
}

# Test 18: Hook output has no trailing whitespace
test_instructions_hook_no_trailing_whitespace() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Both files missing = worst case for trailing whitespace
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Check that no line ends with trailing whitespace (runtime output)
    if echo "$output" | grep -q '[[:blank:]]$'; then
        fail "instructions-loaded-check.sh output has trailing whitespace"
        return
    fi
    # Also check the script source itself for baked-in trailing whitespace
    if grep -q '[[:blank:]]$' "$HOOKS_DIR/instructions-loaded-check.sh"; then
        fail "instructions-loaded-check.sh source has trailing whitespace"
    else
        pass "instructions-loaded-check.sh output has no trailing whitespace"
    fi
}

# ---- Setup completeness tests (wizard dogfood) ----

# Test 19: SDLC.md contains wizard version metadata comment
test_sdlc_version_metadata() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- SDLC Harness Version: [0-9]' "$sdlc_md"; then
        pass "SDLC.md contains wizard version metadata comment"
    else
        fail "SDLC.md should contain <!-- SDLC Harness Version: X.X.X --> metadata comment"
    fi
}

# Test 20: SDLC.md wizard version matches wizard document version
test_sdlc_version_matches_wizard() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"

    local installed_version
    installed_version=$(grep -o 'SDLC Harness Version: [0-9.]*' "$sdlc_md" | head -1 | sed 's/SDLC Harness Version: //')
    local wizard_version
    wizard_version=$(grep -o 'SDLC Harness Version: [0-9.]*' "$wizard" | head -1 | sed 's/SDLC Harness Version: //')

    if [ -z "$installed_version" ]; then
        fail "Could not extract version from SDLC.md"
        return
    fi
    if [ "$installed_version" = "$wizard_version" ]; then
        pass "SDLC.md version ($installed_version) matches wizard ($wizard_version)"
    else
        fail "SDLC.md version ($installed_version) != wizard version ($wizard_version)"
    fi
}

# Test 21: SDLC.md contains setup date metadata
test_sdlc_setup_date() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- Setup Date: [0-9]' "$sdlc_md"; then
        pass "SDLC.md contains setup date metadata comment"
    else
        fail "SDLC.md should contain <!-- Setup Date: YYYY-MM-DD --> metadata comment"
    fi
}

# Test 22: SDLC.md contains completed steps metadata
test_sdlc_completed_steps() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- Completed Steps:' "$sdlc_md"; then
        pass "SDLC.md contains completed steps metadata comment"
    else
        fail "SDLC.md should contain <!-- Completed Steps: ... --> metadata comment"
    fi
}

# Test 23: Light hook references /code-review (not outdated subagent pattern)
# GH #486: the per-prompt self-review directive is GONE, and this asserts its
# absence rather than its presence.
#
# The Opus 5 prompting guide says explicit verification instructions cause
# over-verification. That advice targets SAME-MODEL self-checking, and this
# repo's own evidence is blunt about it: /code-review reported 64/64 green three
# times in one session while an independent model found real P1s each time,
# including a shipped hook proven silently dead. The same-model layer has zero
# recorded unique catches here.
#
# A per-prompt injection is the worst surface for it — it fires on every turn and
# compounds. Cross-model review keeps the heavyweight job; the cheap part
# ("read back the diff you modified") survives as a scored rubric row, which is
# measurement rather than instruction.
test_sdlc_hook_self_review_reference() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "/code-review"; then
        fail "sdlc-prompt-check.sh still injects a /code-review self-review directive on every prompt — deleted in #486 as same-model verification with no recorded unique catches"
    else
        pass "#486: no per-prompt self-review directive (cross-model review carries it)"
    fi
}

# Test 24: SDLC.md update frequency says weekly (not daily)
test_sdlc_update_frequency() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -qi "daily.*workflow.*checks\|daily.*checks.*for.*update" "$sdlc_md"; then
        fail "SDLC.md says 'daily' but update workflow runs weekly"
    else
        pass "SDLC.md does not falsely claim daily update checks"
    fi
}

# Test 26: sdlc-prompt-check outputs claude-setup-wizard directive when SDLC.md missing
test_sdlc_hook_setup_redirect_missing_sdlc() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/TESTING.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "claude-setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to claude-setup-wizard when SDLC.md missing"
    else
        fail "Should output claude-setup-wizard directive (not SDLC BASELINE) when SDLC.md missing"
    fi
}

# Test 27: sdlc-prompt-check outputs claude-setup-wizard directive when TESTING.md missing
test_sdlc_hook_setup_redirect_missing_testing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "claude-setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to claude-setup-wizard when TESTING.md missing"
    else
        fail "Should output claude-setup-wizard directive (not SDLC BASELINE) when TESTING.md missing"
    fi
}

# Test 28: sdlc-prompt-check outputs normal baseline when both files exist (non-empty)
test_sdlc_hook_normal_when_setup_complete() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local output
    output=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE" && ! echo "$output" | grep -q "SETUP NOT COMPLETE"; then
        pass "sdlc-prompt-check.sh outputs normal baseline when setup complete"
    else
        fail "Should output SDLC BASELINE (not setup redirect) when both files exist"
    fi
}

# Test 29: sdlc-prompt-check redirects when files are empty stubs
test_sdlc_hook_setup_redirect_empty_stubs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "claude-setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to claude-setup-wizard for empty stub files"
    else
        fail "Empty stub files should trigger claude-setup-wizard redirect, not baseline"
    fi
}

# Test 30: Template hook redirects to claude-setup-wizard on partial setup (one file present)
test_template_hook_setup_redirect() {
    local TEMPLATE_HOOK="$SCRIPT_DIR/../hooks/sdlc-prompt-check.sh"
    if [ ! -f "$TEMPLATE_HOOK" ]; then fail "Template hook not found"; return; fi
    local tmpdir
    tmpdir=$(mktemp -d)
    # Partial setup: only TESTING.md exists, CWD below HOME for walk-up
    mkdir -p "$tmpdir/project"
    touch "$tmpdir/project/TESTING.md"
    local output
    output=$(cd "$tmpdir/project" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" bash "$TEMPLATE_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "claude-setup-wizard"; then
        pass "Template hook redirects to claude-setup-wizard on partial setup"
    else
        fail "Template hook should redirect to claude-setup-wizard, got: $output"
    fi
}

# ---- Effort level recommendation tests ----

# Test 31: Wizard doc has "Effort Level" section
test_wizard_effort_level_section() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -q "## .*Effort Level" "$wizard"; then
        pass "Wizard doc has Effort Level section"
    else
        fail "Wizard doc should have an Effort Level section"
    fi
}

# Test 32: Wizard doc recommends model-aware effort (v1.84.0+: Sonnet 5 default)
# Also accepts "high" references since the wizard discusses effort floors.
test_wizard_effort_high_default() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -qi "max.*default\|default.*max\|recommended default" "$wizard" && grep -qE "effort.*(max|high)" "$wizard"; then
        pass "Wizard doc recommends a default effort level (v1.84.0+)"
    else
        fail "Wizard doc should recommend a default effort level"
    fi
}

# Test 33: Wizard confidence table mentions escalating effort for LOW confidence
# (v1.84.0: model-aware, not a blanket /effort max)
test_wizard_confidence_effort_max() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    local section
    section=$(sed -n '/## Confidence Check/,/^## /p' "$wizard")
    if echo "$section" | grep -qi 'escalate effort' && echo "$section" | grep -q 'LOW'; then
        pass "Wizard confidence table mentions escalating effort for LOW confidence"
    else
        fail "Wizard confidence table should mention escalating effort for LOW confidence"
    fi
}

# Test 34: SDLC skill confidence table mentions escalating effort for LOW confidence
# (v1.84.0: model-aware, not a blanket /effort max)
test_skill_confidence_effort_max() {
    local skill="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    local section
    section=$(sed -n '/## Confidence Check/,/^## /p' "$skill")
    if echo "$section" | grep -qi 'escalate now'; then
        pass "SDLC skill confidence table mentions escalating effort for LOW confidence"
    else
        fail "SDLC skill confidence table should mention escalating effort for LOW confidence"
    fi
}

# ---------------------------------------------------------------------------
# SDLC Enforcement Gap Audit Tests
# Verify that documented SDLC sections have TodoWrite enforcement
# ---------------------------------------------------------------------------

SKILL_TEMPLATE="$SCRIPT_DIR/../skills/sdlc/SKILL.md"

# Test: TodoWrite checklist has "capture learnings" / "after session" task
test_todowrite_has_capture_learnings() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'capture.*learning\|after.*session\|learnings'; then
        pass "TodoWrite has capture learnings task"
    else
        fail "TodoWrite missing capture learnings task — After Session section not enforced"
    fi
}

# Test: TodoWrite checklist has scope guard / stay in lane reminder
test_todowrite_has_scope_guard() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'scope.*guard\|stay.*lane\|scope.*check\|only.*related'; then
        pass "TodoWrite has scope guard task"
    else
        fail "TodoWrite missing scope guard task — Scope Guard section not enforced"
    fi
}

# Test: TodoWrite checklist has deployment conditional tasks
test_todowrite_has_deploy_tasks() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'deploy\|post-deploy\|deployment'; then
        pass "TodoWrite has deployment tasks"
    else
        fail "TodoWrite missing deployment tasks — Deployment section not enforced"
    fi
}

# Test: TodoWrite checklist has new pattern approval check
test_todowrite_has_new_pattern_check() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'new.*pattern\|pattern.*approv\|pattern.*exist'; then
        pass "TodoWrite has new pattern approval check"
    else
        fail "TodoWrite missing new pattern check — New Pattern section not enforced"
    fi
}

# Test: TodoWrite checklist has legacy/delete code check
test_todowrite_has_legacy_delete_check() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'legacy\|delete.*old\|fallback.*code\|backward.*compat'; then
        pass "TodoWrite has legacy code delete check"
    else
        fail "TodoWrite missing legacy delete check — DELETE Legacy Code section not enforced"
    fi
}

# Test: Enforcement coverage score — count documented sections with TodoWrite tasks
# This is the "audit score" — tracks how many prose sections have enforcement
test_enforcement_coverage_score() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    local enforced=0
    # 11, not 12: #486 deleted the Self-Review Loop section, so there is no
    # longer a documented section for a self-review TodoWrite item to enforce.
    # Dropping the denominator is the honest fix — re-adding a checklist item
    # for prose that no longer exists would be enforcing nothing, and the
    # instructed same-model loop is exactly what #486 removed.
    local total=11

    # Already enforced (baseline)
    echo "$todowrite_section" | grep -qi 'doc\|read.*doc' && enforced=$((enforced + 1))          # Planning: read docs
    echo "$todowrite_section" | grep -qi 'DRY\|reuse\|pattern.*exist' && enforced=$((enforced + 1)) # DRY scan
    echo "$todowrite_section" | grep -qi 'blast.*radius\|depend' && enforced=$((enforced + 1))    # Blast radius
    echo "$todowrite_section" | grep -qi 'confidence' && enforced=$((enforced + 1))                # Confidence
    echo "$todowrite_section" | grep -qi 'TDD RED\|failing test' && enforced=$((enforced + 1))    # TDD RED
    echo "$todowrite_section" | grep -qi 'security' && enforced=$((enforced + 1))                  # Security review

    # New enforcement (gaps we're fixing)
    echo "$todowrite_section" | grep -qi 'capture.*learning\|after.*session' && enforced=$((enforced + 1))  # After Session
    echo "$todowrite_section" | grep -qi 'scope.*guard\|stay.*lane\|scope.*check' && enforced=$((enforced + 1))   # Scope Guard
    echo "$todowrite_section" | grep -qi 'deploy' && enforced=$((enforced + 1))                    # Deploy tasks
    echo "$todowrite_section" | grep -qi 'new.*pattern\|pattern.*approv' && enforced=$((enforced + 1))  # New pattern
    echo "$todowrite_section" | grep -qi 'legacy\|delete.*old\|fallback' && enforced=$((enforced + 1))  # Legacy delete

    if [ "$enforced" -ge "$total" ]; then
        pass "Enforcement coverage: $enforced/$total documented sections have TodoWrite tasks"
    else
        fail "Enforcement coverage: $enforced/$total — missing TodoWrite tasks for $((total - enforced)) documented sections"
    fi
}

# Run all tests
test_sdlc_hook_exists
test_sdlc_hook_keywords
test_sdlc_hook_auto_invoke
test_sdlc_hook_phases
test_sdlc_hook_size
test_tdd_pretool_size_cap
test_model_effort_size_cap
test_instructions_loaded_size_cap
test_precompact_hook_exists
test_precompact_silent_without_handoff_or_git_op
test_precompact_blocks_on_git_rebase_in_progress
test_precompact_blocks_on_git_rebase_apply_in_progress
test_precompact_blocks_on_git_merge_in_progress
test_precompact_blocks_on_cherry_pick_in_progress
test_precompact_silent_on_stale_rebase_head_alone
test_precompact_blocks_on_rebase_head_with_rebase_merge_dir
test_precompact_size_cap



# ---- #240: dry-run env var for safe smoke-testing ----
# Consumer issue: smoke-testing hook behavior required cp'ing real .git/
# aside, fabricating fake state, restoring — error-prone. SDLC_DRY_RUN_GIT_STATE
# simulates an in-flight git operation without touching the filesystem.



test_precompact_dry_run_git_state_rebase_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # No .git/, but env var simulates rebase
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=rebase \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=rebase simulates rebase block (rc=2)"
    else
        fail "#240: dry-run git rebase should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_merge_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=merge \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=merge simulates merge block (rc=2)"
    else
        fail "#240: dry-run git merge should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_cherry_pick_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=cherry-pick \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "cherry"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=cherry-pick simulates cherry-pick block (rc=2)"
    else
        fail "#240: dry-run cherry-pick should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

# Critical: dry-run must NOT mutate real state. Run a dry-run that would
# trigger HOLD; then re-run without dry-run env vars and confirm real
# state (no handoff, no git op) returns silent rc=0.
# Codex round 1 P1: invalid SDLC_DRY_RUN_GIT_STATE values (typos like
# "bogus") used to skip the real .git/ check entirely — silently bypassing
# the merge-in-progress safety. Now: unknown values fall through to real
# state checks, so a typo can't disable the safety check.
test_precompact_dry_run_git_state_typo_falls_back_to_real_check() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # Real .git/MERGE_HEAD present
    mkdir -p "$tmpdir/.git"
    touch "$tmpdir/.git/MERGE_HEAD"
    # Bogus dry-run value should NOT bypass real merge-in-progress check
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=bogus \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "#240 Codex#1: typo in SDLC_DRY_RUN_GIT_STATE falls back to real .git/ check (no safety bypass)"
    else
        fail "#240 Codex#1: typo should fall back to real check (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_rebase_blocks
test_precompact_dry_run_git_state_merge_blocks
test_precompact_dry_run_git_state_cherry_pick_blocks
test_precompact_dry_run_git_state_typo_falls_back_to_real_check
test_tdd_hook_exists
test_tdd_hook_src_warning
test_tdd_hook_valid_json
test_tdd_hook_test_file_ok
test_tdd_hook_other_file_ok
test_tdd_hook_missing_path
test_tdd_gate_blocks_src_write_when_no_test_touched
test_tdd_gate_allows_src_write_after_test_touched
test_tdd_gate_allows_test_file_writes_unconditionally
test_tdd_gate_recognizes_test_patterns
test_tdd_gate_no_block_without_session_id
test_tdd_gate_blocks_relative_src_path
test_tdd_gate_respects_src_pattern_override
test_tdd_gate_override_replaces_not_extends_default_pattern
test_instructions_hook_exists
test_instructions_hook_missing_both
test_instructions_hook_all_present
test_instructions_hook_exit_code
test_instructions_hook_no_trailing_whitespace
test_sdlc_version_metadata
test_sdlc_version_matches_wizard
test_sdlc_setup_date
test_sdlc_completed_steps
test_sdlc_hook_self_review_reference
test_sdlc_update_frequency
test_sdlc_hook_setup_redirect_missing_sdlc
test_sdlc_hook_setup_redirect_missing_testing
test_sdlc_hook_normal_when_setup_complete
test_sdlc_hook_setup_redirect_empty_stubs
test_template_hook_setup_redirect
test_wizard_effort_level_section
test_wizard_effort_high_default
test_wizard_confidence_effort_max
test_skill_confidence_effort_max

echo ""
echo "--- Update notification tests ---"

# Test 35: Shows update notification when newer version available
test_update_notification_newer_available() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Create fake npm that returns a newer version
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.22.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "update available" && echo "$output" | grep -q "1.20.0" && echo "$output" | grep -q "1.22.0"; then
        pass "Shows update notification when newer version available"
    else
        fail "Should show update notification with both versions, got: $output"
    fi
}

# Test 36: No notification when versions match
test_update_notification_same_version() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.22.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.22.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "update available"; then
        fail "Should NOT show update notification when versions match, got: $output"
    else
        pass "No update notification when versions match"
    fi
}

# Test 37: No notification when npm is not available
test_update_notification_npm_unavailable() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Empty bin dir — npm not in PATH
    mkdir -p "$tmpdir/bin"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -q "update available"; then
        pass "No notification and exit 0 when npm unavailable"
    else
        fail "Should silently skip when npm unavailable, exit=$exit_code, got: $output"
    fi
}

# Test 38: No notification when npm fails (e.g., network error)
test_update_notification_npm_fails() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -q "update available"; then
        pass "No notification and exit 0 when npm fails"
    else
        fail "Should silently skip when npm fails, exit=$exit_code, got: $output"
    fi
}

# Test 39: No notification when SDLC.md lacks version metadata
test_update_notification_no_version_metadata() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC Config" > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.22.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Wizard.*update available"; then
        fail "Should NOT show wizard notification when SDLC.md has no version metadata, got: $output"
    else
        pass "No notification when SDLC.md lacks version metadata"
    fi
}

# Test 40: Update notification mentions /claude-update-wizard
test_update_notification_mentions_update_wizard() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.22.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "/claude-update-wizard"; then
        pass "Update notification mentions /claude-update-wizard"
    else
        fail "Update notification should mention /claude-update-wizard, got: $output"
    fi
}

# Test (ROADMAP #196): Loud staleness nudge when ≥3 minor versions behind.
# User feedback 2026-04-18: the 1-line "update available" nudge is too easy
# to skip — users went months without running /update. This test drives a
# stronger, multi-line warning when the gap is material (≥3 minor versions).
test_update_notification_loud_when_3_minor_behind() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Louder format must mention the exact delta (9 here) AND use stronger
    # language than the one-line fallback. Require both an explicit "behind"
    # count and a WARNING/!! marker so the nudge stands out.
    echo "$output" | grep -qE '(9.*minor.*behind|behind.*9.*minor|9[[:space:]]*versions.*behind)' || ok=false
    echo "$output" | grep -qE 'WARNING|!!|⚠|strongly recommend' || ok=false
    echo "$output" | grep -q '/claude-update-wizard' || ok=false
    if [ "$ok" = true ]; then
        pass "Loud nudge fires when ≥3 minor versions behind (1.25.0 → 1.34.0)"
    else
        fail "Expected loud '9 minor versions behind' nudge, got: $output"
    fi
}

# Companion: mild nudge (1-2 minor behind) does NOT print the loud markers.
# This ensures we don't over-warn on small gaps.
test_update_notification_mild_when_2_minor_behind() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.32.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Must still mention the update is available
    echo "$output" | grep -q "update available" || ok=false
    # Must NOT include the loud markers
    if echo "$output" | grep -qE 'minor.*behind|strongly recommend'; then
        ok=false
    fi
    if [ "$ok" = true ]; then
        pass "Mild nudge (no loud markers) for 2 minor versions behind"
    else
        fail "Expected mild one-line nudge for 2-minor gap, got: $output"
    fi
}

# Cache: npm is only called once per 24h. On second invocation with a fresh
# cache file, the hook must use the cached value instead of re-invoking npm.
test_update_notification_uses_daily_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # npm returns 1.34.0 on first call; on second call it would return
    # nothing (we replace the binary to prove the cache is used).
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    # First run — populates cache
    (cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" > /dev/null 2>/dev/null)
    # Replace npm with one that fails — forces the hook to use the cache or skip
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    # Second run — should still see the loud nudge because cache is <24h old
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'minor.*behind'; then
        pass "Second invocation uses daily cache (no re-fetch from npm)"
    else
        fail "Second invocation should use cached latest version, got: $output"
    fi
}

# Codex round 1 (P1): malformed cache contents (whitespace, non-version like
# "junk") were being treated as valid, producing "Latest: junk" / bogus
# "99 behind" output. Strict semver validation must reject non-x.y.z content
# and fall back to npm.
test_update_notification_rejects_malformed_cache_junk() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Seed cache with garbage — must be ignored, npm must be called
    printf 'junk' > "$tmpdir/cache/latest-version"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Must NOT leak "junk" into output
    if echo "$output" | grep -q 'junk'; then ok=false; fi
    # Must fall back to npm and produce real 1.34.0 nudge
    echo "$output" | grep -q '1.34.0' || ok=false
    if [ "$ok" = true ]; then
        pass "Malformed cache ('junk') is rejected and npm refetched"
    else
        fail "Expected malformed cache to be ignored, got: $output"
    fi
}

test_update_notification_rejects_malformed_cache_whitespace() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Whitespace-only cache contents — must be rejected
    printf '   \n' > "$tmpdir/cache/latest-version"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Must not print "99 behind" (which would indicate whitespace → major-bump delta)
    if echo "$output" | grep -qE '99.*minor.*behind'; then
        fail "Whitespace cache leaked through, got: $output"
    else
        pass "Whitespace-only cache is rejected"
    fi
}

# Codex round 1 (P2): npm returning a non-numeric minor field (e.g.
# "1.alpha.0") must not run delta math. awk '$2+0' silently coerces alpha
# to 0, producing nonsense output. Strict semver gate must reject.
test_update_notification_rejects_non_numeric_minor() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    # Stub returns non-numeric minor ONLY for the wizard package; anything
    # else (e.g. the CC version check later in the hook) errors silently so
    # we're only exercising the wizard-version path.
    cat > "$tmpdir/bin/npm" <<'NPMEOF'
#!/bin/bash
if [[ "$*" == *"agentic-sdlc-wizard"* ]]; then
    echo "1.alpha.0"
else
    exit 1
fi
NPMEOF
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Must not surface "1.alpha.0" to the user or compute a bogus delta
    if echo "$output" | grep -q '1.alpha.0'; then
        fail "Non-numeric version leaked to output, got: $output"
    elif echo "$output" | grep -qE 'SDLC Harness update available|minor.*behind'; then
        fail "Expected silent skip on invalid npm response, got: $output"
    else
        pass "Non-numeric minor field (1.alpha.0) is rejected silently"
    fi
}

# Test (#254 Bug 2 / #239): when cached "latest" < installed (cache poison
# post-upgrade, or stale-but-not-expired cache after a release), the hook MUST
# stay silent — never emit a reverse "update available" nudge. Previous
# behavior printed "1.42.1 → 1.41.1" because line 80 used `!=` equality.
test_update_notification_silent_when_installed_newer_than_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.43.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Cache holds an older version (post-upgrade scenario)
    printf '1.41.1' > "$tmpdir/cache/latest-version"
    # Make sure the file looks fresh so the cache age check passes
    touch "$tmpdir/cache/latest-version"
    # npm should not be called — but stub it just in case
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'update available|minor.*behind'; then
        fail "#254 Bug 2: Hook emitted reverse nudge when installed > latest, got: $output"
    else
        pass "#254 Bug 2: Hook silent when installed (1.43.0) > cached latest (1.41.1)"
    fi
}

# #236(b): the CC-version check used to be an uncached npm call on every
# session start with bare `!=` (fires in either direction). Now mirrors the
# wizard's own version-check cache + semver_lt direction pattern above.
# Prove caching: seed a fresh, valid, NEWER-than-local cache entry and stub
# npm to return a DIFFERENT version — if the hook actually calls npm instead
# of using the cache, the output would show npm's version, not the cache's.
test_cc_version_check_uses_fresh_cache_not_npm() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.86.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    printf '2.1.95' > "$tmpdir/cache/latest-cc-version"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.99"; else echo "1.86.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "2.1.95" && ! echo "$output" | grep -q "2.1.99"; then
        pass "CC version check uses fresh cache (2.1.95), doesn't hit npm (would've shown 2.1.99)"
    else
        fail "expected cached '2.1.95' in output, not npm's '2.1.99' (proves cache miss), got: $output"
    fi
}

# #236(b): direction fix — the old code used bare `!=`, which fires a
# nonsensical reverse nudge ("update available: 2.1.90 -> 2.1.50") whenever
# npm/cache returns anything OLDER than local (e.g. a transient bad response,
# or a mirror lagging behind). No cache seeded — isolates the semver_lt
# direction check itself, independent of caching behavior.
test_cc_version_check_silent_when_npm_returns_older_version() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.86.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.50"; else echo "1.86.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "claude code update"; then
        fail "should stay silent when npm returns an older version (2.1.50) than local (2.1.90), got: $output"
    else
        pass "CC version check silent when npm returns an older version than local (semver_lt direction, not bare !=)"
    fi
}

# Test (#239): when npm view fails AND cache is missing/stale, the hook should
# surface the failure once (one-line warning) instead of silently serving
# nothing. Currently the version-check block produces no output at all in
# this state — user has no way to know the nudge mechanism is broken.
test_update_notification_surfaces_npm_failure() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.30.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # No cache file; npm fails with EPERM-style error
    cat > "$tmpdir/bin/npm" <<'NPMEOF'
#!/bin/bash
echo "npm error code EPERM" >&2
exit 1
NPMEOF
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>&1)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'npm view failed|npm.*unavailable|version check unavailable'; then
        pass "#239: Hook surfaces npm failure with one-line warning when cache miss"
    else
        fail "#239: Expected one-line warning on npm failure, got: $output"
    fi
}

test_update_notification_newer_available
test_update_notification_same_version
test_update_notification_npm_unavailable
test_update_notification_npm_fails
test_update_notification_no_version_metadata
test_update_notification_mentions_update_wizard
test_update_notification_loud_when_3_minor_behind
test_update_notification_mild_when_2_minor_behind
test_update_notification_uses_daily_cache
test_update_notification_rejects_malformed_cache_junk
test_update_notification_rejects_malformed_cache_whitespace
test_update_notification_rejects_non_numeric_minor
test_update_notification_silent_when_installed_newer_than_cache
test_cc_version_check_uses_fresh_cache_not_npm
test_cc_version_check_silent_when_npm_returns_older_version
test_update_notification_surfaces_npm_failure

# #375: CC version check must NOT fire under non-Claude hosts (Codex, OpenCode).
# The bug: `command -v claude` is true even under Codex/OpenCode when the user
# has Claude Code installed. Gate on CLAUDE_PROJECT_DIR instead of CLI presence.
test_cc_version_check_silent_under_non_claude_host() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    # Fake claude CLI that reports an old version
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    # Fake npm that reports a newer version
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.168"; else echo "1.20.0"; fi\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm"
    local output
    # Key: explicitly unset CLAUDE_PROJECT_DIR — simulates running under Codex/OpenCode.
    # Must use env -u to prevent inheriting from the parent shell (e.g., when run from Claude Code).
    output=$(cd "$tmpdir" && env -u CLAUDE_PROJECT_DIR PATH="$tmpdir/bin:$PATH" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Claude Code update"; then
        fail "#375: CC version check should NOT fire when CLAUDE_PROJECT_DIR is unset (non-Claude host)"
    else
        pass "#375: CC version check silent under non-Claude host (CLAUDE_PROJECT_DIR unset)"
    fi
}

test_cc_version_check_silent_under_non_claude_host

echo ""
echo "--- Hook if-conditional tests (#68) ---"

# Test: settings.json PreToolUse hook has `if` field
test_settings_has_if_field() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    if [ -n "$if_value" ]; then
        pass "settings.json PreToolUse hook has 'if' field"
    else
        fail "settings.json PreToolUse hook should have 'if' field for conditional filtering"
    fi
}

# Test: if field targets workflow files (*.yml in .github/workflows/)
test_if_field_targets_workflows() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    if echo "$if_value" | grep -qF '.github/workflows/'; then
        pass "if field targets .github/workflows/ files"
    else
        fail "if field should target .github/workflows/ files, got: $if_value"
    fi
}

# Test: CLI template settings.json also has if field
test_template_settings_has_if_field() {
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$template")
    if [ -n "$if_value" ]; then
        pass "CLI template settings.json PreToolUse hook has 'if' field"
    else
        fail "CLI template settings.json should have 'if' field matching repo settings"
    fi
}

# Test: Wizard doc documents the if field
test_wizard_documents_if_field() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -q '"if"' "$wizard" || grep -q '`if`.*field\|`if`.*hook\|hook.*`if`' "$wizard"; then
        pass "Wizard doc documents the if field"
    else
        fail "Wizard doc should document the hook if field"
    fi
}

# Test: Wizard settings.json example includes if field
test_wizard_settings_example_has_if() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    # The settings.json code block in the wizard should show the if field
    if grep -q '"if":' "$wizard"; then
        pass "Wizard settings.json example includes if field"
    else
        fail "Wizard settings.json example should include the if field"
    fi
}

# Test: if field in repo settings matches template settings (parity)
test_if_field_parity() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local repo_if template_if
    repo_if=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    template_if=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$template")
    # Template uses /src/ pattern, repo uses .github/workflows/ — both should have if field
    # but values differ because repo is customized for this meta-project
    if [ -n "$repo_if" ] && [ -n "$template_if" ]; then
        pass "Both repo and template settings have if field (parity check)"
    else
        fail "Both repo ($repo_if) and template ($template_if) should have if field"
    fi
}

test_settings_has_if_field
test_if_field_targets_workflows
test_template_settings_has_if_field
test_wizard_documents_if_field
test_wizard_settings_example_has_if
test_if_field_parity

echo ""
echo "--- CWD walk-up tests (#171: monorepo / nested project support) ---"

# Test: Shared helper _find-sdlc-root.sh exists
test_find_sdlc_root_helper_exists() {
    if [ -f "$HOOKS_DIR/_find-sdlc-root.sh" ]; then
        pass "_find-sdlc-root.sh helper exists"
    else
        fail "_find-sdlc-root.sh helper not found (needed by sdlc-prompt-check + instructions-loaded-check)"
    fi
}

# Test: sdlc-prompt-check walks up from CWD to find nested SDLC.md
test_sdlc_hook_cwd_walkup_finds_nested() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Project at $tmpdir/project/, but CLAUDE_PROJECT_DIR is empty (simulates parent launch)
    mkdir -p "$tmpdir/project/src/components"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    local output
    # Run hook from deep inside the project — CWD walk should find SDLC.md
    output=$(cd "$tmpdir/project/src/components" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE" && ! echo "$output" | grep -q "SETUP NOT COMPLETE"; then
        pass "sdlc-prompt-check.sh walks up from CWD to find nested SDLC.md"
    else
        fail "sdlc-prompt-check.sh should walk up from CWD when CLAUDE_PROJECT_DIR is empty"
    fi
}

# Test: CWD walk-up prefers nearest SDLC.md (monorepo with per-package setup)
test_sdlc_hook_cwd_walkup_prefers_nearest() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Monorepo root has SDLC.md, but sub-package also has its own
    echo "# Root SDLC" > "$tmpdir/SDLC.md"
    echo "# Root Testing" > "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/packages/api/src"
    echo "# API SDLC" > "$tmpdir/packages/api/SDLC.md"
    echo "# API Testing" > "$tmpdir/packages/api/TESTING.md"
    local output
    # CWD is deep inside packages/api — should find packages/api/SDLC.md first
    output=$(cd "$tmpdir/packages/api/src" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh prefers nearest SDLC.md in monorepo"
    else
        fail "Should find nearest SDLC.md when multiple exist in ancestor chain"
    fi
}

# Test: Falls back to CLAUDE_PROJECT_DIR when CWD walk finds nothing
test_sdlc_hook_cwd_walkup_fallback() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # CWD has nothing — hook should exit silently (#173: no fallback to CLAUDE_PROJECT_DIR)
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "sdlc-prompt-check.sh exits silently when CWD walk finds no SDLC project"
    else
        fail "Should exit silently when CWD walk finds nothing, got: $(echo "$output" | head -1)"
    fi
}

# Test: instructions-loaded-check also walks up from CWD
test_instructions_hook_cwd_walkup() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/project/src"
    # Use the CURRENT wizard version from package.json so the staleness nudge
    # (≥3 minor behind = loud warning) never fires. Version drift between
    # test fixture + current release was a foot-gun pre-fix (the loud nudge
    # contains "missing" which spuriously triggered the negative grep below).
    local current_version
    current_version=$(grep -oE '"version":\s*"[0-9.]+"' "$SCRIPT_DIR/../package.json" | grep -oE '[0-9.]+')
    echo "<!-- SDLC Harness Version: ${current_version} -->" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    # Mock npm/claude/codex to prevent version check output
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    # Isolate HOME so the user's ~/.cache/sdlc-wizard/latest-version cache
    # doesn't poison the staleness check (real-world bug: a stale 1.73.0
    # cache makes a 1.43.0 install look "30 releases behind" and the loud
    # nudge fires, breaking the negative-grep below).
    output=$(cd "$tmpdir/project/src" && PATH="$tmpdir/bin:$PATH" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ] || ! echo "$output" | grep -qi "missing"; then
        pass "instructions-loaded-check.sh walks up from CWD (no false warning)"
    else
        fail "instructions-loaded-check.sh should walk up from CWD, got: $output"
    fi
}

# Test: CWD walk-up with empty SDLC.md still triggers setup (non-empty check preserved)
test_sdlc_hook_cwd_walkup_empty_stubs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/project/src"
    touch "$tmpdir/project/SDLC.md"   # empty
    touch "$tmpdir/project/TESTING.md" # empty
    local output
    output=$(cd "$tmpdir/project/src" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "claude-setup-wizard"; then
        pass "CWD walk-up still triggers setup for empty stub files"
    else
        fail "Empty stubs found by CWD walk should still trigger claude-setup-wizard"
    fi
}

# Test: Non-SDLC directory — hooks silent when walk-up finds nothing (#173)
test_sdlc_hook_silent_non_sdlc_dir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # CWD has no SDLC.md anywhere up to $HOME, CLAUDE_PROJECT_DIR unset
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "sdlc-prompt-check.sh silent in non-SDLC directory (#173)"
    else
        fail "sdlc-prompt-check.sh should be silent in non-SDLC dir, got: $(echo "$output" | head -1)"
    fi
}

# Test: instructions-loaded-check silent in non-SDLC directory (#173)
test_instructions_hook_silent_non_sdlc_dir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent in non-SDLC directory (#173)"
    else
        fail "instructions-loaded-check.sh should be silent in non-SDLC dir, got: $(echo "$output" | head -1)"
    fi
}

test_find_sdlc_root_helper_exists
test_sdlc_hook_cwd_walkup_finds_nested
test_sdlc_hook_cwd_walkup_prefers_nearest
test_sdlc_hook_cwd_walkup_fallback
test_instructions_hook_cwd_walkup
test_sdlc_hook_cwd_walkup_empty_stubs
test_sdlc_hook_silent_non_sdlc_dir
test_instructions_hook_silent_non_sdlc_dir

echo ""
echo "--- Model/effort upgrade detection (#179) ---"

# Test: model-effort-check.sh exists and is executable
test_model_effort_check_exists() {
    if [ -x "$HOOKS_DIR/model-effort-check.sh" ]; then
        pass "model-effort-check.sh exists and is executable"
    else
        fail "model-effort-check.sh not found or not executable"
    fi
}

# #236(b): unset (no env var, no settings.json entry anywhere) is CC's own
# current default, not a problem state — the hook used to loud-warn on it
# every single session start regardless. Only an EXPLICITLY set low-effort
# value (or the settings-only-max quirk, tested separately) should warn now.
test_model_effort_check_silent_on_unset() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "model-effort-check.sh silent on unset effort (no env var, no settings entry)"
    else
        fail "model-effort-check.sh should be silent on unset effort, got: $output"
    fi
}

# Test: detects genuinely stale (below-floor) effort and outputs upgrade nudge
# with model recommendation. The nudge must name the wizard's recommended
# model alias so the command is copy-pasteable.
# #440: `medium` is Sonnet 5's documented default (CodeRabbit-tested) — the
# hook must not nag users for following the wizard's own recommendation.
# Only an EXPLICITLY set `low` should still warn (#236(b): unset itself no
# longer warns, tested above).
test_model_effort_check_medium_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"medium"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "#440: model-effort-check.sh is silent on medium (Sonnet 5 documented default)"
    else
        fail "#440: medium should be silent (wizard's own recommended default), got: $output"
    fi
}

test_model_effort_check_stale_effort() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"low"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '/effort' \
        && echo "$output" | grep -q 'WARNING' \
        && echo "$output" | grep -qF 'opusplan'; then
        pass "model-effort-check.sh warns on effort=low (below the medium floor)"
    else
        fail "model-effort-check.sh should warn on effort=low, got: $output"
    fi
}

# #430 regression: RECOMMENDED_MODEL(S) once hardcoded a stray "[1m]" fragment
# (a broken ANSI-bold escape missing its leading \e) that printed as literal
# text in the SessionStart warning. Already dead by unrelated evolution
# (#403's multi-model string, then #440's medium-floor rewrite) — this locks
# it so nothing can reintroduce the artifact.
test_model_effort_check_no_stray_ansi_artifact() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"low"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! printf '%s' "$output" | grep -qF '[1m]'; then
        pass "#430: no stray [1m] ANSI-escape artifact in the model warning"
    else
        fail "#430: warning output contains a literal [1m] artifact: $output"
    fi
}

# Test: high is silent — it's Sonnet 5's and Fable's tested default (v1.84.0)
test_model_effort_check_high_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "v1.84.0: model-effort-check.sh is silent on high (Sonnet 5/Fable tested default)"
    else
        fail "v1.84.0: high should be silent (acceptable floor), got: $output"
    fi
}

# Test: xhigh is silent — Opus 4.8's floor, and Sonnet 5's escalation level (#434)
test_model_effort_check_xhigh_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"xhigh"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "#434: model-effort-check.sh is silent on xhigh (Opus 4.8 floor, Sonnet 5 escalation level)"
    else
        fail "#434: xhigh should be silent (acceptable floor), got: $output"
    fi
}

# Same as above but via env var (the persisted path)
test_model_effort_check_xhigh_env_var_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="xhigh" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "#434: CLAUDE_CODE_EFFORT_LEVEL=xhigh is silent (acceptable floor)"
    else
        fail "#434: env var xhigh should be silent, got: $output"
    fi
}

# RECOMMENDED_MODELS must include Sonnet 5 — it's Setup B's driver
# (Simple/One-Off lane; Opus 5 is Setup A's default as of 2026-07-24).
test_model_effort_check_recommends_sonnet_5() {
    if grep -qi 'sonnet' "$HOOKS_DIR/model-effort-check.sh"; then
        pass "#434: model-effort-check.sh recommends Sonnet 5 (Setup B driver)"
    else
        fail "#434: model-effort-check.sh must mention Sonnet in RECOMMENDED_MODELS"
    fi
}

# The hook must NOT blanket-recommend persisting max via a shell-rc env var.
# That advice bit a real user: CLAUDE_CODE_EFFORT_LEVEL=max in .zshrc silently
# overrode /effort xhigh after switching from Opus 4.6 to Sonnet 5. The hook
# should point to model-aware guidance instead of a one-size-fits-all env var.
test_model_effort_check_no_blanket_max_persist_advice() {
    if grep -qE 'CLAUDE_CODE_EFFORT_LEVEL=max in settings env block' "$HOOKS_DIR/model-effort-check.sh"; then
        fail "#434: hook must not blanket-recommend persisting max via env var — see AI_SETUP_LANES.md instead"
    else
        pass "#434: hook does not blanket-recommend persisting max via env var"
    fi
}

# Test: graceful when no JSON stdin (non-blocking)
test_model_effort_check_no_stdin() {
    local exit_code
    echo "" | CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" > /dev/null 2>&1
    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "model-effort-check.sh exits 0 when stdin is empty"
    else
        fail "model-effort-check.sh should exit 0 on empty stdin, got exit $exit_code"
    fi
}

# Test: settings.json has SessionStart hook wired
test_settings_has_session_start_hook() {
    local SETTINGS="$SCRIPT_DIR/../.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then fail "settings.json not found"; return; fi
    if grep -q '"SessionStart"' "$SETTINGS" && grep -q 'model-effort-check.sh' "$SETTINGS"; then
        pass "settings.json wires SessionStart hook to model-effort-check.sh"
    else
        fail "settings.json should have SessionStart hook for model-effort-check.sh"
    fi
}

# Test: nested CWD uses CLAUDE_PROJECT_DIR for settings (Codex P0 fix)
# Uses "low" (below the medium floor) so the hook still warns — "medium" is
# now silent (#440), which would defeat this test's purpose.
test_model_effort_check_nested_cwd() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude" "$tmpdir/src/deep"
    echo '{"effortLevel":"low"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(cd "$tmpdir/src/deep" && echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="/nonexistent" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '/effort'; then
        pass "model-effort-check.sh finds project settings via CLAUDE_PROJECT_DIR from nested CWD"
    else
        fail "model-effort-check.sh should find project settings from nested CWD, got: $output"
    fi
}

# Test: env var overrides settings — local settings high + env var max = silent
test_model_effort_check_env_overrides_settings() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="/nonexistent" CLAUDE_CODE_EFFORT_LEVEL="max" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "model-effort-check.sh env var max overrides settings high (silent)"
    else
        fail "model-effort-check.sh env var max should override settings, got: $output"
    fi
}

# Test: effort=max is silent (preferred; above the floor, no nudge needed)
# Per ROADMAP #217: xhigh is the floor, max is preferred. Anything at-or-above the
# floor should produce no output.
# effortLevel: max in settings WITHOUT env var → NOTE (CC ignores it)
test_model_effort_check_max_settings_warns_persistence() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"max"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "WARNING"; then
        pass "#395: effortLevel:max in settings triggers WARNING (CC ignores it there)"
    else
        fail "#395: settings-only max should trigger WARNING, got: $output"
    fi
}

# env var CLAUDE_CODE_EFFORT_LEVEL=max → truly silent (correctly persisted)
test_model_effort_check_max_env_var_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="max" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "#395: CLAUDE_CODE_EFFORT_LEVEL=max is truly silent (correctly persisted)"
    else
        fail "#395: env var max should be silent, got: $output"
    fi
}

# Test: below-high produces LOUD warning mentioning SDLC compliance + /effort xhigh
# Per v1.84.0: high is now an acceptable floor too (Sonnet 5's/Fable's tested
# default, see test_model_effort_check_high_silent) — only medium/low should
# still warn. max is the Opus 4.6 sweet spot; blanket-recommending max
# regressed on Sonnet 5/Opus 4.8. Hook must produce a distinguishable WARNING
# that recommends /effort xhigh (not just the soft "upgrade available" nudge).
test_model_effort_check_below_xhigh_loud_warning() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fails=0
    # #440: medium is now silent (Sonnet 5's documented default) — only low warns
    for bad_effort in low; do
        mkdir -p "$tmpdir/.claude"
        echo "{\"effortLevel\":\"$bad_effort\"}" > "$tmpdir/.claude/settings.json"
        local output
        output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
        # Must contain: WARNING marker, SDLC mention, explicit /effort recommendation
        if ! echo "$output" | grep -q 'WARNING'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing WARNING marker: $output" >&2
        fi
        if ! echo "$output" | grep -qi 'SDLC'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing SDLC mention: $output" >&2
        fi
        if ! echo "$output" | grep -q '/effort'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing '/effort' recommendation: $output" >&2
        fi
        rm -rf "$tmpdir/.claude"
    done
    rm -rf "$tmpdir"
    if [ "$fails" -eq 0 ]; then
        pass "model-effort-check.sh produces LOUD WARNING + SDLC + /effort recommendation for low"
    else
        fail "model-effort-check.sh LOUD warning has $fails missing markers for low"
    fi
}

# Regression test (ROADMAP #217): instructions-loaded-check.sh must NOT emit its
# own effort/model nudge. The duplicate check used the old xhigh-as-recommended
# logic, so effort=max produced a false "Upgrade available" nudge. Single source
# of truth is hooks/model-effort-check.sh.
test_instructions_loaded_no_duplicate_effort_nudge() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Effort=max should be silent; the duplicate in instructions-loaded used to
    # flag it as needing upgrade to xhigh, which is backwards post-#217.
    echo '{"effortLevel":"max"}' > "$tmpdir/.claude/settings.json"
    # instructions-loaded-check needs SDLC.md to proceed past its own gate
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q 'Upgrade available: effort'; then
        fail "instructions-loaded-check.sh emitted stale 'Upgrade available: effort' nudge — should delegate to model-effort-check.sh (#217)"
    elif echo "$output" | grep -q 'effort.*→.*xhigh'; then
        fail "instructions-loaded-check.sh recommends xhigh — stale per #217 (max is preferred, xhigh is floor)"
    else
        pass "instructions-loaded-check.sh does not duplicate effort/model nudge (delegated to model-effort-check.sh per #217)"
    fi
}

test_model_effort_check_exists
test_model_effort_check_silent_on_unset
test_model_effort_check_medium_silent
test_model_effort_check_stale_effort
test_model_effort_check_no_stray_ansi_artifact
test_model_effort_check_high_silent
test_model_effort_check_xhigh_silent
test_model_effort_check_xhigh_env_var_silent
test_model_effort_check_recommends_sonnet_5
test_model_effort_check_no_blanket_max_persist_advice
test_model_effort_check_max_settings_warns_persistence
test_model_effort_check_max_env_var_silent
test_model_effort_check_below_xhigh_loud_warning
test_model_effort_check_no_stdin
test_settings_has_session_start_hook
test_model_effort_check_nested_cwd
test_model_effort_check_env_overrides_settings
test_instructions_loaded_no_duplicate_effort_nudge

# #395: CLAUDE_CODE_EFFORT_LEVEL env var takes precedence over effortLevel in settings
test_model_effort_env_var_takes_precedence() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"low"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" CLAUDE_CODE_EFFORT_LEVEL="max" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "#395: CLAUDE_CODE_EFFORT_LEVEL=max overrides effortLevel=low in settings (silent)"
    else
        fail "#395: env var should take precedence over settings, got: $output"
    fi
}

test_model_effort_env_var_takes_precedence

# ROADMAP token-bloat audit: prevent 2× per-prompt hook print when both
# project (.claude/settings.json) and plugin (hooks.json) register the same
# hook (e.g., the wizard's own dogfood + locally-installed plugin).
# Helper: dedupe_plugin_or_project — plugin invocation yields if project also
# registers the same hook. Project always wins; consumer plugin-only installs
# still fire normally.
test_dedupe_plugin_yields_to_project() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"$CLAUDE_PROJECT_DIR/hooks/sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        fail "plugin invocation should yield (return 1) when project settings.json registers same hook"
    else
        pass "plugin invocation yields to project registration (no double-print)"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_plugin_proceeds_when_no_project_registration() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # No .claude/settings.json — consumer plugin-only install
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "plugin proceeds when no project settings.json (consumer plugin-only)"
    else
        fail "plugin should proceed when no project registration exists"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_plugin_proceeds_when_project_settings_unrelated() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Project settings.json exists but doesn't register THIS hook
    echo '{"hooks":{"PostToolUse":[{"hooks":[{"command":"some-other-hook.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "plugin proceeds when project settings exists but doesn't register this hook"
    else
        fail "plugin should proceed when project settings doesn't reference this hook by name"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_project_invocation_always_proceeds() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local non_plugin_path="/Users/somebody/myrepo/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$non_plugin_path" "$tmpdir"; then
        pass "project (non-plugin) invocation always proceeds regardless of settings"
    else
        fail "non-plugin invocation should never yield"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_recognizes_plugins_cache_path() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    # Marketplace install path uses /plugins/cache/ instead of /plugins-local/
    local fake_cache_path="/Users/somebody/.claude/plugins/cache/sdlc-wizard-local/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_cache_path" "$tmpdir"; then
        fail "marketplace plugin path (/plugins/cache/) should also yield"
    else
        pass "marketplace plugin path (/plugins/cache/) yields to project"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-001 regression (Codex round 1): helper must not depend on `basename`.
# Uses parameter expansion so it survives PATH-restricted test environments.
test_dedupe_works_with_path_restricted() {
    # Static-analysis test (Codex DEDUPE-001): the dedupe helper must NOT call
    # external `basename` — it must use parameter expansion `${path##*/}`.
    # Direct PATH-restriction simulation is unreliable on macOS (Gatekeeper
    # kills cp'd /usr/bin/grep), so we verify the property statically: the
    # helper's source code uses parameter expansion and contains no basename.
    local helper="$HOOKS_DIR/_find-sdlc-root.sh"
    local fails=0
    # Match a basename invocation in CODE (not in comments): grep non-comment
    # lines for `$(basename` or backtick-basename subshell forms.
    if /usr/bin/grep -vE '^\s*#' "$helper" | /usr/bin/grep -qE '\$\(basename|`basename' 2>/dev/null; then
        fails=$((fails + 1))
        echo "  helper still calls external 'basename' command" >&2
    fi
    if ! /usr/bin/grep -q 'script_path##\*/' "$helper" 2>/dev/null; then
        fails=$((fails + 1))
        echo "  helper missing parameter-expansion form '\${script_path##*/}'" >&2
    fi
    if [ "$fails" -eq 0 ]; then
        pass "dedupe helper uses parameter expansion, no external 'basename' (PATH-restricted safe)"
    else
        fail "dedupe helper has $fails parameter-expansion regressions (#DEDUPE-001)"
    fi
}

# DEDUPE-002 regression (Codex round 1): script-name match must be scoped to
# `"command"` JSON entries, not anywhere in settings.json. Otherwise a hook
# basename appearing in `permissions.allow` falsely triggers yield.
test_dedupe_does_not_match_basename_in_permissions() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # settings.json mentions "sdlc-prompt-check.sh" only in permissions.allow,
    # NOT in any hook command registration.
    cat > "$tmpdir/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(./hooks/sdlc-prompt-check.sh *)"]
  },
  "hooks": {
    "PostToolUse": [
      {"hooks": [{"command": "some-other-hook.sh"}]}
    ]
  }
}
JSON
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/x/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "dedupe ignores script name in permissions.allow (project does not register the hook)"
    else
        fail "dedupe falsely yielded — script name in permissions.allow should not count as registration"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-002 positive: still yields when the basename appears in a real
# `"command"` registration (the legitimate dual-install scenario).
test_dedupe_matches_command_field_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    cat > "$tmpdir/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {"hooks": [{"command": "$CLAUDE_PROJECT_DIR/hooks/sdlc-prompt-check.sh"}]}
    ]
  }
}
JSON
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/x/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        fail "dedupe should yield when basename appears in a hook \"command\" registration"
    else
        pass "dedupe matches \"command\" field correctly (legitimate dual-install yields)"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-003 regression: hook scripts must source helper correctly even when
# invoked directly from the hooks/ directory (BASH_SOURCE[0] has no slash).
test_dedupe_hook_direct_invocation_no_slash() {
    # Run sdlc-prompt-check.sh via bash from inside hooks/ where BASH_SOURCE[0]
    # is just the filename — the no-slash fallback to "." must source helper.
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local rc=0 stderr_out
    stderr_out=$(cd "$HOOKS_DIR" && CLAUDE_PROJECT_DIR="$tmpdir" bash -c './sdlc-prompt-check.sh </dev/null' 2>&1) || rc=$?
    rm -rf "$tmpdir"
    # Expect rc=0 AND no "No such file or directory" for _find-sdlc-root.sh
    if [ "$rc" -eq 0 ] && ! echo "$stderr_out" | grep -q 'No such file'; then
        pass "hook handles direct invocation with no-slash BASH_SOURCE (sources helper via . fallback)"
    else
        fail "hook failed direct invocation (rc=$rc, stderr='$stderr_out')"
    fi
}

test_dedupe_plugin_yields_to_project
test_dedupe_plugin_proceeds_when_no_project_registration
test_dedupe_plugin_proceeds_when_project_settings_unrelated
test_dedupe_project_invocation_always_proceeds
test_dedupe_recognizes_plugins_cache_path
test_dedupe_works_with_path_restricted
test_dedupe_does_not_match_basename_in_permissions
test_dedupe_matches_command_field_only
test_dedupe_hook_direct_invocation_no_slash

echo ""
echo "--- SDLC enforcement gap audit ---"
test_todowrite_has_capture_learnings
test_todowrite_has_scope_guard
test_todowrite_has_deploy_tasks
test_todowrite_has_new_pattern_check
test_todowrite_has_legacy_delete_check
test_enforcement_coverage_score

echo ""
echo "--- Dual-channel install drift guardrails (#181) ---"

# Helper: create a fake project + fake HOME with plugin install path
prepare_dual_install_fixture() {
    local tmpdir="$1"
    local plugin_which="$2"  # "local", "cache", "both", or "none"
    local has_cli_skills="$3"  # "yes" or "no"
    mkdir -p "$tmpdir/project"
    touch "$tmpdir/project/SDLC.md"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    if [ "$has_cli_skills" = "yes" ]; then
        mkdir -p "$tmpdir/project/.claude/skills/update"
        echo "# Update skill" > "$tmpdir/project/.claude/skills/update/SKILL.md"
    fi
    mkdir -p "$tmpdir/.claude"
    if [ "$plugin_which" = "local" ] || [ "$plugin_which" = "both" ]; then
        mkdir -p "$tmpdir/.claude/plugins-local/sdlc-wizard-wrap"
    fi
    if [ "$plugin_which" = "cache" ] || [ "$plugin_which" = "both" ]; then
        mkdir -p "$tmpdir/.claude/plugins/cache/sdlc-wizard-local"
    fi
    # Mock npm/claude/codex so version/update checks are silent
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
}

# Test: hook emits dual-install nudge when BOTH CLI skills and plugin paths exist
test_instructions_hook_dual_install_nudge_local() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "local" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "dual-install\|both channels\|plugin.*and.*CLI\|CLI.*and.*plugin\|pick one"; then
        pass "instructions-loaded-check.sh emits dual-install nudge (plugins-local)"
    else
        fail "Should emit dual-install nudge when CLI skills + plugins-local present, got: $output"
    fi
}

# Test: hook emits dual-install nudge when plugin cache path exists
test_instructions_hook_dual_install_nudge_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "cache" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "dual-install\|both channels\|plugin.*and.*CLI\|CLI.*and.*plugin\|pick one"; then
        pass "instructions-loaded-check.sh emits dual-install nudge (plugins cache)"
    else
        fail "Should emit dual-install nudge when CLI skills + plugin cache present, got: $output"
    fi
}

# Test: hook silent when only plugin installed (no CLI skills in project)
test_instructions_hook_silent_plugin_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "no"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "instructions-loaded-check.sh silent when plugin-only (no CLI skills)"
    else
        fail "Should NOT emit dual-install nudge when only plugin present, got: $output"
    fi
}

# Test: hook silent when only CLI skills installed (no plugin paths)
test_instructions_hook_silent_cli_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "none" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "instructions-loaded-check.sh silent when CLI-only (no plugin paths)"
    else
        fail "Should NOT emit dual-install nudge when only CLI skills present, got: $output"
    fi
}

# Test: dual-install nudge is non-blocking (exit 0)
test_instructions_hook_dual_install_non_blocking() {
    local tmpdir exit_code
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    (cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh") > /dev/null 2>&1
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "instructions-loaded-check.sh dual-install nudge is non-blocking (exit 0)"
    else
        fail "Hook should exit 0 even with dual-install nudge (exit=$exit_code)"
    fi
}

# Test (#238): dual-channel nudge stays silent when the user has explicitly
# acknowledged the dual-install setup via a sentinel file. Without this
# silence mechanism, the warning fires on every SessionStart and trains
# users to ignore all hook output — including legit signals.
test_instructions_hook_dual_install_silenced_by_ack_sentinel() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # User acknowledged the dual-install setup
    mkdir -p "$tmpdir/cache"
    touch "$tmpdir/cache/dual-channel-acknowledged"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "#238: dual-install nudge silenced by ack sentinel"
    else
        fail "#238: ack sentinel should silence dual-install nudge, got: $output"
    fi
}

# Test (#238): mention the silence mechanism in the dual-install nudge so
# users know how to acknowledge it (otherwise the sentinel is undiscoverable).
test_instructions_hook_dual_install_nudge_mentions_silence() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # No sentinel — nudge should fire and reference the silence path
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'dual-channel-acknowledged|silence.*nudge|to silence|acknowledge'; then
        pass "#238: dual-install nudge mentions how to silence it"
    else
        fail "#238: nudge should reference the ack sentinel path, got: $output"
    fi
}

# Test (#238 Codex finding 1): the printed silence hint must work even when
# the cache dir doesn't exist yet (fresh install on a new host has no
# ~/.cache/sdlc-wizard/ until something creates it). Plain `touch <path>`
# fails with "No such file or directory" when the parent dir is missing.
test_instructions_hook_dual_install_silence_hint_works_when_cache_dir_absent() {
    local tmpdir nudge ack_cmd
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # Deliberately do NOT create $tmpdir/cache — simulate fresh install
    if [ -d "$tmpdir/cache" ]; then
        rm -rf "$tmpdir/cache"
    fi
    nudge=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    # Extract the line that contains the ack command. The hint must be
    # actionable: running the printed command should succeed even with
    # a missing cache dir.
    ack_cmd=$(echo "$nudge" | grep -E 'Keep both' | sed 's/.*Keep both:[[:space:]]*//;s/[[:space:]]*(silences.*$//')
    if [ -z "$ack_cmd" ]; then
        fail "#238 Codex#1: no 'Keep both' silence hint in nudge output"
        rm -rf "$tmpdir"
        return
    fi
    # Run the suggested command. If it fails (e.g. cache dir missing),
    # the hint is broken.
    bash -c "$ack_cmd" 2>/dev/null
    local rc=$?
    if [ "$rc" -eq 0 ] && [ -f "$tmpdir/cache/dual-channel-acknowledged" ]; then
        pass "#238 Codex#1: silence hint works even with missing cache dir"
    else
        fail "#238 Codex#1: printed silence command failed (rc=$rc) — hint should mkdir -p first. Cmd: $ack_cmd"
    fi
    rm -rf "$tmpdir"
}

test_instructions_hook_dual_install_nudge_local
test_instructions_hook_dual_install_nudge_cache
test_instructions_hook_silent_plugin_only
test_instructions_hook_silent_cli_only
test_instructions_hook_dual_install_non_blocking
test_instructions_hook_dual_install_silenced_by_ack_sentinel
test_instructions_hook_dual_install_nudge_mentions_silence
test_instructions_hook_dual_install_silence_hint_works_when_cache_dir_absent

# Test (#207): when settings.json has BOTH `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
# AND `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, the hook must warn about the
# compound misconfiguration. Setting both compounds (e.g. 30% × 400K = 120K
# trigger, which is ~12% of a 1M window) — a docs footgun the consumer
# (issue #207) hit in practice when autocompact fired at 12% context.
test_instructions_hook_warns_on_autocompact_compound_misconfig() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "model": "opus[1m]",
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    echo "$output" | grep -qiE 'autocompact|AUTOCOMPACT' || ok=false
    echo "$output" | grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' || ok=false
    echo "$output" | grep -q 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' || ok=false
    echo "$output" | grep -qE 'compound|combined|both|alternative|pick one|either' || ok=false
    if [ "$ok" = true ]; then
        pass "#207: warns when settings.json has both PCT_OVERRIDE + AUTO_COMPACT_WINDOW"
    else
        fail "#207: expected compound-misconfig warning, got: $output"
    fi
}

test_instructions_hook_silent_on_single_autocompact_pct_only() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'autocompact.*compound|both.*autocompact|PCT_OVERRIDE.*AUTO_COMPACT_WINDOW'; then
        fail "#207: should not warn when only PCT_OVERRIDE is set, got: $output"
    else
        pass "#207: silent when only PCT_OVERRIDE is set (single-knob)"
    fi
}

test_instructions_hook_silent_on_single_autocompact_window_only() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'autocompact.*compound|both.*autocompact|PCT_OVERRIDE.*AUTO_COMPACT_WINDOW'; then
        fail "#207: should not warn when only AUTO_COMPACT_WINDOW is set, got: $output"
    else
        pass "#207: silent when only AUTO_COMPACT_WINDOW is set (single-knob)"
    fi
}

# #207: warning shows effective compound trigger (30% × 400K = 120K) so user
# can diagnose impact from the warning alone.
test_instructions_hook_compound_warning_shows_effective_trigger() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE '120000|120[Kk]|120,000'; then
        pass "#207: warning shows effective compound trigger (120K = 30% × 400K)"
    else
        fail "#207: expected effective trigger (120K) in warning, got: $output"
    fi
}

# --- GH #520: the compound check was aimed at the wrong signature -----------
#
# Verified against decompiled Claude Code v2.1.221 (functions EX, CCo, F0s, ZJu,
# fEe, kO), recorded on GH #520:
#
#   window    = min(model_window, clamp(WINDOW_env, 100000..1000000))    [EX]
#   threshold = min(floor(window x pct/100), window - 13000)             [CCo]
#   ...with up to 20000 tokens of system overhead subtracted first       [fEe]
#
# Two consequences the original #207 check gets wrong:
#
#  1. Setting both vars is ARITHMETIC, not a misconfiguration. 35% of a 1M
#     window is a ~350K trigger, which is a perfectly sane deliberate choice
#     (the maintainer runs it for context-quality reasons, GH #483). The old
#     check warned on it, so the hook was firing on a working config — and the
#     only configuration empirically proven to compact early on a local 1M
#     Opus session at that.
#
#  2. The genuinely dangerous setting was invisible to it: ZJu returns false
#     unconditionally for any window below bIe = 200000, so WINDOW in the
#     100000..199999 range SILENTLY DISABLES autocompact altogether. A consumer
#     trying to be conservative by picking a small window gets no autocompact
#     at all, and nothing told them.
#
# So the signature is not "both set" — it is "the effective trigger is below
# 200000", whichever vars produced it. These three assertions pin that.

_autocompact_hook_output() {
    # $1 = the JSON body of the settings "env" block.
    local tmpdir output env_body="$1"
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin" "$tmpdir/home"
    printf '{\n  "env": {\n%s\n  }\n}\n' "$env_body" > "$tmpdir/.claude/settings.json"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" \
        HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" \
        "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    printf '%s' "$output"
}

# A window under 200000 makes compaction fire SOONER. The hook used to call
# this DISABLED and tell the consumer to raise it — advice that moved the
# trigger later for someone whose config was already doing what they wanted.
# The word "disabl" is now a FAILURE condition, not a requirement.
test_instructions_hook_reports_sub_200k_window_fires_sooner() {
    local output
    output=$(_autocompact_hook_output '    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "150000"')
    local ok=true
    echo "$output" | grep -q 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' || ok=false
    echo "$output" | grep -qiE 'disabl' && ok=false
    echo "$output" | grep -qiE 'sooner|earlier' || ok=false
    # 150000 - 20000 overhead - 13000 cap = 117000
    echo "$output" | grep -qE '\b117000\b' || ok=false
    if [ "$ok" = true ]; then
        pass "#520: reports that a sub-200000 window compacts sooner, and names the trigger"
    else
        fail "#520: WINDOW=150000 makes compaction fire at 117000, not disabled — hook must say so without the word 'disabled', got: $output"
    fi
}

# The false positive. 35% x 1000000 = 350000, well above the 200000 floor.
# This is the config that actually works on a local 1M Opus session, and the
# hook used to call it a misconfig.
test_instructions_hook_silent_on_deliberate_large_compound_trigger() {
    local output
    output=$(_autocompact_hook_output '    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "35",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"')
    if echo "$output" | grep -qiE 'misconfig|WARNING: autocompact'; then
        fail "#520: 35% x 1000000 = 350000 is a deliberate, working config — the hook must not call it a misconfig, got: $output"
    else
        pass "#520: silent on a compound trigger that lands above the 200000 floor"
    fi
}

# Same input, the other half of the claim. The hook cannot know which model
# will run, but it CAN evaluate the same formula at 200000 and print that as a
# number. It used to print a ratio instead — "roughly a third" — which is wrong
# here: 35% x 1000000 reports 350000, and a 200K model yields 70000, a fifth.
# Cross-model review flagged that a wrong ratio next to "not an error" approves
# a 70000 trigger. So: the exact figure must appear, and no approving verdict.
test_instructions_hook_reports_the_200k_model_figure_not_a_ratio() {
    local output
    output=$(_autocompact_hook_output '    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "35",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "1000000"')
    local ok=true
    echo "$output" | grep -qE 'NOTE: autocompact fires at 350000' || ok=false
    echo "$output" | grep -qE '\b70000\b' || ok=false
    # The verdict language is the defect, not just the ratio. "not an error"
    # sanctioned a trigger the hook had mis-stated by a factor of ~1.7.
    echo "$output" | grep -qiE 'not an error|roughly a third' && ok=false
    if [ "$ok" = true ]; then
        pass "#520: reports the computed 200K-model trigger (70000), not a ratio, and passes no verdict"
    else
        fail "#520: 35% x 1000000 must report 350000 AND the 200K figure 70000 with no approving verdict — got: $output"
    fi
}

# The regression guard: the real #207 case must still fire, because its
# effective trigger (120000) IS below the floor.
test_instructions_hook_still_warns_when_compound_trigger_below_floor() {
    local output
    output=$(_autocompact_hook_output '    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"')
    local ok=true
    # Must be the WARNING form specifically. An earlier version of this
    # assertion only required "autocompact" + "120000", which the NOTE branch
    # also satisfies — so raising AC_FLOOR silently downgraded a real warning
    # to an approving note and this test stayed green. Caught by mutation.
    echo "$output" | grep -qE 'WARNING: autocompact fires at' || ok=false
    echo "$output" | grep -qE '120000|120[Kk]' || ok=false
    if [ "$ok" = true ]; then
        pass "#520: still WARNS (not merely notes) on the original #207 case — 120000 is below the floor"
    else
        fail "#520: 30% x 400000 = 120000 must produce a WARNING, not a NOTE, got: $output"
    fi
}

test_instructions_hook_warns_on_autocompact_compound_misconfig
test_instructions_hook_silent_on_single_autocompact_pct_only
test_instructions_hook_silent_on_single_autocompact_window_only
test_instructions_hook_compound_warning_shows_effective_trigger
# The window is clamped to 100000..1000000 before the percentage is applied
# (EX). Multiplying the RAW setting overstates the trigger: 15% of a stated
# 2000000 looks like 300000 and would be waved through, but the clamp caps the
# window at 1000000, so the real trigger is 150000 — below the floor, and
# exactly the early-compaction surprise this check exists to catch. Found by
# cross-model review after the first version of the fix shipped the raw product.
test_instructions_hook_clamps_oversized_window_before_multiplying() {
    local output
    output=$(_autocompact_hook_output '    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "15",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "2000000"')
    local ok=true
    echo "$output" | grep -qE 'WARNING: autocompact fires at' || ok=false
    echo "$output" | grep -qE '150000' || ok=false
    if [ "$ok" = true ]; then
        pass "#520: clamps a 2000000 window to 1000000 before multiplying (150000, not 300000)"
    else
        fail "#520: 15% of a window clamped to 1000000 is 150000 and must WARN — got: $output"
    fi
}

# The live env governs the session; settings.json is only a CLAIM about it.
# The #520 incident was exactly that gap — the value came from the user's
# GLOBAL settings, so the project file showed nothing while the session ran on
# an inherited override. A hook is a child process and inherits exported vars,
# so it can and must read them. This fixture sets a disable-trap value in the
# env while settings.json holds a perfectly sane one: the env must win.
test_instructions_hook_prefers_live_env_over_settings_file() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Harness Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin" "$tmpdir/home"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" \
        HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" \
        CLAUDE_CODE_AUTO_COMPACT_WINDOW="150000" \
        "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    echo "$output" | grep -qE 'NOTE: CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000' || ok=false
    echo "$output" | grep -qi 'sooner' || ok=false
    echo "$output" | grep -qi 'live environment' || ok=false
    if [ "$ok" = true ]; then
        pass "#520: reads the live env over settings.json, and names which it used"
    else
        fail "#520: env WINDOW=150000 must win over settings.json's 400000 — got: $output"
    fi
}

test_instructions_hook_reports_sub_200k_window_fires_sooner
test_instructions_hook_silent_on_deliberate_large_compound_trigger
test_instructions_hook_reports_the_200k_model_figure_not_a_ratio
test_instructions_hook_still_warns_when_compound_trigger_below_floor
test_instructions_hook_clamps_oversized_window_before_multiplying
test_instructions_hook_prefers_live_env_over_settings_file

echo ""
echo "--- CC release review nudge (#85) ---"

# Helper: fixture with weekly-update.yml + mocked gh returning configurable PR count
prepare_cc_update_fixture() {
    local tmpdir="$1"
    local pr_count="$2"       # integer — count returned by mocked gh
    local has_workflow="$3"   # "yes" or "no"
    mkdir -p "$tmpdir/project"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    if [ "$has_workflow" = "yes" ]; then
        mkdir -p "$tmpdir/project/.github/workflows"
        echo "name: Weekly Update" > "$tmpdir/project/.github/workflows/weekly-update.yml"
    fi
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    # Mock gh: returns pr_count when asked for auto-update PRs, empty otherwise
    cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
# Look at full args — distinguish 'pr list ... auto-update' from other calls
for arg in "\$@"; do
    if [ "\$arg" = "auto-update" ]; then
        echo "$pr_count"
        exit 0
    fi
    if [ "\$arg" = "api-review-needed" ]; then
        echo "0"
        exit 0
    fi
done
# Default: empty (keeps other gh calls quiet)
echo ""
exit 0
EOF
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex" "$tmpdir/bin/gh"
}

test_hook_queries_auto_update_label() {
    if grep -qF 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh"; then
        pass "hook queries for auto-update label"
    else
        fail "hook must check for open PRs with auto-update label (#85)"
    fi
}

test_hook_gates_cc_nudge_on_weekly_update_workflow() {
    # Mirror the api-review-needed gating pattern — only fire when the
    # detector workflow lives in this repo (not in consumer projects).
    if grep -B1 -A10 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh" | grep -q 'weekly-update.yml'; then
        pass "hook gates CC update nudge on weekly-update.yml presence"
    else
        fail "hook must gate auto-update nudge on .github/workflows/weekly-update.yml"
    fi
}

test_hook_guards_gh_for_cc_nudge() {
    if grep -B1 -A10 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh" | grep -q 'command -v gh'; then
        pass "hook guards on gh availability for CC nudge"
    else
        fail "hook must check 'command -v gh' before querying auto-update PRs"
    fi
}

test_hook_emits_cc_nudge_when_pending() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "2" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'Claude Code.*update.*pending|auto-update.*PR|CC.*release.*review'; then
        pass "hook emits CC update nudge when auto-update PRs open"
    else
        fail "Should emit nudge when gh reports open auto-update PR(s), got: $output"
    fi
}

test_hook_silent_when_no_pending_cc_updates() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "0" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'Claude Code.*update.*pending|auto-update.*PR|CC.*release.*review'; then
        fail "Should be silent when no open auto-update PRs, got: $output"
    else
        pass "hook silent when no auto-update PRs pending"
    fi
}

test_hook_silent_without_weekly_update_workflow() {
    # Consumer projects don't own the detector — don't pester them.
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "3" "no"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'auto-update.*PR|CC.*release.*review'; then
        fail "Consumer project without detector workflow shouldn't see upstream nudge, got: $output"
    else
        pass "hook silent without weekly-update.yml (consumer project)"
    fi
}

test_hook_queries_auto_update_label
test_hook_gates_cc_nudge_on_weekly_update_workflow
test_hook_guards_gh_for_cc_nudge
test_hook_emits_cc_nudge_when_pending
test_hook_silent_when_no_pending_cc_updates
test_hook_silent_without_weekly_update_workflow


# ---- codex-gate-check.sh tests ----
echo ""
echo "--- codex-gate-check.sh ---"

# #436 P0: the gate must actually DENY the tool call (exit 2), not just print
# scary text and exit 0. A PreToolUse hook only blocks Claude Code when it
# exits 2 with the reason on stderr — exit 0 always lets the command through
# regardless of what's echoed. This is the same bug class the codex gate
# exists to prevent (a safety check that looks real but doesn't act real).
test_codex_gate_blocks_commit_without_review() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir"
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: something\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) commit without review artifact"
    else
        fail "codex gate should exit 2 + mention cross-model review, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_allows_commit_with_certified_review() {
    local tmpdir head_sha
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && git commit -q --allow-empty -m init) > /dev/null 2>&1
    head_sha=$(cd "$tmpdir" && git rev-parse HEAD)
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"CERTIFIED","score":9,"commit_sha":"%s"}' "$head_sha" > "$tmpdir/.reviews/handoff.json"
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: something\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1)
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate allows (exit 0) commit with CERTIFIED review matching current HEAD"
    else
        fail "codex gate should exit 0 silent with CERTIFIED review matching HEAD, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_allows_commit_with_reviewed_status() {
    local tmpdir head_sha
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && git commit -q --allow-empty -m init) > /dev/null 2>&1
    head_sha=$(cd "$tmpdir" && git rev-parse HEAD)
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"REVIEWED","commit_sha":"%s"}' "$head_sha" > "$tmpdir/.reviews/handoff.json"
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: something\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1)
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate allows (exit 0) commit with REVIEWED status matching current HEAD"
    else
        fail "codex gate should exit 0 silent with REVIEWED review matching HEAD, got exit=$exit_code out: $out"
    fi
}

# ROADMAP #437: a CERTIFIED/REVIEWED handoff.json has no freshness check — any
# number of new commits can land after certification and still sail through
# the gate on the same stale status string. Proven live in the v1.84.0
# release: 2 real post-certification commits both passed the gate on a
# round-11 CERTIFIED handoff that never got re-issued. Fix: certification
# records commit_sha (HEAD at cert time); the gate compares it to current
# HEAD and treats a mismatch as stale. This allows exactly one commit after
# certification (HEAD still equals the recorded SHA at that commit's
# PreToolUse check) and blocks the next one until re-cert.
test_codex_gate_blocks_stale_certification_after_new_commit() {
    local tmpdir cert_sha
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && git commit -q --allow-empty -m init) > /dev/null 2>&1
    cert_sha=$(cd "$tmpdir" && git rev-parse HEAD)
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"CERTIFIED","commit_sha":"%s"}' "$cert_sha" > "$tmpdir/.reviews/handoff.json"
    # A commit lands after certification (simulates the real v1.84.0 incident:
    # a post-certification CI-shepherd fix committed without re-review).
    (cd "$tmpdir" && git commit -q --allow-empty -m "post-cert fix") > /dev/null 2>&1
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"another fix\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "stale"; then
        pass "codex gate BLOCKS (exit 2) a stale certification after a new commit landed"
    else
        fail "codex gate should exit 2 + mention staleness once HEAD has moved past the certified commit_sha, got exit=$exit_code out: $out"
    fi
}

# Missing commit_sha (an old-format handoff.json from before this fix) is
# treated as stale, not silently allowed — no legacy-compat fallback.
test_codex_gate_blocks_missing_commit_sha_as_stale() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && git commit -q --allow-empty -m init) > /dev/null 2>&1
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"CERTIFIED"}' > "$tmpdir/.reviews/handoff.json"
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: something\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "stale"; then
        pass "codex gate BLOCKS (exit 2) an old-format handoff.json with no commit_sha"
    else
        fail "codex gate should exit 2 + mention staleness when commit_sha is missing, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_silent_on_non_commit_commands() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git status"}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1)
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate silent + exit 0 on non-commit commands"
    else
        fail "codex gate should exit 0 silent on git status, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_blocks_on_invalid_status() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"PENDING"}' > "$tmpdir/.reviews/handoff.json"
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: thing\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) commit with PENDING status"
    else
        fail "codex gate should exit 2 with non-certified status, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_skip_override() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: something\""}}' | (cd "$tmpdir" && CODEX_GATE_SKIP=1 "$HOOKS_DIR/codex-gate-check.sh") 2>&1)
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate respects CODEX_GATE_SKIP=1 override (exit 0)"
    else
        fail "codex gate should exit 0 silent with CODEX_GATE_SKIP=1, got exit=$exit_code out: $out"
    fi
}

# #236(b) minor finding: `set -e` + a `command` field the extraction regex
# can't match (e.g. genuinely absent from tool_input, an old-format payload)
# makes the grep exit 1, which under set -e kills the whole script with an
# undefined exit 1 — neither the intentional "allow" (0) nor "deny" (2) path.
# Must fail closed to a clean, deliberate exit 0 (this isn't a git-commit
# command at all, same as any other non-commit Bash call), not crash.
test_codex_gate_no_command_field_does_not_crash() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"foo":"bar"}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate exits cleanly (0) when tool_input has no command field, does not crash"
    else
        fail "codex gate should exit 0 silent on missing command field, got exit=$exit_code out: $out"
    fi
}

# #236(b) minor finding: literal substring match on "git commit" misses git's
# own global-flag forms — `git -C <dir> commit` and `git -c k=v commit` are
# both real, valid git invocations that never contain the literal substring
# "git commit", so they sailed through the gate unreviewed.
test_codex_gate_blocks_commit_with_dash_C_global_flag() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git -C /tmp/repo commit -m \"fix\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) 'git -C <dir> commit' global-flag form"
    else
        fail "codex gate should exit 2 for 'git -C <dir> commit', got exit=$exit_code out: $out"
    fi
}

test_codex_gate_blocks_commit_with_dash_c_config_flag() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git -c user.email=x@y.com commit -m \"fix\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) 'git -c k=v commit' global-flag form"
    else
        fail "codex gate should exit 2 for 'git -c k=v commit', got exit=$exit_code out: $out"
    fi
}

# Codex review finding (hook-enforcement-436, round 1): a quote appearing
# BEFORE "git commit" in the command (e.g. `cd "$dir" && git commit ...`)
# breaks the grep/sed extraction — `[^"]*` stops at the first embedded quote
# regardless of JSON escaping, truncating the captured command before it ever
# reaches "git commit". The gate then falls through to the silent-allow
# default. Real false negative: a review-less commit slips through untouched.
test_codex_gate_blocks_commit_with_quote_before_git_commit() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"cd \"$dir\" && git commit -m \"message\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) commit even when an earlier quote precedes 'git commit'"
    else
        fail "codex gate should exit 2 despite embedded quote before git commit, got exit=$exit_code out: $out"
    fi
}

# Codex review finding (hook-enforcement-436, round 2): the round-1 fix
# (match "git commit" against the whole raw TOOL_INPUT) traded the false
# negative for a false positive — a non-commit command is blocked if ANY
# other field (e.g. the Bash tool's own "description") happens to mention
# "git commit" in prose. The gate must only look inside the "command" value.
test_codex_gate_silent_when_only_description_mentions_commit() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git status","description":"check status before next git commit"}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && [ -z "$out" ]; then
        pass "codex gate silent on non-commit command even when description mentions 'git commit'"
    else
        fail "codex gate should exit 0 silent (only 'description' mentions commit, not 'command'), got exit=$exit_code out: $out"
    fi
}

# Codex cross-model review finding (#236(b) round 1, 2026-07-06): a `-c`/`-C`
# value containing a space inside quotes (a real, valid git invocation --
# `git -c user.name="A B" commit`) breaks the `-c\s+\S+` alternative, since
# `\S+` stops at the embedded space. The structural git/commit match then
# fails entirely and the commit sails through unreviewed.
test_codex_gate_blocks_commit_with_quoted_value_containing_space() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git -c user.name=\"A B\" commit -m \"fix\""}}' | (cd "$tmpdir" && "$HOOKS_DIR/codex-gate-check.sh") 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "cross-model review"; then
        pass "codex gate BLOCKS (exit 2) 'git -c k=\"v w\" commit' with a spaced quoted value"
    else
        fail "codex gate should exit 2 for a git commit with a quoted flag value containing a space, got exit=$exit_code out: $out"
    fi
}

test_codex_gate_blocks_commit_without_review
test_codex_gate_allows_commit_with_certified_review
test_codex_gate_allows_commit_with_reviewed_status
test_codex_gate_silent_on_non_commit_commands
test_codex_gate_blocks_on_invalid_status
test_codex_gate_skip_override
test_codex_gate_no_command_field_does_not_crash
test_codex_gate_blocks_commit_with_dash_C_global_flag
test_codex_gate_blocks_commit_with_dash_c_config_flag
test_codex_gate_blocks_commit_with_quote_before_git_commit
test_codex_gate_silent_when_only_description_mentions_commit
test_codex_gate_blocks_commit_with_quoted_value_containing_space
test_codex_gate_blocks_stale_certification_after_new_commit
test_codex_gate_blocks_missing_commit_sha_as_stale

# ---- codex-review-stop-check.sh tests ----
# Fable self-enforcement audit finding: a full SDLC workflow can complete —
# Claude presents "done, here's what I changed" — without ever running
# `git commit`. codex-gate-check.sh only fires on that one command, so the
# gate never triggers and cross-model review is silently skippable. This
# Stop hook closes that gap: non-blocking warning (Stop hooks shouldn't
# prevent the user from getting their response) when significant uncommitted
# changes exist with no REVIEWED/CERTIFIED review artifact.
echo ""
echo "--- codex-review-stop-check.sh ---"

test_stop_hook_exists() {
    if [ -x "$HOOKS_DIR/codex-review-stop-check.sh" ]; then
        pass "codex-review-stop-check.sh exists and is executable"
    else
        fail "codex-review-stop-check.sh not found or not executable"
    fi
}

test_stop_hook_silent_no_git_repo() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local out
    out=$(printf '%s' '{"session_id":"s1"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -z "$out" ]; then
        pass "stop hook silent outside a git repo"
    else
        fail "stop hook should be silent outside a git repo, got: $out"
    fi
}

test_stop_hook_silent_clean_tree() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && git commit -q --allow-empty -m init) > /dev/null 2>&1
    local out
    out=$(printf '%s' '{"session_id":"s2"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -z "$out" ]; then
        pass "stop hook silent on a clean working tree"
    else
        fail "stop hook should be silent when nothing changed, got: $out"
    fi
}

test_stop_hook_silent_doc_only_changes() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && echo "# doc" > README.md && git add . && git commit -q -m init) > /dev/null 2>&1
    echo "updated" >> "$tmpdir/README.md"
    local out
    out=$(printf '%s' '{"session_id":"s3"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -z "$out" ]; then
        pass "stop hook silent on doc-only (*.md) changes"
    else
        fail "stop hook should be silent on doc-only changes, got: $out"
    fi
}

test_stop_hook_warns_significant_uncommitted_no_review() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && echo "x=1" > app.sh && git add . && git commit -q -m init) > /dev/null 2>&1
    echo "x=2" >> "$tmpdir/app.sh"
    local out
    out=$(printf '%s' '{"session_id":"s4"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if echo "$out" | grep -qi "review"; then
        pass "stop hook warns on significant uncommitted changes with no review artifact"
    else
        fail "stop hook should mention review, got: $out"
    fi
}

test_stop_hook_silent_with_certified_review() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && echo "x=1" > app.sh && git add . && git commit -q -m init) > /dev/null 2>&1
    echo "x=2" >> "$tmpdir/app.sh"
    mkdir -p "$tmpdir/.reviews"
    printf '{"status":"CERTIFIED"}' > "$tmpdir/.reviews/handoff.json"
    local out
    out=$(printf '%s' '{"session_id":"s5"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -z "$out" ]; then
        pass "stop hook silent when review is CERTIFIED"
    else
        fail "stop hook should be silent with a CERTIFIED review, got: $out"
    fi
}

test_stop_hook_ignores_reviews_dir_changes() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && mkdir -p .reviews && echo '{}' > .reviews/response.json && git add . && git commit -q -m init) > /dev/null 2>&1
    echo '{"a":1}' > "$tmpdir/.reviews/response.json"
    local out
    out=$(printf '%s' '{"session_id":"s6"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -z "$out" ]; then
        pass "stop hook ignores changes confined to .reviews/ (metadata, not reviewed work)"
    else
        fail "stop hook should ignore .reviews/-only changes, got: $out"
    fi
}

test_stop_hook_delivers_via_stdout_json_not_stderr() {
    # #236(b) BUG 1: on exit 0, stderr is never surfaced to the user or to
    # Claude — only stdout JSON (hookSpecificOutput.additionalContext) is.
    # The other tests here capture 2>&1 (combined), which is exactly how a
    # stderr-only, exit-0 warning could look "delivered" while actually being
    # silently discarded by the real Claude Code harness.
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && echo "x=1" > app.sh && git add . && git commit -q -m init) > /dev/null 2>&1
    echo "x=2" >> "$tmpdir/app.sh"
    local stdout_out stderr_out
    stdout_out=$(printf '%s' '{"session_id":"s-delivery"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>"$tmpdir/stderr.out")
    stderr_out=$(cat "$tmpdir/stderr.out")
    rm -rf "$tmpdir"
    if printf '%s' "$stdout_out" | grep -q '"hookEventName"[[:space:]]*:[[:space:]]*"Stop"' \
        && printf '%s' "$stdout_out" | grep -qi '"additionalContext"' \
        && [ -z "$stderr_out" ]; then
        pass "stop hook delivers warning via stdout JSON (hookSpecificOutput.additionalContext), not stderr"
    else
        fail "stop hook must emit valid stdout JSON with hookEventName:Stop and leave stderr empty — stdout: '$stdout_out' stderr: '$stderr_out'"
    fi
}

test_stop_hook_fires_once_per_session() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && git init -q && echo "x=1" > app.sh && git add . && git commit -q -m init) > /dev/null 2>&1
    echo "x=2" >> "$tmpdir/app.sh"
    local cache="$tmpdir/cache"
    local first second
    first=$(printf '%s' '{"session_id":"s7"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    second=$(printf '%s' '{"session_id":"s7"}' | (cd "$tmpdir" && SDLC_WIZARD_CACHE_DIR="$cache" "$HOOKS_DIR/codex-review-stop-check.sh") 2>&1)
    rm -rf "$tmpdir"
    if [ -n "$first" ] && [ -z "$second" ]; then
        pass "stop hook warns once per session, silent on repeat Stop events"
    else
        fail "stop hook should warn once then go silent same session, got first: '$first' second: '$second'"
    fi
}

test_stop_hook_exists
test_stop_hook_silent_no_git_repo
test_stop_hook_silent_clean_tree
test_stop_hook_silent_doc_only_changes
test_stop_hook_warns_significant_uncommitted_no_review
test_stop_hook_silent_with_certified_review
test_stop_hook_ignores_reviews_dir_changes
test_stop_hook_delivers_via_stdout_json_not_stderr
test_stop_hook_fires_once_per_session

# GH #475 — the TDD hook shipped SILENTLY DEAD for monorepo consumers.
#
# Claude Code 2.1.214 changed single-segment `dir/**` hook `if:` conditions to
# match only <cwd>/dir; any-depth matching now needs `**/dir/**`. hooks/hooks.json
# gated the TDD hook on `Write(src/**)`, and hooks/ is in package.json's `files`,
# so every consumer whose source is not at repo-root src/ — every monorepo,
# packages/*/src/, apps/web/src/ — lost the gate with no error. This repo did not
# notice because its own paths genuinely sit at the root.
#
# EXECUTES glob semantics against a real monorepo-shaped tree rather than
# grepping hooks.json for a string, per AGENTS.md Code Review Rule 1.
test_tdd_hook_matcher_covers_nested_src() {
    local manifest="$SCRIPT_DIR/../hooks/hooks.json"
    [ -f "$manifest" ] || { fail "hooks/hooks.json not found"; return; }

    local result
    result=$(python3 - "$manifest" <<'PYEOF'
import glob, json, os, sys, tempfile, re
manifest = json.load(open(sys.argv[1]))
conds = []
def walk(o):
    if isinstance(o, dict):
        if "if" in o and isinstance(o["if"], str): conds.append(o["if"])
        for v in o.values(): walk(v)
    elif isinstance(o, list):
        for v in o: walk(v)
walk(manifest)
pats = sorted({m for c in conds for m in re.findall(r"\((.*?)\)", c)})
if not pats:
    print("NO_PATTERNS"); sys.exit()

root = tempfile.mkdtemp()
for d in ["src", "packages/api/src", "apps/web/src"]:
    os.makedirs(os.path.join(root, d), exist_ok=True)
    open(os.path.join(root, d, "widget.ts"), "w").close()
os.chdir(root)

bad = []
for pat in pats:
    hits = [h for h in glob.glob(pat, recursive=True) if h.endswith("widget.ts")]
    nested = [h for h in hits if "/" in h.rstrip("widget.ts").rstrip("/").replace("src", "", 1)]
    if not any(h.startswith(("packages/", "apps/")) for h in hits):
        bad.append(f"{pat} matched only {sorted(hits)}")
print("OK" if not bad else "BAD:" + "; ".join(bad))
PYEOF
)
    case "$result" in
        OK) pass "TDD hook if: patterns match nested source dirs (monorepo consumers keep the gate)" ;;
        NO_PATTERNS) fail "no if: patterns found in hooks/hooks.json — the extractor broke, not the manifest" ;;
        *) fail "GH #475: a shipped hook if: pattern does NOT match nested source — the gate is silently dead for monorepo consumers. $result" ;;
    esac
}
test_tdd_hook_matcher_covers_nested_src

# NOTE: an unbounded-stdin-drain detector lived here briefly and was deleted on
# both reviewers' certify conditions. It pattern-matched the source text for
# bare `cat`, and independent review constructed a dozen real drains it missed
# — `$(cat 2>/dev/null)`, `/bin/cat`, `cat <&0`, `mapfile`, `IFS= read` without
# `-t`, `exec 0<`, `head -c`, `jq .` — while it false-positived on the string
# "cat > /dev/null" inside a comment or heredoc. Widening it is the unwinnable
# denylist shape ROADMAP #495(a) describes: every new spelling is discovered
# only after it escapes.
#
# The real guarantee is behavioural and lives in tests/test-hook-stdin-bounded.sh,
# which runs every hook against a stdin that never reaches EOF and fails if it
# outlives its bound — independent of how the read is spelled. That roster is now
# derived from hooks/hooks.json rather than hand-listed, which is what let
# model-effort-check.sh escape v1.94.0 in the first place.

# ---- GH #476: shipped hooks must not push the sudo-npm footgun ----
#
# Official setup docs mark the native install "Recommended" and explicitly warn
# against `sudo npm install -g`, which breaks future updates and uninstalls.
# instructions-loaded-check.sh nudged every consumer toward the global npm
# install on every session start, so the wizard did not merely omit the advice
# in #476 — it shipped the opposite. `claude update` is correct for both
# install kinds.
test_no_shipped_hook_recommends_global_npm_cc_install() {
    local hits
    # Order-independent and flag-tolerant: matches `install -g`, `i -g`,
    # `--global`, `-g install`, extra flags, and a quoted package name. A pure
    # syntax denylist is still losable (see the positive test below, which is
    # the real anchor) — this is the cheap tripwire, not the guarantee.
    hits=$(grep -rnE "npm([[:space:]]+[^[:space:]]+)*[[:space:]]+(-g|--global)([[:space:]]+[^[:space:]]+)*[[:space:]]+[\"']?@anthropic-ai/claude-code" "$HOOKS_DIR" 2>/dev/null || true)
    if [ -z "$hits" ]; then
        pass "#476: no shipped hook recommends a global npm install of Claude Code"
    else
        fail "#476: a shipped hook tells consumers to switch install channels:
$hits"
    fi
}
test_no_shipped_hook_recommends_global_npm_cc_install

# The positive anchor. Absence tests are losable — any unlisted spelling of the
# wrong advice passes one. This asserts what the hook actually EMITS, by running
# it, which is a fixed target rather than an open-ended syntax space (the
# defining-output shape ROADMAP #495(a) recommends over a denylist).
test_cc_update_nudge_is_install_method_aware() {
    local hook="$HOOKS_DIR/instructions-loaded-check.sh"
    local cache_dir out
    cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/cc-nudge.XXXXXX") || {
        fail "#476: could not create temp cache dir"; return
    }
    # Stub `claude` rather than depending on the real binary. The nudge branch
    # is gated on `command -v claude` (hooks/instructions-loaded-check.sh), and
    # CI's ubuntu-latest runner has no Claude Code installed — so without this
    # the test would fail in CI for an environmental reason while passing on a
    # maintainer laptop. It also pins the "local" version, so the assertion no
    # longer depends on whatever version happens to be installed here.
    mkdir -p "$cache_dir/bin"
    printf '#!/bin/sh\necho "1.0.0 (Claude Code)"\n' > "$cache_dir/bin/claude"
    chmod +x "$cache_dir/bin/claude"
    # npm is stubbed too: the branch is gated on it, and a real `npm view`
    # would make this test depend on the network and on the live published
    # version. The cached latest-cc-version below is what should be consulted.
    printf '#!/bin/sh\nexit 1\n' > "$cache_dir/bin/npm"
    chmod +x "$cache_dir/bin/npm"

    # Force the drift branch: a cached "latest" far above the stubbed local.
    # CLAUDE_PROJECT_DIR is required — the nudge is deliberately gated on it so
    # it stays silent under Codex/OpenCode (#375).
    printf '%s' '99.99.99' > "$cache_dir/latest-cc-version"
    out=$(PATH="$cache_dir/bin:$PATH" CLAUDE_PROJECT_DIR="$SCRIPT_DIR/.." \
          SDLC_WIZARD_CACHE_DIR="$cache_dir" \
          "$hook" < /dev/null 2>&1 || true)
    rm -rf "$cache_dir"

    if ! printf '%s' "$out" | grep -q 'Claude Code update available'; then
        fail "#476: could not exercise the update nudge — fixture no longer triggers it, so the assertion below would be vacuous. Output was: $(printf '%s' "$out" | head -c 200)"
        return
    fi
    local nudge
    nudge=$(printf '%s' "$out" | grep 'Claude Code update available')

    # BOTH halves are asserted. Requiring only `claude update` accepted a
    # regression to a bare `(run 'claude update')`, which is wrong for
    # brew/apt/dnf/apk/winget installs — those need their own package manager,
    # and `claude update` reports them as already current.
    if printf '%s' "$nudge" | grep -qE 'npm[[:space:]]+(install|i)|--global'; then
        fail "#476: the emitted nudge still names npm as the update channel:
$nudge"
    elif ! printf '%s' "$nudge" | grep -q 'claude update'; then
        fail "#476: the update nudge names no usable update command:
$nudge"
    elif ! printf '%s' "$nudge" | grep -qiE 'package manager'; then
        fail "#476: the nudge gives only 'claude update' and never mentions package-manager installs, which it cannot update:
$nudge"
    else
        pass "#476: the emitted update nudge covers both halves (claude update + package-manager installs)"
    fi
}
test_cc_update_nudge_is_install_method_aware

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All hook tests passed!"
