#!/bin/bash
# A review leg typed by hand instead of run through the launcher must be
# refused (#590 completion — the launcher existed, was documented, and was
# bypassed anyway).
#
# WHY THIS EXISTS RATHER THAN MORE DOCUMENTATION
#
# `scripts/run-review-leg.sh` has prevented the stdin hang since #590 closed.
# Its own header says "A leg typed ad hoc, outside this script, has no owner
# and no status." On 2026-08-14 two review legs for PR #606 were typed by hand
# anyway, in a session that had read that header: the first hung at 39 bytes
# with no `< /dev/null` — the exact signature #590 was closed on — and the
# second ran without the launcher's discipline and exhausted its budget with
# no verdict. The maintainer's reaction was "are we failing to do reviews is
# it breaking or hanging".
#
# Written knowledge that is not applied is the failure this closes. Both
# review legs ruled independently that the fix is mechanization, and that it
# belongs on the ALREADY-REGISTERED Bash gate rather than as a new hook.
#
# WHAT IT DOES NOT CLAIM. This is an accident-catcher for the in-harness Bash
# path, not a security boundary. A leg launched outside the Claude Code Bash
# tool never meets this hook, exactly as `merge-gate-check.sh` never meets a
# merge driven through a browser. Say that narrowly rather than overclaiming
# it, which is the error #479's ROADMAP note records.

set -u

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOOK="$REPO_ROOT/hooks/codex-gate-check.sh"
PASSED=0
FAILED=0

# The suite must be able to report a regression to CI. Hoisted ABOVE every
# definition, because a guard placed after the thing it guards is skipped by
# any early exit that lands between them (#598 round 20).
if [ -z "${LAUNCHER_SUITE_FORCE_FAILURE:-}" ]; then
    if LAUNCHER_SUITE_FORCE_FAILURE=1 "$0" > /dev/null 2>&1; then
        echo "FATAL: a forced failure still exited 0 — this suite cannot report a regression to CI" >&2
        exit 1
    fi
fi

pass() { PASSED=$((PASSED + 1)); printf '\033[0;32mPASS\033[0m: %s\n' "$1"; }
fail() { FAILED=$((FAILED + 1)); printf '\033[0;31mFAIL\033[0m: %s\n' "$1"; }

# Run the hook against one Bash command, exactly as Claude Code invokes it:
# the command arrives as the "command" field of a JSON tool-input on stdin.
# Exit 2 is a refusal; 0 is an allow.
run_hook() {
    python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"d"}}))' "$1" \
        | "$HOOK" > /dev/null 2>&1
    echo $?
}

expect_refused() {
    local desc="$1" cmd="$2" rc
    rc=$(run_hook "$cmd")
    if [ "$rc" = "2" ]; then
        pass "refused: $desc"
    else
        fail "ALLOWED (exit $rc), must be refused: $desc — [$cmd]"
    fi
}

expect_allowed() {
    local desc="$1" cmd="$2" rc
    rc=$(run_hook "$cmd")
    if [ "$rc" = "0" ]; then
        pass "allowed: $desc"
    else
        fail "REFUSED (exit $rc), must be allowed: $desc — [$cmd]"
    fi
}

# --- the shapes that must be refused ---------------------------------------
# These are real commands from the 2026-08-14 session, not invented ones.

expect_refused "bare codex exec, no launcher and no /dev/null (the leg that hung)" \
    'codex exec --model gpt-5.6-sol -c model_reasoning_effort=high "review this" > .reviews/out.md 2>&1'

expect_refused "bare codex exec WITH < /dev/null — the redirect is not the point, ownership is" \
    'codex exec --model gpt-5.6-sol "review this" < /dev/null > .reviews/out.md 2>&1'

expect_refused "codex exec after a cd" \
    'cd /tmp && codex exec --model gpt-5.6-sol "review"'

expect_refused "codex exec as the second command in a chain" \
    'git status; codex exec --model gpt-5.6-sol "review"'

expect_refused "codex exec with the sandbox flag this repo uses" \
    'codex exec --sandbox read-only --cd /Users/x "prompt" > out.md 2>&1'

# --- the shapes that must still be allowed ----------------------------------

expect_allowed "the launcher itself, which supplies /dev/null to its child" \
    'scripts/run-review-leg.sh .reviews/out.md "review this" --model gpt-5.6-sol'

expect_allowed "the launcher by absolute path" \
    "$REPO_ROOT/scripts/run-review-leg.sh .reviews/out.md \"review\" --model gpt-5.6-sol"

expect_allowed "prose that merely mentions the command — the #588 defect class, not repeated here" \
    'grep -rn "codex exec" CLAUDE_CODE_SDLC_WIZARD.md'

expect_allowed "a codex subcommand that is not exec" \
    'codex --version'

expect_allowed "an unrelated command" \
    'ls -la scripts/'

# Forced failure for the hoisted guard above. Runs LAST so it cannot mask a
# real result, and only under the sentinel the guard sets.
if [ -n "${LAUNCHER_SUITE_FORCE_FAILURE:-}" ]; then
    fail "forced failure (LAUNCHER_SUITE_FORCE_FAILURE=1) — proves this suite can report one"
fi

echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
