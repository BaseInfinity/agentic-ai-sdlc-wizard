#!/bin/bash
# release-drift-check.sh — ROADMAP #449: has main silently outrun npm?
#
# Source: ROADMAP #449, filed 2026-07-14 after npm `latest` sat at
# v1.86.0 while main was 7 consumer-affecting commits ahead — nothing
# in the process would ever have prompted a release. Called from
# .github/workflows/release-drift.yml, mirrors cc-drift-check.sh's
# split: the workflow fetches real data (git log, npm view), this
# script does pure computation on synthetic counts/epochs so tests
# need no live git repo or network.
#
# Output: single-line JSON to stdout. Exit codes:
#   0 — JSON written successfully (including "below_threshold" results)
#   2 — input invalid (missing required arg, non-numeric, now < oldest)
#
# JSON shape:
#   {
#     "commit_count": 6,
#     "oldest_age_days": 3,
#     "count_threshold": 5,
#     "age_threshold_days": 7,
#     "count_exceeded": true,
#     "age_exceeded": false,
#     "alert": true
#   }
#
# bash 3-compatible (macOS default ships bash 3.x).

set -eo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: release-drift-check.sh --commit-count N --oldest-commit-epoch T --now-epoch T2
                               [--count-threshold N] [--age-threshold-days N]

Computes whether consumer-path commits since the last v* tag exceed a
count or age threshold. commit-count=0 never alerts (oldest-commit-epoch
is meaningless when there are no pending commits).

Defaults: --count-threshold 5, --age-threshold-days 7.

Exits 0 on success (JSON to stdout), 2 on invalid input.
EOF
    exit "${1:-1}"
}

COMMIT_COUNT=""
OLDEST_EPOCH=""
NOW_EPOCH=""
COUNT_THRESHOLD=5
AGE_THRESHOLD_DAYS=7

while [ "$#" -gt 0 ]; do
    case "$1" in
        --commit-count)        COMMIT_COUNT="$2"; shift 2 ;;
        --oldest-commit-epoch) OLDEST_EPOCH="$2"; shift 2 ;;
        --now-epoch)           NOW_EPOCH="$2"; shift 2 ;;
        --count-threshold)     COUNT_THRESHOLD="$2"; shift 2 ;;
        --age-threshold-days)  AGE_THRESHOLD_DAYS="$2"; shift 2 ;;
        -h|--help)             usage 0 ;;
        *) echo "::error::unknown arg: $1" >&2; usage 2 ;;
    esac
done

if [ -z "$COMMIT_COUNT" ] || [ -z "$OLDEST_EPOCH" ] || [ -z "$NOW_EPOCH" ]; then
    echo "::error::--commit-count, --oldest-commit-epoch, and --now-epoch are required" >&2
    usage 2
fi

# Validate all numeric inputs are non-negative integers. Silent
# fallback on a bad number would hide a broken workflow step — fail
# loud, same philosophy as #350's cc-drift-check.sh.
is_nonneg_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
        *) return 0 ;;
    esac
}

for name_val in "commit-count:$COMMIT_COUNT" "oldest-commit-epoch:$OLDEST_EPOCH" \
                 "now-epoch:$NOW_EPOCH" "count-threshold:$COUNT_THRESHOLD" \
                 "age-threshold-days:$AGE_THRESHOLD_DAYS"; do
    name="${name_val%%:*}"
    val="${name_val#*:}"
    if ! is_nonneg_int "$val"; then
        echo "::error::--$name must be a non-negative integer (got: '$val')" >&2
        exit 2
    fi
done

if [ "$NOW_EPOCH" -lt "$OLDEST_EPOCH" ]; then
    echo "::error::--now-epoch ($NOW_EPOCH) is before --oldest-commit-epoch ($OLDEST_EPOCH) — check inputs" >&2
    exit 2
fi

COUNT_EXCEEDED="false"
AGE_EXCEEDED="false"
OLDEST_AGE_DAYS=0

if [ "$COMMIT_COUNT" -gt 0 ]; then
    OLDEST_AGE_DAYS=$(( (NOW_EPOCH - OLDEST_EPOCH) / 86400 ))
    # Strict greater-than, matching cc-drift-check.sh's convention:
    # exactly at the threshold does NOT alert.
    if [ "$COMMIT_COUNT" -gt "$COUNT_THRESHOLD" ]; then
        COUNT_EXCEEDED="true"
    fi
    if [ "$OLDEST_AGE_DAYS" -gt "$AGE_THRESHOLD_DAYS" ]; then
        AGE_EXCEEDED="true"
    fi
fi
# commit_count=0 leaves both *_exceeded false and oldest_age_days=0 —
# nothing pending, age is meaningless, never alert.

ALERT="false"
if [ "$COUNT_EXCEEDED" = "true" ] || [ "$AGE_EXCEEDED" = "true" ]; then
    ALERT="true"
fi

printf '{"commit_count":%d,"oldest_age_days":%d,"count_threshold":%d,"age_threshold_days":%d,"count_exceeded":%s,"age_exceeded":%s,"alert":%s}\n' \
    "$COMMIT_COUNT" "$OLDEST_AGE_DAYS" "$COUNT_THRESHOLD" "$AGE_THRESHOLD_DAYS" "$COUNT_EXCEEDED" "$AGE_EXCEEDED" "$ALERT"
