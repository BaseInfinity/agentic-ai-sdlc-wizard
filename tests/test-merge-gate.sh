#!/bin/bash
# Tests for the repo-local merge-safety gate: .claude/hooks/merge-gate-check.sh
# (redirect-only PreToolUse hook) and scripts/merge-pr.sh (verifying wrapper).
#
# Both are intentionally repo-local, not shipped in hooks/hooks.json — see
# ROADMAP.md and CLAUDE_CODE_SDLC_WIZARD.md's CI Feedback Loop section for why.
# Kept in a dedicated file rather than tests/test-hooks.sh (which covers only
# shipped hooks) — mirrors tests/test-cowork-drift.sh's one-file-per-narrow-
# mechanism precedent.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../.claude/hooks/merge-gate-check.sh"
WRAPPER="$SCRIPT_DIR/../scripts/merge-pr.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Merge Gate Tests ==="
echo ""
echo "--- merge-gate-check.sh (redirect hook) ---"

# Test: hook script exists and is executable
test_hook_exists() {
    if [ -x "$HOOK" ]; then
        pass "merge-gate-check.sh exists and is executable"
    else
        fail "merge-gate-check.sh not found or not executable at $HOOK"
    fi
}

# Test: bare `gh pr merge` redirects
test_hook_redirects_bare_merge() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -q "scripts/merge-pr.sh"; then
        pass "bare 'gh pr merge' redirects to scripts/merge-pr.sh"
    else
        fail "bare 'gh pr merge' should redirect (exit 2, mention scripts/merge-pr.sh), got exit=$exit_code out=$out"
    fi
}

# Test: --squash form redirects
test_hook_redirects_squash() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --squash 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -q "scripts/merge-pr.sh"; then
        pass "'gh pr merge --squash' redirects to scripts/merge-pr.sh"
    else
        fail "'gh pr merge --squash' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: -m (merge commit) form redirects
test_hook_redirects_dash_m() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge -m 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh pr merge -m' redirects to scripts/merge-pr.sh"
    else
        fail "'gh pr merge -m' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: -r/--rebase form redirects (Fable's edge case — rebase must not walk
# around the gate just because the policy prose only mentions --squash)
test_hook_redirects_rebase() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --rebase 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh pr merge --rebase' redirects (not a bypass route)"
    else
        fail "'gh pr merge --rebase' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: --auto blocks unconditionally, with a distinct message that does NOT
# route to the wrapper (auto-merge stays permanently banned regardless of
# clearance — never presented as something the wrapper can satisfy)
test_hook_blocks_auto_unconditionally() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --auto 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ] && echo "$out" | grep -qi "unconditionally banned" && ! echo "$out" | grep -qi "^BLOCKED: use scripts/merge-pr.sh"; then
        pass "'gh pr merge --auto' blocks unconditionally, distinct from the redirect message"
    else
        fail "'gh pr merge --auto' should block with an auto-specific message, not a redirect, got exit=$exit_code out=$out"
    fi
}

# Test: unrelated command mentioning "merge" in prose only doesn't false-positive
test_hook_no_false_positive_on_prose() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m \"fix: merge conflict in gh pr workflow\""}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "prose mentioning 'gh pr merge'-like words in a commit message doesn't false-trigger"
    else
        fail "unrelated command should exit 0, got exit=$exit_code out=$out"
    fi
}

# Test: description field mentioning merge doesn't false-positive (matches
# codex-gate-check.sh's own round-2 lesson: match only the command field)
test_hook_no_false_positive_on_description_field() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git status","description":"check status before next gh pr merge"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "unrelated command with 'gh pr merge' only in description field doesn't false-trigger"
    else
        fail "should exit 0 when only description mentions merge, got exit=$exit_code out=$out"
    fi
}

# Test: embedded-quote command still extracts and matches correctly
test_hook_handles_embedded_quotes() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"cd \"$dir\" && gh pr merge --squash 123"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "command with embedded quotes still correctly redirects"
    else
        fail "embedded-quote command should still redirect, got exit=$exit_code out=$out"
    fi
}

# Test: MERGE_CLEARANCE_SKIP=1 bypasses the hook
test_hook_bypass_env_var() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --squash 123"}}' | MERGE_CLEARANCE_SKIP=1 "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "MERGE_CLEARANCE_SKIP=1 bypasses the redirect hook"
    else
        fail "MERGE_CLEARANCE_SKIP=1 should bypass, got exit=$exit_code out=$out"
    fi
}

# Test: malformed/missing command field doesn't crash
test_hook_handles_missing_command_field() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"foo":"bar"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "missing command field exits 0 cleanly, no crash"
    else
        fail "missing command field should exit 0, got exit=$exit_code out=$out"
    fi
}

test_hook_exists
test_hook_redirects_bare_merge
test_hook_redirects_squash
test_hook_redirects_dash_m
test_hook_redirects_rebase
test_hook_blocks_auto_unconditionally
test_hook_no_false_positive_on_prose
test_hook_no_false_positive_on_description_field
test_hook_handles_embedded_quotes
test_hook_bypass_env_var
test_hook_handles_missing_command_field

# Test: `gh -R owner/repo pr merge` (a global flag between gh and pr) still
# redirects — Codex round-1 finding #1: the original regex required "gh"
# immediately followed by "pr", missing this common, non-adversarial form.
test_hook_redirects_with_global_flag() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh -R owner/repo pr merge 123 --squash"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh -R owner/repo pr merge' redirects (global flag between gh and pr)"
    else
        fail "'gh -R owner/repo pr merge' should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: a merge command wrapped in a nested shell invocation still redirects
# — Codex round-1 finding #1: the original masking step collapsed the ENTIRE
# single-quoted nested command into a placeholder before matching, hiding
# "gh pr merge" from detection whenever it appeared inside `bash -lc '...'`.
test_hook_redirects_nested_shell_invocation() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"bash -lc '"'"'gh pr merge 123 --squash'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'bash -lc '\''gh pr merge ...'\''' (nested shell invocation) redirects"
    else
        fail "nested shell invocation of gh pr merge should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: hitting the merge REST endpoint directly via `gh api` also blocks —
# Codex round-1 finding #1: this bypasses the `gh pr merge` phrase match
# entirely since it never says those three words.
test_hook_redirects_gh_api_merge_endpoint() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh api -X PUT repos/owner/repo/pulls/123/merge"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh api -X PUT .../pulls/N/merge' (raw REST endpoint) redirects"
    else
        fail "gh api merge-endpoint call should redirect, got exit=$exit_code out=$out"
    fi
}

# Test: a merge command structurally embedded inside prose (not at a command
# boundary) does NOT false-trigger — Codex round-1 finding #6 (P2): the
# original matcher fired on ANY occurrence of the phrase anywhere in the
# command string, including inside explanatory text in a heredoc (this
# happened live to this session's own preflight doc). Tightened to require
# the phrase sit at a command boundary (start of string, or after
# ;/&&/||/|/newline/backtick-open), not mid-sentence prose.
test_hook_no_false_positive_on_embedded_prose() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"cat > doc.md << '"'"'EOF'"'"'\nThe policy requires gh pr merge to go through the wrapper.\nEOF"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' embedded mid-sentence in heredoc prose does not false-trigger"
    else
        fail "mid-sentence prose mentioning the phrase should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a quoted STRING ARGUMENT to an unrelated command (printf, not a
# shell-exec wrapper) mentioning the phrase does NOT false-trigger — Codex
# round-2 finding #6: removing all quote-masking (to fix round-1's nested
# `bash -lc '...'` bypass) over-corrected, since any quoted text containing
# the phrase now matched unconditionally, including inert printf/echo
# string arguments that were never going to run as a command.
test_hook_no_false_positive_on_quoted_printf_arg() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"printf '"'"'The policy requires gh pr merge to go through the wrapper.'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' inside a quoted printf argument does not false-trigger"
    else
        fail "phrase inside an inert printf argument should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a quoted commit message mentioning the phrase does NOT false-trigger
# — same class as above, Codex round-2 finding #6's second example.
test_hook_no_false_positive_on_quoted_commit_message() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"git commit -m '"'"'docs: explain gh pr merge policy'"'"'"}}' | "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "'gh pr merge' inside a quoted commit message does not false-trigger"
    else
        fail "phrase inside a commit message should not block, got exit=$exit_code out=$out"
    fi
}

# Test: a configured `gh` alias that expands to `pr merge` still redirects —
# Codex round-2 finding #1: literal-text matching alone can't see through
# a user-configured alias (e.g. `gh land` -> `pr merge`), since the
# expansion happens inside gh itself, invisible in the command text. Fixed
# by querying `gh alias list` (confirmed local/instant, ~54ms, no network)
# and treating an invocation of any alias whose expansion contains "pr
# merge" as equivalent to the literal phrase.
test_hook_redirects_configured_alias() {
    local tmpdir out exit_code
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "alias" ] && [ "$2" = "list" ]; then
    echo "land: pr merge"
    exit 0
fi
echo "unstubbed gh invocation in alias test: $*" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    out=$(printf '%s' '{"tool_input":{"command":"gh land 123 --auto"}}' | PATH="$tmpdir/bin:$PATH" "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 2 ]; then
        pass "'gh land' (configured alias for 'pr merge') is blocked like the literal phrase"
    else
        fail "configured alias expanding to 'pr merge' should be blocked, got exit=$exit_code out=$out"
    fi
}

test_hook_redirects_with_global_flag
test_hook_redirects_nested_shell_invocation
test_hook_redirects_gh_api_merge_endpoint
test_hook_no_false_positive_on_quoted_printf_arg
test_hook_no_false_positive_on_quoted_commit_message
test_hook_redirects_configured_alias
test_hook_no_false_positive_on_embedded_prose

echo ""
echo "--- merge-pr.sh (verifying wrapper) ---"

# All wrapper tests run in an isolated tmpdir with a stub `gh` on PATH so no
# real network/GitHub calls happen. The stub reads a small control file to
# decide what to return for each gh subcommand it's asked to fake.

setup_wrapper_fixture() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin" "$tmpdir/.reviews" "$tmpdir/tests"
    git init -q "$tmpdir"

    # Control file the stub gh reads: one KEY=VALUE per line.
    # HEAD_SHA, VALIDATE_CONCLUSION, DIFF_FILES (newline-separated, base64
    # would be overkill — use a sentinel-delimited list), DELETED_TEST_FILES,
    # RENAMED_TEST_FILES (space-separated "old->new" pairs, old under tests/,
    # new NOT under tests/ — simulates an effective deletion via rename),
    # PACKAGE_JSON_VERSION_CHANGED (boolean flag — the actual patch text
    # is hardcoded in the stub below, not passed through this sourced
    # config file, since embedding raw diff syntax like `+`/`-`/newlines
    # in a shell-sourced KEY=VALUE line is fragile), and BEYOND_FIRST_PAGE
    # (a filename only returned by the pulls/files stub when the real
    # command includes --paginate — simulates gh's default single-page
    # API behavior). package.json's patch is only available via the
    # pulls/files endpoint — NOT via `gh pr diff`, which has no per-path
    # filter flag.
    cat > "$tmpdir/.gh-stub-config" <<'CONFIG'
HEAD_SHA=abc123
VALIDATE_CONCLUSION=success
DIFF_FILES=src/foo.js
DELETED_TEST_FILES=
RENAMED_TEST_FILES=
PACKAGE_JSON_VERSION_CHANGED=
BEYOND_FIRST_PAGE=
CONFIG

    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
CONFIG="$(dirname "$0")/../.gh-stub-config"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && source "$CONFIG"

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    echo "{\"headRefOid\":\"$HEAD_SHA\",\"number\":${PR_NUM:-123},\"state\":\"OPEN\"}"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
    printf '%s\n' "$DIFF_FILES"
    exit 0
elif [ "$1" = "api" ]; then
    case "$*" in
        *check-runs*)
            echo "{\"conclusion\":\"$VALIDATE_CONCLUSION\",\"name\":\"validate\"}"
            ;;
        *pulls*files*)
            if [ -n "$DELETED_TEST_FILES" ]; then
                for f in $DELETED_TEST_FILES; do
                    echo "{\"filename\":\"$f\",\"status\":\"removed\"}"
                done
            fi
            if [ -n "$RENAMED_TEST_FILES" ]; then
                for pair in $RENAMED_TEST_FILES; do
                    old="${pair%%->*}"
                    new="${pair##*->}"
                    echo "{\"filename\":\"$new\",\"status\":\"renamed\",\"previous_filename\":\"$old\"}"
                done
            fi
            if [ -n "$PACKAGE_JSON_VERSION_CHANGED" ]; then
                printf '%s\n' '{"filename":"package.json","status":"modified","patch":"@@ -1,3 +1,3 @@\n {\n-  \"version\": \"1.0.0\",\n+  \"version\": \"1.0.1\","}'
            fi
            if [ -n "$BEYOND_FIRST_PAGE" ]; then
                case "$*" in
                    *--paginate*)
                        echo "{\"filename\":\"$BEYOND_FIRST_PAGE\",\"status\":\"removed\"}"
                        ;;
                esac
            fi
            ;;
    esac
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "merge" ]; then
    echo "GH_MERGE_INVOKED: $*"
    exit 0
fi
echo "unstubbed gh invocation: $*" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    echo "$tmpdir"
}

write_clearance() {
    local tmpdir="$1" pr="$2" status="$3" round="$4" sha="$5" review_file="$6"
    cat > "$tmpdir/.reviews/merge-clearance-$pr.json" <<JSON
{
  "pr_number": $pr,
  "status": "$status",
  "round": $round,
  "sha": "$sha",
  "review_file": "$review_file"
}
JSON
}

# Test: wrapper script exists and is executable (guards the tests below —
# without this, a missing-script "No such file or directory" error can
# coincidentally satisfy a loose substring match, e.g. the path itself
# containing "pr" or "merge-pr.sh", and false-PASS before any real code runs)
test_wrapper_exists() {
    if [ -x "$WRAPPER" ]; then
        pass "merge-pr.sh exists and is executable"
    else
        fail "merge-pr.sh not found or not executable at $WRAPPER"
    fi
}

# Test: no PR argument
test_wrapper_requires_pr_arg() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "usage" && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper requires a PR number argument"
    else
        fail "wrapper should fail with a usage message when no PR arg given, got exit=$exit_code out=$out"
    fi
}

# Test: gh failure fails closed
test_wrapper_fails_closed_on_gh_error() {
    local tmpdir out exit_code
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
echo "network error" >&2
exit 1
STUB
    chmod +x "$tmpdir/bin/gh"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper fails closed when gh errors"
    else
        fail "wrapper should fail closed on gh error, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate pending blocks
test_wrapper_blocks_ci_pending() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "pending"; then
        pass "wrapper blocks when CI validate is pending"
    else
        fail "wrapper should block on pending validate, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate skipped blocks (not treated as pass)
test_wrapper_blocks_ci_skipped() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=skipped/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "skipped"; then
        pass "wrapper blocks when CI validate is skipped"
    else
        fail "wrapper should block on skipped validate, got exit=$exit_code out=$out"
    fi
}

# Test: CI validate neutral blocks
test_wrapper_blocks_ci_neutral() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=neutral/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "neutral"; then
        pass "wrapper blocks when CI validate is neutral"
    else
        fail "wrapper should block on neutral validate, got exit=$exit_code out=$out"
    fi
}

# Test: missing clearance file blocks, naming the missing file
test_wrapper_blocks_missing_clearance() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "merge-clearance-123"; then
        pass "wrapper blocks and names the missing clearance file"
    else
        fail "wrapper should block naming merge-clearance-123.json, got exit=$exit_code out=$out"
    fi
}

# Test: clearance status != CERTIFIED blocks
test_wrapper_blocks_non_certified_status() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "PENDING_REVIEW" 1 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "PENDING_REVIEW\|CERTIFIED"; then
        pass "wrapper blocks when clearance status isn't CERTIFIED"
    else
        fail "wrapper should block on non-CERTIFIED status, got exit=$exit_code out=$out"
    fi
}

# Test: round-1-only CERTIFIED is treated as suspicious and blocks
test_wrapper_blocks_round_1_only() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks a round-1-only CERTIFIED as insufficient dialogue"
    else
        fail "wrapper should block round=1 CERTIFIED, got exit=$exit_code out=$out"
    fi
}

# Test: stale SHA (clearance doesn't match remote head) blocks
test_wrapper_blocks_stale_clearance() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "old-sha-999" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "stale"; then
        pass "wrapper blocks stale clearance (SHA mismatch vs remote head)"
    else
        fail "wrapper should block on stale SHA, got exit=$exit_code out=$out"
    fi
}

# Test: empty/missing review artifact file blocks
test_wrapper_blocks_empty_review_artifact() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/missing-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "review"; then
        pass "wrapper blocks when the referenced review artifact is missing/empty"
    else
        fail "wrapper should block on missing review artifact, got exit=$exit_code out=$out"
    fi
}

# Test: denylist match (workflow file) blocks, naming the path
test_wrapper_blocks_denylisted_workflow_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=.github/workflows/ci.yml#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "ci.yml"; then
        pass "wrapper blocks a PR touching .github/workflows/, naming the path"
    else
        fail "wrapper should block workflow-touching PR, got exit=$exit_code out=$out"
    fi
}

# Test: self-referential denylist — PR touching the wrapper/hook itself blocks
# (closes the exact loophole both Codex and Fable flagged: a PR editing the
# merge policy/mechanism wouldn't otherwise be excluded by a release-only list)
test_wrapper_blocks_self_referential_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=scripts/merge-pr.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "merge-pr.sh" && ! echo "$out" | grep -q "No such file or directory"; then
        pass "wrapper blocks a PR touching its own wrapper script (self-referential loophole closed)"
    else
        fail "wrapper should block self-referential touch, got exit=$exit_code out=$out"
    fi
}

# Test: net test-file deletion blocks
test_wrapper_blocks_test_deletion() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DELETED_TEST_FILES=#DELETED_TEST_FILES=tests/test-foo.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "test-foo.sh"; then
        pass "wrapper blocks a PR that net-deletes test files, naming the path"
    else
        fail "wrapper should block test deletion, got exit=$exit_code out=$out"
    fi
}

# Test: renaming a test file OUT of tests/ is an effective deletion and must
# block — Codex round-1 finding #4: the original check only recognized
# status:"removed", missing status:"renamed" with a previous_filename under
# tests/ and a new filename that isn't.
test_wrapper_blocks_test_file_renamed_out_of_tests_dir() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak "s#RENAMED_TEST_FILES=#RENAMED_TEST_FILES='tests/test-foo.sh->archive/test-foo.sh'#" "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "tests/test-foo.sh"; then
        pass "wrapper blocks a test file renamed out of tests/ (effective deletion)"
    else
        fail "wrapper should block a test renamed out of tests/, got exit=$exit_code out=$out"
    fi
}

# Test: pagination — a deleted test file beyond the API's first page must
# still be caught. Codex round-1 finding #3: the pulls/files call lacked
# --paginate, so gh's default single-page response silently hid anything
# past the first page.
test_wrapper_blocks_test_deletion_beyond_first_page() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#BEYOND_FIRST_PAGE=#BEYOND_FIRST_PAGE=tests/test-late-page.sh#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "test-late-page.sh"; then
        pass "wrapper catches a deleted test file beyond the API's first page (--paginate used)"
    else
        fail "wrapper should catch a beyond-first-page deletion, got exit=$exit_code out=$out"
    fi
}

# Test: a package.json version-field change is caught via the pulls/files
# patch content, not an invalid `gh pr diff -- <path>` call — Codex round-1
# finding #2: `gh pr diff <PR> -- package.json` is not valid gh syntax
# ("accepts at most 1 arg"); stderr was suppressed so the check silently
# no-opped, letting every version bump through unblocked.
test_wrapper_blocks_package_json_version_change() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak -e 's#DIFF_FILES=src/foo.js#DIFF_FILES=package.json#' \
        -e 's#PACKAGE_JSON_VERSION_CHANGED=#PACKAGE_JSON_VERSION_CHANGED=1#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "package.json"; then
        pass "wrapper blocks a package.json version-field change (patch-content check, not invalid gh pr diff syntax)"
    else
        fail "wrapper should block a package.json version change, got exit=$exit_code out=$out"
    fi
}

# Test: CLAUDE_CODE_SDLC_WIZARD.md is in the denylist — Codex round-1 finding
# #5: it contains the merge-confirmation policy itself, so a PR weakening
# that policy wasn't excluded from the exception it's editing.
test_wrapper_blocks_wizard_doc_touch() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DIFF_FILES=src/foo.js#DIFF_FILES=CLAUDE_CODE_SDLC_WIZARD.md#' "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "CLAUDE_CODE_SDLC_WIZARD.md"; then
        pass "wrapper blocks a PR touching CLAUDE_CODE_SDLC_WIZARD.md (contains the policy itself)"
    else
        fail "wrapper should block CLAUDE_CODE_SDLC_WIZARD.md touch, got exit=$exit_code out=$out"
    fi
}

# Test: all conditions pass — wrapper invokes the exact expected merge command
test_wrapper_merges_when_all_conditions_met() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "abc123" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED: pr merge 123 --squash --match-head-commit abc123"; then
        pass "wrapper merges with the exact expected command when all conditions are met"
    else
        fail "wrapper should invoke 'gh pr merge 123 --squash --match-head-commit abc123', got exit=$exit_code out=$out"
    fi
}

# Test: fail-fast ordering — when two conditions fail at once, the FIRST
# checked (denylist/self-reference) surfaces, not a later one, per the
# documented check order (denylist -> test-deletion -> CI -> clearance -> merge)
test_wrapper_fail_fast_ordering() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Fails BOTH denylist (workflow touch) AND CI (pending) simultaneously.
    sed -i.bak -e 's#DIFF_FILES=src/foo.js#DIFF_FILES=.github/workflows/ci.yml#' \
        -e 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "ci.yml" && ! echo "$out" | grep -qi "pending"; then
        pass "wrapper surfaces the denylist failure first, not the later CI check (documented fail-fast order)"
    else
        fail "wrapper should report the denylist match first when multiple conditions fail, got exit=$exit_code out=$out"
    fi
}

# Test: MERGE_CLEARANCE_SKIP=1 bypasses the wrapper's own checks but still
# merges (mirrors CODEX_GATE_SKIP semantics: skip THIS gate, don't do nothing)
# and logs a distinct BYPASSED line.
test_wrapper_bypass_still_merges_and_logs() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" MERGE_CLEARANCE_SKIP=1 "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -qi "BYPASSED" && echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "MERGE_CLEARANCE_SKIP=1 bypasses wrapper checks, still merges, logs BYPASSED"
    else
        fail "bypass should skip checks but still merge and log, got exit=$exit_code out=$out"
    fi
}

test_wrapper_requires_pr_arg
test_wrapper_fails_closed_on_gh_error
test_wrapper_blocks_ci_pending
test_wrapper_blocks_ci_skipped
test_wrapper_blocks_ci_neutral
test_wrapper_blocks_missing_clearance
test_wrapper_blocks_non_certified_status
test_wrapper_blocks_round_1_only
test_wrapper_blocks_stale_clearance
test_wrapper_blocks_empty_review_artifact
test_wrapper_blocks_denylisted_workflow_touch
test_wrapper_blocks_self_referential_touch
test_wrapper_blocks_test_deletion
test_wrapper_blocks_test_file_renamed_out_of_tests_dir
test_wrapper_blocks_test_deletion_beyond_first_page
test_wrapper_blocks_package_json_version_change
test_wrapper_blocks_wizard_doc_touch
test_wrapper_merges_when_all_conditions_met
test_wrapper_fail_fast_ordering
test_wrapper_bypass_still_merges_and_logs

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All merge gate tests passed!"

# ─────────────────────────────────────────────────────────────────────
# ROADMAP #478 — TIERED DENYLIST
#
# The flat denylist fired on 48% of PRs (12 of the last 25 measured), so
# its exception was the norm rather than the exception — which trains
# bypass habits. Worse, MERGE_CLEARANCE_SKIP=1 was all-or-nothing: escaping
# a benign doc hit ALSO disabled the CI check, the test-deletion check, and
# every clearance-artifact check.
#
# Fable xhigh design (see ROADMAP #478): split into HARD_DENY (live
# enforcement + release machinery — a human runs it, by design) and
# ACKABLE_DENY (prose that steers but doesn't mechanically enforce — may
# proceed with an explicit, user-confirmed acknowledgment in the clearance
# artifact while ALL other checks still run).
# ─────────────────────────────────────────────────────────────────────

test_hard_deny_covers_live_enforcement() {
    # hooks/ is this repo's LIVE enforcement (.claude/settings.json runs
    # codex-gate-check.sh etc. from $CLAUDE_PROJECT_DIR/hooks/), so a PR
    # gutting it weakens the pipeline that makes CERTIFIED mean anything.
    # Same for workflows (which define `validate` and hold publish secrets)
    # and the wrapper itself. These must NEVER be ackable.
    local missing=""
    for p in '\^\\\.github/workflows/' '\^hooks/' '\^\\\.claude/' '\^scripts/merge-pr\\\.sh\$'; do
        grep -A 12 'HARD_DENY=(' "$WRAPPER" | grep -q "$p" || missing="$missing $p"
    done
    if [ -z "$missing" ]; then
        pass "HARD_DENY covers workflows, hooks/, .claude/, and the wrapper itself"
    else
        fail "HARD_DENY missing live-enforcement patterns:$missing"
    fi
}

test_ackable_deny_covers_prose_only() {
    local missing=""
    for p in 'CLAUDE_CODE_SDLC_WIZARD' 'skills/sdlc/SKILL' 'cowork/skills/sdlc/SKILL'; do
        grep -A 8 'ACKABLE_DENY=(' "$WRAPPER" | grep -q "$p" || missing="$missing $p"
    done
    if [ -z "$missing" ]; then
        pass "ACKABLE_DENY covers the steering-prose paths"
    else
        fail "ACKABLE_DENY missing:$missing"
    fi
}

test_hooks_never_ackable() {
    # M2: moving ^hooks/ into the ackable tier must fail this test.
    if grep -A 8 'ACKABLE_DENY=(' "$WRAPPER" | grep -qE "\^hooks/|\^\\\\\.claude/|merge-pr"; then
        fail "live-enforcement path found in ACKABLE_DENY — must stay HARD"
    else
        pass "no live-enforcement path is ackable"
    fi
}

test_changelog_delisted() {
    # M1: re-adding ^CHANGELOG\.md$ to either tier must fail. It was pure
    # dead weight — release PRs touching it also bump package.json's
    # version, which the separate version-field check already blocks.
    # Scoped to the ARRAY BODIES so the explanatory comment doesn't count.
    local arrays
    arrays=$(sed -n '/^HARD_DENY=(/,/^)/p;/^ACKABLE_DENY=(/,/^)/p' "$WRAPPER")
    if printf '%s' "$arrays" | grep -q "CHANGELOG"; then
        fail "CHANGELOG.md is still denylisted — dead weight, already covered by the version-field check"
    else
        pass "CHANGELOG.md de-listed (covered by the package.json version check)"
    fi
}

test_ack_requires_user_confirmation() {
    # M7: dropping the requirement must fail. Checking merely that the
    # string "user_confirmed" appears somewhere is vacuous — the first
    # version of this test passed a mutation that hardcoded
    # ACK_CONFIRMED="yes" while leaving the word in a comment. Assert that
    # the value is actually DERIVED from the artifact.
    if grep -qE 'ACK_CONFIRMED=\$\(.*user_confirmed.*true' "$WRAPPER"; then
        pass "denylist ack derives user_confirmed from the clearance artifact"
    else
        fail "ack path must DERIVE user_confirmed:true from the artifact, not assume it"
    fi
}

test_ack_does_not_skip_other_checks() {
    # M3: the whole point — acking a denylist hit must NOT disable CI,
    # test-deletion, or clearance freshness the way MERGE_CLEARANCE_SKIP did.
    if grep -q 'ACK_DENYLIST_ONLY\|ack_scope_note' "$WRAPPER"; then
        pass "ack is scoped to the denylist; other checks still run"
    else
        fail "ack must be scoped — CI, test-deletion, and clearance checks must still run"
    fi
}

test_hard_deny_rejects_ack() {
    # M5: an ack naming a HARD path must be refused outright.
    if grep -q 'hard-tier\|HARD tier\|cannot be acknowledged' "$WRAPPER"; then
        pass "HARD tier explicitly rejects acknowledgment"
    else
        fail "wrapper must state that HARD-tier hits cannot be acknowledged"
    fi
}

test_hard_deny_covers_live_enforcement
test_ackable_deny_covers_prose_only
test_hooks_never_ackable
test_changelog_delisted
test_ack_requires_user_confirmation
test_ack_does_not_skip_other_checks
test_hard_deny_rejects_ack
