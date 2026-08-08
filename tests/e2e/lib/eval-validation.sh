#!/bin/bash
# Eval result validation functions
#
# Validates LLM judge output before scoring to catch:
#   - Missing required JSON fields (schema validation)
#   - Out-of-range points (bounds checking)
#   - Wrong max total (sum validation)
#   - Provides clamping as fallback for out-of-range values
#
# Usage: source this file in your script
#   source "$(dirname "$0")/lib/eval-validation.sh"

# Prompt version — increment when the eval prompt changes materially
EVAL_PROMPT_VERSION="v6"

# Validate that eval result JSON has required structure
#
# Required: .criteria (non-empty object), .summary (string), .improvements (array)
# Each criterion must have: .points (number), .max (number), .evidence (string)
#
# Args:
#   $1 - JSON string to validate
#
# Returns:
#   0 if valid, 1 if invalid (errors on stderr)
validate_eval_schema() {
    local json="$1"

    # Check top-level required fields in a single jq call
    local validation
    validation=$(echo "$json" | jq -r '
        (if has("criteria") and (.criteria | type == "object") and (.criteria | length > 0)
         then "ok" else "Schema error: .criteria must be a non-empty object" end),
        (if has("summary") and (.summary | type == "string")
         then "ok" else "Schema error: .summary must be a string" end),
        (if has("improvements") and (.improvements | type == "array")
         then "ok" else "Schema error: .improvements must be an array" end)
    ' 2>/dev/null)

    # jq parse failure (non-JSON input) = empty validation
    if [ -z "$validation" ]; then
        echo "Schema error: input is not valid JSON" >&2
        return 1
    fi

    local error
    error=$(echo "$validation" | grep -v "^ok$" | head -1)
    if [ -n "$error" ]; then
        echo "$error" >&2
        return 1
    fi

    # Validate each criterion has required fields
    local invalid_criteria
    invalid_criteria=$(echo "$json" | jq -r '
        .criteria | to_entries[] |
        select(
            (.value | has("points") | not) or
            (.value | has("max") | not) or
            (.value | has("evidence") | not)
        ) | .key
    ')

    if [ -n "$invalid_criteria" ]; then
        echo "Schema error: criteria missing required fields (points, max, evidence): $invalid_criteria" >&2
        return 1
    fi

    return 0
}

# Validate that all criteria points are within bounds: 0 <= points <= max
#
# Args:
#   $1 - JSON string with .criteria object
#
# Returns:
#   0 if all within bounds, 1 if any out of bounds (details on stderr)
validate_criteria_bounds() {
    local json="$1"

    local violations
    violations=$(echo "$json" | jq -r '
        .criteria | to_entries[] |
        select(.value.points < 0 or .value.points > .value.max) |
        "\(.key): points=\(.value.points) max=\(.value.max)"
    ')

    if [ -n "$violations" ]; then
        echo "Bounds error: out-of-range criteria:" >&2
        echo "$violations" >&2
        return 1
    fi

    return 0
}

# Validate that the sum of all .max values equals the expected total
#
# Args:
#   $1 - JSON string with .criteria object
#   $2 - Expected total (10 for standard, 11 for UI)
#
# Returns:
#   0 if sum matches, 1 if not (details on stderr)
validate_max_total() {
    local json="$1"
    local expected="$2"

    local actual
    actual=$(echo "$json" | jq '[.criteria[].max] | add')

    if [ "$actual" != "$expected" ]; then
        echo "Total error: sum of max is $actual, expected $expected" >&2
        return 1
    fi

    return 0
}

# Clamp all criteria points to valid range [0, max] with warnings
#
# Args:
#   $1 - JSON string with .criteria object
#
# Returns:
#   JSON string with clamped values (warnings on stderr)
clamp_criteria_bounds() {
    local json="$1"

    # Log any clamping that occurs
    local violations
    violations=$(echo "$json" | jq -r '
        .criteria | to_entries[] |
        select(.value.points < 0 or .value.points > .value.max) |
        "\(.key): \(.value.points) -> clamped to [0, \(.value.max)]"
    ')

    if [ -n "$violations" ]; then
        echo "Warning: clamping out-of-range criteria:" >&2
        echo "$violations" >&2
    fi

    # Clamp values
    echo "$json" | jq '
        .criteria |= (to_entries | map(
            .value.points = (
                if .value.points < 0 then 0
                elif .value.points > .value.max then .value.max
                else .value.points
                end
            )
        ) | from_entries)
    '
}

# Check critical criteria — tdd_red is the sole must-pass.
# Failing it means the SDLC process was fundamentally violated.
#
# GH #486: self_review was dropped from critical. It is still SCORED (1 point,
# "read back the files you modified") because every longitudinal baseline is
# calibrated on a 10-point total — deleting the row would invalidate
# baselines.json, the golden scores and the CUSUM history to save ~80 bytes.
# What changed is that a same-model read-back no longer FAILS a run on its own:
# it has zero recorded unique catches here, while cross-model review caught real
# P1s in the same sessions where self-review reported 64/64 green.
#
# Args:
#   $1 - JSON string with .criteria object (must include tdd_red)
#
# Returns:
#   JSON string: {"critical_miss": bool, "critical_failures": [...]}
check_critical_criteria() {
    local json="$1"
    echo "$json" | jq '
        {
            critical_miss: (
                ((.criteria.tdd_red.points // 0) == 0)
            ),
            critical_failures: [
                (if (.criteria.tdd_red.points // 0) == 0 then "tdd_red" else empty end)
            ]
        }
    '
}

# Enforce: tdd_green_pass requires tdd_green_ran
# If tdd_green_ran=NO (0 points), force tdd_green_pass=NO regardless of LLM output
#
# Args:
#   $1 - JSON string with .criteria object (object-keyed, not array)
#
# Returns:
#   JSON string with consistency enforced
enforce_tdd_consistency() {
    local json="$1"
    echo "$json" | jq '
        if (.criteria.tdd_green_ran.points == 0)
        then .criteria.tdd_green_pass = {
            met: false,
            points: 0,
            max: .criteria.tdd_green_pass.max,
            evidence: "Forced to NO: tdd_green_ran was NO"
        }
        else . end
    '
}
