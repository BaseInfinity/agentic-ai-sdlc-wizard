#!/bin/bash
# Roadmap (TBD): regression test for sdlc-prompt-check.sh "BASELINE block
# emits once per session" optimization. The static SDLC BASELINE block
# (~250 tokens) was firing on every UserPromptSubmit, duplicating itself
# in context after Claude already had the SDLC skill loaded — an estimated
# ~12K wasted tokens per 50-prompt session.
#
# Fix: when stdin JSON includes a session_id, write a sentinel to
# $SDLC_WIZARD_CACHE_DIR/baseline-shown-<session_id> after first emit, and
# skip the BASELINE block on subsequent fires within the same session.
#
# Compatibility: when stdin has no session_id (e.g. legacy CC versions,
# direct shell tests), behavior is unchanged — BASELINE emits every fire.
#
# Things that MUST keep firing every prompt regardless of sentinel:
#   - SETUP NOT COMPLETE warning (when SDLC.md / TESTING.md missing)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/sdlc-prompt-check.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== sdlc-prompt-check.sh BASELINE-fires-once-per-session Tests ==="
echo ""

WORKSPACE="${TMPDIR:-/tmp}/sdlc-baseline-once-$$"
mkdir -p "$WORKSPACE"
trap 'rm -rf "$WORKSPACE"' EXIT
echo "<!-- SDLC Wizard Version: 1.69.0 -->" > "$WORKSPACE/SDLC.md"
echo "# Testing" > "$WORKSPACE/TESTING.md"

# Each test gets a fresh cache dir so sentinels from one test don't leak
# into another. Tests that need persistence across hook fires share a cache.

invoke() {
    local cache="$1"
    local payload="$2"
    (cd "$WORKSPACE" && CLAUDE_PROJECT_DIR="$WORKSPACE" \
        SDLC_WIZARD_CACHE_DIR="$cache" \
        bash "$HOOK" <<<"$payload" 2>/dev/null)
}

# ---- Test 1: First fire with session_id emits BASELINE ----
test_first_fire_emits_baseline() {
    local cache="$WORKSPACE/cache-1"
    rm -rf "$cache"
    local out
    out=$(invoke "$cache" '{"prompt":"hello","session_id":"sess-A"}')
    if echo "$out" | grep -q "SDLC BASELINE:"; then
        pass "first fire (session=A) emits SDLC BASELINE"
    else
        fail "first fire should emit BASELINE. Output: $out"
    fi
}

# ---- Test 2: Second fire same session_id suppresses BASELINE ----
test_second_fire_suppresses_baseline() {
    local cache="$WORKSPACE/cache-2"
    rm -rf "$cache"
    invoke "$cache" '{"prompt":"first","session_id":"sess-B"}' > /dev/null
    local out
    out=$(invoke "$cache" '{"prompt":"second","session_id":"sess-B"}')
    if echo "$out" | grep -q "SDLC BASELINE:"; then
        fail "second fire (same session) should NOT emit BASELINE. Output: $out"
    else
        pass "second fire (session=B, same sentinel) suppresses BASELINE"
    fi
}

# ---- Test 3: Different session_id re-emits BASELINE ----
test_different_session_re_emits() {
    local cache="$WORKSPACE/cache-3"
    rm -rf "$cache"
    invoke "$cache" '{"prompt":"first","session_id":"sess-C"}' > /dev/null
    local out
    out=$(invoke "$cache" '{"prompt":"hello","session_id":"sess-D"}')
    if echo "$out" | grep -q "SDLC BASELINE:"; then
        pass "different session_id (C → D, same cache) re-emits BASELINE"
    else
        fail "different session_id should emit BASELINE. Output: $out"
    fi
}

# ---- Test 4: No session_id → BASELINE every fire (back-compat) ----
test_no_session_id_back_compat() {
    local cache="$WORKSPACE/cache-4"
    rm -rf "$cache"
    local out1 out2
    out1=$(invoke "$cache" '{"prompt":"first"}')
    out2=$(invoke "$cache" '{"prompt":"second"}')
    if echo "$out1" | grep -q "SDLC BASELINE:" && echo "$out2" | grep -q "SDLC BASELINE:"; then
        pass "no session_id → BASELINE emits every fire (legacy/test compat preserved)"
    else
        fail "without session_id, BASELINE must emit every fire. Out1=$out1 / Out2=$out2"
    fi
}

# ---- Test 5: Setup-missing warning fires every time, ignores sentinel ----
test_setup_missing_always_fires() {
    # Use a sibling tmpdir (NOT a child of $WORKSPACE) — _find-sdlc-root.sh
    # walks up from CWD to find SDLC.md, so a child dir would inherit the
    # parent's full SDLC fixture and skip the SETUP-NOT-COMPLETE branch.
    local broken_workspace
    broken_workspace=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-broken-XXXXXX")
    # Empty SDLC.md (zero bytes) triggers `[ ! -s "$PROJECT_DIR/SDLC.md" ]`
    # → SETUP NOT COMPLETE fires. find_partial_sdlc_root sees the file and
    # sets PROJECT_DIR; the empty-file check then fires the warning.
    : > "$broken_workspace/SDLC.md"
    local cache="$WORKSPACE/cache-5"
    rm -rf "$cache"
    local out1 out2
    out1=$( (cd "$broken_workspace" && CLAUDE_PROJECT_DIR="$broken_workspace" \
        SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" <<<'{"prompt":"x","session_id":"sess-E"}' 2>/dev/null) )
    out2=$( (cd "$broken_workspace" && CLAUDE_PROJECT_DIR="$broken_workspace" \
        SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" <<<'{"prompt":"y","session_id":"sess-E"}' 2>/dev/null) )
    rm -rf "$broken_workspace"
    if echo "$out1" | grep -q "SETUP NOT COMPLETE" && echo "$out2" | grep -q "SETUP NOT COMPLETE"; then
        pass "SETUP NOT COMPLETE warning fires every prompt regardless of sentinel"
    else
        fail "SETUP NOT COMPLETE must always fire. Out1=$out1 / Out2=$out2"
    fi
}

# ---- Test 7: Sentinel does not leak across cache dirs ----
test_sentinel_isolated_per_cache() {
    local cache_a="$WORKSPACE/cache-7a"
    local cache_b="$WORKSPACE/cache-7b"
    rm -rf "$cache_a" "$cache_b"
    invoke "$cache_a" '{"prompt":"x","session_id":"shared"}' > /dev/null
    local out
    out=$(invoke "$cache_b" '{"prompt":"y","session_id":"shared"}')
    if echo "$out" | grep -q "SDLC BASELINE:"; then
        pass "sentinel isolated per SDLC_WIZARD_CACHE_DIR (no global state)"
    else
        fail "different cache dir must re-emit BASELINE. Output: $out"
    fi
}

# ---- Test 8: Suppressed-fire output is markedly smaller ----
test_suppressed_fire_is_smaller() {
    local cache="$WORKSPACE/cache-8"
    rm -rf "$cache"
    local first_size second_size
    first_size=$(invoke "$cache" '{"prompt":"first","session_id":"sess-G"}' | wc -c | tr -d ' ')
    second_size=$(invoke "$cache" '{"prompt":"second","session_id":"sess-G"}' | wc -c | tr -d ' ')
    # First fire emits BASELINE (~600 chars including the cat block).
    # Second fire emits at most a trailing newline (or empty). Demand 5x reduction
    # to confirm the bulk of the BASELINE block is actually gone, not just trimmed.
    if [ "$first_size" -gt 400 ] && [ "$second_size" -lt $((first_size / 5)) ]; then
        pass "suppressed fire is >5x smaller (${first_size} → ${second_size} chars)"
    else
        fail "suppression didn't shrink output enough. first=${first_size} second=${second_size}"
    fi
}

# ---- Test 9: Concurrency race — 50 parallel same-session fires emit BASELINE
#       exactly once. Codex round 1 P1: prior "check then write-after-emit"
#       allowed N parallel fires to all emit; atomic noclobber claim fixes it.
test_concurrency_same_session_emits_once() {
    local cache="$WORKSPACE/cache-9"
    rm -rf "$cache"
    local agg="$WORKSPACE/cache-9-outputs"
    rm -f "$agg"
    local i pids=()
    # Fire 50 invocations concurrently with the same session_id. Each
    # invocation appends its stdout to the aggregate file; greping for
    # "SDLC BASELINE:" counts how many actually emitted.
    for i in $(seq 1 50); do
        ( invoke "$cache" '{"prompt":"p","session_id":"sess-CONCURRENT"}' >> "$agg" ) &
        pids+=($!)
    done
    for p in "${pids[@]}"; do
        wait "$p" || true
    done
    local count
    count=$(grep -c "^SDLC BASELINE:" "$agg" 2>/dev/null || echo 0)
    if [ "$count" = "1" ]; then
        pass "50 parallel same-session fires emit BASELINE exactly once (atomic claim)"
    else
        fail "concurrency race: ${count} BASELINE outputs across 50 fires (expected 1)"
    fi
}

# ---- Test 10: jq missing — session_id extraction must not depend on jq.
#        Codex round 1 P1: jq-coupled extraction silently dropped the gate
#        when jq was unavailable. Now grep+sed extracts session_id directly.
test_session_id_works_without_jq() {
    # Build a PATH with no jq for this test only. Keep coreutils +
    # bash/grep/sed/find available via a temp dir of symlinks.
    local nojq_path="$WORKSPACE/path-no-jq"
    rm -rf "$nojq_path"
    mkdir -p "$nojq_path"
    # Use `type -P` (executable path only) — `command -v` returns function
    # names when the user's shell wraps tools (e.g. CC's grep wrapper) and
    # ln -sf <funcname> creates a dangling self-referencing symlink.
    for tool in bash sh cat printf sed grep head awk find mkdir touch chmod tr date wc stat ln rm ls mv cp tee dirname pwd; do
        local src
        src=$(type -P "$tool" 2>/dev/null)
        [ -n "$src" ] && [ -x "$src" ] && ln -sf "$src" "$nojq_path/$tool"
    done
    # Confirm jq is NOT in the restricted PATH
    if PATH="$nojq_path" command -v jq > /dev/null 2>&1; then
        fail "test setup error: jq leaked into restricted PATH"
        rm -rf "$nojq_path"
        return
    fi

    local cache="$WORKSPACE/cache-10"
    rm -rf "$cache"
    local out1 out2
    out1=$( PATH="$nojq_path" \
        bash -c "cd '$WORKSPACE' && CLAUDE_PROJECT_DIR='$WORKSPACE' SDLC_WIZARD_CACHE_DIR='$cache' bash '$HOOK' <<<'{\"prompt\":\"x\",\"session_id\":\"sess-NOJQ\"}'" 2>/dev/null )
    out2=$( PATH="$nojq_path" \
        bash -c "cd '$WORKSPACE' && CLAUDE_PROJECT_DIR='$WORKSPACE' SDLC_WIZARD_CACHE_DIR='$cache' bash '$HOOK' <<<'{\"prompt\":\"y\",\"session_id\":\"sess-NOJQ\"}'" 2>/dev/null )
    rm -rf "$nojq_path"

    if echo "$out1" | grep -q "SDLC BASELINE:" && ! echo "$out2" | grep -q "SDLC BASELINE:"; then
        pass "session_id gate works without jq (first emits, second suppresses)"
    else
        fail "no-jq path broke gate. Out1 has BASELINE: $(echo "$out1" | grep -q 'SDLC BASELINE:' && echo yes || echo no). Out2 has BASELINE: $(echo "$out2" | grep -q 'SDLC BASELINE:' && echo yes || echo no)"
    fi
}

test_first_fire_emits_baseline
test_second_fire_suppresses_baseline
test_different_session_re_emits
test_no_session_id_back_compat
test_setup_missing_always_fires
test_sentinel_isolated_per_cache
test_suppressed_fire_is_smaller
test_concurrency_same_session_emits_once
test_session_id_works_without_jq

echo ""
echo "=== Results ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    exit 1
fi
echo "All BASELINE-fires-once tests passed."
