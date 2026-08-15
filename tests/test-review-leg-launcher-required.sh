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

# ACCEPTED LIMIT (round 4 redesign): an option between `codex` and the
# subcommand escapes by design. See the header of the lane in the hook.
expect_allowed "ACCEPTED LIMIT: the alias behind an option that takes a value" \
    'codex --model gpt-5.6-sol e "review this"'

expect_allowed "ACCEPTED LIMIT: the alias behind a short option" \
    'codex -m gpt-5.6-sol e "review"'

# Wrappers must still be caught when they wrap codex ITSELF.
expect_refused "env wrapping codex directly" \
    'env codex exec "review"'

expect_allowed "ACCEPTED LIMIT: a wrapper carrying its own argument" \
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

# --- rounds 2 and 3, and the redesign they forced ---------------------------
#
# Round 2 (6/10) and round 3 (4/10) each demonstrated real facts about codex's
# option grammar that an option-aware predicate got wrong. The score across
# three rounds went 3 -> 6 -> 4: every fix was correct and every fix opened new
# surface, because modelling a CLI's grammar in a regex is building the parser
# #533 rules out. The gap is now closed instead of described.
#
# EVERY command either round demonstrated is still a row. The ones an
# option-aware predicate would have had to reason about are now ALLOWED, each
# an accepted limit rather than a defect — the direction this lane is permitted
# to be wrong in.

# Round 2: an option's VALUE is not the subcommand. From a directory containing
# `exec/`, `codex -C exec review --help` is a valid invocation of `codex
# review`. Correct then and correct now, by a rule with no arity in it.
expect_allowed "an option value named exec, short form" \
    'codex -C exec review --help'

expect_allowed "an option value named exec, model flag" \
    'codex -m exec review --help'

expect_allowed "an option value named exec, long form" \
    'codex --cd exec review --help'

expect_allowed "an option value named e" \
    'codex --model e review'

expect_allowed "ACCEPTED LIMIT: an option value, then the real subcommand" \
    'codex --model gpt-5.6-sol exec "review"'

expect_allowed "ACCEPTED LIMIT: short option with value, then the alias" \
    'codex -c model_reasoning_effort=high e "review"'

# Round 2: wrapper options that take a TEXTUAL value. All three reach codex.
# Round 3 then showed the letter class fixing these was wrong in BOTH
# directions at once — `xargs -E` takes a value and was missed, `sudo -n` is
# boolean and produced a false refusal. A wrapper now carries nothing.
expect_allowed "ACCEPTED LIMIT: env -u FOO wrapping a leg" \
    'env -u FOO codex exec "review"'

expect_allowed "ACCEPTED LIMIT: xargs -I X wrapping a leg" \
    'xargs -I X codex exec "review"'

expect_allowed "ACCEPTED LIMIT: sudo -u USER wrapping a leg" \
    'sudo -u USER codex exec "review"'

expect_allowed "ACCEPTED LIMIT: xargs -E, the uppercase value option round 3 found" \
    'xargs -E EOF codex exec "review"'

expect_allowed "sudo -n is BOOLEAN and echo is the command — a false refusal, now gone" \
    'sudo -n echo codex exec'

expect_allowed "env -i running echo, with the words as its argument" \
    'env -i echo codex exec'

# Round 3: `-h`/`-V` and their long forms terminate at global help/version and
# never dispatch exec. An option-aware predicate refused all four. There is no
# leg here to miss — these are pure false positives that the redesign removes.
expect_allowed "-h terminates at global help and never dispatches exec" \
    'codex -h exec'

expect_allowed "--help terminates at global help" \
    'codex --help exec'

expect_allowed "-V terminates at version" \
    'codex -V exec'

expect_allowed "--version terminates at version" \
    'codex --version exec'

# Round 3: compact short-option values. `codex -mfoo exec --help` reaches exec.
expect_allowed "ACCEPTED LIMIT: compact short value, model flag" \
    'codex -mfoo exec --help'

expect_allowed "ACCEPTED LIMIT: compact short value, sandbox flag" \
    'codex -sread-only exec --help'

expect_allowed "ACCEPTED LIMIT: compact short value, relocation flag" \
    'codex -C/tmp exec --help'

expect_allowed "ACCEPTED LIMIT: compact short value, approval flag" \
    'codex -anever exec --help'

# Round 3: `--image`/`-i` is VARIADIC, so `codex -i a exec --help` prints
# top-level help — `exec` is a second image operand, not the subcommand. The
# single-value model got this backwards. No arity model, no way to be wrong.
expect_allowed "-i is variadic, so a following 'exec' is another operand" \
    'codex -i a exec --help'

# --- round 4: the token boundary must be a SHELL boundary -------------------
# The redesign scored 8/10 with one blocker. `[^A-Za-z0-9_-]` treats `$`, `.`
# and `=` as ending the token, but all three CONTINUE it. The first row below
# is the reviewer's: bash expands it to a valid `codex exec-server --help`.

# shellcheck disable=SC2016  # the UNEXPANDED text is the input under test
expect_allowed "an expansion continues the token — this runs codex exec-server" \
    'SUFFIX=-server; codex exec$SUFFIX --help'

expect_allowed "a dot continues the token" \
    'codex exec.foo'

expect_allowed "an equals continues the token" \
    'codex exec=foo'

# ...and the boundaries that ARE real must still catch a leg.
expect_refused "end of line is a boundary" \
    'codex exec'

expect_refused "a redirection immediately after the subcommand is a boundary" \
    'codex exec>out.md'

expect_refused "a semicolon is a boundary" \
    'codex e;true'

# --- round 5: two independent reviewers, one one-line defect each -----------
# Both certified the round-4 design and each found a real blocker in it.

# `}` is not a shell token boundary. It closes a group only as a RESERVED WORD,
# which needs a preceding `;` or newline and its own whitespace; as a bare
# character it is ordinary. `bash -c 'printf "[%s]" exec}foo'` prints one word.
expect_allowed "a closing brace continues the token — it is not a metacharacter" \
    'codex exec}foo --help'

expect_allowed "an opening brace continues the token" \
    'codex exec{foo --help'

# The launcher escape hatch is GONE, and this is the shape that killed it: the
# lane used to be satisfied by MENTIONING the launcher anywhere in the command.
expect_refused "naming the launcher does not license a hand-typed leg beside it" \
    'scripts/run-review-leg.sh out p && codex exec "q"'

expect_refused "...nor does mentioning it in an argument" \
    'echo scripts/run-review-leg.sh; codex exec "q"'

# A boolean long option is an option like any other: it escapes.
expect_allowed "ACCEPTED LIMIT: a boolean long option before the subcommand" \
    'codex --oss exec "review"'

expect_allowed "ACCEPTED LIMIT: the = form of a value-taking option" \
    'codex --sandbox=read-only exec "review"'

# Forced failure for the hoisted guard above. Runs LAST so it cannot mask a
# real result, and only under the sentinel the guard sets.
if [ -n "${LAUNCHER_SUITE_FORCE_FAILURE:-}" ]; then
    fail "forced failure (LAUNCHER_SUITE_FORCE_FAILURE=1) — proves this suite can report one"
fi

echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
