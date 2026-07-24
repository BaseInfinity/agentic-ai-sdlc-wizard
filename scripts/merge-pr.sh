#!/bin/bash
# merge-pr.sh <PR_NUMBER> — the only way this repo's own agent should merge
# a PR once .claude/hooks/merge-gate-check.sh redirects a bare `gh pr merge`
# here. Repo-local only (not shipped — see CLAUDE_CODE_SDLC_WIZARD.md's CI
# Feedback Loop section and ROADMAP.md for why).
#
# What this mechanically proves (hard-verified, fail-closed):
#   - CI's `validate` check is success for the PR's REMOTE head SHA (not a
#     cached field — queried fresh every run).
#   - The PR doesn't touch a release/policy-adjacency denylist, including
#     this wrapper and its redirect hook themselves (closes the
#     self-referential loophole both Codex and a fresh Fable subagent
#     independently flagged in the original prose-only policy: a PR editing
#     the merge policy/mechanism wasn't excluded by a release-only list).
#   - The PR doesn't net-delete files under tests/.
#   - A per-PR clearance artifact exists, is CERTIFIED, references a round
#     >= 2 dialogue (a round-1-only CERTIFIED is treated as suspicious — see
#     below), is bound to the current remote head SHA (not stale), and
#     points at a non-empty review artifact.
#   - The merge itself is atomically bound to the SHA just checked via
#     `--match-head-commit`, closing the TOCTOU race between the checks
#     above and the actual merge (GitHub rejects the merge if HEAD moved).
#
# What stays fundamentally trust-based, even after all of the above (state
# this honestly, don't oversell it): "Codex reached CERTIFIED via a genuine
# adversarial dialogue" and "the Fable subagent was truly fresh/diff-only"
# can never be confirmed by a local script — an agent willing to forge the
# clearance artifact would also set MERGE_CLEARANCE_SKIP. round >= 2 plus a
# non-empty review file is the best available proxy that review wasn't
# skipped or stale, not proof it wasn't faked. Real fake-resistance needs a
# server-side required check (tracked as a Research Parking Lot row in
# ROADMAP.md, not built here). This is a fast local gate against an honest
# agent under time pressure, not a security boundary against a determined
# adversary.

set -u

DENYLIST_PATTERNS=(
    '^\.github/workflows/'
    '^hooks/'
    '^\.claude/'
    '^skills/sdlc/SKILL\.md$'
    '^cowork/skills/sdlc/SKILL\.md$'
    '^CLAUDE_CODE_SDLC_WIZARD\.md$'
    '^CHANGELOG\.md$'
    '^\.github/workflows/release'
    '^scripts/merge-pr\.sh$'
)
# CLAUDE_CODE_SDLC_WIZARD.md added per Codex round-1 finding (2026-07-21):
# it now contains this exception's own portable policy prose, so a PR
# weakening that policy wasn't excluded from the exception it was editing.
# package.json is denylisted only for its version field specifically, not
# any touch (a PR bumping a dependency shouldn't need this exception's
# denylist, but a version-field change is release-adjacent) — checked
# separately below via a content diff, not the path-only denylist above.

if [ $# -lt 1 ]; then
    echo "Usage: scripts/merge-pr.sh <PR_NUMBER>" >&2
    exit 1
fi

PR_NUM="$1"
BYPASSED=0
[ "${MERGE_CLEARANCE_SKIP:-}" = "1" ] && BYPASSED=1

if ! PR_JSON=$(gh pr view "$PR_NUM" --json headRefOid,number,state 2>&1); then
    echo "FAILED CLOSED: could not fetch PR #$PR_NUM (gh error): $PR_JSON" >&2
    exit 1
fi
HEAD_SHA=$(printf '%s' "$PR_JSON" | grep -o '"headRefOid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"headRefOid"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$HEAD_SHA" ]; then
    echo "FAILED CLOSED: could not determine remote head SHA for PR #$PR_NUM" >&2
    exit 1
fi

if [ "$BYPASSED" -eq 1 ]; then
    echo "BYPASSED: MERGE_CLEARANCE_SKIP=1 set — skipping all clearance checks for PR #$PR_NUM at $HEAD_SHA. This is an emergency override; the merge is not otherwise verified." >&2
else
    # --- Fetch per-file status/patch data once, with pagination. Codex
    # round-1 finding: without --paginate, gh's API call silently returns
    # only the first page (default 30 entries) — a deleted test outside
    # that page was invisible. Fetched early (before the denylist loop) so
    # the package.json version check below can reuse it instead of an
    # invalid `gh pr diff -- <path>` call (gh pr diff has no per-path
    # filter flag; that call errors with stderr suppressed, so the check
    # silently no-opped — Codex round-1 finding). ---
    if ! PR_FILES=$(gh api --paginate "repos/:owner/:repo/pulls/$PR_NUM/files" 2>&1); then
        echo "FAILED CLOSED: could not fetch file statuses for PR #$PR_NUM: $PR_FILES" >&2
        exit 1
    fi

    # --- Denylist / release-policy-adjacency check (checked first so the
    # self-referential case fails loud and immediately) ---
    if ! DIFF_FILES=$(gh pr diff "$PR_NUM" --name-only 2>&1); then
        echo "FAILED CLOSED: could not fetch diff for PR #$PR_NUM: $DIFF_FILES" >&2
        exit 1
    fi
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pattern in "${DENYLIST_PATTERNS[@]}"; do
            if printf '%s' "$f" | grep -qE "$pattern"; then
                echo "BLOCKED: PR #$PR_NUM touches '$f', which matches the release/policy-adjacency denylist ($pattern). This exception does not apply — explicit user confirmation is required." >&2
                exit 1
            fi
        done
        if [ "$f" = "package.json" ]; then
            PKG_PATCH=$(printf '%s' "$PR_FILES" | grep -oE '"filename"[[:space:]]*:[[:space:]]*"package\.json"[^}]*"patch"[[:space:]]*:.*')
            if printf '%s' "$PKG_PATCH" | grep -qE '[+-][[:space:]]*\\"version\\"'; then
                echo "BLOCKED: PR #$PR_NUM changes package.json's version field — release-adjacent. Explicit user confirmation is required." >&2
                exit 1
            fi
        fi
    done <<< "$DIFF_FILES"

    # --- Test-deletion check: covers both outright deletion (status
    # "removed") and renaming a test OUT of tests/ (status "renamed" with a
    # previous_filename under tests/ but a new filename that isn't) — Codex
    # round-1 finding: the original check only recognized "removed",
    # missing this equally-effective removal path. ---
    DELETED_TESTS=$(printf '%s' "$PR_FILES" | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"[^}]*"status"[[:space:]]*:[[:space:]]*"removed"' \
        | grep -o '"filename"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"filename"[[:space:]]*:[[:space:]]*"//; s/"$//' \
        | grep '^tests/' || true)
    RENAMED_OUT_OF_TESTS=$(printf '%s' "$PR_FILES" | grep -oE '"previous_filename"[[:space:]]*:[[:space:]]*"tests/[^"]*"[^}]*"status"[[:space:]]*:[[:space:]]*"renamed"|"status"[[:space:]]*:[[:space:]]*"renamed"[^}]*"previous_filename"[[:space:]]*:[[:space:]]*"tests/[^"]*"' \
        | grep -o '"previous_filename"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"previous_filename"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)
    ALL_REMOVED_TESTS=$(printf '%s\n%s' "$DELETED_TESTS" "$RENAMED_OUT_OF_TESTS" | grep -v '^$' || true)
    if [ -n "$ALL_REMOVED_TESTS" ]; then
        echo "BLOCKED: PR #$PR_NUM net-removes test file(s) (deleted or renamed out of tests/): $ALL_REMOVED_TESTS. Explicit user confirmation is required." >&2
        exit 1
    fi

    # --- CI validate check (must be exactly "success" for the remote head) ---
    if ! CHECK_RUNS=$(gh api "repos/:owner/:repo/commits/$HEAD_SHA/check-runs" 2>&1); then
        echo "FAILED CLOSED: could not fetch check-runs for $HEAD_SHA: $CHECK_RUNS" >&2
        exit 1
    fi
    VALIDATE_CONCLUSION=$(printf '%s' "$CHECK_RUNS" | grep -o '"conclusion"[[:space:]]*:[[:space:]]*"[^"]*"[^}]*"name"[[:space:]]*:[[:space:]]*"validate"' \
        | grep -o '^"conclusion"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | sed 's/.*"conclusion"[[:space:]]*:[[:space:]]*"//; s/"$//' \
        | head -1)
    if [ -z "$VALIDATE_CONCLUSION" ]; then
        VALIDATE_CONCLUSION=$(printf '%s' "$CHECK_RUNS" | grep -o '"name"[[:space:]]*:[[:space:]]*"validate"[^}]*"conclusion"[[:space:]]*:[[:space:]]*"[^"]*"' \
            | grep -o '"conclusion"[[:space:]]*:[[:space:]]*"[^"]*"$' \
            | sed 's/.*"conclusion"[[:space:]]*:[[:space:]]*"//; s/"$//' \
            | head -1)
    fi
    if [ "$VALIDATE_CONCLUSION" != "success" ]; then
        echo "BLOCKED: CI 'validate' check is '${VALIDATE_CONCLUSION:-missing}', not green (must be exactly 'success' — pending/skipped/neutral/failure all block). Explicit user confirmation is required." >&2
        exit 1
    fi

    # --- Clearance artifact check ---
    CLEARANCE_FILE=".reviews/merge-clearance-$PR_NUM.json"
    if [ ! -f "$CLEARANCE_FILE" ]; then
        echo "BLOCKED: no clearance artifact found at $CLEARANCE_FILE. Run the full cross-model review protocol and write this file before merging without explicit confirmation." >&2
        exit 1
    fi
    CL_STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEARANCE_FILE" | head -1 | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')
    if [ "$CL_STATUS" != "CERTIFIED" ]; then
        echo "BLOCKED: $CLEARANCE_FILE status is '${CL_STATUS:-missing}', not CERTIFIED. Explicit user confirmation is required." >&2
        exit 1
    fi
    CL_ROUND=$(grep -o '"round"[[:space:]]*:[[:space:]]*[0-9]*' "$CLEARANCE_FILE" | head -1 | sed 's/.*"round"[[:space:]]*:[[:space:]]*//')
    if [ -z "$CL_ROUND" ] || [ "$CL_ROUND" -lt 2 ]; then
        echo "BLOCKED: $CLEARANCE_FILE shows round=${CL_ROUND:-missing} — a round-1-only CERTIFIED is treated as an insufficient dialogue (real adversarial review takes at least one recheck round). Explicit user confirmation is required." >&2
        exit 1
    fi
    CL_SHA=$(grep -o '"sha"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEARANCE_FILE" | head -1 | sed 's/.*"sha"[[:space:]]*:[[:space:]]*"//; s/"$//')
    if [ "$CL_SHA" != "$HEAD_SHA" ]; then
        echo "BLOCKED: $CLEARANCE_FILE is stale — its sha ($CL_SHA) does not match the current remote head ($HEAD_SHA). New commits landed since certification. Explicit user confirmation is required." >&2
        exit 1
    fi
    CL_REVIEW_FILE=$(grep -o '"review_file"[[:space:]]*:[[:space:]]*"[^"]*"' "$CLEARANCE_FILE" | head -1 | sed 's/.*"review_file"[[:space:]]*:[[:space:]]*"//; s/"$//')
    if [ -z "$CL_REVIEW_FILE" ] || [ ! -s "$CL_REVIEW_FILE" ]; then
        echo "BLOCKED: $CLEARANCE_FILE's referenced review artifact ('$CL_REVIEW_FILE') is missing or empty — can't verify the dialogue was substantive. Explicit user confirmation is required." >&2
        exit 1
    fi
fi

# --- Execute: always squash, no passthrough flags, atomically bound to the
# checked SHA. Only the PR number is accepted as input, closing the
# flag-smuggling surface entirely. ---
MERGE_OUTPUT=$(gh pr merge "$PR_NUM" --squash --match-head-commit "$HEAD_SHA" 2>&1)
MERGE_EXIT=$?
if [ "$MERGE_EXIT" -ne 0 ]; then
    echo "FAILED: gh pr merge did not succeed (possibly a race — head moved after checks passed): $MERGE_OUTPUT" >&2
    exit 1
fi

echo "$MERGE_OUTPUT"
echo "MERGED: PR #$PR_NUM at $HEAD_SHA (squash, match-head-commit). Conditions verified: $([ "$BYPASSED" -eq 1 ] && echo 'BYPASSED via MERGE_CLEARANCE_SKIP=1' || echo 'denylist clear, no test deletions, CI validate green, clearance CERTIFIED round>=2 fresh')."
exit 0
