#!/bin/bash
#
# GH #566 — test fixtures must FAIL CLOSED when their sandbox cannot be created.
#
# The bug this guards, stated as the failure it produced:
#
#   root=$(mktemp -d)     # fails under sandbox -> root is EMPTY
#   mkdir -p "$root"      # mkdir -p "" -> fails, status ignored (no set -e)
#   cd "$root"            # cd "" -> fails ("null directory"), status ignored
#   git init ...          # runs in the CURRENT directory. The real repo.
#
# Both guarded lines FAIL and both statuses were discarded, so execution walked
# straight past them into git commands aimed at the caller's working directory.
#
# `cd ""` IS VERSION-DEPENDENT, and the dangerous version is the default one:
#
#   bash 3.2  (/bin/bash on macOS - what every #!/bin/bash script gets)
#             -> returns 0, prints nothing, does not move.  SILENT.
#   bash 5.x  -> returns 1, prints "cd: null directory".
#
# So on macOS `cd "$root" || exit 1` DOES NOT FIRE on an empty root, which makes
# the per-call-site `root=$(new_root) || exit 1` the load-bearing guard there.
# On Linux CI the cd guard does fire. Both are needed.
#
# This was nearly mis-retracted mid-review: a check run under Homebrew bash 5
# contradicted the original bash 3.2 observation, and the true claim was briefly
# withdrawn as false. Recorded because the lesson is the point - "I tested it"
# is only evidence if you tested the same interpreter the code actually runs.
#
# These tests assert the OBSERVABLE consequence — files appearing in the caller's
# working directory — not the presence of any particular guard string. A test
# that greps the fixture for `|| exit 1` would pass on a fixture that guards the
# wrong variable.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

PASSED=0
FAILED=0

pass() { echo -e "\033[0;32mPASS\033[0m: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "\033[0;31mFAIL\033[0m: $1"; FAILED=$((FAILED + 1)); }

# A sandbox that is NOT the repo, containing a shadowing `mktemp` that always
# fails. Running a fixture with this on PATH reproduces the sandbox condition
# that caused the real incident.
#
# The stub fails on the Nth invocation only, and succeeds on every other.
#
# WHY N MATTERS — this guard was NOT-CERTIFIED once for getting it wrong.
# An always-failing mktemp aborts the fixture at its FIRST allocation, so call
# sites 2, 3 and 4 are never reached and their guards are never exercised.
# Review proved it by deleting `|| exit 1` from the second call site: the broken
# mutant still passed 3/3. That is the dead-check class this repo has shipped
# seven times — a guard that passes on the very thing it exists to reject.
#
# Failing on a selected invocation forces each allocation site to be the one
# that fails, so a missing guard anywhere is visible.
make_broken_mktemp_env() {
    local stage=$1
    local fail_on=$2
    mkdir -p "$stage/bin" "$stage/cwd"
    rm -f "$stage/mktemp-count"
    cat > "$stage/bin/mktemp" <<STUB
#!/bin/bash
# Counts invocations across the whole fixture run and fails on #$fail_on,
# simulating an unwritable TMPDIR at exactly that allocation.
count_file="$stage/mktemp-count"
n=\$(cat "\$count_file" 2>/dev/null || echo 0)
n=\$((n + 1))
echo "\$n" > "\$count_file"
if [ "\$n" -eq $fail_on ]; then
    echo "mktemp: failed to create directory" >&2
    exit 1
fi
exec /usr/bin/mktemp "\$@"
STUB
    chmod +x "$stage/bin/mktemp"
}

# ---------------------------------------------------------------------------
# 1. The fixture named in #566 must not write into the caller's cwd.
# ---------------------------------------------------------------------------
test_persist_score_history_fails_closed() {
    local fail_on=$1
    local stage
    stage=$(mktemp -d "${TMPDIR:-/tmp}/failclosed.XXXXXX") || {
        fail "could not stage the test itself"; return
    }
    make_broken_mktemp_env "$stage" "$fail_on"

    # Run the fixture from an empty directory with the failing mktemp first on
    # PATH. Nothing may appear in that directory.
    (
        cd "$stage/cwd" || exit 1
        # Execute directly so the shebang picks the interpreter, exactly as CI
        # and a human do. Running it as `bash <file>` picked up whatever bash is
        # first on PATH (5.x here) and silently tested a shell nobody uses --
        # which is why a mutant with a deleted guard survived this check once.
        PATH="$stage/bin:$PATH" "$REPO_ROOT/tests/test-persist-score-history.sh" > "$stage/out.txt" 2>&1
        echo $? > "$stage/exit.txt"
    )

    local polluted
    polluted=$(find "$stage/cwd" -mindepth 1 2>/dev/null | head -5)

    if [ -n "$polluted" ]; then
        fail "allocation #$fail_on fails -> the fixture wrote into the caller's cwd:"
        printf '        %s\n' $polluted
    else
        pass "allocation #$fail_on fails -> caller's cwd untouched"
    fi

    local rc
    rc=$(cat "$stage/exit.txt" 2>/dev/null || echo "missing")
    if [ "$rc" = "0" ]; then
        fail "allocation #$fail_on fails -> fixture exited 0, a green run that tested nothing"
    else
        pass "allocation #$fail_on fails -> fixture exits non-zero (got $rc)"
    fi

    rm -rf "$stage"
}

# ---------------------------------------------------------------------------
# 2. Pin the actual mechanism: `cd ""` FAILS and leaves you where you were.
#    That is what makes an unchecked `cd` catastrophic — the shell keeps going
#    in the caller's directory. Recorded so the reason for the guard survives a
#    rewrite, and so the retracted "cd \"\" returns 0" claim cannot creep back.
# ---------------------------------------------------------------------------
test_cd_empty_is_silent_under_the_shebang_shell() {
    local rc pwd_after
    read -r rc pwd_after <<< "$(/bin/bash -c 'cd /usr; cd "" 2>/dev/null; echo "$? $PWD"')"

    if [ "$rc" = "0" ] && [ "$pwd_after" = "/usr" ]; then
        pass "/bin/bash: cd \"\" returns 0 and does not move — an unguarded empty tmpdir is SILENT here"
    elif [ "$rc" != "0" ]; then
        pass "/bin/bash: cd \"\" fails (rc=$rc) — this shell catches it, the call-site guard still carries macOS"
    else
        fail "unexpected /bin/bash cd \"\" behaviour: rc=$rc pwd=$pwd_after"
    fi
}

echo "=== GH #566: fixtures fail closed when the sandbox cannot be created ==="
echo
# One run per allocation site. test-persist-score-history.sh calls new_root()
# four times; failing each in turn is what makes every guard observable.
for n in 1 2 3 4; do
    test_persist_score_history_fails_closed "$n"
done
test_cd_empty_is_silent_under_the_shebang_shell
echo
echo "=== Results: $PASSED passed, $FAILED failed ==="
[ "$FAILED" -eq 0 ]
