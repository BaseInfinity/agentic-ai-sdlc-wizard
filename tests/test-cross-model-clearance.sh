#!/bin/bash
# tests/test-cross-model-clearance.sh
#
# ROADMAP #479: maintainer *approval* and safety-check *bypass* were the same
# lever. `MERGE_CLEARANCE_SKIP=1` was the only way past a denylist hit, and it
# also disabled the CI check, the test-deletion check, the head-SHA freshness
# check and the clearance-artifact check — so acknowledging one red row meant
# disarming four green ones. It was also unusable by an agent: Claude Code's
# auto-mode classifier denies it as a safeguard bypass, by design.
#
# This replaces it with `--cross-model-cleared`, which satisfies the DENYLIST
# FINDING ONLY. Every other check stays mandatory and fail-closed.
#
# The key property, and the reason this is not just a renamed bypass: the
# evidence is EXTERNALLY VERIFIABLE. Clearance is read from comments on the
# remote PR, not from a local file the agent just wrote. `.reviews/` is
# gitignored, so a local artifact has no audit trail and merge-pr.sh's own
# header concedes it is "not a security boundary against a determined agent".
# A PR comment is timestamped, attributable, SHA-bound, and readable by anyone
# after the fact — including a future maintainer auditing why something merged.
#
# Required shape of a clearance comment on the PR:
#
#   <!-- CROSS-MODEL-CLEARANCE -->
#   ```json
#   {"reviewer":"codex-gpt-5.6-sol","confidence":100,"sha":"<40 hex>"}
#   ```
#
# Merge is permitted past a denylist hit only when at least two DISTINCT
# reviewers have posted such a comment, each at confidence >= 95, each bound to
# the exact head SHA being merged. Pushing a new commit invalidates clearance.
#
# Per ROADMAP #482, every assertion below checks the EXIT CODE, not a grepped
# message string: message text drifts, and an assertion that only greps prose
# passes vacuously the moment the wording changes.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$REPO_ROOT/scripts/merge-pr.sh"
HOOK="$REPO_ROOT/.claude/hooks/merge-gate-check.sh"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

HEAD_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
OTHER_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# ---------------------------------------------------------------------------
# Stub harness: a fake `gh` on PATH. Extends the pattern in test-merge-gate.sh
# with the issues/<PR>/comments endpoint the new check reads.
#
# Knobs (env vars read by the stub):
#   DIFF_FILES            newline list of changed paths
#   VALIDATE_CONCLUSION   conclusion of the CI `validate` check run
#   DELETED_TEST_FILES    space list of removed test paths
#   CLEARANCE_COMMENTS    newline list of "reviewer|confidence|sha" triples
# ---------------------------------------------------------------------------
make_stub_env() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/xmc.XXXXXX") || return 1
    mkdir -p "$tmpdir/bin" "$tmpdir/.reviews"
    cat > "$tmpdir/bin/gh" <<'STUB'
#!/bin/bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
    echo "{\"headRefOid\":\"$HEAD_SHA\",\"number\":123,\"state\":\"OPEN\"}"
    exit 0
elif [ "$1" = "pr" ] && [ "$2" = "diff" ]; then
    printf '%s\n' "$DIFF_FILES"
    exit 0
elif [ "$1" = "api" ]; then
    case "$*" in
        *check-runs*)
            echo "{\"conclusion\":\"$VALIDATE_CONCLUSION\",\"name\":\"validate\"}"
            ;;
        *issues*comments*)
            # A JSON array, exactly as real `gh api --paginate` returns.
            printf '['
            first=1
            if [ -n "${CLEARANCE_COMMENTS:-}" ]; then
                while IFS='|' read -r who conf sha; do
                    [ -z "$who" ] && continue
                    [ "$first" = 0 ] && printf ','
                    first=0
                    printf '{"body":"<!-- CROSS-MODEL-CLEARANCE -->\\n{\\"reviewer\\":\\"%s\\",\\"confidence\\":%s,\\"sha\\":\\"%s\\"}"}' \
                        "$who" "$conf" "$sha"
                done <<EOF
$CLEARANCE_COMMENTS
EOF
            fi
            printf ']\n'
            ;;
        *pulls*files*)
            if [ -n "${DELETED_TEST_FILES:-}" ]; then
                for f in $DELETED_TEST_FILES; do
                    echo "{\"filename\":\"$f\",\"status\":\"removed\"}"
                done
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

write_clearance_artifact() {
    cat > "$1/.reviews/merge-clearance-123.json" <<JSON
{ "pr_number": 123, "status": "CERTIFIED", "round": 4, "sha": "$2",
  "review_file": ".reviews/r.md" }
JSON
    echo "review body" > "$1/.reviews/r.md"
}

# Runs the wrapper with a fully-green baseline unless overridden.
run_wrapper() {
    local tmpdir="$1"; shift
    ( cd "$tmpdir" \
      && PATH="$tmpdir/bin:$PATH" \
         HEAD_SHA="${HEAD_SHA_OVERRIDE:-$HEAD_SHA}" \
         DIFF_FILES="${DIFF_FILES:-README.md}" \
         VALIDATE_CONCLUSION="${VALIDATE_CONCLUSION:-success}" \
         DELETED_TEST_FILES="${DELETED_TEST_FILES:-}" \
         CLEARANCE_COMMENTS="${CLEARANCE_COMMENTS:-}" \
         "$WRAPPER" "$@" ) >/dev/null 2>&1
}

echo "=== cross-model clearance replaces MERGE_CLEARANCE_SKIP ==="
echo

# ---------------------------------------------------------------------------
# Group 1: the old bypass is GONE, not renamed
# ---------------------------------------------------------------------------
echo "[1] MERGE_CLEARANCE_SKIP is removed, not aliased"

if grep -q 'MERGE_CLEARANCE_SKIP' "$WRAPPER"; then
    fail "scripts/merge-pr.sh still references MERGE_CLEARANCE_SKIP"
else
    pass "scripts/merge-pr.sh has no MERGE_CLEARANCE_SKIP"
fi

if grep -q 'MERGE_CLEARANCE_SKIP' "$HOOK"; then
    fail ".claude/hooks/merge-gate-check.sh still references MERGE_CLEARANCE_SKIP"
else
    pass ".claude/hooks/merge-gate-check.sh has no MERGE_CLEARANCE_SKIP"
fi

# Setting the retired variable must have NO effect: a denylist hit still blocks.
t=$(make_stub_env)
write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" MERGE_CLEARANCE_SKIP=1 run_wrapper "$t" 123; then
    fail "retired MERGE_CLEARANCE_SKIP=1 still bypasses a denylist hit"
else
    pass "retired MERGE_CLEARANCE_SKIP=1 has no effect"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 2: --cross-model-cleared satisfies the denylist finding
# ---------------------------------------------------------------------------
echo "[2] --cross-model-cleared clears a denylist hit when evidence is valid"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|96|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    pass "two distinct reviewers >=95 at the head SHA clears the denylist"
else
    fail "valid dual clearance did not permit the merge"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "a SINGLE reviewer was accepted as cross-model clearance"
else
    pass "one reviewer is not enough"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
codex-gpt-5.6-sol|97|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "the same reviewer twice was accepted as two reviewers"
else
    pass "two comments from the same reviewer are not two reviewers"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|94|$HEAD_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "a reviewer below 95 was accepted"
else
    pass "confidence below 95 blocks"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" \
   CLEARANCE_COMMENTS="codex-gpt-5.6-sol|100|$OTHER_SHA
fable-xhigh|96|$OTHER_SHA" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "clearance bound to a DIFFERENT sha was accepted (stale after a push)"
else
    pass "clearance for another sha is stale and blocks"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "the flag alone cleared a denylist hit with NO evidence on the PR"
else
    pass "the flag without posted evidence is inert"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 3: the flag clears the denylist and NOTHING ELSE
# This is the whole point of #479. Each check below is independently green in
# the cases above, so a failure here means the flag widened past its scope.
# ---------------------------------------------------------------------------
echo "[3] --cross-model-cleared does not disable any other check"

VALID="codex-gpt-5.6-sol|100|$HEAD_SHA
fable-xhigh|96|$HEAD_SHA"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="$VALID" \
   VALIDATE_CONCLUSION="failure" run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded with CI validate FAILING"
else
    pass "CI validate is still enforced under clearance"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="$VALID" \
   DELETED_TEST_FILES="tests/test-merge-gate.sh" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded while DELETING a test"
else
    pass "test-deletion check is still enforced under clearance"
fi
rm -rf "$t"

t=$(make_stub_env)  # deliberately no local clearance artifact written
if DIFF_FILES="hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="$VALID" \
   run_wrapper "$t" 123 --cross-model-cleared; then
    fail "cleared merge proceeded with NO local clearance artifact"
else
    pass "local clearance artifact is still required under clearance"
fi
rm -rf "$t"

# ---------------------------------------------------------------------------
# Group 4: regressions — behaviour without the flag is unchanged
# ---------------------------------------------------------------------------
echo "[4] Unflagged behaviour is unchanged"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="hooks/codex-gate-check.sh" CLEARANCE_COMMENTS="$VALID" \
   run_wrapper "$t" 123; then
    fail "a denylist hit merged WITHOUT the flag just because evidence existed"
else
    pass "evidence alone does not clear a denylist hit; the flag is explicit"
fi
rm -rf "$t"

t=$(make_stub_env); write_clearance_artifact "$t" "$HEAD_SHA"
if DIFF_FILES="README.md" run_wrapper "$t" 123; then
    pass "a clean PR still merges with no flag and no comments"
else
    fail "a clean PR no longer merges"
fi
rm -rf "$t"

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
