#!/bin/bash
# External Benchmark Fetcher
# Fetches model benchmark scores from external sources (cheapest first)
#
# Usage:
#   ./external-benchmark.sh [model]
#   ./external-benchmark.sh --help
#
# Sources (in priority order):
#   1. DailyBench (GitHub raw CSV) - Free
#   2. LiveBench (GitHub data) - Free
#   3. Cached baseline - Free (fallback)
#
# Features:
#   - 24-hour cache to reduce API calls
#   - Self-healing failure tracking
#   - Falls back to baseline on all failures

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL="${1:-claude-sonnet-4}"
CACHE_DIR="$SCRIPT_DIR/../.cache"
CACHE_FILE="$CACHE_DIR/external-benchmark-${MODEL}.json"
CACHE_TTL=86400  # 24 hours
FAIL_COUNT_FILE="$CACHE_DIR/scrape-fail-count.txt"
BASELINE_FILE="$SCRIPT_DIR/../external-baseline.json"

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << 'EOF'
Usage: external-benchmark.sh [model] [options]

Fetches external benchmark scores for AI models.

Arguments:
  model           Model name (default: claude-sonnet-4)

Options:
  --help, -h      Show this help message

Sources (tried in order):
  1. DailyBench   GitHub CSV (free, updated 4x daily)
  2. LiveBench    GitHub data (free, monthly fresh questions)
  3. Baseline     Local fallback (always available)

Output:
  Numeric score (0-100 scale)

Examples:
  ./external-benchmark.sh                    # Default model
  ./external-benchmark.sh claude-opus-4      # Specific model
EOF
    exit 0
fi

mkdir -p "$CACHE_DIR"

# Check cache first
check_cache() {
    if [ -f "$CACHE_FILE" ]; then
        local age
        # macOS and Linux compatible stat
        if stat -f%m "$CACHE_FILE" >/dev/null 2>&1; then
            age=$(($(date +%s) - $(stat -f%m "$CACHE_FILE")))
        else
            age=$(($(date +%s) - $(stat -c%Y "$CACHE_FILE")))
        fi

        if [ "$age" -lt "$CACHE_TTL" ]; then
            jq -r '.score' "$CACHE_FILE" 2>/dev/null
            return 0
        fi
    fi
    return 1
}

# Source 1: DailyBench (GitHub raw CSV)
# CSV columns: model,scenario_class,metric_name,split,run_timestamp,run_date,
#              count,sum,mean,min,max,std,variance,p25,p50,p75,p90,p95,p99
try_dailybench() {
    local URL="https://raw.githubusercontent.com/jacobphillips99/daily-bench/main/results/benchmark_summary.csv"

    # Map model names to DailyBench format
    local db_model
    case "$MODEL" in
        claude-sonnet-4|claude-4-sonnet)
            db_model="anthropic/claude-4-sonnet"
            ;;
        claude-opus-4|claude-4-opus)
            db_model="anthropic/claude-4-opus"
            ;;
        claude-3-5-sonnet)
            db_model="anthropic/claude-3-5-sonnet"
            ;;
        *)
            db_model="anthropic/$MODEL"
            ;;
    esac

    # Download CSV, filter for model, get latest mean score
    local csv_data
    csv_data=$(curl -sf --connect-timeout 10 --max-time 30 "$URL" 2>/dev/null) || return 1

    # Extract mean score (column 9) for the model
    local score
    score=$(echo "$csv_data" | grep -i "$db_model" | tail -1 | awk -F',' '{print $9}' 2>/dev/null)

    # Validate score is numeric and not header
    if [ -n "$score" ] && [ "$score" != "mean" ] && echo "$score" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "$score"
        return 0
    fi

    return 1
}

# Source 2: LiveBench (GitHub data)
try_livebench() {
    local URL="https://raw.githubusercontent.com/LiveBench/LiveBench/main/livebench/model_scores.json"

    # Map model names
    local lb_model
    case "$MODEL" in
        claude-sonnet-4)
            lb_model="claude-4-sonnet"
            ;;
        claude-opus-4)
            lb_model="claude-4-opus"
            ;;
        *)
            lb_model="$MODEL"
            ;;
    esac

    local score
    score=$(curl -sf --connect-timeout 10 --max-time 30 "$URL" 2>/dev/null | jq -r ".\"$lb_model\" // empty" 2>/dev/null)

    if [ -n "$score" ] && echo "$score" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        echo "$score"
        return 0
    fi

    return 1
}

# Source 3: Cached baseline (always works)
use_baseline() {
    if [ -f "$BASELINE_FILE" ]; then
        local score
        score=$(jq -r ".\"$MODEL\".baseline // 75" "$BASELINE_FILE" 2>/dev/null)
        if [ -n "$score" ] && [ "$score" != "null" ]; then
            echo "$score"
            return 0
        fi
    fi
    # Ultimate fallback
    echo "75"
}

# Track failures for self-healing
record_failure() {
    local count
    count=$(cat "$FAIL_COUNT_FILE" 2>/dev/null || echo 0)
    count=$((count + 1))
    echo "$count" > "$FAIL_COUNT_FILE"

    if [ "$count" -ge 3 ]; then
        echo "::warning::External benchmark scraping failed ${count}x - consider updating scrapers" >&2
    fi
}

reset_failures() {
    echo "0" > "$FAIL_COUNT_FILE" 2>/dev/null || true
}

# Main logic
main() {
    local score

    # Try cache first
    if score=$(check_cache); then
        echo "$score"
        exit 0
    fi

    # Try sources in order
    if score=$(try_dailybench 2>/dev/null); then
        reset_failures
    elif score=$(try_livebench 2>/dev/null); then
        reset_failures
    else
        record_failure
        score=$(use_baseline)
        echo "::warning::All external sources failed, using baseline: $score" >&2
    fi

    # Cache result using jq for proper JSON escaping
    jq -n \
        --arg model "$MODEL" \
        --argjson score "$score" \
        --arg fetched "$(date -Iseconds 2>/dev/null || date)" \
        '{model: $model, score: $score, fetched: $fetched}' > "$CACHE_FILE" 2>/dev/null || true

    echo "$score"
}

main
