#!/bin/bash
# Scenario selection for multi-scenario CI rotation
#
# Provides deterministic round-robin selection of scenarios
# based on PR number. Same PR always gets the same scenario,
# different PRs rotate through the pool.
#
# Usage: source this file in your script
#   source "$(dirname "$0")/lib/scenario-selector.sh"

# List all available scenario files (sorted for determinism)
# Args: $1 = scenarios directory
# Returns: one scenario path per line
list_scenarios() {
    local scenarios_dir="$1"
    ls "$scenarios_dir"/*.md 2>/dev/null | sort
}

# Select a scenario based on PR number (deterministic round-robin)
# Args:
#   $1 = scenarios directory
#   $2 = PR number (or empty for push events)
# Returns: full path to selected scenario file
select_scenario() {
    local scenarios_dir="$1"
    local pr_number="$2"

    # Get sorted list of scenarios into array (portable, no mapfile)
    local scenarios=()
    while IFS= read -r line; do
        scenarios+=("$line")
    done < <(list_scenarios "$scenarios_dir")
    local count=${#scenarios[@]}

    if [ "$count" -eq 0 ]; then
        echo "Error: No scenarios found in $scenarios_dir" >&2
        return 1
    fi

    # For empty PR number (push events), use day-of-year for rotation
    # Strip leading zeros to avoid octal interpretation
    if [ -z "$pr_number" ]; then
        pr_number=$(date +%j | sed 's/^0*//' )
        pr_number=${pr_number:-0}
    fi

    # Round-robin: PR number mod scenario count
    local index=$((pr_number % count))
    echo "${scenarios[$index]}"
}
