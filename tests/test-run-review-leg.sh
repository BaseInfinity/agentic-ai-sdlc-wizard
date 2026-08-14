#!/bin/bash
# Tests for the review-leg launcher (#590).
#
# WHY THIS SUITE IS SHORT
#
# Two earlier designs put a second process in charge of deciding whether a leg
# was alive — first by reading the output file and the process table, then by
# reading pid/exit sidecars. Sol (GPT-5.6 high) falsified both with running
# code, and the tests for them were elaborate because the subject was
# unsound: fixtures had to simulate blocked reads, publication races, stale
# state and pid reuse.
#
# There is no second observer now. The launcher's own exit status is the
# verdict, delivered by the process that has it. What is left to test is what
# the launcher itself promises: the child gets EOF on stdin no matter what the
# launcher inherited, the child's exit status reaches the caller unchanged,
# and the output lands where it was asked to.
#
# The stub `codex` reads stdin to EOF, exactly as the real one does, so any
# test that finishes at all is proof the launcher supplied that EOF.

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/scripts/run-review-leg.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
FAIL=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASS=$((PASS + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAIL=$((FAIL + 1)); }

check_rc() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$desc"
    else
        fail "$desc (expected exit $expected, got $actual)"
    fi
}

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/run-review-leg-tests.XXXXXX") || {
    echo "FATAL: could not create a temp dir; refusing to run in the caller's repo" >&2
    exit 1
}
trap 'rm -rf "$TMPROOT"' EXIT

# Stub codex on PATH:
#   STUB_EXIT        exit status to return
#   STUB_STDOUT      text to print
#   STUB_READ_STDIN  read stdin to EOF first — the real codex behaviour behind
#                    the hang, so a launcher that fails to supply EOF blocks
#                    here forever instead of quietly passing.
STUBDIR="$TMPROOT/bin"
mkdir -p "$STUBDIR"
cat > "$STUBDIR/codex" <<'STUB'
#!/bin/bash
if [ -n "$STUB_READ_STDIN" ]; then
    cat > /dev/null
fi
printf '%s' "${STUB_STDOUT:-}"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$STUBDIR/codex"
export PATH="$STUBDIR:$PATH"
export STUB_READ_STDIN=1

echo "=== review-leg launcher (#590) ==="

new_leg() {
    local d
    d=$(mktemp -d "$TMPROOT/leg.XXXXXX")
    echo "$d/out.md"
}

# ---------------------------------------------------------------------------
# 1. A successful leg exits 0 and its output is in the file we named.
out=$(new_leg)
set +e
STUB_STDOUT=$'VERDICT: CERTIFIED\nNo defects found.\n' STUB_EXIT=0 \
    "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a successful leg exits 0" 0 "$rc"
if grep -qF 'VERDICT: CERTIFIED' "$out"; then
    pass "the leg's output lands in the named file"
else
    fail "the leg's output did not land in $out"
fi

# ---------------------------------------------------------------------------
# 2. The leg's exit status reaches the caller unchanged. This is the whole
# verdict mechanism: run as a background task, this status is what the
# completion notification carries, so nothing else needs to be consulted.
out=$(new_leg)
set +e
STUB_STDOUT='boom' STUB_EXIT=7 "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "the leg's exit status reaches the caller unchanged" 7 "$rc"

# ---------------------------------------------------------------------------
# 3. A failing leg's partial output is still readable — the failure is worth
# diagnosing, not discarding.
if grep -qF 'boom' "$out"; then
    pass "a failed leg's partial output is preserved"
else
    fail "a failed leg's output was lost"
fi

# ---------------------------------------------------------------------------
# 4. THE HANG, in the shape reproduced against real codex 0.147.0:
#
#     tail -f /dev/null | codex exec ... 'prompt'
#
# codex reads stdin to EOF and appends it to the argv prompt, so an unclosed
# pipe blocks it before it contacts the model. Here the LAUNCHER inherits that
# never-closing pipe. It must still complete, because it redirects its child's
# stdin rather than passing its own through.
#
# The pipe is a fifo this shell holds open on fd 9 rather than `tail -f`,
# which never exits and would hang the harness rather than the subject.
out=$(new_leg)
fifo="$(dirname "$out")/stdin.fifo"
mkfifo "$fifo"
exec 9<> "$fifo"
set +e
STUB_STDOUT='done' STUB_EXIT=0 "$RUNNER" "$out" 'review this' <"$fifo" >/dev/null 2>&1
rc=$?
set -e
exec 9>&-
rm -f "$fifo"
check_rc "a leg inheriting an unclosed pipe on stdin still completes" 0 "$rc"

# ---------------------------------------------------------------------------
# 5. A stale output file from a previous run is not mistaken for this run's.
out=$(new_leg)
printf 'OLD RUN: VERDICT CERTIFIED\n' > "$out"
set +e
STUB_STDOUT='fresh output' STUB_EXIT=0 "$RUNNER" "$out" 'review this' >/dev/null 2>&1
rc=$?
set -e
check_rc "a relaunch over an existing output file exits 0" 0 "$rc"
if grep -qF 'OLD RUN' "$out"; then
    fail "the previous run's output survived into this run's file"
else
    pass "the previous run's output is cleared, not appended to"
fi

# ---------------------------------------------------------------------------
# 6. Usage errors are distinguishable from a leg that ran and failed.
set +e
"$RUNNER" >/dev/null 2>&1
rc=$?
set -e
check_rc "no arguments is a usage error, exit 64" 64 "$rc"

set +e
"$RUNNER" "$(new_leg)" >/dev/null 2>&1
rc=$?
set -e
check_rc "an output file with no prompt is a usage error, exit 64" 64 "$rc"

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Some review-leg launcher tests failed"
    exit 1
fi
echo "All review-leg launcher tests passed!"
