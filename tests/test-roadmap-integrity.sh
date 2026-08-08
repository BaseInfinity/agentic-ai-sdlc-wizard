#!/bin/bash
# tests/test-roadmap-integrity.sh
#
# Guards ROADMAP.md against three mechanical rot modes that have all occurred:
#
#   1. Dangling cross-references — a row cites "ROADMAP #479" but no such row
#      exists in ROADMAP.md or ROADMAP_ARCHIVE.md. Observed 2026-07-26: row #480
#      cited #479 twice as the sharpest example of its own thesis, and #479 was
#      never actually written. The claim survived a commit, CI, and a merge.
#
#   2. Stale "Currently In Flight" — the section exists specifically to be the
#      cold-open pointer for a maintainer resuming the repo, so it is the single
#      worst place for rot. Observed 2026-07-26: it still listed PR #468 and
#      PR #469 as "awaiting merge" two days after both merged.
#
#   3. Duplicate row IDs — two rows claiming the same number silently hides one.
#
# LIMITS (state honestly, do not oversell):
#   - Check 1 only validates the explicit "ROADMAP #N" citation form. Bare "#N"
#     is ambiguous in this file (PRs, GitHub issues, and rows all use it), so it
#     is deliberately not checked. A row cited as bare "#479" still slips through.
#   - Check 2 proves a listed PR is NOT yet merged. It cannot prove the prose
#     about that PR is accurate, only that the PR is still genuinely open.
#   - Check 2 needs real git history. A shallow clone FAILS LOUDLY rather than
#     passing vacuously — see ci.yml's `fetch-depth: 0` on the validate job.
#   - Check 2b enforces the *form* of every bullet in the Open PRs block, so a
#     stale entry cannot be spelled around. It cannot detect an open PR that was
#     simply never listed — that needs network, which this test deliberately
#     avoids.
#
# Codex xhigh review 2026-07-26 defeated the first draft three ways, each
# reproduced by running the test rather than reading it. All three are fixed
# here and each has a named mutation:
#   F1 — check 2 matched only squash subjects "(#N)". This repo has 9 real
#        "Merge pull request #N from ..." commits, so PR #76 could be listed as
#        open and pass. Both subject forms are now parsed.
#   F2 — the first draft asked authors to spell merged work as bare "#N" and
#        called that a documented limit. It was not a limit, it was the hole:
#        "- **#468** — still awaiting merge." passed cleanly. Author discipline
#        is now replaced by check 2b, which constrains bullet *form*.
#   F3 — "| 66 |" was matched but compact "|66|" was not, so a duplicate row ID
#        could be hidden by removing spaces. Cell matching is whitespace-tolerant.
#
# Round 2 of the same review then defeated the FIXES three more ways. Each is
# also reproduced and closed here:
#   R2-1 — check 2b selected bullets with "^- " only, so "* **#468**" and an
#          indented "  - **#468**" both passed. Worse, the awk block boundary
#          could be terminated early by a bold line hidden inside an HTML
#          comment — invisible in rendered Markdown. Bullet matching now covers
#          -/*/+ and indentation, and HTML comments are stripped before parsing.
#   R2-2 — the whitespace-tolerant cell pattern matched "|999|" inside a fenced
#          code block, so a "ROADMAP #999" citation resolved to a row that does
#          not exist. Fences are now stripped before any structural matching.
#   R2-3 — the squash-suffix and merge-commit parsers both matched
#          "Merge pull request #76 from BaseInfinity/feature/(#999)", inventing
#          a merged PR 999 and falsely rejecting a genuinely open PR #999. The
#          two parsers are now mutually exclusive.
#
# Round 3 defeated those fixes three more times. The pattern by then was clear:
# every attempt to parse Markdown more cleverly in awk opened a new hole, so
# R3-1 is closed by PROHIBITION rather than by a better parser.
#   R3-1 — strip_noise() is a naive fence toggle. A four-backtick fence, a tilde
#          fence, or a 4-space-indented line containing backticks could make a
#          VISIBLE stale bullet vanish from the normalized view, passing 4/4.
#          That is the dangerous direction, and it disproved the "over-stripping
#          always fails safe" claim above. Fix: checks 2/2b read the RAW section
#          and FAIL if it contains any fence or HTML comment at all. The section
#          has no legitimate need for either.
#   R3-2 — check 2b ignored ordered list items, so a visible "1. **#468**"
#          rendered as a list entry under Open PRs and passed. The selector now
#          covers -, *, +, and "N." / "N)".
#   R3-3 — `grep -v '^Merge pull request #'` was broader than the parser it
#          complements, so a squash subject titled "Merge pull request #release
#          candidate (#999)" was dropped entirely and its (#999) never counted.
#          The exclusion now requires a digit, matching the parser exactly.
#
# THREAT MODEL (added round 3, to bound the scope of this file):
# This guards against ACCIDENTAL rot by an honest author — forgetting to update
# the section after a merge, which is the failure that actually happened twice.
# It is not a security boundary against someone deliberately crafting nested
# Markdown to hide an entry; that person can also just edit this test. The
# prohibition above exists because it is cheap and bounded, not because the
# adversarial case is the threat.
#
# Known residual, recorded rather than hidden (Codex round 4, raised and then
# ruled out by the reviewer itself): a raw HTML block containing an H2-shaped
# literal —
#     <pre>
#     ## literal, not a Markdown heading
#     </pre>
# — makes the awk section reader stop early, so a stale bullet after it is not
# examined. It is neither a fence nor an HTML comment, so the prohibition does
# not catch it. Deliberately not fixed: reaching it requires inserting a raw
# HTML code block plus a heading-shaped delimiter into a cold-open section that
# has no legitimate code content, which is the adversarial case above and not
# the accidental rot this file exists to catch.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROADMAP="$REPO_ROOT/ROADMAP.md"
ARCHIVE="$REPO_ROOT/ROADMAP_ARCHIVE.md"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== ROADMAP integrity ==="
echo

test -f "$ROADMAP" || { echo "FATAL: $ROADMAP not found"; exit 1; }
test -f "$ARCHIVE" || { echo "FATAL: $ARCHIVE not found"; exit 1; }

# Every check below reads a NORMALIZED view of the file, never the raw bytes.
# Two kinds of content must not be able to steer the parser:
#   - HTML comments, because they are invisible when the Markdown is rendered.
#     A reviewer eyeballing the section cannot see them, so a hidden line must
#     not be able to redefine a block boundary (Codex R2-1).
#   - Fenced code blocks, because they are illustrative text, not structure.
#     A "|999|" inside a fence is not a table row, but the row matcher treated
#     it as one, letting a citation resolve to a row that does not exist
#     (Codex R2-2).
# Scope correction (Codex R3-1): this normalized view is used ONLY by checks 1
# and 3. Over-stripping there makes a real row invisible, which surfaces as a
# check-1 FAILURE — safe. It is NOT safe for checks 2/2b, where hiding a line
# means hiding a stale entry, so those read the raw section instead. My earlier
# claim that over-stripping always fails safe was wrong in exactly that case.
strip_noise() {
    perl -0777 -pe 's/<!--.*?-->//gs' \
        | awk '/^[[:space:]]*(```|~~~)/{inf = !inf; next} !inf'
}
ROADMAP_BODY=$(strip_noise < "$ROADMAP")
ARCHIVE_BODY=$(strip_noise < "$ARCHIVE")

# A row is defined by a leading table cell holding only its number. Whitespace
# is optional on both sides: Markdown accepts "|479|" exactly as it accepts
# "| 479 |", and requiring the spaces let a compact cell hide from checks 1
# and 3 (Codex F3).
ROW_CELL='^\|[[:space:]]*%s[[:space:]]*\|'
row_exists() {
    local re
    # shellcheck disable=SC2059
    re=$(printf "$ROW_CELL" "$1")
    grep -qE "$re" <<<"$ROADMAP_BODY" || grep -qE "$re" <<<"$ARCHIVE_BODY"
}

# ---------------------------------------------------------------------------
# Check 1: every "ROADMAP #N" citation resolves to a real row
# ---------------------------------------------------------------------------
echo "[1] Cross-references resolve to a real row"

# Captures "ROADMAP #92/#207" as one match; the tr/grep pair splits it back out.
CITED=$(grep -oE 'ROADMAP #[0-9]+(/#[0-9]+)*' <<<"$ROADMAP_BODY" \
    | grep -oE '[0-9]+' \
    | sort -un)

if [ -z "$CITED" ]; then
    fail "no 'ROADMAP #N' citations found at all — the extractor is broken"
else
    DANGLING=""
    for n in $CITED; do
        row_exists "$n" || DANGLING="$DANGLING $n"
    done
    if [ -n "$DANGLING" ]; then
        fail "cited but no such row in ROADMAP.md or ROADMAP_ARCHIVE.md:$DANGLING"
    else
        pass "all $(echo "$CITED" | wc -w | tr -d ' ') cited rows resolve"
    fi
fi

# ---------------------------------------------------------------------------
# Check 2: "Currently In Flight" lists no already-merged PR
# ---------------------------------------------------------------------------
echo "[2] 'Currently In Flight' names no already-merged PR"

# Checks 2 and 2b read the RAW section, NOT the normalized body. strip_noise()
# is a naive fence toggle, not a CommonMark parser, and Codex R3-1 showed a
# four-backtick, tilde, or indented fence could make a VISIBLE stale bullet
# vanish from the normalized view — a silent pass, the one direction that
# actually matters. Rather than chase CommonMark parity in awk (three rounds of
# that produced three new holes), the section is simply forbidden from
# containing fences or HTML comments at all. It has no legitimate need for
# either, and a bounded prohibition is checkable where a parser is not.
INFLIGHT=$(awk '/^## Currently In Flight/{f=1; next} /^## /{f=0} f' "$ROADMAP")
INFLIGHT_AMBIGUOUS=$(echo "$INFLIGHT" | grep -nE '^[[:space:]]*(```|~~~)|<!--|-->' | head -1)

if [ -z "$INFLIGHT" ]; then
    fail "'Currently In Flight' section is missing or empty — it is the cold-open pointer"
elif [ -n "$INFLIGHT_AMBIGUOUS" ]; then
    fail "'Currently In Flight' must contain no code fences and no HTML comments (line ${INFLIGHT_AMBIGUOUS%%:*}) — either can hide a visible stale entry from this check"
else
    DEPTH=$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)
    if [ "$DEPTH" -lt 50 ]; then
        # Never degrade to a silent pass: an unverifiable check is a failed check.
        fail "shallow clone (depth $DEPTH) — cannot verify merge status; set fetch-depth: 0"
    else
        SUBJECTS=$(git -C "$REPO_ROOT" log --format='%s' HEAD)
        # Both merge styles this repo's history actually contains. Matching only
        # the squash form left 9 real merge commits invisible (Codex F1).
        MERGED_PRS=$( { echo "$SUBJECTS" | grep -v '^Merge pull request #[0-9]' \
                            | grep -oE '\(#[0-9]+\)$' | tr -d '(#)'
                        echo "$SUBJECTS" | grep -oE '^Merge pull request #[0-9]+' \
                            | grep -oE '[0-9]+$'
                      } | grep -E '^[0-9]+$' | sort -un)

        LISTED=$(echo "$INFLIGHT" | grep -oE 'PR #[0-9]+' | grep -oE '[0-9]+' | sort -un)

        STALE=""
        for pr in $LISTED; do
            if echo "$MERGED_PRS" | grep -qx "$pr"; then
                STALE="$STALE $pr"
            fi
        done

        if [ -n "$STALE" ]; then
            fail "listed as in-flight but already merged into this branch's history:$STALE"
        elif [ -z "$LISTED" ]; then
            pass "section present, names no specific PR"
        else
            pass "all $(echo "$LISTED" | wc -w | tr -d ' ') listed PRs are still unmerged"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Check 2b: every bullet in the Open PRs block uses the checkable form
#
# Check 2 above can only see the literal "PR #N". The first draft asked authors
# to spell merged work as a bare "#N" and treated that as a documented limit,
# but the same convention let a stale entry be written as
# "- **#468** — still awaiting merge." and pass (Codex F2). Constraining the
# FORM of every bullet in the block removes the author-discipline dependency:
# a bullet that check 2 cannot read is now itself a failure.
# ---------------------------------------------------------------------------
echo "[2b] Open PRs bullets use the checkable '- **PR #N**' form"

if [ -z "$INFLIGHT" ]; then
    fail "no 'Currently In Flight' section to check"
elif [ -n "$INFLIGHT_AMBIGUOUS" ]; then
    fail "'Currently In Flight' contains a code fence or HTML comment — block boundaries are not trustworthy"
elif ! echo "$INFLIGHT" | grep -qE '^\*\*Open PRs'; then
    # Without this, deleting the header would silently disable the whole check.
    fail "'Open PRs' block header is missing from 'Currently In Flight'"
else
    OPEN_BLOCK=$(echo "$INFLIGHT" | awk '/^\*\*Open PRs/{f=1; next} f && /^\*\*/{f=0} f')
    BAD=$(echo "$OPEN_BLOCK" | grep -E '^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]' \
        | grep -vE '^- \*\*PR #[0-9]+\*\*' || true)
    if [ -n "$BAD" ]; then
        fail "Open PRs bullets must start with '- **PR #N**' so check 2 can read them: $(echo "$BAD" | head -1 | cut -c1-60)"
    else
        pass "all Open PRs bullets are in checkable form"
    fi
fi

# ---------------------------------------------------------------------------
# Check 3: no duplicate row IDs
# ---------------------------------------------------------------------------
echo "[3] Row IDs are unique"

DUPES=$(grep -oE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' <<<"$ROADMAP_BODY" \
    | grep -oE '[0-9]+' | sort -n | uniq -d | tr '\n' ' ')
if [ -n "$DUPES" ]; then
    fail "duplicate row IDs in ROADMAP.md: $DUPES"
else
    pass "no duplicate row IDs"
fi

# Check: ROADMAP must not assert PR-open state at all.
#
# It said "**Open PRs — none.**" while PR #503 was open, and every existing check
# passed — they enforce the FORM of bullets in that block, so a claim of "none"
# has no bullets to inspect and sails through. A staleness guard that cannot
# detect the staleness it exists for.
#
# The fix is not a better checker. Whether a PR is open is the tracker's fact,
# and no offline test can verify it. ROADMAP restating it is the duplicate-source
# hazard #482 names, so the honest move is to stop making the claim and point at
# the tracker, which is always current by construction.
if grep -qiE '^\*\*Open PRs? (—|-|:)? *none' "$ROADMAP"; then
    fail "ROADMAP asserts 'Open PRs — none'. That is the tracker's fact and goes stale silently — no offline test can verify it. Link to the PR list instead of restating it."
else
    pass "ROADMAP does not restate PR-open state (tracker is the source — #482)"
fi

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
