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
