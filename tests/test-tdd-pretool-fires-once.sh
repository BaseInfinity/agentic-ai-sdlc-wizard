#!/bin/bash
# Roadmap #236 phase 2: regression test for tdd-pretool-check.sh
# "TDD CHECK nudge fires once per session" optimization.
#
# Background: hooks/tdd-pretool-check.sh fires on every Write|Edit|MultiEdit
# touching src/** and emits a ~50-token JSON nudge ("TDD CHECK: Are you
# writing IMPLEMENTATION before a FAILING TEST?"). After the SDLC skill
# auto-invokes (which already covers TDD RED/GREEN), this nudge is duplicate
# context — typical SDLC session has 10-30 src Edits = 0.5-1.5K wasted tokens.
#
# Fix: when stdin JSON includes a session_id, atomic-claim a sentinel under
# $SDLC_WIZARD_CACHE_DIR/tdd-shown-<safe_sid>. First src/ Edit per session
# emits the nudge; subsequent fires suppress.
#
# Behavior preserved:
#   - file_path NOT in src/ → no output (existing behavior, regardless of sentinel)
#   - no session_id stdin → emit every fire (legacy CC + direct shell tests)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/tdd-pretool-check.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== tdd-pretool-check.sh fires-once-per-session Tests ==="
echo ""

WORKSPACE="${TMPDIR:-/tmp}/sdlc-tdd-once-$$"
mkdir -p "$WORKSPACE"
trap 'rm -rf "$WORKSPACE"' EXIT

invoke() {
    local cache="$1"
    local payload="$2"
    SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" <<<"$payload" 2>/dev/null
}

# #436 added a src/ edit-ordering gate that blocks (exit 2) when no test file
# has been touched yet this session — it runs BEFORE the nudge-once logic
# these tests exercise. Prime the "test touched" sentinel per session/cache
# so payloads reach the nudge code, same as a real session would after
# writing its failing test first.
prime_test_touched() {
    local cache="$1"
    local sid="$2"
    SDLC_WIZARD_CACHE_DIR="$cache" bash "$HOOK" \
        <<<"{\"tool_input\":{\"file_path\":\"/proj/src/__tests__/prime.test.ts\"},\"session_id\":\"$sid\"}" \
        > /dev/null 2>&1
}

SRC_PAYLOAD_A='{"tool_input":{"file_path":"/proj/src/foo.ts"},"session_id":"sess-A"}'
SRC_PAYLOAD_A2='{"tool_input":{"file_path":"/proj/src/bar.ts"},"session_id":"sess-A"}'
SRC_PAYLOAD_B='{"tool_input":{"file_path":"/proj/src/baz.ts"},"session_id":"sess-B"}'
NON_SRC_PAYLOAD='{"tool_input":{"file_path":"/proj/README.md"},"session_id":"sess-A"}'
NO_SID_PAYLOAD='{"tool_input":{"file_path":"/proj/src/foo.ts"}}'

# ---- Test 1: First src/ edit with session_id emits TDD CHECK ----
test_first_fire_emits() {
    local cache="$WORKSPACE/cache-1"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    local out
    out=$(invoke "$cache" "$SRC_PAYLOAD_A")
    if echo "$out" | grep -q "TDD CHECK"; then
        pass "first src/ edit (session=A) emits TDD CHECK nudge"
    else
        fail "first src/ edit should emit TDD CHECK. Output: $out"
    fi
}

# ---- Test 2: Second src/ edit same session_id suppresses ----
test_second_fire_suppresses() {
    local cache="$WORKSPACE/cache-2"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    invoke "$cache" "$SRC_PAYLOAD_A" > /dev/null
    local out
    out=$(invoke "$cache" "$SRC_PAYLOAD_A2")
    if echo "$out" | grep -q "TDD CHECK"; then
        fail "second src/ edit (same session) should NOT emit. Output: $out"
    else
        pass "second src/ edit (session=A, same sentinel) suppresses TDD CHECK"
    fi
}

# ---- Test 3: Different session_id re-emits ----
test_different_session_re_emits() {
    local cache="$WORKSPACE/cache-3"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    prime_test_touched "$cache" "sess-B"
    invoke "$cache" "$SRC_PAYLOAD_A" > /dev/null
    local out
    out=$(invoke "$cache" "$SRC_PAYLOAD_B")
    if echo "$out" | grep -q "TDD CHECK"; then
        pass "different session_id (A → B, same cache) re-emits TDD CHECK"
    else
        fail "different session_id should emit. Output: $out"
    fi
}

# ---- Test 4: No session_id → emit every fire (back-compat) ----
test_no_session_id_back_compat() {
    local cache="$WORKSPACE/cache-4"
    rm -rf "$cache"
    local out1 out2
    out1=$(invoke "$cache" "$NO_SID_PAYLOAD")
    out2=$(invoke "$cache" "$NO_SID_PAYLOAD")
    if echo "$out1" | grep -q "TDD CHECK" && echo "$out2" | grep -q "TDD CHECK"; then
        pass "no session_id → TDD CHECK fires every src/ edit (legacy/test compat)"
    else
        fail "without session_id, TDD CHECK must emit every src/ edit. Out1=$out1 / Out2=$out2"
    fi
}

# ---- Test 5: Non-src/ file produces no output regardless of sentinel ----
test_non_src_never_emits() {
    local cache="$WORKSPACE/cache-5"
    rm -rf "$cache"
    local out1 out2
    out1=$(invoke "$cache" "$NON_SRC_PAYLOAD")
    out2=$(invoke "$cache" "$NON_SRC_PAYLOAD")
    if [ -z "$out1" ] && [ -z "$out2" ]; then
        pass "non-src/ file edits produce no output (existing behavior preserved)"
    else
        fail "non-src/ should be silent. Out1=$out1 / Out2=$out2"
    fi
}

# ---- Test 6: Non-src/ does NOT consume the sentinel slot ----
#       I.e. if user edits README first, then src/foo, TDD CHECK should still
#       fire on src/foo because no src/ edit has happened yet.
test_non_src_doesnt_consume_sentinel() {
    local cache="$WORKSPACE/cache-6"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    invoke "$cache" "$NON_SRC_PAYLOAD" > /dev/null  # README — should not claim sentinel
    local out
    out=$(invoke "$cache" "$SRC_PAYLOAD_A")
    if echo "$out" | grep -q "TDD CHECK"; then
        pass "non-src/ edit doesn't consume sentinel (TDD CHECK still fires on first src/)"
    else
        fail "non-src/ edit should not pre-claim sentinel. src/ output: $out"
    fi
}

# ---- Test 7: Sentinel isolated per cache dir ----
test_sentinel_isolated_per_cache() {
    local cache_a="$WORKSPACE/cache-7a"
    local cache_b="$WORKSPACE/cache-7b"
    rm -rf "$cache_a" "$cache_b"
    prime_test_touched "$cache_a" "sess-A"
    prime_test_touched "$cache_b" "sess-A"
    invoke "$cache_a" "$SRC_PAYLOAD_A" > /dev/null
    local out
    out=$(invoke "$cache_b" "$SRC_PAYLOAD_A")
    if echo "$out" | grep -q "TDD CHECK"; then
        pass "sentinel isolated per SDLC_WIZARD_CACHE_DIR"
    else
        fail "different cache dir should re-emit TDD CHECK. Output: $out"
    fi
}

# ---- Test 8: Concurrency — 50 parallel same-session fires emit exactly once ----
test_concurrency_same_session_emits_once() {
    local cache="$WORKSPACE/cache-8"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    local agg="$WORKSPACE/cache-8-outputs"
    rm -f "$agg"
    local i pids=()
    for i in $(seq 1 50); do
        ( invoke "$cache" "$SRC_PAYLOAD_A" >> "$agg" ) &
        pids+=($!)
    done
    for p in "${pids[@]}"; do
        wait "$p" || true
    done
    local count
    count=$(grep -c "TDD CHECK" "$agg" 2>/dev/null || echo 0)
    if [ "$count" = "1" ]; then
        pass "50 parallel same-session src/ edits emit TDD CHECK exactly once (atomic claim)"
    else
        fail "concurrency race: ${count} TDD CHECK outputs across 50 fires (expected 1)"
    fi
}

# ---- Test 9: Suppressed fire is empty (no leftover JSON shell) ----
test_suppressed_fire_is_empty() {
    local cache="$WORKSPACE/cache-9"
    rm -rf "$cache"
    prime_test_touched "$cache" "sess-A"
    invoke "$cache" "$SRC_PAYLOAD_A" > /dev/null
    local out
    out=$(invoke "$cache" "$SRC_PAYLOAD_A2")
    if [ -z "$out" ]; then
        pass "suppressed fire produces no stdout (clean — no empty JSON wrapper)"
    else
        fail "suppressed fire leaked stdout: '$out'"
    fi
}

test_first_fire_emits
test_second_fire_suppresses
test_different_session_re_emits
test_no_session_id_back_compat
test_non_src_never_emits
test_non_src_doesnt_consume_sentinel
test_sentinel_isolated_per_cache
test_concurrency_same_session_emits_once
test_suppressed_fire_is_empty

echo ""
echo "=== Results ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    exit 1
fi
echo "All tdd-pretool-fires-once tests passed."
