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

# Test: the hook has NO env-var escape at all (ROADMAP #479).
#
# This test used to assert the opposite — that MERGE_CLEARANCE_SKIP=1 bypassed
# the redirect. That variable is gone: it was the single lever that disabled
# every check at once, and its docstring claiming "both scripts must set it,
# intentional friction" was false, since both read the same variable name.
# Inverted rather than deleted, so reintroducing any env bypass fails loudly.
test_hook_has_no_env_bypass() {
    local out exit_code
    out=$(printf '%s' '{"tool_input":{"command":"gh pr merge --squash 123"}}' | MERGE_CLEARANCE_SKIP=1 "$HOOK" 2>&1) && exit_code=0 || exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        pass "the retired env var does not bypass the redirect hook"
    else
        fail "an env var bypassed the redirect hook, got exit=$exit_code out=$out"
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
test_hook_has_no_env_bypass
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

    # #540: the merge boundary compares the REMOTE HEAD's TREE against the
    # certified candidate_tree, so the fixture's head can no longer be a
    # made-up string like "abc123" — it has to be an object git can resolve.
    # The fixture therefore makes one real commit and publishes it as both the
    # PR head and origin/<base>. Tests that want a STALE sha still pass a
    # literal; only the "current head" ones read .fixture-sha.
    git -C "$tmpdir" config user.email t@example.com
    git -C "$tmpdir" config user.name "SDLC Test"
    printf 'fixture\n' > "$tmpdir/tests/keep.txt"
    git -C "$tmpdir" add tests/keep.txt
    git -C "$tmpdir" commit -qm fixture
    git -C "$tmpdir" rev-parse HEAD > "$tmpdir/.fixture-sha"
    git -C "$tmpdir" rev-parse 'HEAD^{tree}' > "$tmpdir/.fixture-tree"
    # origin/main must exist: base_tree is compared against the branch the PR
    # actually targets, read from the PR itself rather than assumed.
    git -C "$tmpdir" update-ref refs/remotes/origin/main HEAD

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
HEAD_SHA=__FIXTURE_SHA__
BASE_REF=main
VALIDATE_CONCLUSION=success
EXTRA_VALIDATE_CONCLUSION=
DIFF_FILES=src/foo.js
DELETED_TEST_FILES=
RENAMED_TEST_FILES=
PACKAGE_JSON_VERSION_CHANGED=
BEYOND_FIRST_PAGE=
CLEARANCE_PAYLOADS=
CONFIG
    # Splice the real sha in after the heredoc, which is quoted so it cannot
    # expand.
    sed -i.bak "s/__FIXTURE_SHA__/$(cat "$tmpdir/.fixture-sha")/" "$tmpdir/.gh-stub-config"
    rm -f "$tmpdir/.gh-stub-config.bak"

    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
CONFIG="$(dirname "$0")/../.gh-stub-config"
# shellcheck disable=SC1090
[ -f "$CONFIG" ] && source "$CONFIG"

if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    # The wrapper now asks for changedFiles separately to prove the classified
    # path set is complete; answer with the fixture's real count.
    case "$*" in
        *changedFiles*)
            n=0
            for _f in $DIFF_FILES; do n=$((n+1)); done
            for _f in ${DELETED_TEST_FILES:-}; do n=$((n+1)); done
            [ "$n" -eq 0 ] && n=1
            echo "$n"; exit 0 ;;
    esac
    # baseRefOid is SERVER truth about where the base branch is now. The local
    # refs/remotes/origin/<base> tracking ref is a cache and can be stale or
    # absent; both reviewers broke the gate through it in round 1.
    echo "{\"headRefOid\":\"$HEAD_SHA\",\"number\":${PR_NUM:-123},\"state\":\"OPEN\",\"baseRefName\":\"${BASE_REF:-main}\",\"baseRefOid\":\"${BASE_OID:-$HEAD_SHA}\"}"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
    printf '%s\n' "$DIFF_FILES"
    exit 0
elif [ "$1" = "api" ]; then
    case "$*" in
        *check-runs*)
            # REAL envelope: {"total_count":N,"check_runs":[...]}, one such object
            # per page, which is how `gh --paginate` concatenates pages. Codex
            # round 2: this stub emitted bare concatenated objects, exercising
            # NEITHER shape GitHub actually returns — so the extraction was being
            # validated against a payload that does not exist, and a real
            # bare-array page was silently dropped by the unwrap.
            #
            # A SECOND run also named "validate": branch protection requires the
            # check by NAME, so more than one can exist and the wrapper must not
            # stop at the first. `null` is emitted UNQUOTED, as a queued or
            # in-progress run really is, and "name" precedes "conclusion" as it
            # does live (the opposite of the API docs example).
            echo "{\"total_count\":1,\"check_runs\":[{\"name\":\"validate\",\"status\":\"completed\",\"conclusion\":\"$VALIDATE_CONCLUSION\"}]}"
            if [ -n "${EXTRA_VALIDATE_CONCLUSION:-}" ]; then
                if [ "$EXTRA_VALIDATE_CONCLUSION" = "null" ]; then
                    extra='{"name":"validate","status":"in_progress","conclusion":null}'
                else
                    extra="{\"name\":\"validate\",\"status\":\"completed\",\"conclusion\":\"$EXTRA_VALIDATE_CONCLUSION\"}"
                fi
                # EXTRA_VALIDATE_PAGE_SHAPE=bare emits a page as a naked array,
                # the shape the round-2 finding is about.
                case "${EXTRA_VALIDATE_PAGE_SHAPE:-wrapped}" in
                    bare) echo "[$extra]" ;;
                    *)    echo "{\"total_count\":1,\"check_runs\":[$extra]}" ;;
                esac
            fi
            ;;
        *issues*comments*)
            # Cross-model clearance comments. CLEARANCE_PAYLOADS holds one
            # compact JSON object per line; each becomes a PR comment wrapping
            # that object in the required marker + fenced json block.
            printf '['
            _first=1
            while IFS= read -r payload; do
                [ -z "$payload" ] && continue
                [ "$_first" -eq 0 ] && printf ','
                _first=0
                # Escape BACKSLASHES before quotes. Without this a payload
                # containing v was decoded by jq while parsing the comment
                # body, so it reached the parser as a plain literal and the
                # unicode-escape test silently tested nothing. GitHub's API
                # returns a real comment's backslash as \\, which is what this
                # now reproduces.
                # __FIXTURE_SHA__ resolves here rather than in the config,
                # because #540 made the fixture head a real git object and a
                # test cannot know its value at authoring time.
                payload=${payload//__FIXTURE_SHA__/$HEAD_SHA}
                printf '{"user":{"login":"maintainer"},"author_association":"OWNER","body":"**CROSS-MODEL-CLEARANCE**\\n\\n```json\\n%s\\n```"}' \
                    "$(printf '%s' "$payload" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
            done <<< "${CLEARANCE_PAYLOADS:-}"
            printf ']'
            ;;
        *pulls*files*)
            # Tier classification now reads THIS endpoint, not `gh pr diff`
            # (Codex round-2: diff output is display text and caps at 300
            # files). So it must list every changed path, not just deletions.
            for f in $DIFF_FILES; do
                echo "{\"filename\":\"$f\",\"status\":\"modified\"}"
            done
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
elif [ "$1" = "pr" ] && [ "$2" = "comment" ]; then
    # The override record. COMMENT_FAILS=1 simulates the post failing, which
    # must block the merge — an unrecorded override is exactly what
    # --user-approved exists to prevent.
    if [ "${COMMENT_FAILS:-0}" = "1" ]; then
        echo "stub: comment post failed" >&2
        exit 1
    fi
    # The wrapper suppresses gh's stdout, so the posted BODY is invisible to a
    # test that only reads the wrapper's output — which is exactly how the
    # round-1 record tests came to assert on a confirmation phrase instead of on
    # the payload. Persist it so the payload itself can be asserted.
    # Prefix EVERY line: a record body is multi-line, so an unprefixed dump is
    # unassertable with line-based grep — the path would sit on a different line
    # from the marker and a naive assertion would silently never match.
    printf '%s\n' "$*" | sed 's/^/GH_COMMENT_BODY: /' >> "$(dirname "$0")/../.posted-comments"
    echo "GH_COMMENT_POSTED: $*"
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
    # #540: a clearance names the CONTENT it was issued over, not just the
    # commit it sat on. Both default to the fixture's real trees so existing
    # rows keep testing what they were written to test; pass 7/8 to certify
    # content that is deliberately wrong.
    local cand="${7:-$(cat "$tmpdir/.fixture-tree")}"
    local base="${8:-$(cat "$tmpdir/.fixture-tree")}"
    cat > "$tmpdir/.reviews/merge-clearance-$pr.json" <<JSON
{
  "pr_number": $pr,
  "status": "$status",
  "round": $round,
  "sha": "$sha",
  "candidate_tree": "$cand",
  "base_tree": "$base",
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
    write_clearance "$tmpdir" 123 "PENDING_REVIEW" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -qi "round"; then
        pass "wrapper blocks a round-1-only CERTIFIED as insufficient dialogue"
    else
        fail "wrapper should block round=1 CERTIFIED, got exit=$exit_code out=$out"
    fi
}

# --- #540: the clearance names CONTENT, and the merge boundary checks it ---
#
# The hook can only speak for the index it saw before the commit; PreToolUse
# cannot observe post-command state. This is the other half, and the half that
# sees the object that actually merges.

# Test: certified content is not the content that would merge
test_wrapper_blocks_wrong_candidate_tree() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # A well-formed clearance, current SHA, round 2 — everything the pre-#540
    # gate asked for — but naming a tree that is not the one on the head.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "4b825dc642cb6eb9a060e54bf8d69288fbee4904" "$(cat "$tmpdir/.fixture-tree")"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "not the content that was certified"; then
        pass "wrapper blocks when the merging tree is not the certified candidate_tree"
    else
        fail "wrapper should block on candidate_tree mismatch, got exit=$exit_code out=$out"
    fi
}

# Test: the base moved under the certification. Same candidate_tree, different
# base — a rebase onto moved upstream leaves the diff alone and changes the
# result, which is the measurement that killed patch-id as the primitive.
test_wrapper_blocks_moved_base() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md" \
        "$(cat "$tmpdir/.fixture-tree")" "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "the base moved since certification"; then
        pass "wrapper blocks when the certified base_tree is not the current base"
    else
        fail "wrapper should block on base_tree mismatch, got exit=$exit_code out=$out"
    fi
}

# Test: the SERVER base moved while the local tracking ref stayed put.
#
# Round 1, found independently by BOTH reviewers and constructed rather than
# argued. The first version of this check read `origin/$BASE_BRANCH^{tree}` — a
# local cache — and skipped the comparison entirely when that ref was absent.
# Sol built a bare server repo, advanced server main, left refs/remotes/origin/
# main at the certified commit, and merged a bogus certification at exit 0.
# Fable reached the same exit 0 by deleting the ref outright.
#
# The base is now read from the PR's baseRefOid, which is server truth. This row
# is the regression: the local ref deliberately still says "unchanged".
test_wrapper_blocks_moved_server_base_with_stale_tracking_ref() {
    local tmpdir out exit_code candidate_sha candidate_tree server_base_sha
    tmpdir=$(setup_wrapper_fixture)
    candidate_sha=$(cat "$tmpdir/.fixture-sha")
    candidate_tree=$(cat "$tmpdir/.fixture-tree")

    printf 'server base moved\n' > "$tmpdir/server-base.txt"
    git -C "$tmpdir" add server-base.txt
    git -C "$tmpdir" commit -qm 'move server base'
    server_base_sha=$(git -C "$tmpdir" rev-parse HEAD)

    # Back to the certified content, and the local tracking ref left lying.
    git -C "$tmpdir" reset -q --hard "$candidate_sha"
    git -C "$tmpdir" update-ref refs/remotes/origin/main "$candidate_sha"
    echo "BASE_OID=$server_base_sha" >> "$tmpdir/.gh-stub-config"

    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$candidate_sha" ".reviews/some-review.md" \
        "$candidate_tree" "$candidate_tree"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "the base moved since certification"; then
        pass "wrapper blocks when the server base moved despite a stale local tracking ref"
    else
        fail "stale origin/main authorized a merge past a moved server base: exit=$exit_code out=$out"
    fi
}

# Test: the base object named by the PR cannot be read, so nothing can be
# compared. Same posture as the unreadable remote head ten lines above it —
# the first version skipped the check instead, which is fail-OPEN in the one
# situation where the answer is unknown.
test_wrapper_blocks_unreadable_base_object() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    echo "BASE_OID=ffffffffffffffffffffffffffffffffffffffff" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    # Asserting the SPECIFIC message, not just a non-zero exit. Neutering the
    # fail-closed branch leaves CUR_BASE_TREE empty, which the mismatch check
    # below it then rejects anyway — so an exit-code-only assertion stays green
    # through the mutation and proves nothing. Measured, not assumed.
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED" \
        && echo "$out" | grep -q "could not read the tree of the base commit"; then
        pass "wrapper blocks when the PR's base object cannot be read"
    else
        fail "unreadable base object should block on the unreadable-base branch, got exit=$exit_code out=$out"
    fi
}

# Test: the pre-#540 artifact format fails closed. A clearance carrying only a
# sha named no content, and honouring it would be the hole reopened under an
# older key — the same posture #437 took for a missing commit_sha.
test_wrapper_blocks_clearance_without_trees() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    # Hand-written in the OLD shape: no candidate_tree, no base_tree.
    cat > "$tmpdir/.reviews/merge-clearance-123.json" <<JSON
{
  "pr_number": 123,
  "status": "CERTIFIED",
  "round": 2,
  "sha": "$(cat "$tmpdir/.fixture-sha")",
  "review_file": ".reviews/some-review.md"
}
JSON
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && echo "$out" | grep -q "declares no 'candidate_tree'"; then
        pass "wrapper fails closed on a pre-#540 clearance that names no content"
    else
        fail "wrapper should block a clearance with no candidate_tree, got exit=$exit_code out=$out"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/missing-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
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
    local tmpdir out exit_code fixture_sha
    tmpdir=$(setup_wrapper_fixture)
    # Captured BEFORE the fixture is removed. Reading it afterwards substitutes
    # the empty string, which leaves a prefix match that passes without ever
    # checking the SHA — the whole point of this row (Sol, round 1 P2).
    fixture_sha=$(cat "$tmpdir/.fixture-sha")
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$fixture_sha" ".reviews/some-review.md"
    echo "content" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && echo "$out" | grep -q "GH_MERGE_INVOKED: pr merge 123 --squash --match-head-commit $fixture_sha"; then
        pass "wrapper merges with the exact expected command when all conditions are met"
    else
        fail "wrapper should invoke 'gh pr merge 123 --squash --match-head-commit <fixture sha>', got exit=$exit_code out=$out"
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

# Test: no env var can make the wrapper merge past a RED CI check (#479).
#
# This test used to assert that MERGE_CLEARANCE_SKIP=1 merged anyway while
# logging BYPASSED. That is precisely the defect #479 names: acknowledging one
# denylist row also disarmed CI, test-deletion, SHA-freshness and the clearance
# artifact. CI is pending in this fixture, so a merge here would be a merge on
# unverified code. Inverted rather than deleted: it now guards the property.
test_wrapper_has_no_env_bypass() {
    local tmpdir out exit_code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's/VALIDATE_CONCLUSION=success/VALIDATE_CONCLUSION=pending/' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" MERGE_CLEARANCE_SKIP=1 "$WRAPPER" 123 2>&1) && exit_code=0 || exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -ne 0 ] && ! echo "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "no env var merges past a red CI check"
    else
        fail "an env var merged past red CI, got exit=$exit_code out=$out"
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
test_wrapper_blocks_wrong_candidate_tree
test_wrapper_blocks_moved_base
test_wrapper_blocks_moved_server_base_with_stale_tracking_ref
test_wrapper_blocks_unreadable_base_object
test_wrapper_blocks_clearance_without_trees
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
test_wrapper_has_no_env_bypass

# --- Cross-model clearance payloads (GH #478) --------------------------------
#
# A missing VERDICT field survived here despite verify_cross_model_clearance
# being well covered — 49 assertions in tests/test-cross-model-clearance.sh over
# confidence bounds, SHA binding, authorship and payload visibility. Every one
# fed a fixture that omitted a verdict, so the suite tested the SHAPE of the
# evidence and never the ANSWER inside it: a payload asserting MERGE_SAFE: NO in
# its prose while carrying confidence 97 satisfied every check and merged.
# Confidence was standing in for a decision nobody had modelled.
#
# Helper: run the wrapper against a fixture whose PR comments carry $1 (one
# compact JSON payload per line), touching an ACKABLE_DENY path so clearance
# is actually consulted, and echo "exit=<n> <output>".
run_with_clearance() {
    local payloads="$1" tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=CLAUDE_CODE_SDLC_WIZARD.md\n' >> "$tmpdir/.gh-stub-config"
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' "$payloads")" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --cross-model-cleared 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    printf 'exit=%s %s' "$code" "$out"
}

# Assert the merge DID NOT HAPPEN, not merely that the exit code was nonzero.
# Codex found the first version of these tests checking exit status and message
# text — the SHAPE of the refusal — while the stub's GH_MERGE_INVOKED line proved
# the merge had actually fired in some cases. That is the identical defect this
# whole change exists to fix: 49 assertions checked the shape of the clearance
# evidence and never the answer inside it. The side effect is the ground truth.
refute_merge() {  # $1=result  $2=what was being attempted
    if printf '%s' "$1" | grep -q "GH_MERGE_INVOKED"; then
        fail "$2 — the merge ACTUALLY FIRED: $1"
    elif printf '%s' "$1" | grep -q "^exit=0"; then
        fail "$2 — wrapper exited 0: $1"
    else
        pass "$2"
    fi
}

test_clearance_requires_verdict_field() {
    # Two reviewers, both >=95, both bound to the head SHA, NEITHER declaring a
    # verdict. Confidence alone must not clear a merge.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","confidence":96,"sha":"__FIXTURE_SHA__"}')" \
        "clearance with no verdict field does not merge"
}

test_clearance_rejects_negative_verdict() {
    # THE DEFECT, stated as a test: a reviewer who says NO, at high confidence,
    # must never clear. Before the fix this merged.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"NO","confidence":99,"sha":"__FIXTURE_SHA__"}')" \
        "two confident NO verdicts do not merge"
}

test_clearance_rejects_lowercase_verdict() {
    # Codex: `ascii_upcase` in the jq projection normalised 'yes' and 'YeS' into
    # YES, so the exact-match check I had documented as strict was not strict.
    # A verdict is a machine-written field in a machine-written payload; a
    # reviewer that cannot emit the exact token has not cleared anything.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"yes","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YeS","confidence":96,"sha":"__FIXTURE_SHA__"}')" \
        "case-variant verdicts (yes / YeS) do not merge"
}

test_clearance_rejects_duplicate_verdict_keys() {
    # Codex: a payload carrying `verdict` TWICE — NO first, YES last — merged,
    # because JSON parsers keep the last duplicate key. The rendered comment can
    # be made to read as a refusal while the parsed object says YES.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__","verdict":"YES"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__","verdict":"YES"}')" \
        "a duplicated verdict key (NO then YES) does not merge"
}

test_clearance_rejects_unicode_escaped_duplicate_key() {
    # Codex round 2: `verdict` and `verdict` decode to `verdict`, so
    # the raw-text duplicate scan never saw a second key while the JSON parser
    # did — and kept the last one, YES. Counting literal text cannot win against
    # escaping, which is why the fix stopped counting text and instead pins the
    # payload to an exact key set with no escapes permitted anywhere.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"NO","confidence":97,"sha":"__FIXTURE_SHA__","\u0076erdict":"YES"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__","ver\u0064ict":"YES"}')" \
        "unicode-escaped duplicate keys do not merge"
}

test_clearance_rejects_unknown_extra_key() {
    # Consequence of the positive anchor: the payload carries exactly the four
    # decision-bearing keys. An unrecognised field is refused rather than
    # ignored, so nothing can ride along unexamined.
    refute_merge "$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__","note":"x"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__","note":"x"}')" \
        "a payload with an unexpected extra key does not merge"
}

test_clearance_accepts_two_yes_verdicts() {
    # Non-vacuity control. If this fails, the two tests above prove nothing —
    # they would pass against a gate that rejects everything.
    local r
    r=$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__"}')
    if printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        pass "two YES verdicts at >=95 bound to the head SHA do clear the merge"
    else
        fail "valid clearance failed to merge — the negative tests above are vacuous without this: $r"
    fi
}

test_sub_threshold_message_prescribes_next_action() {
    # A YES under 95 means a named residual concern, not a dead end. The gate
    # must say what to do next; tonight it just refused and the human ran the
    # merge by hand (GH #478).
    local r
    r=$(run_with_clearance '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":93,"sha":"__FIXTURE_SHA__"}')
    if printf '%s' "$r" | grep -qi "focused merge-safety round"; then
        pass "a sub-threshold YES prescribes the next action instead of dead-ending"
    else
        fail "sub-95 rejection gave no next action: $r"
    fi
}


test_clearance_requires_verdict_field
test_clearance_rejects_negative_verdict
test_clearance_rejects_lowercase_verdict
test_clearance_rejects_duplicate_verdict_keys
test_clearance_rejects_unicode_escaped_duplicate_key
test_clearance_rejects_unknown_extra_key
test_clearance_accepts_two_yes_verdicts
test_sub_threshold_message_prescribes_next_action

echo ""
# --- --user-approved: the human decision HARD_DENY demands (ROADMAP #479) -----
#
# HARD_DENY says "a human decides this one" and then provides no way for the
# human to say so. The maintainer hit this three times in one session; the last
# time the only route left was clicking merge in a browser, which bypasses the
# hook harness entirely and leaves no record in the repo.
#
# This flag does NOT prove a human typed it — nothing available here can. What
# it changes is that an override becomes EXPLICIT, REASONED and LOGGED instead
# of silent and out-of-band. That is the honest claim; the header comment in
# merge-pr.sh must not overstate it.

# Args are passed through as SEPARATE PARAMETERS, never as one string. An
# earlier version took a single string and word-split it unquoted, so
# `--user-approved ""` arrived as the literal two-character token `""` (which
# is non-empty, and merged) and a multi-word reason split into a usage error.
# Both failures were the harness, not the wrapper.
run_hard_deny() {   # "$@" = extra args, already separated
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 "$@" 2>&1) && code=0 || code=$?
    printf 'exit=%s %s' "$code" "$out"
    rm -rf "$tmpdir"
}

test_hard_deny_still_blocks_without_the_flag() {
    refute_merge "$(run_hard_deny)" \
        "HARD_DENY path still blocks with no --user-approved"
}
test_hard_deny_still_blocks_without_the_flag

test_hard_deny_blocks_when_reason_is_missing() {
    # A bare flag is not a decision. If the reason can be omitted, the flag
    # becomes a silent bypass wearing an audit trail's clothes.
    refute_merge "$(run_hard_deny --user-approved)" \
        "--user-approved with no reason does not merge"
}
test_hard_deny_blocks_when_reason_is_missing

test_hard_deny_blocks_when_reason_is_blank() {
    refute_merge "$(run_hard_deny --user-approved "")" \
        "--user-approved with an empty reason does not merge"
}
test_hard_deny_blocks_when_reason_is_blank

test_cross_model_cleared_still_cannot_clear_hard_deny() {
    # The whole point of the tier: self-produced evidence never clears it.
    refute_merge "$(run_hard_deny --cross-model-cleared)" \
        "--cross-model-cleared still cannot clear a HARD_DENY path"
}
test_cross_model_cleared_still_cannot_clear_hard_deny

test_user_approved_with_reason_merges_and_logs() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision: gate fix, certified round 3")

    if ! printf '%s' "$result" | grep -q "GH_MERGE_INVOKED"; then
        fail "--user-approved with a reason did not merge: $result"
    elif ! printf '%s' "$result" | grep -qi "USER-APPROVED OVERRIDE"; then
        fail "--user-approved merged but logged no override record — a silent bypass: $result"
    elif ! printf '%s' "$result" | grep -q "maintainer decision: gate fix"; then
        fail "--user-approved merged but did not record the stated reason: $result"
    else
        pass "--user-approved with a reason merges AND logs an auditable override"
    fi
}
test_user_approved_with_reason_merges_and_logs

test_user_approved_records_the_path_it_overrode() {
    # The record has to name WHAT was overridden. "Approved" without the path
    # is unauditable after the fact.
    local result
    result=$(run_hard_deny --user-approved "shipping the hook fix")
    if printf '%s' "$result" | grep -q "hooks/codex-gate-check.sh"; then
        pass "--user-approved names the HARD_DENY path it overrode"
    else
        fail "override record does not name the path it cleared: $result"
    fi
}
test_user_approved_records_the_path_it_overrode

test_user_approved_also_clears_the_weaker_ackable_tier() {
    # Design gap found live merging PR #494: --user-approved cleared HARD_DENY
    # (the STRICTER tier) and then blocked on ACKABLE_DENY (the WEAKER one).
    # A human authorised to override the merge-evidence chain is necessarily
    # authorised to override the tier that only steers behaviour. Requiring a
    # second, different flag for the lesser bar is incoherent.
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    # Both tiers at once: a hooks/ path (HARD) and the wizard doc (ACKABLE).
    # Quoted multi-line value: the stub does `printf '%s\n' "$DIFF_FILES"`, so
    # two separate config lines would leave the second as a bare token the
    # sourced file cannot assign — which fails closed on a truncated file set.
    printf 'DIFF_FILES=%s\n' "'hooks/codex-gate-check.sh
CLAUDE_CODE_SDLC_WIZARD.md'" >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "maintainer decision" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"

    if printf '%s' "$out" | grep -q "GH_MERGE_INVOKED"; then
        pass "--user-approved clears BOTH tiers, not just the stricter one"
    else
        fail "--user-approved cleared HARD_DENY but still blocked on the weaker ACKABLE tier (exit=$code): $out"
    fi
}
test_user_approved_also_clears_the_weaker_ackable_tier

# The two things --user-approved must NEVER waive. These are not paperwork:
# they are objective statements about whether the code works and whether the
# evidence that it works still exists. If a human can wave those away from a
# shell flag, the gate is decoration.
test_user_approved_cannot_waive_red_ci() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#VALIDATE_CONCLUSION=success#VALIDATE_CONCLUSION=failure#' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "ship it anyway" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "--user-approved cannot merge over a red CI validate check"
}
test_user_approved_cannot_waive_red_ci

test_user_approved_cannot_waive_deleted_tests() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    sed -i.bak 's#DELETED_TEST_FILES=#DELETED_TEST_FILES=tests/test-merge-gate.sh#' "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "removing a flaky suite" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "--user-approved cannot merge a PR that net-removes test files"
}
test_user_approved_cannot_waive_deleted_tests

# Argument shaping. Found by probing before the reviewers reported:
# `--user-approved --cross-model-cleared` made the NEXT FLAG the reason, firing
# a full override whose stated justification was the string "--cross-model-cleared".
# A reason that is actually a flag is not a reason.
test_user_approved_rejects_a_flag_as_its_reason() {
    refute_merge "$(run_hard_deny --user-approved --cross-model-cleared)" \
        "--user-approved does not accept the next flag as its reason"
}
test_user_approved_rejects_a_flag_as_its_reason

test_user_approved_rejects_whitespace_only_reason() {
    refute_merge "$(run_hard_deny --user-approved "   ")" \
        "--user-approved does not accept a whitespace-only reason"
}
test_user_approved_rejects_whitespace_only_reason

# The audit record must not claim verification that did not happen. The first
# version printed "clearance CERTIFIED round>=2 fresh ... denylist clear"
# unconditionally, so an override that skipped both still produced a record
# saying both were checked. Cross-model review reproduced the contradiction.
test_override_audit_record_does_not_claim_false_verification() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision")

    if ! printf '%s' "$result" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot check the audit line: $result"
    elif printf '%s' "$result" | grep -q "clearance CERTIFIED round>=2 fresh"; then
        fail "audit record claims clearance was verified when the override SKIPPED it: $result"
    elif printf '%s' "$result" | grep -q "denylist clear"; then
        fail "audit record claims the denylist was clear when the override WAIVED it: $result"
    elif ! printf '%s' "$result" | grep -q "OVERRIDDEN by --user-approved"; then
        fail "audit record does not say which checks were waived: $result"
    elif ! printf '%s' "$result" | grep -q "VERIFIED (not waivable)"; then
        fail "audit record does not separate what WAS verified from what was waived: $result"
    else
        pass "override audit record states what was verified vs what was waived"
    fi
}
test_override_audit_record_does_not_claim_false_verification

test_override_posts_a_durable_record_to_the_pr() {
    local result
    result=$(run_hard_deny --user-approved "maintainer decision")
    # The wrapper suppresses gh's own output, so assert on its confirmation.
    # That line only prints when the post succeeded — proven by the
    # COMMENT_FAILS test below, which shows a failed post blocks the merge.
    if printf '%s' "$result" | grep -q "Override recorded on PR"; then
        pass "override posts a durable record to the PR, not just stderr"
    else
        fail "override merged with no durable record — the reason evaporates with the session: $result"
    fi
}
test_override_posts_a_durable_record_to_the_pr

test_override_refuses_to_merge_if_the_record_cannot_be_posted() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    printf 'COMMENT_FAILS=1\n' >> "$tmpdir/.gh-stub-config"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 --user-approved "maintainer decision" 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "an override that cannot be recorded does not merge"
}
test_override_refuses_to_merge_if_the_record_cannot_be_posted

echo ""
# --- --dual-certified: dual cross-model agreement AS merge authority (#511) ---
#
# The maintainer stated it as standing policy: "if fable and codex agree with the
# merge then you don't need me". The gate could not express that. HARD_DENY said
# "a human decides" and the only way to say yes was --user-approved, so every
# merge on 2026-08-07/08 recorded a per-PR human decision that had actually been
# made once, months earlier, as policy. The mechanism was forcing a framing lie
# into the audit trail — worse than an inconvenience, because these records are
# the durable evidence of WHY something merged.
#
# What makes this different from self-review, and therefore admissible where
# --cross-model-cleared is not: two models that did not write the code, run blind
# to each other, each able to refuse. PR #497 took five rounds before both
# certified and every round found real defects.
#
# What it still is not: authentication. Both clearance comments are posted by the
# same gh token. The success line must say ATTESTED, NOT AUTHENTICATED.

# The fixture's gate files must byte-match its own origin/main for the dual
# path's self-integrity check to have anything honest to compare against.
# The fixture must install the REAL wrapper and REAL hook and execute the
# fixture's own copy. Round 1, both reviewers independently: the first version
# committed two-line `echo gate` dummies as the "pristine" gate while
# `run_dual_in` executed the real repo's script by absolute path — so integrity
# passed against files that had nothing to do with the code deciding the merge.
# The fixture was demonstrating the very hole it was supposed to guard.
make_gate_pristine() {   # $1=tmpdir
    local d="$1"
    mkdir -p "$d/scripts" "$d/.claude/hooks"
    cp "$WRAPPER" "$d/scripts/merge-pr.sh"
    cp "$HOOK" "$d/.claude/hooks/merge-gate-check.sh"
    chmod +x "$d/scripts/merge-pr.sh" "$d/.claude/hooks/merge-gate-check.sh"
    git -C "$d" add -A >/dev/null 2>&1
    git -C "$d" -c user.email=t@example.com -c user.name=t commit -qm fixture >/dev/null 2>&1
    git -C "$d" update-ref refs/remotes/origin/main HEAD
    # This commit MOVES the head, so everything keyed on it must move with it.
    # Before #540 only the sha mattered and the stub's HEAD_SHA was a constant,
    # so nothing here needed refreshing; now the clearance also names the tree
    # that merges, and a stale one reads as "the base moved since
    # certification" — a true statement about a fixture artifact, not about
    # anything under test.
    git -C "$d" rev-parse HEAD > "$d/.fixture-sha"
    git -C "$d" rev-parse 'HEAD^{tree}' > "$d/.fixture-tree"
    printf 'HEAD_SHA=%s\n' "$(cat "$d/.fixture-sha")" >> "$d/.gh-stub-config"
}

DUAL_YES_PAYLOADS='{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"YES","confidence":96,"sha":"__FIXTURE_SHA__"}'

# Everything a HARD-tier dual-certified merge is supposed to need, all valid.
# Individual tests then break exactly one thing.
setup_dual_fixture() {   # echoes tmpdir
    local tmpdir
    tmpdir=$(setup_wrapper_fixture)
    printf 'DIFF_FILES=hooks/codex-gate-check.sh\n' >> "$tmpdir/.gh-stub-config"
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' "$DUAL_YES_PAYLOADS")" >> "$tmpdir/.gh-stub-config"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    make_gate_pristine "$tmpdir"
    # AFTER make_gate_pristine, never before: it commits, so it is the last
    # thing that moves the head and the trees the clearance has to name.
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "$tmpdir"
}

# Executes the FIXTURE'S copy, by the relative path the redirect hook trains
# agents to use — not the real repo's script. Anything else makes the integrity
# assertion meaningless.
run_dual_in() {   # $1=tmpdir, rest=wrapper args
    local tmpdir="$1"; shift
    local out code
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" ./scripts/merge-pr.sh 123 "$@" 2>&1) && code=0 || code=$?
    # Fold in what was actually POSTED, not just what the wrapper said it did.
    local posted=""
    [ -f "$tmpdir/.posted-comments" ] && posted=$(cat "$tmpdir/.posted-comments")
    rm -rf "$tmpdir"
    printf 'exit=%s %s %s' "$code" "$out" "$posted"
}

# THE POINT OF THE WHOLE CHANGE. If this fails, every refusal test below is
# vacuous — they would all pass against a gate that refuses everything.
test_dual_certified_clears_hard_deny() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "two SHA-bound YES verdicts did not clear a HARD_DENY path — the gate still cannot express the standing policy: $r"
    elif ! printf '%s' "$r" | grep -q "DUAL-CERTIFIED"; then
        fail "merged but did not name the authority it merged under: $r"
    else
        pass "--dual-certified clears a HARD_DENY path on two SHA-bound YES verdicts"
    fi
}
test_dual_certified_clears_hard_deny

# The audit record is the deliverable, not a nicety. #511 exists because the
# records were misattributing a standing policy to a per-PR judgement; a record
# that overstates what was proven repeats that failure in the other direction.
test_dual_certified_record_says_attested_not_authenticated() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the audit line: $r"
    elif ! printf '%s' "$r" | grep -qi "ATTESTED, NOT AUTHENTICATED"; then
        fail "the dual-certified audit record does not state that both clearances came from the same token: $r"
    elif ! printf '%s' "$r" | grep -q "gpt-5.6-sol"; then
        fail "the audit record does not name which reviewers cleared it: $r"
    else
        pass "the dual-certified record names its reviewers and does not oversell them as authenticated"
    fi
}
test_dual_certified_record_says_attested_not_authenticated

test_dual_certified_needs_two_distinct_reviewers() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}')" \
        >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "one reviewer alone does not dual-certify a HARD_DENY path"
}
test_dual_certified_needs_two_distinct_reviewers

test_dual_certified_refuses_a_no_verdict() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'CLEARANCE_PAYLOADS=%s\n' "$(printf '%q' '{"reviewer":"gpt-5.6-sol","verdict":"YES","confidence":97,"sha":"__FIXTURE_SHA__"}
{"reviewer":"fable-5","verdict":"NO","confidence":96,"sha":"__FIXTURE_SHA__"}')" >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "one YES and one NO does not dual-certify — disagreement is the human's case, not a merge"
}
test_dual_certified_refuses_a_no_verdict

# The staleness bar #511 asked for: round-1-only CERTIFIED is a rubber stamp.
# --user-approved waives the artifact checks; --dual-certified must NOT, because
# the artifact is the only evidence that a dialogue happened at all.
test_dual_certified_still_requires_round_2_artifact() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    write_clearance "$tmpdir" 123 "CERTIFIED" 1 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a round-1-only clearance artifact still blocks under --dual-certified"
}
test_dual_certified_still_requires_round_2_artifact

# Self-integrity. A PR that edits the gate would otherwise be judged by its own
# edited gate — the exact circularity HARD_DENY exists to prevent, and the one
# thing dual review alone does not fix (the reviewers read the diff; the running
# code is what actually decides).
#
# Fable round 2: after the fixture rework this test became vacuous — it clobbered
# the EXECUTING script with two words of prose, so the run died at exit 127
# ("command not found") and verify_gate_integrity never ran. It was asserting
# that garbage does not merge. The tamper must stay FUNCTIONAL to reach the check
# at all, which is also the only shape that matters: a PR branch whose gate still
# works but no longer says what origin/main's says.
test_dual_certified_blocks_a_modified_gate() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf '\n# functional, but no longer the reviewed gate\n' >> "$tmpdir/scripts/merge-pr.sh"
    local r
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if printf '%s' "$r" | grep -q "command not found\|exit=127"; then
        fail "the tampered gate did not even execute — this test would pass against no check at all: $r"
    else
        refute_merge "$r" \
            "an executing gate that differs from origin/main does not dual-certify"
    fi
}
test_dual_certified_blocks_a_modified_gate

test_dual_certified_blocks_a_modified_redirect_hook() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    echo "hook, but disarmed" > "$tmpdir/.claude/hooks/merge-gate-check.sh"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a working-tree redirect hook that differs from origin/main does not dual-certify"
}
test_dual_certified_blocks_a_modified_redirect_hook

# THE ROUND-1 P0/P1, found independently by both reviewers. The check compared
# cwd-relative paths and never looked at $0, so the executed script was never the
# verified one — and the gate's OWN error message ("run the merge from a clean
# main checkout") steers an agent straight into the gap: it re-runs the absolute
# path it already knows, from a clean cwd, and the PR's edited gate decides while
# the audit line says the gate matched origin/main.
#
# Not the conceded "an agent could edit the script": nothing is edited or
# deleted here. The check simply binds the wrong artifact.
test_dual_certified_verifies_the_executing_script_not_the_cwd_copy() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    # cwd copy stays pristine; a DIFFERENT copy — byte-different, behaviourally
    # identical (a comment) — is what actually runs.
    mkdir -p "$tmpdir/pr-branch"
    cp "$tmpdir/scripts/merge-pr.sh" "$tmpdir/pr-branch/merge-pr.sh"
    printf '\n# tampered on the PR branch\n' >> "$tmpdir/pr-branch/merge-pr.sh"
    chmod +x "$tmpdir/pr-branch/merge-pr.sh"
    local out code
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$tmpdir/pr-branch/merge-pr.sh" 123 --dual-certified 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "the RUNNING script must match origin/main, not just the cwd copy"
}
test_dual_certified_verifies_the_executing_script_not_the_cwd_copy

# Fable round 1: the dual path asserted "gate byte-matches origin/main" and
# "artifact CERTIFIED at round>=2" nowhere durable — stdout only, gone with the
# session. Exactly the defect fixed once already for --user-approved after PR
# #494 merged traceless, re-introduced on the new path. #511's whole framing is
# that the RECORD is the deliverable.
test_dual_certified_posts_a_durable_record() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot check for a durable record: $r"
    elif printf '%s' "$r" | grep -q "Dual certification recorded on PR"; then
        pass "the dual path posts a durable record to the PR, not just stdout"
    else
        fail "dual-certified merged leaving no durable record of what was verified: $r"
    fi
}
test_dual_certified_posts_a_durable_record

test_dual_certified_refuses_to_merge_if_the_record_cannot_be_posted() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'COMMENT_FAILS=1\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "a dual-certified merge whose record cannot be posted does not merge"
}
test_dual_certified_refuses_to_merge_if_the_record_cannot_be_posted

# Fable round 1, pre-existing but on-theme: with a clearance flag and NO
# denylisted path, clearance never runs, so CLEARED_BY is empty and the audit
# line read "...and denylist acknowledged by ." — an acknowledgement by nobody.
test_clearance_flag_on_a_clean_pr_does_not_claim_a_phantom_acknowledgement() {
    local tmpdir r
    tmpdir=$(setup_dual_fixture)
    printf 'DIFF_FILES=src/foo.js\n' >> "$tmpdir/.gh-stub-config"
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the audit line: $r"
    elif printf '%s' "$r" | grep -qE "acknowledged by[[:space:]]*\.?$|acknowledged by[[:space:]]*$"; then
        fail "audit line claims a denylist acknowledgement by nobody: $r"
    else
        pass "a clearance flag on a clean PR reports 'denylist clear', not an empty acknowledgement"
    fi
}
test_clearance_flag_on_a_clean_pr_does_not_claim_a_phantom_acknowledgement

# The three things NO amount of model agreement clears. Red CI and missing tests
# are objective statements about whether the code works and whether the evidence
# it works still exists. A version bump is a release, and releases stay human.
test_dual_certified_cannot_waive_red_ci() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot merge over a red CI validate check"
}
test_dual_certified_cannot_waive_red_ci

test_dual_certified_cannot_waive_test_deletion() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'DELETED_TEST_FILES=tests/test-something.sh\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot merge a PR that net-removes test files"
}
test_dual_certified_cannot_waive_test_deletion

test_dual_certified_cannot_waive_a_version_bump() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    printf 'PACKAGE_JSON_VERSION_CHANGED=1\n' >> "$tmpdir/.gh-stub-config"
    refute_merge "$(run_dual_in "$tmpdir" --dual-certified)" \
        "--dual-certified cannot publish a release — a version bump still needs --user-approved"
}
test_dual_certified_cannot_waive_a_version_bump

# Greater authority covers lesser: a PR touching both tiers must not need two
# flags. Merging PR #494 hit the mirror-image of this bug, where --user-approved
# cleared six hooks/ paths and then blocked on a doc.
test_dual_certified_covers_the_ackable_tier_too() {
    local tmpdir
    tmpdir=$(setup_dual_fixture)
    # Quoted: the stub config is `source`d, so an unquoted second word is run as
    # a command, and its "not found" lands on stderr — which the wrapper folds
    # into the API payload with 2>&1 and then fails closed on. The failure looked
    # like a gate bug and was a harness bug.
    printf "DIFF_FILES='hooks/codex-gate-check.sh CLAUDE_CODE_SDLC_WIZARD.md'\n" >> "$tmpdir/.gh-stub-config"
    local r
    r=$(run_dual_in "$tmpdir" --dual-certified)
    if printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        pass "--dual-certified clears both tiers, not just the stricter one"
    else
        fail "--dual-certified cleared HARD_DENY but still blocked on the weaker ACKABLE tier: $r"
    fi
}
test_dual_certified_covers_the_ackable_tier_too

# The block message has to name the new route or the gate is a dead end again —
# which is the failure mode #478 and #511 are both about.
test_hard_deny_block_message_offers_the_dual_route() {
    local r
    r=$(run_hard_deny)
    if printf '%s' "$r" | grep -q -- "--dual-certified"; then
        pass "the HARD_DENY refusal names --dual-certified as a route, not just --user-approved"
    else
        fail "the HARD_DENY refusal still offers only a human override: $r"
    fi
}
test_hard_deny_block_message_offers_the_dual_route

echo ""
# --- CI validate: a second check-run of the same name must not be shadowed ----
#
# Branch protection requires the check by NAME, so nothing stops more than one
# run called "validate" existing on a SHA. The conclusion lookup stopped at the
# first match, so a green one ordered ahead of a red one satisfied the gate.
# This is the same defect class as reading evidence structure and never the
# answer inside it.
test_wrapper_blocks_a_shadowed_red_validate() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a red second check-run named validate is not shadowed by a green first one"
}
test_wrapper_blocks_a_shadowed_red_validate

# Both reviewers, round 1: "ALL runs of that name must be green" was only true
# for runs carrying a STRING conclusion. GitHub represents a queued or
# in-progress run as `"conclusion": null`, which the quoted-value regex could not
# see — so a still-running `validate` alongside an old green one merged, while
# the block message claimed pending blocks and the ROADMAP claimed every run of
# that name was green. The extraction is jq now, which sees the null.
test_wrapper_blocks_an_in_progress_duplicate_validate() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=null\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a second 'validate' still in progress (conclusion null) blocks the merge"
}
test_wrapper_blocks_an_in_progress_duplicate_validate

# Codex round 2: the jq unwrap handled the {check_runs:[...]} envelope but a
# BARE ARRAY page fell through `else .` and was dropped by the type filter, so a
# green wrapped page followed by a bare page carrying a red validate merged. The
# round-1 stub emitted neither real shape, so nothing could have caught it.
test_wrapper_blocks_a_red_validate_on_a_bare_array_page() {
    local tmpdir out code
    tmpdir=$(setup_wrapper_fixture)
    printf 'EXTRA_VALIDATE_CONCLUSION=failure\n' >> "$tmpdir/.gh-stub-config"
    printf 'EXTRA_VALIDATE_PAGE_SHAPE=bare\n' >> "$tmpdir/.gh-stub-config"
    write_clearance "$tmpdir" 123 "CERTIFIED" 2 "$(cat "$tmpdir/.fixture-sha")" ".reviews/some-review.md"
    echo "review body" > "$tmpdir/.reviews/some-review.md"
    out=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" "$WRAPPER" 123 2>&1) && code=0 || code=$?
    rm -rf "$tmpdir"
    refute_merge "$(printf 'exit=%s %s' "$code" "$out")" \
        "a red validate on a bare-array page is not dropped by the envelope unwrap"
}
test_wrapper_blocks_a_red_validate_on_a_bare_array_page

# Codex round 2: the record tests asserted only on the wrapper's own
# confirmation line and never on what was actually POSTED, so a body that
# rendered empty or truncated would still have passed. Assert the payload.
test_dual_record_body_names_the_authorized_path() {
    local r
    r=$(run_dual_in "$(setup_dual_fixture)" --dual-certified)
    if ! printf '%s' "$r" | grep -q "GH_MERGE_INVOKED"; then
        fail "fixture did not merge, cannot inspect the posted body: $r"
    elif ! printf '%s' "$r" | grep -q "GH_COMMENT_BODY:.*hooks/codex-gate-check.sh"; then
        fail "the posted dual-certification body does not name the merge-evidence path it authorised: $r"
    elif ! printf '%s' "$r" | grep -q "GH_COMMENT_BODY:.*gpt-5.6-sol"; then
        fail "the posted body does not name the reviewers who cleared it: $r"
    else
        pass "the posted dual-certification body names the authorised path and the reviewers"
    fi
}
test_dual_record_body_names_the_authorized_path

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi


echo ""
echo "All merge gate tests passed!"
