#!/bin/bash
# cc-drift-check.sh — release-gap delta between two SemVer strings.
#
# Source: ROADMAP #350. Called from .github/workflows/cc-version-drift.yml
# to compute whether the wizard's CC baseline has drifted far enough from
# npm latest to open a "CC version drift" tracking issue.
#
# Codex design constraint (.reviews/176-followup-prio-codex.md #350.4):
# the meaningful gap for CC is PATCH-level within a `MAJOR.MINOR.x` line
# (e.g. 2.1.150 → 2.1.180 = 30-release gap). Naming it "minor" is wrong;
# this script uses "patch_delta" / "release_gap".
#
# Output: single-line JSON to stdout. Exit codes:
#   0 — JSON written successfully (including "below_threshold" results)
#   2 — input invalid (non-SemVer, latest < baseline, etc.)
#
# JSON shape:
#   {
#     "baseline": "2.1.150",
#     "latest": "2.1.180",
#     "threshold": 5,
#     "patch_delta": 30,
#     "component": "patch" | "minor" | "major",
#     "threshold_exceeded": true | false,
#     "alert": true | false   // true on threshold_exceeded OR any minor/major jump
#   }
#
# bash 3-compatible (macOS default ships bash 3.x — no associative arrays).

set -eo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: cc-drift-check.sh --baseline VERSION --latest VERSION [--threshold N]

Computes release-gap between two SemVer strings (vX.Y.Z or X.Y.Z).
Default threshold is 5 (patch-level releases beyond the baseline).

Exits 0 on success (JSON to stdout), 2 on invalid input.
EOF
    exit "${1:-1}"
}

BASELINE=""
LATEST=""
THRESHOLD=5

while [ "$#" -gt 0 ]; do
    case "$1" in
        --baseline) BASELINE="$2"; shift 2 ;;
        --latest)   LATEST="$2";   shift 2 ;;
        --threshold) THRESHOLD="$2"; shift 2 ;;
        -h|--help)  usage 0 ;;
        *) echo "::error::unknown arg: $1" >&2; usage 2 ;;
    esac
done

if [ -z "$BASELINE" ] || [ -z "$LATEST" ]; then
    echo "::error::--baseline and --latest are required" >&2
    usage 2
fi

# Strip optional 'v' prefix (both 'v2.1.150' and '2.1.150' are accepted).
strip_v() { echo "${1#v}"; }
B=$(strip_v "$BASELINE")
L=$(strip_v "$LATEST")

# Validate threshold: non-negative integer. Anything else (empty, "foo",
# "-3", "10.5") triggers exit 2 — silent fallback would hide config bugs.
case "$THRESHOLD" in
    ''|*[!0-9]*) echo "::error::--threshold must be a non-negative integer (got: '$THRESHOLD')" >&2; exit 2 ;;
esac

# Validate SemVer shape: MAJOR.MINOR.PATCH where each part is digits.
# Refuses prerelease tags (e.g. 2.1.150-beta.1) — npm releases of CC
# don't ship those to `latest`, and adding prerelease ordering here
# would let bugs leak past comparisons. Be strict; reject anything else.
validate_semver() {
    case "$1" in
        ''|*[!0-9.]*) return 1 ;;
    esac
    local maj min pat
    maj=$(echo "$1" | cut -d. -f1)
    min=$(echo "$1" | cut -d. -f2)
    pat=$(echo "$1" | cut -d. -f3)
    # All three parts must be present, non-empty, and pure digits.
    [ -n "$maj" ] && [ -n "$min" ] && [ -n "$pat" ] \
        && case "${maj}${min}${pat}" in *[!0-9]*) return 1 ;; esac
}

if ! validate_semver "$B"; then
    echo "::error::invalid baseline SemVer: '$BASELINE'" >&2
    exit 2
fi
if ! validate_semver "$L"; then
    echo "::error::invalid latest SemVer: '$LATEST'" >&2
    exit 2
fi

B_MAJ=$(echo "$B" | cut -d. -f1)
B_MIN=$(echo "$B" | cut -d. -f2)
B_PAT=$(echo "$B" | cut -d. -f3)
L_MAJ=$(echo "$L" | cut -d. -f1)
L_MIN=$(echo "$L" | cut -d. -f2)
L_PAT=$(echo "$L" | cut -d. -f3)

# Refuse to compute on regressions (latest < baseline). The wizard
# would never set its baseline higher than npm latest deliberately, so
# this means the workflow caller passed swapped arguments or the npm
# detection misfired. Better to fail loud than emit a misleading
# "negative gap is fine" JSON.
if [ "$L_MAJ" -lt "$B_MAJ" ] \
    || { [ "$L_MAJ" -eq "$B_MAJ" ] && [ "$L_MIN" -lt "$B_MIN" ]; } \
    || { [ "$L_MAJ" -eq "$B_MAJ" ] && [ "$L_MIN" -eq "$B_MIN" ] && [ "$L_PAT" -lt "$B_PAT" ]; }; then
    echo "::error::latest ($LATEST) is older than baseline ($BASELINE) — check inputs" >&2
    exit 2
fi

COMPONENT="patch"
PATCH_DELTA=0
ALERT="false"
EXCEEDED="false"

if [ "$L_MAJ" -gt "$B_MAJ" ]; then
    COMPONENT="major"
    # Major-jump always alerts; patch delta is meaningless across major
    # lines so report 0 and let the consumer surface "MAJOR jump".
    PATCH_DELTA=0
    ALERT="true"
    EXCEEDED="true"
elif [ "$L_MIN" -gt "$B_MIN" ]; then
    COMPONENT="minor"
    # Same as major: minor-jump always alerts regardless of threshold.
    PATCH_DELTA=0
    ALERT="true"
    EXCEEDED="true"
else
    # Same major.minor line — compute true patch delta.
    PATCH_DELTA=$(( L_PAT - B_PAT ))
    # Codex constraint: threshold of N means "alert when delta > N";
    # exactly N does NOT alert. Strict greater-than.
    if [ "$PATCH_DELTA" -gt "$THRESHOLD" ]; then
        EXCEEDED="true"
        ALERT="true"
    fi
fi

# Emit single-line JSON. Use printf (not echo -n) for POSIX portability
# and to avoid bash-3 quirks with \n handling inside echo arguments.
printf '{"baseline":"%s","latest":"%s","threshold":%d,"patch_delta":%d,"component":"%s","threshold_exceeded":%s,"alert":%s}\n' \
    "$B" "$L" "$THRESHOLD" "$PATCH_DELTA" "$COMPONENT" "$EXCEEDED" "$ALERT"
