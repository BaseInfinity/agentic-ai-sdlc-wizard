#!/bin/bash
# CUSUM (Cumulative Sum) Drift Detection
#
# Detects gradual score drift that before/after comparisons might miss.
# Based on statistical process control methodology.
#
# Supports two data formats:
#   - Plain text (score-history.txt): one total score per line (legacy)
#   - JSON-lines (score-history.jsonl): per-criterion breakdown per line
#
# Usage:
#   ./cusum.sh [--check] [--add <score>] [--add-json <json>] [--reset]
#
# Options:
#   --check           Check current total CUSUM status
#   --check-criteria  Check per-criterion CUSUM status
#   --add <score>     Add a plain total score
#   --add-json <json> Add a JSON score with per-criterion breakdown
#   --reset           Reset all score history
#   --status          Show current drift status
#
# Exit codes:
#   0 - Normal operation / no drift
#   1 - Drift detected (CUSUM crossed threshold)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_FILE="$SCRIPT_DIR/score-history.txt"
JSONL_HISTORY_FILE="$SCRIPT_DIR/score-history.jsonl"

# Configuration
TARGET_SCORE=7.0         # Where we want to be (total)
DRIFT_THRESHOLD=3.0      # CUSUM threshold for alerting
WARNING_THRESHOLD=2.0    # CUSUM threshold for warning

# Per-criterion targets (max points for each)
# Used when calculating per-criterion CUSUM drift
CRITERION_TARGETS="plan_mode_outline:1 plan_mode_tool:1 tdd_green_ran:1 tdd_green_pass:1 self_review:1 clean_code:1 task_tracking:1 confidence:1 tdd_red:2"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 [--check] [--add <score>] [--add-json <json>] [--check-criteria] [--reset] [--status]"
    echo ""
    echo "Options:"
    echo "  --check           Check current CUSUM status (default)"
    echo "  --check-criteria  Check per-criterion CUSUM status"
    echo "  --add <score>     Add a new score and recalculate"
    echo "  --add-json <json> Add a JSON score with per-criterion breakdown"
    echo "  --reset           Reset score history"
    echo "  --status          Show detailed status"
    exit 0
}

# Ensure history files exist
ensure_history() {
    if [ ! -f "$HISTORY_FILE" ]; then
        touch "$HISTORY_FILE"
    fi
    if [ ! -f "$JSONL_HISTORY_FILE" ]; then
        touch "$JSONL_HISTORY_FILE"
    fi
}

# Get all total scores from both history files
# Returns one score per line
get_all_total_scores() {
    # Scores from plain text file
    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        cat "$HISTORY_FILE"
    fi
    # Scores from JSON-lines file (extract .total)
    if [ -f "$JSONL_HISTORY_FILE" ] && [ -s "$JSONL_HISTORY_FILE" ]; then
        jq -r '.total' "$JSONL_HISTORY_FILE"
    fi
}

# Calculate CUSUM from all total scores
calculate_cusum() {
    local all_scores
    all_scores=$(get_all_total_scores)

    if [ -z "$all_scores" ]; then
        echo "0.00"
        return
    fi

    echo "$all_scores" | awk -v target="$TARGET_SCORE" '
    BEGIN { cusum = 0 }
    {
        deviation = $1 - target
        cusum += deviation
    }
    END {
        printf "%.2f", cusum
    }
    '
}

# Calculate per-criterion CUSUM from JSON-lines history
# Args: $1 = criterion name, $2 = target value
# Returns: CUSUM value
calculate_criterion_cusum() {
    local criterion="$1"
    local target="$2"

    if [ ! -f "$JSONL_HISTORY_FILE" ] || [ ! -s "$JSONL_HISTORY_FILE" ]; then
        echo "0.00"
        return
    fi

    jq -r --arg c "$criterion" '.[$c] // 0' "$JSONL_HISTORY_FILE" | awk -v target="$target" '
    BEGIN { cusum = 0 }
    {
        deviation = $1 - target
        cusum += deviation
    }
    END {
        printf "%.2f", cusum
    }
    '
}

# Get drift status for a CUSUM value
# Args: $1 = CUSUM value
# Returns: NORMAL, WARNING, or ALERT
get_drift_status() {
    local cusum="$1"
    local abs_cusum
    abs_cusum=$(echo "$cusum" | awk '{printf "%.2f", ($1 < 0) ? -$1 : $1}')

    if echo "$abs_cusum $DRIFT_THRESHOLD" | awk '{exit !($1 >= $2)}'; then
        echo "ALERT"
    elif echo "$abs_cusum $WARNING_THRESHOLD" | awk '{exit !($1 >= $2)}'; then
        echo "WARNING"
    else
        echo "NORMAL"
    fi
}

# Get score count (both files)
get_score_count() {
    local count=0
    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        count=$((count + $(wc -l < "$HISTORY_FILE" | tr -d ' ')))
    fi
    if [ -f "$JSONL_HISTORY_FILE" ] && [ -s "$JSONL_HISTORY_FILE" ]; then
        count=$((count + $(wc -l < "$JSONL_HISTORY_FILE" | tr -d ' ')))
    fi
    echo "$count"
}

# Get mean score
get_mean_score() {
    local all_scores
    all_scores=$(get_all_total_scores)

    if [ -z "$all_scores" ]; then
        echo "N/A"
        return
    fi

    echo "$all_scores" | awk '
    BEGIN { sum = 0; count = 0 }
    { sum += $1; count++ }
    END {
        if (count > 0) printf "%.1f", sum/count
        else print "N/A"
    }
    '
}

# Get latest score
get_latest_score() {
    local latest_txt="" latest_jsonl=""

    if [ -f "$HISTORY_FILE" ] && [ -s "$HISTORY_FILE" ]; then
        latest_txt=$(tail -1 "$HISTORY_FILE")
    fi
    if [ -f "$JSONL_HISTORY_FILE" ] && [ -s "$JSONL_HISTORY_FILE" ]; then
        latest_jsonl=$(tail -1 "$JSONL_HISTORY_FILE" | jq -r '.total')
    fi

    # Return whichever was added most recently (by file modification time)
    if [ -n "$latest_jsonl" ]; then
        echo "$latest_jsonl"
    elif [ -n "$latest_txt" ]; then
        echo "$latest_txt"
    else
        echo "N/A"
    fi
}

# Check drift status (total)
check_drift() {
    local cusum
    cusum=$(calculate_cusum)
    get_drift_status "$cusum"
}

# Show status
show_status() {
    ensure_history

    local cusum score_count mean_score latest_score status
    cusum=$(calculate_cusum)
    score_count=$(get_score_count)
    mean_score=$(get_mean_score)
    latest_score=$(get_latest_score)
    status=$(check_drift)

    echo ""
    echo "=========================================="
    echo "  CUSUM Drift Detection Status"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Target Score:      $TARGET_SCORE"
    echo "  Warning Threshold: ±$WARNING_THRESHOLD"
    echo "  Alert Threshold:   ±$DRIFT_THRESHOLD"
    echo ""
    echo "Current State:"
    echo "  Score Count:       $score_count"
    echo "  Mean Score:        $mean_score"
    echo "  Latest Score:      $latest_score"
    echo -e "  CUSUM Value:       ${BLUE}$cusum${NC}"
    echo ""

    case "$status" in
        NORMAL)
            echo -e "  Status: ${GREEN}NORMAL${NC} - Scores stable around target"
            ;;
        WARNING)
            if echo "$cusum" | awk '{exit !($1 < 0)}'; then
                echo -e "  Status: ${YELLOW}WARNING${NC} - Scores trending below target"
            else
                echo -e "  Status: ${YELLOW}WARNING${NC} - Scores trending above target (good!)"
            fi
            ;;
        ALERT)
            if echo "$cusum" | awk '{exit !($1 < 0)}'; then
                echo -e "  Status: ${RED}ALERT${NC} - Significant drift BELOW target"
                echo ""
                echo "  Action: Review recent changes for regression causes."
            else
                echo -e "  Status: ${GREEN}ALERT${NC} - Significant drift ABOVE target"
                echo ""
                echo "  Action: Consider raising baseline - scores consistently exceeding target!"
            fi
            ;;
    esac
    echo ""
}

# Add a plain total score
add_score() {
    local score="$1"
    ensure_history

    # Validate score is a number between 0 and 10
    if ! echo "$score" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "Error: Score must be a number" >&2
        exit 1
    fi

    if echo "$score" | awk '{exit !($1 < 0 || $1 > 10)}'; then
        echo "Error: Score must be between 0 and 10" >&2
        exit 1
    fi

    # Add score to history
    echo "$score" >> "$HISTORY_FILE"

    # Show updated status
    echo -e "${GREEN}Added score: $score${NC}"
    echo ""

    local cusum status
    cusum=$(calculate_cusum)
    status=$(check_drift)

    echo "CUSUM: $cusum (Status: $status)"

    # Return appropriate exit code
    if [ "$status" = "ALERT" ]; then
        if echo "$cusum" | awk '{exit !($1 < 0)}'; then
            exit 1  # Negative drift is bad
        fi
    fi
}

# Add a JSON score with per-criterion breakdown
add_json_score() {
    local json="$1"
    ensure_history

    # Validate it's valid JSON with a .total field
    if ! echo "$json" | jq -e '.total' > /dev/null 2>&1; then
        echo "Error: JSON must have a .total field" >&2
        exit 1
    fi

    local total
    total=$(echo "$json" | jq -r '.total')

    # Validate total is in range
    if echo "$total" | awk '{exit !($1 < 0 || $1 > 11)}'; then
        echo "Error: Total score must be between 0 and 11" >&2
        exit 1
    fi

    # Append to JSON-lines history
    echo "$json" | jq -c '.' >> "$JSONL_HISTORY_FILE"

    echo -e "${GREEN}Added JSON score (total: $total)${NC}"
    echo ""

    local cusum status
    cusum=$(calculate_cusum)
    status=$(check_drift)

    echo "CUSUM: $cusum (Status: $status)"

    if [ "$status" = "ALERT" ]; then
        if echo "$cusum" | awk '{exit !($1 < 0)}'; then
            exit 1
        fi
    fi
}

# Check and report per-criterion CUSUM
check_criteria_and_report() {
    ensure_history

    if [ ! -f "$JSONL_HISTORY_FILE" ] || [ ! -s "$JSONL_HISTORY_FILE" ]; then
        echo "No JSON-lines history found. Use --add-json to add per-criterion scores."
        exit 0
    fi

    local output=""

    for entry in $CRITERION_TARGETS; do
        local criterion="${entry%%:*}"
        local target="${entry##*:}"

        local cusum
        cusum=$(calculate_criterion_cusum "$criterion" "$target")
        local status
        status=$(get_drift_status "$cusum")

        output="${output}${criterion} CUSUM=${cusum} STATUS=${status}\n"
    done

    echo -e "$output"
}

# Reset history
reset_history() {
    if [ -f "$HISTORY_FILE" ]; then
        rm "$HISTORY_FILE"
    fi
    touch "$HISTORY_FILE"
    if [ -f "$JSONL_HISTORY_FILE" ]; then
        rm "$JSONL_HISTORY_FILE"
    fi
    touch "$JSONL_HISTORY_FILE"
    echo -e "${GREEN}Score history reset.${NC}"
}

# Check and return status (total)
check_and_report() {
    ensure_history

    local status
    status=$(check_drift)
    local cusum
    cusum=$(calculate_cusum)

    case "$status" in
        NORMAL)
            echo "CUSUM=$cusum STATUS=NORMAL"
            exit 0
            ;;
        WARNING)
            echo "CUSUM=$cusum STATUS=WARNING"
            exit 0
            ;;
        ALERT)
            echo "CUSUM=$cusum STATUS=ALERT"
            if echo "$cusum" | awk '{exit !($1 < 0)}'; then
                exit 1  # Negative drift alert
            else
                exit 0  # Positive drift is good
            fi
            ;;
    esac
}

# Main
main() {
    case "${1:-}" in
        --help|-h)
            usage
            ;;
        --check)
            check_and_report
            ;;
        --check-criteria)
            check_criteria_and_report
            ;;
        --add)
            if [ -z "${2:-}" ]; then
                echo "Error: --add requires a score" >&2
                exit 1
            fi
            add_score "$2"
            ;;
        --add-json)
            if [ -z "${2:-}" ]; then
                echo "Error: --add-json requires a JSON string" >&2
                exit 1
            fi
            add_json_score "$2"
            ;;
        --reset)
            reset_history
            ;;
        --status|"")
            show_status
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
}

main "$@"
