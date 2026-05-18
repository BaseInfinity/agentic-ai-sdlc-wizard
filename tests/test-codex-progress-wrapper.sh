#!/bin/bash
# Quality tests for scripts/codex-review-with-progress.sh (#259).
# Uses a stub codex binary so tests don't burn real OpenAI tokens or
# require Codex to be installed in CI.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$SCRIPT_DIR/../scripts/codex-review-with-progress.sh"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

make_temp() {
    mktemp -d "${TMPDIR:-/tmp}/codex-progress-XXXXXX"
}

# Build a stub codex that:
#  - sleeps for $1 seconds (simulates a long review)
#  - writes "stub review output" to the -o file when finished
#  - exits with the given rc ($2, default 0)
make_stub_codex() {
    local bindir="$1" sleep_sec="${2:-3}" rc="${3:-0}"
    cat > "$bindir/codex" <<EOF
#!/bin/bash
output_file=""
prev_was_o=0
for arg in "\$@"; do
    if [ "\$prev_was_o" = "1" ]; then
        output_file="\$arg"
        prev_was_o=0
    elif [ "\$arg" = "-o" ]; then
        prev_was_o=1
    fi
done
sleep ${sleep_sec}
if [ -n "\$output_file" ]; then
    echo "stub review output, score 9/10 CERTIFIED" > "\$output_file"
fi
exit ${rc}
EOF
    chmod +x "$bindir/codex"
}

echo "=== Codex progress wrapper tests (#259) ==="
echo ""

test_wrapper_exists_and_executable() {
    if [ -x "$WRAPPER" ]; then
        pass "scripts/codex-review-with-progress.sh exists and is executable"
    else
        fail "wrapper missing or not executable: $WRAPPER"
    fi
}

test_wrapper_rejects_too_few_args() {
    local rc=0
    "$WRAPPER" 2>/dev/null || rc=$?
    if [ "$rc" -eq 64 ]; then
        pass "wrapper exits 64 on missing args (POSIX EX_USAGE)"
    else
        fail "wrapper should exit 64 on missing args, got rc=$rc"
    fi
}

test_wrapper_emits_heartbeat_during_long_run() {
    local d bindir output stderr_out heartbeat_count
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 3 0
    stderr_out=$(SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub prompt" 2>&1 >/dev/null)
    rm -rf "$d"
    heartbeat_count=$(echo "$stderr_out" | grep -c "still running" || true)
    if [ "$heartbeat_count" -ge 1 ]; then
        pass "wrapper emits at least 1 heartbeat during a 3s codex run (got ${heartbeat_count})"
    else
        fail "wrapper should emit heartbeats while codex runs (got: $stderr_out)"
    fi
}

test_wrapper_heartbeat_includes_elapsed_time() {
    local d bindir output stderr_out
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 2 0
    stderr_out=$(SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub prompt" 2>&1 >/dev/null)
    rm -rf "$d"
    if echo "$stderr_out" | grep -qE '\[codex [0-9]+m[0-9]{2}s elapsed,'; then
        pass "heartbeat format includes [codex Nm SSs elapsed, ...]"
    else
        fail "heartbeat should include elapsed-time prefix, got: $stderr_out"
    fi
}

test_wrapper_emits_completion_line() {
    local d bindir output stderr_out
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 1 0
    stderr_out=$(SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub prompt" 2>&1 >/dev/null)
    rm -rf "$d"
    if echo "$stderr_out" | grep -qE '\[codex finished in [0-9]+s with rc=0\]'; then
        pass "wrapper emits 'finished in Ns with rc=N' completion line"
    else
        fail "wrapper should emit completion line, got: $stderr_out"
    fi
}

test_wrapper_propagates_codex_rc() {
    local d bindir output rc=0
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 1 2
    SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub prompt" >/dev/null 2>&1 || rc=$?
    rm -rf "$d"
    if [ "$rc" -eq 2 ]; then
        pass "wrapper propagates codex exit code (rc=2)"
    else
        fail "wrapper should propagate codex rc=2, got rc=$rc"
    fi
}

test_wrapper_writes_output_file() {
    local d bindir output
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 1 0
    SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub prompt" >/dev/null 2>&1
    local ok=0
    [ -f "$output" ] && grep -q "CERTIFIED" "$output" && ok=1
    rm -rf "$d"
    if [ "$ok" = 1 ]; then
        pass "wrapper writes codex output to the requested file"
    else
        fail "wrapper should write output file"
    fi
}

test_wrapper_invalid_interval_falls_back() {
    local d bindir output stderr_out
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    make_stub_codex "$bindir" 1 0
    stderr_out=$(SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL="abc" \
        "$WRAPPER" "$output" "stub prompt" 2>&1 >/dev/null) || true
    rm -rf "$d"
    if ! echo "$stderr_out" | grep -qiE 'sleep:.*invalid|sleep:.*not.*number'; then
        pass "wrapper rejects invalid heartbeat interval and falls back to default"
    else
        fail "wrapper should validate SDLC_CODEX_HEARTBEAT_INTERVAL, got: $stderr_out"
    fi
}

# Codex round 1 P1#1: killing the wrapper must terminate the backgrounded
# codex too. Round 2 sharpened the assertion: with INTERVAL=10, plain `sleep`
# blocks signal delivery for up to 10s. Wrapper now uses `sleep & wait` to
# stay interruptible. Test asserts wrapper itself dies within 3s of TERM.
test_wrapper_kills_child_codex_on_termination_promptly() {
    local d bindir output codex_pid_file
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    codex_pid_file="$d/codex.pid"
    mkdir -p "$bindir"
    # Stub codex writes its PID then sleeps 30s — long enough that we KNOW
    # any termination is from cleanup, not natural exit.
    cat > "$bindir/codex" <<EOF
#!/bin/bash
echo "\$\$" > "${codex_pid_file}"
sleep 30
EOF
    chmod +x "$bindir/codex"
    SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=10 \
        "$WRAPPER" "$output" "stub" >/dev/null 2>&1 &
    local wrapper_pid=$!
    # Wait for codex to start (PID file written)
    local waited=0
    while [ ! -s "$codex_pid_file" ] && [ "$waited" -lt 50 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    if [ ! -s "$codex_pid_file" ]; then
        fail "#259 Codex#1 round 2: stub codex never started"
        kill -KILL "$wrapper_pid" 2>/dev/null || true
        rm -rf "$d"
        return
    fi
    local codex_pid
    codex_pid=$(cat "$codex_pid_file")
    # Send TERM and measure how long until both wrapper and codex are gone.
    local term_at
    term_at=$(date +%s)
    kill -TERM "$wrapper_pid" 2>/dev/null || true
    # Poll for both to die. Pre-fix, wrapper waits ~10s for sleep to return.
    waited=0
    while { kill -0 "$wrapper_pid" 2>/dev/null || kill -0 "$codex_pid" 2>/dev/null; } \
            && [ "$waited" -lt 30 ]; do
        sleep 0.1
        waited=$((waited + 1))
    done
    local wrapper_alive=no codex_alive=no
    kill -0 "$wrapper_pid" 2>/dev/null && wrapper_alive=yes
    kill -0 "$codex_pid" 2>/dev/null && codex_alive=yes
    # Cleanup any survivors
    kill -KILL "$wrapper_pid" 2>/dev/null || true
    kill -KILL "$codex_pid" 2>/dev/null || true
    rm -rf "$d"
    # Both should be dead within 3s (waited=30 × 0.1s). Pre-fix, wrapper
    # would still be alive at this point because plain `sleep 10` blocks.
    if [ "$wrapper_alive" = "no" ] && [ "$codex_alive" = "no" ]; then
        pass "#259 Codex#1 round 2: wrapper + child terminate within 3s of TERM (interruptible wait)"
    else
        fail "#259 Codex#1 round 2: termination not prompt (wrapper_alive=$wrapper_alive child_alive=$codex_alive after 3s)"
    fi
}

# Codex round 1 P1#2: heartbeat must NOT fire after codex has exited.
# Loop must recheck liveness after sleep, before printing.
test_wrapper_no_spurious_heartbeat_after_codex_exits() {
    local d bindir output stderr_out
    d=$(make_temp)
    bindir="$d/bin"
    output="$d/review.md"
    mkdir -p "$bindir"
    # Codex exits very fast (0.2s); with 1s heartbeat interval, after the sleep
    # codex is already gone. Pre-fix: we'd still print one heartbeat.
    cat > "$bindir/codex" <<EOF
#!/bin/bash
output_file=""
prev=0
for arg in "\$@"; do
    [ "\$prev" = "1" ] && output_file="\$arg" && prev=0
    [ "\$arg" = "-o" ] && prev=1
done
sleep 0.2
[ -n "\$output_file" ] && echo "fast" > "\$output_file"
EOF
    chmod +x "$bindir/codex"
    stderr_out=$(SDLC_CODEX_BIN="$bindir/codex" SDLC_CODEX_HEARTBEAT_INTERVAL=1 \
        "$WRAPPER" "$output" "stub" 2>&1 >/dev/null)
    rm -rf "$d"
    local heartbeat_count
    heartbeat_count=$(echo "$stderr_out" | grep -c "still running" || true)
    if [ "$heartbeat_count" -eq 0 ]; then
        pass "#259 Codex#2: no spurious heartbeat after fast-exiting codex (got 0)"
    else
        fail "#259 Codex#2: heartbeat fired ${heartbeat_count} time(s) after codex exited (expected 0)"
    fi
}

# Codex round 1 P2#3: missing codex binary must exit with rc=127, not leak
# a confused bash error.
test_wrapper_missing_codex_binary_exits_127() {
    local d output rc=0
    d=$(make_temp)
    output="$d/review.md"
    SDLC_CODEX_BIN="/definitely/not/a/real/codex/path" \
        "$WRAPPER" "$output" "stub" >/dev/null 2>&1 || rc=$?
    rm -rf "$d"
    if [ "$rc" -eq 127 ]; then
        pass "#259 Codex#3: missing codex binary exits 127 (POSIX command-not-found)"
    else
        fail "#259 Codex#3: missing codex should exit 127, got rc=$rc"
    fi
}

# Stdin-hang fix: the wrapper must redirect the child codex's stdin to
# /dev/null. Without it, codex from a non-interactive parent (background,
# hooks, CI, CC Bash tool) blocks on stdin reads even when the prompt is
# given as an argument — process sits at S/0% CPU indefinitely with a
# 0-byte -o output file. Validated on codex-cli 0.130.0 / macOS 14, 2026-05-15.
# This is a static check on the wrapper source — the redirect must exist.
test_wrapper_redirects_child_stdin_to_dev_null() {
    if [ ! -f "$WRAPPER" ]; then
        fail "wrapper script not found at $WRAPPER"
        return
    fi
    # Find the "$CODEX_BIN" exec invocation block and confirm it ends with
    # `< /dev/null &` (the redirect to /dev/null followed by background).
    if awk '
        /"\$CODEX_BIN" exec/ { in_block=1; depth=0; next }
        in_block {
            depth++
            if (/<[[:space:]]*\/dev\/null[[:space:]]*&/) { found=1; exit }
            if (depth > 15) { exit }
        }
        END { exit !found }
    ' "$WRAPPER"; then
        pass "wrapper redirects child codex stdin to /dev/null (stdin-hang fix)"
    else
        fail "wrapper's codex exec block must end with '< /dev/null &' to prevent codex stdin-read hang from non-interactive parents"
    fi
}

test_wrapper_exists_and_executable
test_wrapper_rejects_too_few_args
test_wrapper_emits_heartbeat_during_long_run
test_wrapper_heartbeat_includes_elapsed_time
test_wrapper_emits_completion_line
test_wrapper_propagates_codex_rc
test_wrapper_writes_output_file
test_wrapper_invalid_interval_falls_back
test_wrapper_kills_child_codex_on_termination_promptly
test_wrapper_no_spurious_heartbeat_after_codex_exits
test_wrapper_missing_codex_binary_exits_127
test_wrapper_redirects_child_stdin_to_dev_null

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then exit 1; fi
echo "All codex progress wrapper tests passed!"
