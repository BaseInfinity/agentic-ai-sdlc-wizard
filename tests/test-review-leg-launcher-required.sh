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

# --- round 1 of cross-model review: every shape it demonstrated, as a row ----
#
# The reviewer ran these against the hook and reported the exit status; each is
# recorded here so the finding cannot come back silently. Its verdict was
# NOT CERTIFIED 3/10 on the first version of this lane.

# The declared alias. `codex --help` lists "exec ... [aliases: e]" and
# `codex e --help` prints exec's help; `ex` and `exe` do not resolve.
expect_refused "the declared 'e' alias — a real leg the first version allowed" \
    'codex e "review this"'

expect_refused "the alias behind an option that takes a value" \
    'codex --model gpt-5.6-sol e "review this"'

expect_refused "the alias behind a short option" \
    'codex -m gpt-5.6-sol e "review"'

# Wrappers must still be caught when they wrap codex ITSELF.
expect_refused "env wrapping codex directly" \
    'env codex exec "review"'

expect_refused "timeout wrapping codex directly" \
    'timeout 300 codex exec "review"'

expect_refused "an assignment prefix" \
    'FOO=bar codex exec "review"'

expect_refused "codex by absolute path" \
    '/usr/local/bin/codex exec "review"'

expect_refused "escaped command name" \
    '\codex exec "review"'

# False positives the first version introduced — these invoke no review leg.
# `exec` here is the review PROMPT, an argument, or a different subcommand.
expect_allowed "codex review with 'exec' as the prompt" \
    'codex review exec'

expect_allowed "codex help exec" \
    'codex help exec'

expect_allowed "exec-server is a different subcommand, not a complete 'exec' token" \
    'codex exec-server --help'

expect_allowed "a wrapper running echo, with the words as its argument" \
    'env echo codex exec'

expect_allowed "a wrapper running grep, with the words as its pattern" \
    'env grep codex exec README.md'

expect_allowed "a wrapper running ls, with the words as its path" \
    'env ls /tmp/codex exec'

# --- round 2 of cross-model review -----------------------------------------
# Its verdict was NOT CERTIFIED 6/10, two blockers, both demonstrated against
# the real CLI. It also reproduced the ten-row parity table exactly, which is
# what confirmed the other five round-1 findings as inherited.

# An option's VALUE is not the subcommand. From a directory containing `exec/`,
# `codex -C exec review --help` is a valid invocation of `codex review`.
expect_allowed "an option value named exec, short form" \
    'codex -C exec review --help'

expect_allowed "an option value named exec, model flag" \
    'codex -m exec review --help'

expect_allowed "an option value named exec, long form" \
    'codex --cd exec review --help'

expect_allowed "an option value named e" \
    'codex --model e review'

# ...but the value being consumed must not hide a real leg behind it.
expect_refused "a consumed option value followed by the real subcommand" \
    'codex --model gpt-5.6-sol exec "review"'

expect_refused "short option with value, then the alias" \
    'codex -c model_reasoning_effort=high e "review"'

# Wrapper options that take a TEXTUAL value. All three reach codex.
expect_refused "env -u FOO wrapping a leg" \
    'env -u FOO codex exec "review"'

expect_refused "xargs -I X wrapping a leg" \
    'xargs -I X codex exec "review"'

expect_refused "sudo -u USER wrapping a leg" \
    'sudo -u USER codex exec "review"'

# The wrapper carry must NOT admit a generic word, or round 1's wrapped-prose
# false positives come straight back.
expect_allowed "env -i running echo, with the words as its argument" \
    'env -i echo codex exec'

# --- pinning the two enumerated option lists --------------------------------
# Found by falsifying the arity fix before submitting it, not by a reviewer.
# These rows exist because both lists are transcribed from `codex --help`, and
# a CLI change is the way they rot silently: a boolean that becomes
# value-taking turns into a false REFUSAL, the direction that blocks the
# maintainer's own review leg.

expect_refused "a boolean long option consumes no value" \
    'codex --oss exec "review"'

expect_refused "a boolean short option consumes no value" \
    'codex -h exec'

expect_refused "a value-taking option in its = form" \
    'codex --sandbox=read-only exec "review"'

expect_refused "a value-taking option whose value is a path" \
    'codex --add-dir /tmp exec "review"'

expect_allowed "-a takes a value, so a following 'exec' is that value" \
    'codex -a exec review'

expect_allowed "--add-dir takes a value, so a following 'e' is that value" \
    'codex --add-dir e review'

# Forced failure for the hoisted guard above. Runs LAST so it cannot mask a
# real result, and only under the sentinel the guard sets.
if [ -n "${LAUNCHER_SUITE_FORCE_FAILURE:-}" ]; then
    fail "forced failure (LAUNCHER_SUITE_FORCE_FAILURE=1) — proves this suite can report one"
fi

echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
