#!/bin/bash
#
# Post a comment on a PR or issue, with an argv this script builds and the
# caller cannot extend.
#
#   scripts/post-comment.sh pr|issue <number> <body-file>
#
# WHY THIS EXISTS RATHER THAN A PERMISSION PATTERN
# ------------------------------------------------
# The first attempt was `Bash(gh pr comment:*)` in .claude/settings.json. A
# review leg returned SHAPE: WRONG_SHAPE against it, at 99%, and it was right:
# allow rules are prefix/glob shapes and the dangerous flags TRAIL. That pattern
# also authorized
#
#   --delete-last   erase a comment — including a CROSS-MODEL-CLEARANCE comment
#                   that scripts/merge-pr.sh reads as merge evidence
#   --edit-last     rewrite one after the fact
#   -R other/repo   write to a different repository entirely
#
# Forbidding a suffix is not something the pattern language can express, so no
# pattern survives. What was actually wanted is the CAPABILITY — post a comment
# unattended — not that pattern. A wrapper grants exactly the capability.
#
# This is the repo's existing idiom, not a new one: scripts/run-review-leg.sh
# exists for the same reason, because raw `codex exec` was the wrong shape to
# authorize.
#
# THE BOUNDARY, STATED SO IT IS NOT DRIFTED ACROSS LATER
# ------------------------------------------------------
# This posts comments. It does not edit, delete, label, close, or merge. The
# moment it accepts a passthrough argument it is the pattern again with extra
# steps, and the guard below is theatre. Add a capability by adding a fixed
# argv, never by forwarding "$@".

set -eu

usage() {
    echo "usage: scripts/post-comment.sh pr|issue <number> <body-file>" >&2
    echo "  Posts a comment. No flags are accepted and none are forwarded." >&2
}

# EXACT arity. Not "at least 3" — a trailing argument is the whole attack, and
# `shift 3; gh ... "$@"` is how a wrapper quietly becomes the pattern it
# replaced.
if [ "$#" -ne 3 ]; then
    echo "REFUSED: expected exactly 3 arguments, got $#." >&2
    usage
    exit 2
fi

KIND=$1
NUMBER=$2
BODY_FILE=$3

# A CLOSED SET, not a check that it "looks like" a subcommand. Anything else —
# `release`, `repo`, an empty string, a string with a space in it — is refused
# rather than passed to gh to interpret.
case "$KIND" in
    pr|issue) ;;
    *)
        echo "REFUSED: kind must be exactly 'pr' or 'issue', got '$KIND'." >&2
        exit 2
        ;;
esac

# A POSITIVE GRAMMAR, and this is the row that matters most. A "does it start
# with a dash" check is NOT enough: `650 --delete-last` as one quoted argument
# does not start with a dash, and the shell splits it back into two words inside
# gh's argv. Digits-only cannot express a flag at all.
case "$NUMBER" in
    ''|*[!0-9]*)
        echo "REFUSED: number must be digits only, got '$NUMBER'." >&2
        exit 2
        ;;
esac

# Belt and braces on the remaining free-form argument. The body file is a path,
# so a leading dash there would still reach gh's option parser.
case "$BODY_FILE" in
    -*)
        echo "REFUSED: body file must not begin with '-', got '$BODY_FILE'." >&2
        exit 2
        ;;
esac

if [ ! -f "$BODY_FILE" ] || [ ! -r "$BODY_FILE" ]; then
    echo "REFUSED: body file '$BODY_FILE' is missing or unreadable." >&2
    exit 2
fi

# An empty clearance comment satisfies every structural check and says nothing —
# the same failure the verdict schema's CLAIM_NOT_EMPTY rule closes (#650).
if [ ! -s "$BODY_FILE" ]; then
    echo "REFUSED: body file '$BODY_FILE' is empty." >&2
    exit 2
fi

# THE TARGET IS DECLARED, NOT INHERITED.
#
# Round 2 of this file's own review found the P0: the first version passed no
# repo selector at all and let gh resolve the current remote. That is argv-only
# thinking. `gh` honours GH_REPO from the environment, so a wrapper with a
# spotless argv still posted wherever an inherited variable pointed — and the
# 24-row suite passed the whole time.
#
# Measured on gh 2.92.0 with read-only probes, not assumed:
#
#   GH_REPO=cli/cli gh pr view 650 --json url             -> cli/cli
#   ... -R github.com/BaseInfinity/claude-sdlc-harness    -> this repo
#   ... -R BaseInfinity/claude-sdlc-harness               -> this repo
#
# The unset below is DEFENCE IN DEPTH, not the guard. It enumerates the
# redirectors known today and therefore fails OPEN the moment gh adds another —
# the same trap merge-pr.sh's emit() documents, where an enumerated separator
# set missed NUL. The pinned -R is the guard: it holds under any flag-versus-env
# precedence, and it is a constant rather than a derivation because deriving the
# repo from the remote would duplicate gh's own resolution logic and be read
# through the very variable being defended against.
#
# A hard-coded repository is legitimate HERE and would not be under skills/:
# scripts/ is repo-local by charter (CLAUDE.md — it deliberately never ships),
# this serves one repo's merge protocol, and a rename fails loudly at gh, which
# is fail-closed.
unset GH_REPO GH_HOST

exec gh "$KIND" comment "$NUMBER" \
    -R github.com/BaseInfinity/claude-sdlc-harness \
    --body-file "$BODY_FILE"
