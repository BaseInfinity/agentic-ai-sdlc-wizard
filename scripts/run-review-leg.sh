#!/bin/bash
# Launch a cross-model review leg so it cannot hang, and so its fate is its
# exit status (#590).
#
# Usage:
#   scripts/run-review-leg.sh OUTPUT_FILE PROMPT [EXTRA_CODEX_ARGS...]
#
# Run it as a background task. The task's exit status IS the leg's verdict:
# 0 completed, non-zero failed, nothing by your deadline means inspect and
# relaunch. There is no separate waiter to consult and nothing to poll.
#
# ---------------------------------------------------------------------------
# THE FAILURE
#
# `codex exec` reads stdin to EOF and appends it to the argv prompt — argv and
# stdin are concatenated, not alternatives. Handed a pipe nobody closes, it
# blocks on that read BEFORE contacting the model, forever. On 2026-08-13 two
# review legs were waited on for 51 and 28 minutes; the loop's "still working,
# or done?" decision was made twice against a process that had never started.
#
# ---------------------------------------------------------------------------
# WHY THERE IS NO WAITER HERE, AFTER TWO ATTEMPTS AT ONE
#
# The first attempt watched the output file and the process table from
# outside. Sol (GPT-5.6 high) falsified every signal with running code: `-o`
# output carries no completion marker; `tokens used` appears in codex's echoed
# prompt, so a crashed leg read as complete; an fd reported as PIPE may be at
# EOF and healthy; the hang's byte signature differs per machine (39 here, 143
# on another); and enumerating holders of the file counted readers, so a
# `tail -f` flipped the verdict.
#
# The second attempt recorded the child's pid and exit status in sidecar
# files for a waiter to read. Sol falsified that too: the child exits before
# the status is published, so a successful leg reads as dead; killing only the
# launcher leaves a status that can never arrive while the child pid still
# looks alive; a stale status from a previous run is read as this run's; and a
# reused pid is indistinguishable from the original process.
#
# Both are the same mistake in different clothes — a SECOND OBSERVER trying to
# reconstruct what the first process already knows. The launcher's own exit
# status is that knowledge, delivered by the process that has it. So the
# waiter is gone, and the sidecars with it: with no reader they were only a
# way to be stale.
#
# What remains is the part that actually prevents the failure: the child gets
# /dev/null on stdin, whatever this script inherited. Verified against real
# codex 0.147.0 with this script's own stdin on an unclosed fifo — the shape
# that reproduces a live hang — the leg completed normally.
#
# A leg typed ad hoc, outside this script, has no owner and no status. Its
# fate is unknown immediately; relaunch it through here rather than waiting on
# it. That is the one case detection was ever needed for, and it is prose in
# the skill, not a signal any code can soundly reconstruct.

set -e

if [ $# -lt 2 ]; then
    echo "usage: $0 OUTPUT_FILE PROMPT [EXTRA_CODEX_ARGS...]" >&2
    exit 64
fi

OUTPUT="$1"
shift

: > "$OUTPUT"

# ---------------------------------------------------------------------------
# THE BUILD GOES IN FRONT OF THE REVIEWER (#613)
#
# PR #610 ran EIGHT review rounds with two independent reviewers while CI
# `validate` was red the entire time. Both reviewers ran the test suites
# directly and correctly reported them green — the guard that was failing was
# one nobody was asked about, and the merge gate is what finally caught it.
# That is a gate step discovered mid-merge, which #593 Rung 1's stop condition
# names as a failure in so many words.
#
# Both reviewers then prescribed the same fix independently, and it is not more
# diff scrutiny: "Seven rounds audited the diff; zero audited the build."
#
# So the build is stated where the reviewer reads, BEFORE the model's own
# output. This is preflight, never a gate: a red build is REPORTED and the leg
# proceeds. Deliberately so — a leg must stay launchable against known-red CI
# when that is the point, and a preflight that can refuse to launch is a second
# way for a review to not happen, which is the failure #590 exists to prevent.
#
# Every failure mode of the probe is absorbed. No `gh`, no auth, no network, no
# PR for this branch: each records "unknown" and the review runs. `< /dev/null`
# for the same reason it is on the exec line below, and a timeout because a
# preflight that can hang has reintroduced #590 in the one place nobody would
# look for it.
{
    echo "## CI STATUS (preflight, #613)"
    echo
    # `timeout` is GNU coreutils and is NOT on a stock macOS — this repo's
    # primary machine has neither `timeout` nor `gtimeout`. Hardcoding it makes
    # the probe report UNKNOWN forever on the maintainer's own laptop, silently,
    # which is the failure mode this whole issue is about. Caught by the suite,
    # not by review. So it is used when present and skipped when not: gh carries
    # its own network timeouts, and the leg is background work whose status the
    # caller already owns.
    if command -v timeout > /dev/null 2>&1; then
        CI_TIMEOUT="timeout 30"
    elif command -v gtimeout > /dev/null 2>&1; then
        CI_TIMEOUT="gtimeout 30"
    else
        CI_TIMEOUT=""
    fi
    # shellcheck disable=SC2086  # unquoted on purpose: empty means "no wrapper"
    if CI_OUT=$($CI_TIMEOUT gh pr checks --required 2>&1 < /dev/null); then
        echo "All required checks reported passing:"
        echo
        echo '```'
        echo "$CI_OUT"
        echo '```'
    else
        CI_RC=$?
        if [ -n "$CI_OUT" ]; then
            echo "NOT GREEN, or not determinable (gh exit $CI_RC). Raw output:"
            echo
            echo '```'
            echo "$CI_OUT"
            echo '```'
        else
            echo "UNKNOWN — \`gh pr checks\` produced nothing (exit $CI_RC)."
            echo "No PR for this branch, no auth, no network, or gh unavailable."
        fi
    fi
    echo
    echo "**A certification verdict issued over a build that is not green, or"
    echo "not determinable, is only valid if it says so and says why.** The"
    echo "build is an input to your verdict, not background noise."
    echo
    echo "---"
    echo
} >> "$OUTPUT" 2>&1

# `< /dev/null` is the whole prevention: the child gets EOF immediately and
# proceeds to the model. Keep it on this line — it is not incidental.
#
# exec replaces this shell, so the caller sees codex's own exit status with
# nothing in between that could die separately and leave the status unknown.
exec codex exec \
    -c 'model_reasoning_effort="high"' \
    -s danger-full-access \
    "$@" \
    >> "$OUTPUT" 2>&1 < /dev/null
