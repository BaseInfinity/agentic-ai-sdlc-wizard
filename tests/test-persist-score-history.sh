#!/bin/bash
# Regression tests for scripts/persist-score-history.sh
#
# Root cause this protects against (observed 2026-04-18 on PR #194 CI):
#   The "Persist scores to PR branch" step in ci.yml appends a score
#   commit and pushes `HEAD:refs/heads/<branch>`. When main advances
#   during CI and the PR branch gets a new commit from a concurrent
#   scorer (or a rebase), the push is rejected as non-fast-forward:
#
#     ! [rejected]        HEAD -> <branch> (fetch first)
#     error: failed to push some refs
#
#   The step was marked `continue-on-error: true`, so the failure was
#   silent. The append never landed on the PR branch, never got
#   squash-merged into main, and score-history.jsonl stayed stale for
#   19+ days even though the evaluator ran and produced valid scores.
#
# This test drives `scripts/persist-score-history.sh` which MUST
# fetch-rebase-retry on non-fast-forward rejection instead of giving up.

set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PERSIST="$REPO_ROOT/scripts/persist-score-history.sh"

PASSED=0
FAILED=0

pass() {
    echo -e "\033[0;32mPASS\033[0m: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "\033[0;31mFAIL\033[0m: $1"
    FAILED=$((FAILED + 1))
}

# Build a test setup:
#   <root>/remote.git   bare repo simulating GitHub
#   <root>/ci-clone     the CI's checkout (detached HEAD as if from refs/pull/N/merge)
#   <root>/adv-clone    a second clone that represents "main advanced during CI"
make_fixture() {
    local root=$1
    mkdir -p "$root"
    cd "$root"

    git init --bare --initial-branch=main remote.git > /dev/null

    # Seed the remote with an initial commit on main and a branch feature/x
    git clone -q remote.git seed
    cd seed
    git config user.email "seed@example.com"
    git config user.name "seed"
    echo "initial" > README.md
    git add README.md
    git commit -q -m "initial"
    git push -q origin main
    git checkout -qb feature/x
    mkdir -p tests/e2e
    echo '{"timestamp":"2026-01-01T00:00:00Z","score":7}' > tests/e2e/score-history.jsonl
    git add tests/e2e/score-history.jsonl
    git commit -q -m "seed history"
    git push -q origin feature/x
    cd ..
    rm -rf seed

    # The CI's pr-branch working dir — checkout feature/x, then put HEAD on
    # the merge ref like actions/checkout@v4 does on pull_request events.
    git clone -q remote.git ci-clone
    cd ci-clone
    git config user.email "ci@example.com"
    git config user.name "ci"
    git checkout -q feature/x
    # Detach to mimic refs/pull/N/merge behavior
    git checkout -q --detach HEAD
    cd ..
}

# Simulate a concurrent commit landing on feature/x after the CI clone started.
advance_remote_branch() {
    local root=$1
    git clone -q "$root/remote.git" "$root/adv-clone"
    cd "$root/adv-clone"
    git config user.email "other@example.com"
    git config user.name "other"
    git checkout -q feature/x
    echo '{"timestamp":"2026-04-18T00:00:00Z","score":8}' >> tests/e2e/score-history.jsonl
    git add tests/e2e/score-history.jsonl
    git commit -q -m "other score"
    git push -q origin feature/x
    cd - > /dev/null
}

# Append a new local score in the CI clone's detached HEAD
append_local_score() {
    local timestamp=$1
    echo "{\"timestamp\":\"$timestamp\",\"score\":9}" >> tests/e2e/score-history.jsonl
}

test_persist_succeeds_on_clean_push() {
    local root
    root=$(mktemp -d)
    make_fixture "$root"
    cd "$root/ci-clone"
    append_local_score "2026-04-18T12:00:00Z"
    if "$PERSIST" feature/x tests/e2e/score-history.jsonl > /tmp/persist-out 2>&1; then
        # Verify the commit landed on the remote branch
        local remote_has
        remote_has=$(git ls-remote origin refs/heads/feature/x | awk '{print $1}')
        local local_has
        local_has=$(git rev-parse HEAD)
        if [ "$remote_has" = "$local_has" ]; then
            pass "clean push lands on remote feature/x"
        else
            fail "clean push succeeded but remote head ($remote_has) != local head ($local_has). Output: $(cat /tmp/persist-out)"
        fi
    else
        fail "clean push returned non-zero. Output: $(cat /tmp/persist-out)"
    fi
    cd /
    rm -rf "$root"
}

test_persist_recovers_from_nonfastforward() {
    local root
    root=$(mktemp -d)
    make_fixture "$root"
    # CI clone is on feature/x seed commit; now advance the remote feature/x.
    advance_remote_branch "$root"
    cd "$root/ci-clone"
    append_local_score "2026-04-18T12:00:00Z"
    if "$PERSIST" feature/x tests/e2e/score-history.jsonl > /tmp/persist-out 2>&1; then
        # Both entries (from the concurrent commit AND from this run) should be present on remote.
        git fetch -q origin feature/x
        local line_count
        line_count=$(git show origin/feature/x:tests/e2e/score-history.jsonl | wc -l | tr -d ' ')
        if [ "$line_count" = "3" ]; then
            pass "push recovers from non-fast-forward and preserves concurrent commit"
        else
            fail "push recovered but history line count = $line_count (expected 3). Output: $(cat /tmp/persist-out)"
        fi
    else
        fail "persist returned non-zero on recoverable non-fast-forward. Output: $(cat /tmp/persist-out)"
    fi
    cd /
    rm -rf "$root"
}

test_persist_no_op_when_nothing_to_append() {
    local root
    root=$(mktemp -d)
    make_fixture "$root"
    cd "$root/ci-clone"
    # No change to score-history.jsonl
    if "$PERSIST" feature/x tests/e2e/score-history.jsonl > /tmp/persist-out 2>&1; then
        pass "persist is a no-op when nothing changed"
    else
        fail "persist returned non-zero with no changes. Output: $(cat /tmp/persist-out)"
    fi
    cd /
    rm -rf "$root"
}

# If the push is rejected for a reason OTHER than non-fast-forward (e.g.
# pre-receive hook, branch protection), rebase cannot fix it — we must
# exit 1 on the FIRST attempt and not waste budget retrying 3 times.
test_persist_exits_once_on_hook_rejected_push() {
    local root
    root=$(mktemp -d)
    make_fixture "$root"
    # Install a pre-receive hook that always declines.
    cat > "$root/remote.git/hooks/pre-receive" <<'HOOK'
#!/bin/sh
echo "pushes are disabled for this test"
exit 1
HOOK
    chmod +x "$root/remote.git/hooks/pre-receive"
    cd "$root/ci-clone"
    append_local_score "2026-04-18T12:00:00Z"
    local exit_code=0
    "$PERSIST" feature/x tests/e2e/score-history.jsonl > /tmp/persist-out 2>&1 || exit_code=$?
    local attempts
    attempts=$(grep -c 'attempt' /tmp/persist-out || true)
    if [ "$exit_code" != "0" ] && [ "$attempts" = "0" ]; then
        pass "persist exits once on hook-declined push (no retry)"
    else
        fail "persist should exit 1 on first attempt for hook rejection (exit=$exit_code, attempts=$attempts). Output: $(cat /tmp/persist-out)"
    fi
    cd /
    rm -rf "$root"
}

# #236(c): relocated from the dissolved tests/test-degradation-detection.sh —
# the [skip ci] marker lives in this shared script, so its test belongs here
# with the rest of persist-score-history.sh's regression suite.
test_skip_ci_marker_in_persist_script() {
    if grep -q "\[skip ci\]" "$PERSIST"; then
        pass "persist script commit message contains [skip ci]"
    else
        fail "scripts/persist-score-history.sh missing [skip ci] marker in commit message"
    fi
}

echo "=== Persist Score History Tests ==="
test_persist_succeeds_on_clean_push
test_persist_recovers_from_nonfastforward
test_persist_no_op_when_nothing_to_append
test_persist_exits_once_on_hook_rejected_push
test_skip_ci_marker_in_persist_script

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

[ "$FAILED" -eq 0 ]
