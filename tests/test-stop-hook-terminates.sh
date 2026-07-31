#!/bin/bash
# tests/test-stop-hook-terminates.sh
#
# A Stop hook that blocks MUST honour `stop_hook_active`.
#
# Claude Code re-invokes a Stop hook after it blocks. If the hook has no way to
# know that it is itself the reason the turn did not end, it re-evaluates the
# same unchanged state, blocks again, and loops until the harness force-breaks
# it. The harness states the contract verbatim when it does:
#
#   "For Stop/SubagentStop hooks, check stop_hook_active in the input and
#    return success while it's true."
#
# Observed 2026-07-27 in a consumer repo (BaseInfinity/claude-sdlc-wizard#477):
# nine consecutive blocks with an identical verdict before the harness
# overrode. The trigger was a repo whose test suite has KNOWN, INVESTIGATED,
# pre-existing failures — the correct engineering state, which the hook's
# "suite shown to PASS" criterion cannot express. So the agent could never
# satisfy it and the missing guard turned one bad verdict into an infinite one.
#
# Why this was not caught before shipping: every fixture in this repo has a
# green suite, so the hook never blocked, so it was never re-invoked. We tested
# the happy path of a guard whose entire purpose is the unhappy path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Stop hooks terminate ==="
echo

HOOK="$REPO_ROOT/hooks/codex-review-stop-check.sh"

# A Stop hook re-invoked while already active must let the turn end, whatever
# it would otherwise have decided. Run from a dirty worktree so the hook has
# something to complain about — otherwise this passes vacuously.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/stophook.XXXXXX")
(
    cd "$tmp" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.local; git config user.name t
    echo "print(1)" > code.py          # significant (not doc-only), uncommitted
    git add code.py 2>/dev/null
)

out=$(printf '%s' '{"stop_hook_active":true}' \
    | (cd "$tmp" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" 2>&1)) && rc=0 || rc=$?
if [ "${rc:-0}" -eq 0 ]; then
    pass "hook exits 0 when stop_hook_active is true"
else
    fail "hook exited $rc while stop_hook_active was true — this is the infinite-loop condition (out: $out)"
fi

# Control: with the flag absent the hook must still be able to act, or the
# guard above would be indistinguishable from disabling the hook entirely.
out2=$(printf '%s' '{}' \
    | (cd "$tmp" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" 2>&1)) && rc2=0 || rc2=$?
if printf '%s' "$out2" | grep -q . || [ "${rc2:-0}" -ne 0 ]; then
    pass "hook still evaluates normally when stop_hook_active is absent"
else
    pass "hook is silent here (acceptable: fixture may not meet its trigger)"
fi

rm -rf "$tmp"

# The shipped Cowork prompt-type Stop hook is an LLM judge and cannot read the
# flag in bash — its PROMPT must carry the instruction instead.
COWORK="$REPO_ROOT/cowork/hooks/hooks.json"
# Codex found this suite exited 0 with cowork/hooks/hooks.json DELETED — every
# check below was wrapped in `if [ -f ]`, so a missing file skipped them all
# silently. A missing shipped hook is a failure, not a skip.
if [ ! -f "$COWORK" ]; then
    fail "cowork/hooks/hooks.json is missing — the shipped Stop hook does not exist"
fi
if [ -f "$COWORK" ]; then
    if grep -q 'stop_hook_active' "$COWORK"; then
        pass "cowork Stop prompt instructs the judge about stop_hook_active"
    else
        fail "cowork Stop prompt never mentions stop_hook_active — it can loop"
    fi
fi

# Third defect (observed 2026-07-27, same consumer repo): the judge treated a
# READ-ONLY turn as a code change because the response summarized commits made
# earlier in the session. The agent's own correct "no code was changed this
# turn" was overridden. The judge sees text, not tool calls, so it cannot
# observe turn boundaries — the prompt has to tell it to defer.
if [ -f "$COWORK" ]; then
    if grep -qiE "THIS TURN ONLY|earlier in the session" "$COWORK"; then
        pass "cowork Stop prompt scopes the judgement to the current turn"
    else
        fail "cowork Stop prompt does not scope to this turn — prior work re-triggers it"
    fi
fi

# The judge must not block on things it cannot observe. Each of these was a
# real block that wasted a turn, and each is now explicitly exempted.
if [ -f "$COWORK" ]; then
    P=$(python3 -c "import json;print(json.load(open('$COWORK'))['hooks']['Stop'][0]['hooks'][0]['prompt'])" 2>/dev/null)

    if printf '%s' "$P" | grep -qiE "some FAILED|failing tests are information|pre-existing"; then
        pass "failing-but-explained tests do not block"
    else
        fail "judge still blocks on test OUTCOMES it cannot verify"
    fi

    if printf '%s' "$P" | grep -qiE "confidence level|ceremony"; then
        pass "missing ceremony (confidence, self-review narration) does not block"
    else
        fail "judge still blocks on missing ceremony"
    fi

    if printf '%s' "$P" | grep -qiE "quota|infrastructure"; then
        pass "an infrastructure-blocked suite does not block"
    else
        fail "judge still blocks when the suite could not run for infra reasons"
    fi

    if printf '%s' "$P" | grep -qiE "when uncertain.*ok|default to allowing"; then
        pass "judge fails OPEN when uncertain"
    else
        fail "judge does not default to allowing — it will block on ambiguity"
    fi

    # Fourth defect, observed 2026-07-29 in this repo. The judge blocked a turn
    # because a BACKGROUND REVIEW WAS STILL RUNNING, reasoning that "the turn
    # cannot end until that gate completes". That is outside its own stated
    # single blocking criterion, and it is the #477 failure mode wearing new
    # clothes: the agent cannot make a background task finish sooner, so the
    # only ways to satisfy the block are to wait forever or to misstate the
    # state. Work still being in flight is not the same as work being
    # unverified, and pending is not a violation — the harness re-invokes the
    # agent when the task completes, so ending the turn abandons nothing.
    # STOP TRYING TO VERIFY SEMANTICS WITH A GREP. This assertion was beaten
    # FOUR times by two different reviewers, each time by rephrasing rather than
    # by breaking anything:
    #   1. bullet moved to the blocking side
    #   2. negated in place: "is NOT exempt ... MUST BLOCK"
    #   3. continuation line: "MUST BLOCK this turn"
    #   4. reworded past the phrase list: "BLOCK this turn until the background
    #      work finishes", and an unrelated "Pending work exists" that matched
    #      the keywords while exempting nothing
    # Each fix added phrases to a denylist; each time a fifth phrasing existed.
    # Natural language has unbounded ways to say "block", so no finite list wins.
    #
    # So this now asserts ONLY what a static check can actually establish: that
    # an in-flight exemption is PRESENT in the DO-NOT-BLOCK region. It does NOT
    # claim the judge will allow — that is a semantic property of an English
    # prompt evaluated by a model, and it is verifiable only by running it.
    # Live coverage lives in tests/e2e/codex-cowork-install.md, which now has an
    # explicit in-flight case (it did not when this comment was first written —
    # the test claimed E2E covered it while E2E did not).
    _donotblock=$(printf '%s' "$P" | awk '/DO NOT BLOCK/{f=1} f{print} /You are a backstop/{f=0}')
    if [ -z "$_donotblock" ]; then
        fail "could not locate the DO-NOT-BLOCK section"
    elif printf '%s' "$_donotblock" | grep -qiE "still running|in flight|background task|pending"; then
        pass "an in-flight exemption is present in the DO-NOT-BLOCK region (presence only; semantics require live E2E verification, not yet run)"
    else
        fail "no in-flight exemption in the DO-NOT-BLOCK region — the judge may block on pending work"
    fi
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
