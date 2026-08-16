#!/bin/bash
# Guard scripts/post-comment.sh — the fixed-argv wrapper that exists because a
# permission pattern is the WRONG SHAPE for a write command (#650's SHAPE
# verdict, returned by a review leg against this very change).
#
# `Bash(gh pr comment:*)` was the first attempt. Allow rules are prefix/glob
# shapes and the dangerous flags TRAIL, so that pattern also authorized
# `--delete-last` (erasing a clearance comment the merge gate reads),
# `--edit-last`, and `-R other/repo`. Forbidding a suffix is not something the
# pattern language can express, so no pattern survives. A wrapper that builds
# its own argv does.
#
# The thing under test is therefore NOT "does it post a comment" but "can a
# caller reach any gh flag through it". Every row below is that question.

set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/post-comment.sh"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPDIR_T=$(mktemp -d "${TMPDIR:-/tmp}/post-comment.XXXXXX") || {
    echo "cannot create temp dir"; exit 1
}
trap 'rm -rf "$TMPDIR_T"' EXIT

# A stub `gh` that records the EXACT argv it was handed, one arg per line, so a
# smuggled flag is visible as its own line rather than hidden inside a string.
mkdir -p "$TMPDIR_T/bin"
cat > "$TMPDIR_T/bin/gh" <<'STUB'
#!/bin/bash
: > "$STUB_ARGV_FILE"
for a in "$@"; do printf '%s\n' "$a" >> "$STUB_ARGV_FILE"; done
# The stub also records the ambient target vars it INHERITED, because argv is
# only half the target. `gh` honours GH_REPO, so a wrapper with a spotless argv
# can still post to another repository entirely.
printf 'GH_REPO=%s\n' "${GH_REPO-}" > "$STUB_ENV_FILE"
printf 'GH_HOST=%s\n' "${GH_HOST-}" >> "$STUB_ENV_FILE"
echo "https://github.com/example/repo/pull/1#issuecomment-stub"
STUB
chmod +x "$TMPDIR_T/bin/gh"

BODY="$TMPDIR_T/body.md"
echo "a clearance body" > "$BODY"

export STUB_ARGV_FILE="$TMPDIR_T/argv.txt"
export STUB_ENV_FILE="$TMPDIR_T/env.txt"

# The repository this wrapper is pinned to. scripts/ is repo-local by charter
# (CLAUDE.md: deliberately never ships), so a constant is legitimate here and
# would not be under skills/.
PINNED_REPO="github.com/BaseInfinity/claude-sdlc-harness"

run_wrapper() {
    : > "$STUB_ARGV_FILE"
    PATH="$TMPDIR_T/bin:$PATH" "$SCRIPT" "$@" >/dev/null 2>&1
}

echo ""
echo "=== the wrapper exists and is executable ==="
if [ -x "$SCRIPT" ]; then
    pass "scripts/post-comment.sh is executable"
else
    fail "scripts/post-comment.sh is missing or not executable"
fi

echo ""
echo "=== the happy path invokes gh with a fixed argv ==="
for kind in pr issue; do
    if run_wrapper "$kind" 650 "$BODY"; then
        EXPECTED="$kind
comment
650
-R
$PINNED_REPO
--body-file
$BODY"
        if [ "$(cat "$STUB_ARGV_FILE")" = "$EXPECTED" ]; then
            pass "$kind: gh received exactly the fixed argv"
        else
            fail "$kind: gh argv is not the fixed one — got: $(tr '\n' ' ' < "$STUB_ARGV_FILE")"
        fi
    else
        fail "$kind: a legitimate post was refused"
    fi
done

echo ""
echo "=== no argument starting with '-' reaches gh ==="
# The whole point. A caller must not be able to append a flag through ANY
# position, so every position is tried rather than the one that looks likely.
for bad in --delete-last --edit-last -R; do
    if run_wrapper pr 650 "$BODY" "$bad"; then
        fail "a trailing $bad was accepted"
    else
        pass "a trailing $bad is refused"
    fi
    if grep -qx -- "$bad" "$STUB_ARGV_FILE" 2>/dev/null; then
        fail "$bad reached gh's argv"
    else
        pass "$bad never reached gh"
    fi
done
if run_wrapper -R pr 650 "$BODY"; then
    fail "a leading -R was accepted"
else
    pass "a leading -R is refused"
fi

echo ""
echo "=== the number must be a number ==="
# THE INJECTION ROW. `650 --delete-last` as ONE quoted argument does not start
# with '-', so a flag-prefix check alone lets it through and the shell splits
# it inside gh's argv. A positive grammar is what closes it.
for bad in "650 --delete-last" "650;rm -rf /" "" "abc" "-650"; do
    if run_wrapper pr "$bad" "$BODY"; then
        fail "number '$bad' was accepted"
    else
        pass "number '$bad' is refused"
    fi
    if grep -q -- "--delete-last" "$STUB_ARGV_FILE" 2>/dev/null; then
        fail "a flag smuggled through the number reached gh"
    fi
done

echo ""
echo "=== the kind is a closed set ==="
for bad in release repo "pr comment" ""; do
    if run_wrapper "$bad" 650 "$BODY"; then
        fail "kind '$bad' was accepted"
    else
        pass "kind '$bad' is refused"
    fi
done

echo ""
echo "=== the body file must exist and be readable ==="
if run_wrapper pr 650 "$TMPDIR_T/does-not-exist.md"; then
    fail "a missing body file was accepted"
else
    pass "a missing body file is refused"
fi
: > "$TMPDIR_T/empty.md"
if run_wrapper pr 650 "$TMPDIR_T/empty.md"; then
    fail "an empty body file was accepted — an empty clearance says nothing"
else
    pass "an empty body file is refused"
fi

echo ""
echo "=== argument count is exact ==="
if run_wrapper pr 650; then
    fail "a call with too few arguments was accepted"
else
    pass "too few arguments is refused"
fi
if run_wrapper pr 650 "$BODY" extra; then
    fail "a call with too many arguments was accepted"
else
    pass "too many arguments is refused"
fi

echo ""
echo "=== the target is a pinned constant, not inherited ==="
# ROUND 2 FINDING (sol, P0). The first version passed NO repo selector and let
# gh resolve the current remote. That is argv-only thinking: gh honours GH_REPO
# from the environment, so a wrapper with a spotless argv still posted wherever
# an inherited variable said. The 24-row suite passed throughout.
#
# MEASURED, not assumed, gh 2.92.0, read-only probes:
#   GH_REPO=cli/cli gh pr view 650 --json url          -> cli/cli        (redirected)
#   ... -R github.com/BaseInfinity/claude-sdlc-harness -> this repo      (flag wins)
#   ... -R BaseInfinity/claude-sdlc-harness            -> this repo      (flag wins)
#
# So the fix DECLARES the target rather than sanitizing the environment.
# `unset GH_REPO GH_HOST` is defence in depth and fails OPEN the moment gh adds
# another redirector — the same enumerate-the-cases trap merge-pr.sh's emit()
# documents at NUL. The pinned -R is the guard and holds under any
# flag-versus-env precedence.
run_wrapper pr 650 "$BODY"
if grep -qx -- "$PINNED_REPO" "$STUB_ARGV_FILE" 2>/dev/null; then
    pass "the repo selector is exactly the pinned constant"
else
    fail "the wrapper does not pin its target — gh resolves it from ambient state"
fi

GH_REPO=evil/repo GH_HOST=evil.example.com run_wrapper pr 650 "$BODY"
if grep -qx -- "$PINNED_REPO" "$STUB_ARGV_FILE" 2>/dev/null; then
    pass "an inherited GH_REPO does not move the target off the pinned repo"
else
    fail "GH_REPO redirected the target — the argv guard is not the whole target"
fi
if grep -qx -- "evil/repo" "$STUB_ARGV_FILE" 2>/dev/null; then
    fail "an inherited GH_REPO reached gh's argv"
else
    pass "an inherited GH_REPO never reaches gh's argv"
fi
if [ "$(cat "$STUB_ENV_FILE")" = "GH_REPO=
GH_HOST=" ]; then
    pass "GH_REPO and GH_HOST are cleared from gh's environment"
else
    fail "gh inherited a target variable: $(tr '\n' ' ' < "$STUB_ENV_FILE")"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
    echo "Some post-comment tests failed"
    exit 1
fi
echo "All post-comment tests passed!"
