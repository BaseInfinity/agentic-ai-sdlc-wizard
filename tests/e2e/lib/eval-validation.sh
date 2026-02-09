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
EVAL_PROMPT_VERSION="v2"

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

    # Check top-level required fields
    local has_criteria has_summary has_improvements
    has_criteria=$(echo "$json" | jq 'has("criteria") and (.criteria | type == "object") and (.criteria | length > 0)')
    has_summary=$(echo "$json" | jq 'has("summary") and (.summary | type == "string")')
    has_improvements=$(echo "$json" | jq 'has("improvements") and (.improvements | type == "array")')

    if [ "$has_criteria" != "true" ]; then
        echo "Schema error: .criteria must be a non-empty object" >&2
        return 1
    fi

    if [ "$has_summary" != "true" ]; then
        echo "Schema error: .summary must be a string" >&2
        return 1
    fi

    if [ "$has_improvements" != "true" ]; then
        echo "Schema error: .improvements must be an array" >&2
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
