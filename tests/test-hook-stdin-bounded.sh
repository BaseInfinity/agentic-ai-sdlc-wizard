#!/bin/bash
# Hooks must never block forever on stdin.
#
# Found 2026-08-04 (#491 Class 2). Every shipped hook slurped stdin with an
# unbounded `$(cat)`, guarded only by `[ ! -t 0 ]` — "is stdin not a terminal".
# A unix socket is not a terminal, so the guard passes and `cat` waits for an
# EOF that never arrives. Observed live: hooks/sdlc-prompt-check.sh ran for
# 10h19m against a 10-second hook timeout, with `lsof` showing `0u unix`.
# The documented hook timeout did NOT reap it.
#
# Consumers inherit every one of these via cli/templates/settings.json, so this
# is a shipped defect, not a repo-local one.
#
# PORTABILITY: no `timeout(1)` — it does not exist on macOS, and this repo has
# already shipped two "61 files, 0 failing" reports from suites that silently
# ran zero tests because of it. Bounded waiting is done with a poll loop here,
# and the hooks' own fix uses bash's builtin `read -t`.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

WORKDIR=$(mktemp -d "${TMPDIR:-/tmp}/hook-stdin-XXXXXX") || {
    echo "FATAL: could not create temp dir"; exit 1
}

# Track every helper we spawn so a failing test can never leak a process.
HOLDER_PIDS=""
cleanup() {
    local p
    for p in $HOLDER_PIDS; do
        kill "$p" 2>/dev/null || true
    done
    rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "=== Hook stdin boundedness (#491 Class 2) ==="
echo ""

# Every shipped hook, DERIVED from the manifest — never hand-listed.
#
# This list used to be hardcoded, and that is precisely how the v1.94.0
# regression shipped: model-effort-check.sh was never in it, so the suite
# reported the hang class fixed while one hook still drained stdin with a bare
# `cat`. A hand-maintained roster of things-to-check silently stops covering
# whatever nobody remembered to add. Deriving from hooks/hooks.json means a
# newly registered hook is in scope the moment it is registered.
#
# .claude/hooks/merge-gate-check.sh is appended separately: it is repo-local by
# design (never shipped) so it cannot appear in the shipped manifest.
# Walk the manifest's actual "command" fields rather than regexing the blob for
# a flat hooks/<name>.sh shape. The flat pattern missed any hook registered in a
# subdirectory: a blocking hooks/nested/hang.sh was reported as covered while
# never being executed, and the coverage guard repeated the same blind spot, so
# the pair agreed on an answer that was wrong.
#
# Defined as a variable, not inlined into $( ... ): bash cannot parse a heredoc
# containing unbalanced parentheses inside a command substitution.
read -r -d '' EXTRACT_HOOKS <<'PY' || true
import json, re, sys
def commands(node):
    if isinstance(node, dict):
        if isinstance(node.get("command"), str):
            yield node["command"]
        for v in node.values():
            yield from commands(v)
    elif isinstance(node, list):
        for v in node:
            yield from commands(v)
with open(sys.argv[1]) as fh:
    manifest = json.load(fh)
seen = set()
for cmd in commands(manifest):
    m = re.search(r'((?:[A-Za-z0-9_.-]+/)*[A-Za-z0-9_.-]+[.]sh)', cmd)
    if m:
        seen.add(m.group(1))
print("\n".join(sorted(seen)))
PY

HOOKS="$(printf '%s' "$EXTRACT_HOOKS" | python3 - "$REPO_ROOT/hooks/hooks.json")
.claude/hooks/merge-gate-check.sh
"

# Guard the derivation itself. An extractor that returns nothing turns the
# hang test into a no-op that passes loudly — the exact vacuous-test shape this
# repo keeps rediscovering. Assert the roster is non-trivial AND covers every
# .sh the manifest names.
test_hook_roster_is_derived_and_complete() {
    local declared one missing="" count
    # Compare against the SEMANTIC set of commands in the manifest, not a flat
    # basename grep. The guard previously repeated the extractor's own blind
    # spot, so a nested hook was invisible to both and the pair agreed on an
    # answer that was wrong.
    declared=$(printf '%s' "$EXTRACT_HOOKS" | python3 - "$REPO_ROOT/hooks/hooks.json")
    if [ -z "$declared" ]; then
        fail "hooks.json names no .sh command — the extractor or the manifest broke"
        return
    fi
    for one in $declared; do
        printf '%s' "$HOOKS" | grep -qx "[[:space:]]*$one[[:space:]]*" \
            || printf '%s' "$HOOKS" | tr ' ' '\n' | grep -qx "$one" \
            || missing="$missing $one"
    done
    count=$(printf '%s\n' $declared | wc -l | tr -d ' ')
    if [ -n "$missing" ]; then
        fail "hook roster does not cover every manifest command — untested hooks:$missing"
    else
        pass "hook roster derived from hooks.json covers all $count registered hooks (any depth)"
    fi
}
test_hook_roster_is_derived_and_complete

# Run a hook with stdin attached to a pipe that never closes.
# Returns 0 if the hook exited on its own within $limit seconds, 1 if it had
# to be killed (i.e. it hung).
run_with_open_stdin() {
    local hook="$1" limit="$2"
    local fifo="$WORKDIR/fifo.$$"

    rm -f "$fifo"
    mkfifo "$fifo" || return 2

    # Hold the write end open, writing nothing. This is the observed shape:
    # stdin exists, is not a tty, and never reaches EOF.
    sleep "$((limit + 20))" > "$fifo" &
    local holder=$!
    HOLDER_PIDS="$HOLDER_PIDS $holder"

    "$REPO_ROOT/$hook" < "$fifo" > /dev/null 2>&1 &
    local pid=$!

    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$waited" -ge "$limit" ]; then
            kill -9 "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            kill "$holder" 2>/dev/null || true
            rm -f "$fifo"
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done

    wait "$pid" 2>/dev/null || true
    kill "$holder" 2>/dev/null || true
    rm -f "$fifo"
    return 0
}

# ────────────────────────────────────────────
# The defect: a hook must not outlive a stdin that never closes.
# 15s is generous — the hooks' own read timeout should fire well before it.
# ────────────────────────────────────────────
test_hooks_do_not_hang_on_open_stdin() {
    local hook hung="" absent="" checked=0
    for hook in $HOOKS; do
        # Do NOT silently `continue` on a missing file: a roster entry that
        # does not resolve is an untested hook, which is the failure being
        # guarded against, not a reason to score a pass.
        if [ ! -f "$REPO_ROOT/$hook" ]; then
            absent="$absent $hook"
            continue
        fi
        checked=$((checked + 1))
        if ! run_with_open_stdin "$hook" 15; then
            hung="$hung $hook"
        fi
    done

    if [ -n "$absent" ]; then
        fail "rostered hook file does not exist — it was never exercised:$absent"
    elif [ "$checked" -eq 0 ]; then
        fail "zero hooks exercised — the roster is empty and this test proves nothing"
    elif [ -z "$hung" ]; then
        pass "no shipped hook hangs when stdin never reaches EOF"
    else
        fail "hooks blocked forever on an open stdin — this is the 10h19m hang:
$(echo "$hung" | tr ' ' '\n' | sed '/^$/d' | sed 's/^/  hangs: /')"
    fi
}
test_hooks_do_not_hang_on_open_stdin

# ────────────────────────────────────────────
# Non-regression: bounding the read must not blind the hooks.
# codex-gate-check.sh is the observable one — it exits 2 on a commit command,
# which it can only know by having actually parsed stdin.
# ────────────────────────────────────────────
test_bounded_read_still_parses_normal_stdin() {
    local hook="$REPO_ROOT/hooks/codex-gate-check.sh"
    if [ ! -f "$hook" ]; then
        fail "codex-gate-check.sh missing — cannot verify stdin is still read"
        return
    fi

    # A commit command with no review artifact must be blocked (exit 2).
    # Run from a scratch dir so the repo's own .reviews/ state can't satisfy it.
    local out rc
    set +e
    out=$(cd "$WORKDIR" && printf '%s' \
        '{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}' \
        | "$hook" 2>&1)
    rc=$?
    set -e

    if [ "$rc" -eq 2 ]; then
        pass "bounded read still parses a normal piped payload (gate fired, exit 2)"
    else
        fail "gate did not fire on a piped commit payload (exit $rc) — the bounded read may have swallowed stdin. Output: $out"
    fi
}
test_bounded_read_still_parses_normal_stdin

# ────────────────────────────────────────────
# A hook handed empty stdin must exit promptly rather than blocking.
# ────────────────────────────────────────────
test_hooks_handle_empty_stdin() {
    local hook slow=""
    for hook in $HOOKS; do
        [ -f "$REPO_ROOT/$hook" ] || continue
        local start end
        start=$(date +%s)
        set +e
        printf '' | "$REPO_ROOT/$hook" > /dev/null 2>&1
        set -e
        end=$(date +%s)
        [ $((end - start)) -ge 10 ] && slow="$slow $hook"
    done

    if [ -z "$slow" ]; then
        pass "every hook returns promptly on empty stdin"
    else
        fail "hooks stalled on empty stdin:$slow"
    fi
}
test_hooks_handle_empty_stdin

# ────────────────────────────────────────────
# THE CASE THAT MATTERED, AND THAT THIS SUITE ORIGINALLY MISSED.
#
# Codex review 2026-08-05 (P0): the first version of the fix was tested only
# against (a) a pipe that writes nothing and (b) a normal pipe that closes.
# Neither is the dangerous shape. Write a COMPLETE payload with no trailing
# newline and then hold the pipe open: bash 3.2 discards the unterminated
# line on timeout, the gate saw empty input, and every gate fell through to
# exit 0 — turning a hang into a silent policy bypass.
#
# A gate that cannot read its input must DENY, never allow.
# ────────────────────────────────────────────
# NOTE: iterated with `while read`, NOT `for entry in $GATES`. The payloads
# contain spaces ("git commit -m wip"), and word-splitting shredded them into
# separate loop items — every gate then received a truncated payload and the
# assertion reported a bypass that wasn't real. A test that fails for the
# wrong reason is as useless as one that passes for the wrong reason.
read_gates() {
    cat <<'GATESEOF'
hooks/codex-gate-check.sh|{"tool_name":"Bash","tool_input":{"command":"git commit -m wip"}}
hooks/tdd-pretool-check.sh|{"tool_name":"Write","tool_input":{"file_path":"hooks/x.sh"}}
.claude/hooks/merge-gate-check.sh|{"tool_name":"Bash","tool_input":{"command":"gh pr merge 1 --squash"}}
GATESEOF
}

test_gates_fail_closed_on_stalled_stdin() {
    local hook payload rc allowed=""
    while IFS='|' read -r hook payload; do
        [ -n "$hook" ] || continue
        [ -f "$REPO_ROOT/$hook" ] || continue

        local fifo="$WORKDIR/gatefifo.$$"
        rm -f "$fifo"; mkfifo "$fifo" || continue

        # Hold the write end open on a dedicated fd IN THIS SHELL. A
        # `( printf ...; sleep N ) > fifo &` subshell is racy — the write end
        # sometimes closes anyway, the reader sees EOF, and the test silently
        # measures the wrong condition. An explicit fd cannot close early.
        #
        # `<>` (read-write), not `>`. Opening a FIFO write-only BLOCKS until a
        # reader appears, which deadlocks the test before the hook ever runs.
        exec 9<>"$fifo"
        printf '%s' "$payload" >&9      # complete payload, NO trailing newline

        set +e
        ( cd "$WORKDIR" && SDLC_HOOK_STDIN_TIMEOUT=2 "$REPO_ROOT/$hook" < "$fifo" > /dev/null 2>&1 )
        rc=$?
        set -e

        exec 9>&-
        rm -f "$fifo"

        # 2 = denied. Anything else on a stalled pipe is a bypass.
        [ "$rc" -ne 2 ] && allowed="$allowed $hook(exit=$rc)"
    done < <(read_gates)

    if [ -z "$allowed" ]; then
        pass "every gate FAILS CLOSED when stdin stalls mid-payload (no silent bypass)"
    else
        fail "gates ALLOWED on a stalled stdin — a hang turned into a policy bypass:$allowed"
    fi
}
test_gates_fail_closed_on_stalled_stdin

# ────────────────────────────────────────────
# The overall deadline must be overall, not per-read. A steady trickle of
# newlines restarted the per-read timer in the first version, so a hook could
# stay alive indefinitely while never reaching EOF (same review, P1).
# ────────────────────────────────────────────
test_deadline_is_overall_not_per_line() {
    local helper="$REPO_ROOT/hooks/_find-sdlc-root.sh"
    local fifo="$WORKDIR/trickle.$$"
    rm -f "$fifo"; mkfifo "$fifo" || { fail "mkfifo failed"; return; }

    # One line every 0.3s for far longer than the 2s deadline.
    ( for _ in $(seq 1 40); do printf 'x\n'; sleep 0.3; done ) > "$fifo" &
    local holder=$!
    HOLDER_PIDS="$HOLDER_PIDS $holder"

    local start end elapsed
    start=$(date +%s)
    set +e
    ( . "$helper"; SDLC_HOOK_STDIN_TIMEOUT=2 read_stdin_bounded > /dev/null ) < "$fifo"
    set -e
    end=$(date +%s)
    elapsed=$((end - start))

    kill "$holder" 2>/dev/null || true
    rm -f "$fifo"

    if [ "$elapsed" -le 6 ]; then
        pass "deadline is overall — a newline trickle cannot extend it (${elapsed}s against a 2s budget)"
    else
        fail "a newline trickle kept the read alive ${elapsed}s against a 2s budget — the timer is per-read, not overall"
    fi
}
test_deadline_is_overall_not_per_line

# ────────────────────────────────────────────
# A clean EOF close to the deadline must NOT be misread as a stall.
#
# Round-2 review (#491 P1): $SECONDS is integer and unaligned to when the read
# started, so it can overstate elapsed time by up to a second. With the
# deadline at `limit`, a clean EOF at 0.20s against a 1s budget falsely blocked
# 4 of 15 runs. The helper now measures against limit+1 so the configured
# timeout is a floor that is always honoured.
#
# Repeated, because the failure was intermittent — a single green run proved
# nothing about the original bug.
# ────────────────────────────────────────────
test_clean_eof_near_deadline_is_not_blocked() {
    local hook="$REPO_ROOT/hooks/codex-gate-check.sh"
    local payload='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    local i rc blocked=0 runs=15

    for i in $(seq 1 "$runs"); do
        set +e
        # The delay before EOF is ESSENTIAL and was missing at first: piping
        # with an instant EOF leaves $SECONDS at 0, so the granularity bug
        # cannot manifest and the assertion passes against broken code.
        # Verified by reverting the fix — instant-EOF gave 0/15, this shape
        # reproduces the reported 4/15. Do not "simplify" the sleep away.
        ( cd "$WORKDIR" && ( printf '%s' "$payload"; sleep 0.2 ) \
            | SDLC_HOOK_STDIN_TIMEOUT=1 "$hook" > /dev/null 2>&1 )
        rc=$?
        set -e
        [ "$rc" -eq 2 ] && blocked=$((blocked + 1))
    done

    if [ "$blocked" -eq 0 ]; then
        pass "clean EOF near the deadline is never misread as a stall (0/$runs false blocks at timeout=1)"
    else
        fail "integer-clock granularity falsely blocked a benign payload $blocked/$runs times at timeout=1 — the configured timeout is not a floor"
    fi
}
test_clean_eof_near_deadline_is_not_blocked

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -gt 0 ] && exit 1
echo "All hook stdin tests passed!"
exit 0
