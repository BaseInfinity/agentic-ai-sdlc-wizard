#!/bin/bash
# Wrap `codex exec` with a heartbeat that surfaces elapsed time + output
# growth so the user knows the review is running, not hung (#259). Reviews
# at `high` reasoning routinely take 1-5 minutes — without a progress signal
# the user can't distinguish "still thinking" from "crashed silently".
#
# Usage:
#   scripts/codex-review-with-progress.sh OUTPUT_FILE PROMPT [extra codex args...]
#
# Example (as a drop-in replacement for the Step 2 invocation in skills/sdlc/SKILL.md):
#   scripts/codex-review-with-progress.sh \
#     .reviews/latest-review.md \
#     "You are an independent code reviewer ..."
#
# Tunable via SDLC_CODEX_HEARTBEAT_INTERVAL (default 10 seconds).
#
# Heartbeat format: [codex 2m13s elapsed, 4831 bytes written] still running...
# On completion:    [codex finished in 187s with rc=0]
#
# The wrapper passes -c model_reasoning_effort="high" -s danger-full-access
# by default, matching the SDLC skill's recommended invocation. Pass extra
# codex flags after the prompt — they're forwarded verbatim.

set -e

if [ $# -lt 2 ]; then
    echo "usage: $0 OUTPUT_FILE PROMPT [extra codex args...]" >&2
    exit 64
fi

OUTPUT="$1"
PROMPT="$2"
shift 2

INTERVAL="${SDLC_CODEX_HEARTBEAT_INTERVAL:-10}"

# Validate INTERVAL as a positive integer (typo'd value would silently
# misbehave inside `sleep`). Fall back to 10 if not a clean integer.
case "$INTERVAL" in
    ''|*[!0-9]*) INTERVAL=10 ;;
esac
[ "$INTERVAL" -lt 1 ] && INTERVAL=10

# Allow tests to inject a different codex binary via SDLC_CODEX_BIN. In
# normal use the codex binary on PATH is invoked.
CODEX_BIN="${SDLC_CODEX_BIN:-codex}"

# Codex P2#3: preflight the binary so a missing/typoed CODEX_BIN exits with
# the canonical "command not found" rc=127 (instead of leaking a backgrounded
# bash error and rc=1).
if ! command -v "$CODEX_BIN" >/dev/null 2>&1; then
    echo "$0: codex binary not found: $CODEX_BIN" >&2
    exit 127
fi

# Codex P1#1 (round 1): install signal/exit traps so killing the wrapper
# kills the backgrounded codex too.
# Codex P1#1 (round 2): plain `sleep` blocks bash signal delivery — INT/TERM
# waits up to INTERVAL seconds before the trap fires. We background sleep
# and `wait` on it instead — `wait` IS interruptible. Cleanup kills both
# the codex child AND the sleep child so neither orphans.
CODEX_PID=""
SLEEP_PID=""
cleanup_codex() {
    if [ -n "${SLEEP_PID:-}" ] && kill -0 "$SLEEP_PID" 2>/dev/null; then
        kill -TERM "$SLEEP_PID" 2>/dev/null || true
    fi
    if [ -n "${CODEX_PID:-}" ] && kill -0 "$CODEX_PID" 2>/dev/null; then
        kill -TERM "$CODEX_PID" 2>/dev/null || true
        # Brief grace period (also via wait, not sleep — interruptible)
        sleep 1 & local grace_pid=$!
        wait "$grace_pid" 2>/dev/null || true
        if kill -0 "$CODEX_PID" 2>/dev/null; then
            kill -KILL "$CODEX_PID" 2>/dev/null || true
        fi
    fi
}
# INT/TERM/HUP: cleanup then exit 130 (canonical signal exit).
trap 'cleanup_codex; exit 130' INT TERM HUP
# EXIT: cleanup only (let exit code propagate naturally).
trap cleanup_codex EXIT

# Start codex in background. Default flags match the SDLC skill's
# recommended invocation; extra args (passed after the prompt) are
# appended so callers can override -c, --json, etc.
"$CODEX_BIN" exec \
    -c 'model_reasoning_effort="high"' \
    -s danger-full-access \
    -o "$OUTPUT" \
    "$@" \
    "$PROMPT" \
    < /dev/null &
CODEX_PID=$!

START=$(date +%s)
while kill -0 "$CODEX_PID" 2>/dev/null; do
    # Background `sleep` + `wait` so signals interrupt promptly (Codex P1#1
    # round 2). Plain `sleep` makes bash queue signals until it returns.
    sleep "$INTERVAL" &
    SLEEP_PID=$!
    wait "$SLEEP_PID" 2>/dev/null || true
    SLEEP_PID=""
    # Codex P1#2 (round 1): recheck liveness AFTER sleep — codex may have
    # exited during the interval. Without this, a fast-exiting codex would
    # still print one spurious "still running..." heartbeat.
    if ! kill -0 "$CODEX_PID" 2>/dev/null; then
        break
    fi
    NOW=$(date +%s)
    ELAPSED=$((NOW - START))
    MIN=$((ELAPSED / 60))
    SEC=$((ELAPSED % 60))
    if [ -f "$OUTPUT" ]; then
        SIZE=$(wc -c < "$OUTPUT" 2>/dev/null | tr -d ' ' || echo 0)
    else
        SIZE=0
    fi
    printf '[codex %dm%02ds elapsed, %s bytes written to %s] still running...\n' \
        "$MIN" "$SEC" "$SIZE" "$OUTPUT" >&2
done

# Reap the background process and capture its exit status. `set -e` would
# normally abort here on non-zero exits — `|| RC=$?` keeps that signal.
RC=0
wait "$CODEX_PID" || RC=$?

NOW=$(date +%s)
ELAPSED=$((NOW - START))
printf '[codex finished in %ds with rc=%d]\n' "$ELAPSED" "$RC" >&2
# Disarm cleanup trap — codex already exited, nothing to kill.
CODEX_PID=""
exit "$RC"
