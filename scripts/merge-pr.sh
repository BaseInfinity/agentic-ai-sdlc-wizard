#!/bin/bash
# merge-pr.sh <PR_NUMBER> — the only way this repo's own agent should merge
# a PR once .claude/hooks/merge-gate-check.sh redirects a bare `gh pr merge`
# here. Repo-local only (not shipped — see CLAUDE_CODE_SDLC_WIZARD.md's CI
# Feedback Loop section and ROADMAP.md for why).
#
# What this mechanically proves (hard-verified, fail-closed):
#   - CI's `validate` check is success for the PR's REMOTE head SHA (not a
#     cached field — queried fresh every run).
#   - The PR touches NO HARD_DENY path — the merge-evidence chain, including
#     this wrapper and its redirect hook themselves (closes the
#     self-referential loophole both Codex and a fresh Fable subagent
#     independently flagged in the original prose-only policy: a PR editing
#     the merge policy/mechanism wasn't excluded by a release-only list).
#   - Every ACKABLE_DENY path the PR touches carries qualifying, SHA-bound
#     cross-model evidence. NOTE this is deliberately weaker than "touches no
#     denylist at all": a successful --cross-model-cleared run IS allowed to
#     touch the policy-prose files, and logs DENYLIST ACKNOWLEDGED when it
#     does. An auditor reading this contract must not read a clean exit as
#     "no denylisted path was touched" (Codex round-2 P2 — the earlier
#     wording asserted exactly that, and became false when tiering landed).
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
# clearance artifact could equally forge a clearance comment. round >= 2 plus a
# non-empty review file is the best available proxy that review wasn't
# skipped or stale, not proof it wasn't faked. Real fake-resistance needs a
# server-side required check (tracked as a Research Parking Lot row in
# ROADMAP.md, not built here). This is a fast local gate against an honest
# agent under time pressure, not a security boundary against a determined
# adversary.

set -u

# --- Two tiers (ROADMAP #479). Codex xhigh (96%) and Fable xhigh (85%),
# consulted independently and blind to each other, both recommended this split.
#
# HARD_DENY is the MERGE-EVIDENCE CHAIN: paths where a PR can alter the meaning
# of the evidence used to merge it. On these, every leg of the evidence stack
# becomes the agent's own say-so simultaneously — branch protection requires the
# check by NAME, so ANY new file under .github/workflows/ can mint a green
# "validate"; the gate that runs is the PR's own working-tree gate; and both
# clearance comments come from the same gh token. Errors in the control plane
# compound, errors in the data plane do not. --cross-model-cleared CANNOT
# satisfy these; a human decides.
HARD_DENY=(
    '^\.github/workflows/'
    '^hooks/'
    '^\.claude/'
    '^scripts/merge-pr\.sh$'
)

# ACKABLE_DENY steers behaviour but does not decide whether THIS PR may merge,
# so visible SHA-bound cross-model evidence is a proportionate gate for it.
ACKABLE_DENY=(
    '^skills/sdlc/SKILL\.md$'
    '^cowork/skills/sdlc/SKILL\.md$'
    '^CLAUDE_CODE_SDLC_WIZARD\.md$'
    '^cowork/hooks/'
)

# Deliberately NOT denylisted:
#   CHANGELOG.md — both reviewers measured it as dead weight: across the last
#     ~25 merged PRs it only ever co-fired with a package.json version bump,
#     which the unconditional content check below already blocks.
#   '^\.github/workflows/release' — redundant now that all of
#     .github/workflows/ is hard-denied.
# package.json is checked for its VERSION FIELD specifically, not any touch (a
# dependency bump shouldn't be release-adjacent) — a content diff below, not a
# path pattern, and unconditional in both tiers.
#
# hooks/ granularity: Fable argued a narrower core (only review-evidence hooks
# hard, advisory ones ackable — 15% vs 26% of PRs needing a human) but said
# plainly that the broad directory is the zero-cleverness option. Broad is used
# here: "advisory vs evidence" is a judgement that drifts as hooks change, and
# it matches the guidance already recorded in ROADMAP #478.

# --- Cross-model clearance, read from the REMOTE PR (ROADMAP #479) ---
#
# WHAT THIS IS, STATED HONESTLY (corrected after Codex round 1):
# This is an AUDIT TRAIL, not an authentication boundary. An earlier version of
# this comment claimed PR comments are harder to forge than a local artifact
# because they are "timestamped, attributable, SHA-bound". Attributable was
# never true: the parser discarded the comment's author. Worse, binding to the
# author does not rescue the claim here, because both reviews are posted by the
# SAME gh token — there is no second authenticated principal to tell them apart.
#
# What it does give you: evidence that is durable, timestamped, readable by a
# human long afterwards, and invalidated by any new push. Against the stated
# threat model — an honest agent that is degraded or under time pressure — that
# is worth having. Against a determined agent it is not, and nothing here
# should be read as claiming otherwise.
#
# Requires: at least two DISTINCT reviewers, each at confidence >= 95 (integer
# 0..100), each bound to the exact head SHA. The author login of each comment
# is recorded in the output so an auditor can see who actually posted it.
CLEARED_BY=""
verify_cross_model_clearance() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "FAILED CLOSED: jq is required to verify cross-model clearance." >&2
        return 1
    fi
    local comments records who conf sha author reviewers="" count=0
    CLEARED_BY=""
    if ! comments=$(gh api --paginate "repos/:owner/:repo/issues/$PR_NUM/comments" 2>&1); then
        echo "FAILED CLOSED: could not fetch PR comments for #$PR_NUM: $comments" >&2
        return 1
    fi

    # Codex round-1 findings F3 and F4: the previous version pulled reviewer,
    # confidence and sha with three INDEPENDENT `grep | head -1` pipelines over
    # the whole comment body, so the three fields need not have come from the
    # same JSON object — or from any valid object at all. Three unrelated
    # snippets quoted in prose were accepted as clearance. And the confidence
    # regex grabbed leading digits lexically, so the valid JSON number 95e-100
    # (~9.5e-99) read as 95.
    #
    # Both are fixed the same way: extract exactly ONE fenced json payload per
    # comment and let jq parse it as JSON, evaluating all three fields from that
    # single object and comparing confidence numerically. A comment with zero or
    # more than one payload is rejected rather than partially parsed.
    # Fable finding 8: the previous marker was an HTML comment, and the whole
    # payload could be wrapped in one too — rendering as "LGTM, nice work!" in
    # the GitHub UI while still clearing the merge. Since the entire remaining
    # justification is "a human can read this later", evidence a human cannot
    # see is worse than useless. HTML comments are now STRIPPED before scanning,
    # so both the marker and the payload must be visibly rendered.
    #
    # Fable finding 7: comment authorship was not gated at all — any GitHub user
    # who can comment could mint clearance. Now restricted to OWNER/MEMBER/
    # COLLABORATOR. This does not make forgery hard (see the header), it just
    # stops a drive-by.
    records=$(printf '%s' "$comments" | jq -r '
        .[]?
        | select(.body != null)
        | select((.author_association // "") | . == "OWNER" or . == "MEMBER" or . == "COLLABORATOR")
        | . as $c
        | ($c.body | gsub("(?s)<!--.*?-->"; " ")) as $visible
        | ($visible | gsub("(?s)```.*?```"; " ") | gsub("`[^`]*`"; " ")) as $prose
        | select($prose | test("<!--") | not)   # unbalanced opener hides the rest; code-quoted tokens are fine
        | select($visible | test("CROSS-MODEL-CLEARANCE"))
        | ($visible | [scan("(?s)```json\\s*(\\{.*?\\})\\s*```")] ) as $payloads
        | select(($payloads | length) == 1)
        | ($payloads[0][0] | fromjson? // empty) as $p
        | select($p.reviewer != null and $p.confidence != null and $p.sha != null)
        | select($p.confidence | type == "number")
        | select($p.reviewer | type == "string")
        | select($p.sha | type == "string")
        | [($c.user.login // "unknown"), $p.reviewer, ($p.confidence|tostring), $p.sha]
        | @tsv
    ' 2>/dev/null)

    if [ -z "$records" ]; then
        echo "BLOCKED: no well-formed cross-model clearance comments on PR #$PR_NUM." >&2
        return 1
    fi

    while IFS=$'\t' read -r author who conf sha; do
        [ -z "$who" ] && continue
        # F1: the reviewer identity must be a single safe token. The previous
        # version later ran `set -- $reviewers`, which word-splits on IFS, so a
        # reviewer value of "alice bob" satisfied the two-reviewer threshold
        # from ONE comment.
        case "$who" in *[!A-Za-z0-9._-]*)
            echo "  ignored: reviewer '$who' is not a single [A-Za-z0-9._-] token" >&2; continue ;;
        esac
        # Fable finding 9: honest payloads were silently dropped with no reason
        # given — "the gate refused my valid clearance and won't say why" is the
        # exact frustration loop #479 exists to end. Every rejection now says why,
        # and a SHA differing only in case is accepted.
        if [ "$(printf '%s' "$sha" | tr 'A-F' 'a-f')" != "$(printf '%s' "$HEAD_SHA" | tr 'A-F' 'a-f')" ]; then
            echo "  ignored: $who cleared $sha, not the current head $HEAD_SHA" >&2; continue
        fi
        conf=${conf%.0}                          # jq renders an integer-valued float as 100.0
        case "$conf" in *[!0-9]*)
            echo "  ignored: $who gave a non-integer confidence '$conf'" >&2; continue ;;
        esac
        if [ "$conf" -lt 95 ] || [ "$conf" -gt 100 ]; then
            echo "  ignored: $who gave confidence $conf, outside the 95..100 range" >&2; continue
        fi
        case " $reviewers " in *" $who "*) continue ;; esac
        reviewers="$reviewers $who"
        CLEARED_BY="$CLEARED_BY${CLEARED_BY:+, }$who (posted by @$author)"
        count=$((count + 1))
    done <<< "$records"

    # F1: count parsed RECORDS, never shell words.
    if [ "$count" -lt 2 ]; then
        echo "BLOCKED: cross-model clearance needs 2 distinct reviewers at >=95% bound to $HEAD_SHA; found $count." >&2
        return 1
    fi
    return 0
}

if [ $# -lt 1 ]; then
    echo "Usage: scripts/merge-pr.sh <PR_NUMBER>" >&2
    exit 1
fi

PR_NUM="$1"
shift
CROSS_MODEL_CLEARED=0
while [ $# -gt 0 ]; do
    case "$1" in
        --cross-model-cleared) CROSS_MODEL_CLEARED=1 ;;
        *) echo "Usage: scripts/merge-pr.sh <PR_NUMBER> [--cross-model-cleared]" >&2; exit 1 ;;
    esac
    shift
done

if ! PR_JSON=$(gh pr view "$PR_NUM" --json headRefOid,number,state 2>&1); then
    echo "FAILED CLOSED: could not fetch PR #$PR_NUM (gh error): $PR_JSON" >&2
    exit 1
fi
HEAD_SHA=$(printf '%s' "$PR_JSON" | grep -o '"headRefOid"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"headRefOid"[[:space:]]*:[[:space:]]*"//; s/"$//')
if [ -z "$HEAD_SHA" ]; then
    echo "FAILED CLOSED: could not determine remote head SHA for PR #$PR_NUM" >&2
    exit 1
fi

# --- Every check below is UNCONDITIONAL. ROADMAP #479: the old
# ROADMAP #479: the retired bypass disabled all of them at once, so acknowledging one
# denylist row meant disarming CI, test-deletion, SHA-freshness and the
# clearance artifact. There is now no flag that turns any of these off.
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
    # Tier classification reads the FILES API, never `gh pr diff --name-only`
    # (Codex round-2, two proven HARD-tier bypasses):
    #
    #  - `gh pr diff` emits DISPLAY text, preserving core.quotePath quoting and
    #    octal escapes. `".github/workflows/validate-\360\237\230\200.yml"`
    #    begins with a quote, so every column-anchored HARD pattern missed it and
    #    the merge reported "denylist clear". jq decodes the real pathname.
    #  - A PR diff is capped at 300 files, so a HARD path at position 301 was
    #    simply absent from the classified set while a visible ACKABLE hit
    #    cleared normally.
    #
    # Both current and previous names are classified, so renaming a protected
    # file out of a protected directory cannot change its tier.
    if ! command -v jq >/dev/null 2>&1; then
        echo "FAILED CLOSED: jq is required to classify changed paths." >&2
        exit 1
    fi
    CLASSIFY_PATHS=$(printf '%s' "$PR_FILES" \
        | jq -rs 'map(if type == "array" then .[] else . end)
                  | map(select(type == "object"))
                  | map(.filename // empty, .previous_filename // empty)
                  | .[]' 2>/dev/null | grep -v '^$' || true)

    # Completeness: never classify a truncated set. If the API returned fewer
    # files than the PR claims to change, fail closed rather than silently
    # judging a subset (GitHub caps the files endpoint at 3000).
    # Codex round-3: `|| echo ""` turned an API/CLI failure into "skip the
    # check" — precisely the condition that must fail closed. A HARD file past
    # the files-API ceiling was invisible whenever this second query failed.
    if ! CHANGED_COUNT=$(gh pr view "$PR_NUM" --json changedFiles --jq '.changedFiles' 2>/dev/null); then
        echo "FAILED CLOSED: could not read changedFiles for PR #$PR_NUM — cannot prove the classified path set is complete." >&2
        exit 1
    fi
    case "$CHANGED_COUNT" in
        ''|*[!0-9]*)
            echo "FAILED CLOSED: changedFiles for PR #$PR_NUM was '${CHANGED_COUNT:-empty}', not a number." >&2
            exit 1 ;;
    esac
    if [ "$CHANGED_COUNT" -lt 1 ]; then
        echo "FAILED CLOSED: PR #$PR_NUM reports $CHANGED_COUNT changed files." >&2
        exit 1
    fi
    SEEN_COUNT=$(printf '%s' "$PR_FILES" \
        | jq -rs 'map(if type == "array" then .[] else . end)
                  | map(select(type == "object" and has("filename"))) | length' 2>/dev/null || echo 0)
    if [ "${SEEN_COUNT:-0}" -lt "$CHANGED_COUNT" ]; then
        echo "FAILED CLOSED: PR #$PR_NUM changes $CHANGED_COUNT files but only $SEEN_COUNT were retrievable — the tier classifier would be judging a truncated set." >&2
        exit 1
    fi

    if [ -z "$CLASSIFY_PATHS" ]; then
        echo "FAILED CLOSED: could not determine any changed path for PR #$PR_NUM." >&2
        exit 1
    fi

    # PASS 1 — HARD tier, evaluated across EVERY path before anything can be
    # acknowledged, so a PR touching both tiers is blocked by the hard one.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pattern in "${HARD_DENY[@]}"; do
            if printf '%s' "$f" | grep -qiE "$pattern"; then
                echo "BLOCKED: PR #$PR_NUM touches '$f', part of the merge-evidence chain ($pattern). --cross-model-cleared does NOT apply here: on these paths the PR defines its own CI check, runs its own gate, and posts its own clearance, so every leg of the evidence would be self-produced. A human decides this one." >&2
                exit 1
            fi
        done
    done <<< "$CLASSIFY_PATHS"

    # PASS 2 — ACKABLE tier.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        for pattern in "${ACKABLE_DENY[@]}"; do
            if printf '%s' "$f" | grep -qiE "$pattern"; then
                if [ "$CROSS_MODEL_CLEARED" -eq 1 ] && verify_cross_model_clearance; then
                    echo "DENYLIST ACKNOWLEDGED: '$f' matches $pattern, cleared by $CLEARED_BY. Every other check still ran." >&2
                    continue
                fi
                echo "BLOCKED: PR #$PR_NUM touches '$f' ($pattern). Post cross-model clearance to the PR and re-run with --cross-model-cleared." >&2
                exit 1
            fi
        done
    done <<< "$CLASSIFY_PATHS"

    # Fable round-3 N1: this loop still read $DIFF_FILES — the display-text,
    # 300-file-capped source that classification was moved OFF for exactly this
    # reason. A version bump past position 300 merged as "denylist clear",
    # despite the header calling this check unconditional in both tiers.
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        if [ "$f" = "package.json" ]; then
            PKG_PATCH=$(printf '%s' "$PR_FILES" | grep -oE '"filename"[[:space:]]*:[[:space:]]*"package\.json"[^}]*"patch"[[:space:]]*:.*')
            if printf '%s' "$PKG_PATCH" | grep -qE '[+-][[:space:]]*\\"version\\"'; then
                echo "BLOCKED: PR #$PR_NUM changes package.json's version field — release-adjacent. Explicit user confirmation is required." >&2
                exit 1
            fi
        fi
    done <<< "$CLASSIFY_PATHS"

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
echo "MERGED: PR #$PR_NUM at $HEAD_SHA (squash, match-head-commit). Verified: no test deletions, CI validate green, clearance CERTIFIED round>=2 fresh, and $([ "$CROSS_MODEL_CLEARED" -eq 1 ] && echo "denylist acknowledged by $CLEARED_BY" || echo 'denylist clear')."
exit 0
