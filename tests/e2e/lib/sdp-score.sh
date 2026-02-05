#!/bin/bash
# SDP (SDLC Degradation-adjusted Performance) Score Calculator
#
# Usage:
#   ./sdp-score.sh <raw_score> [model]
#   ./sdp-score.sh --help
#
# Calculates:
#   - SDP = Raw × (baseline_external / current_external)
#   - Robustness = How well SDLC holds up vs general model changes
#   - Interpretation = What the scores mean
#
# Output format:
#   raw=6.0
#   sdp=6.67
#   delta=0.67
#   external=67.5
#   baseline_external=75.0
#   external_change=-10%
#   robustness=0.85
#   interpretation=MODEL_DEGRADED_BUT_ROBUST

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASELINE_FILE="$SCRIPT_DIR/../external-baseline.json"
BENCHMARK_SCRIPT="$SCRIPT_DIR/external-benchmark.sh"

# Show help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    cat << 'EOF'
Usage: sdp-score.sh <raw_score> [model] [options]

Calculates SDLC Degradation-adjusted Performance score.

Arguments:
  raw_score       Our E2E evaluation score (0-10)
  model           Model name (default: claude-sonnet-4)

Options:
  --help, -h      Show this help message

Output Fields:
  raw               Original E2E score
  sdp               Adjusted score (normalized for model conditions)
  delta             Difference between SDP and raw
  external          Current external benchmark score
  baseline_external Baseline external benchmark score
  external_change   Percentage change in external benchmarks
  robustness        How well SDLC holds up vs model changes
  interpretation    What the results mean

Interpretation Values:
  MODEL_DEGRADED        Model dropped, our scores dropped proportionally
  MODEL_IMPROVED        Model improved, our scores improved
  STABLE                No significant change
  SDLC_ISSUE            Model stable but our scores dropped (investigate)
  SDLC_ROBUST           Model dropped but our scores held (good!)

Examples:
  ./sdp-score.sh 6.0                        # Default model
  ./sdp-score.sh 7.5 claude-opus-4          # Specific model
EOF
    exit 0
fi

# Validate input
RAW_SCORE="$1"
MODEL="${2:-claude-sonnet-4}"

if [ -z "$RAW_SCORE" ]; then
    echo "Error: raw_score required" >&2
    echo "Usage: sdp-score.sh <raw_score> [model]" >&2
    exit 1
fi

# Validate raw_score is numeric
if ! echo "$RAW_SCORE" | grep -qE '^[0-9]+\.?[0-9]*$'; then
    echo "Error: raw_score must be numeric" >&2
    exit 1
fi

# Get current external benchmark
get_external_score() {
    if [ -x "$BENCHMARK_SCRIPT" ]; then
        "$BENCHMARK_SCRIPT" "$MODEL" 2>/dev/null || echo "75"
    else
        echo "75"  # Fallback
    fi
}

# Get baseline external from file
get_baseline_external() {
    if [ -f "$BASELINE_FILE" ]; then
        local baseline
        baseline=$(jq -r ".\"$MODEL\".baseline // 75" "$BASELINE_FILE" 2>/dev/null)
        if [ -n "$baseline" ] && [ "$baseline" != "null" ]; then
            echo "$baseline"
            return
        fi
    fi
    echo "75"  # Default baseline
}

# Calculate SDP
calculate_sdp() {
    local raw="$1"
    local external="$2"
    local baseline_ext="$3"

    # SDP = Raw × (baseline / current)
    # If model dropped 10% (75 → 67.5), SDP adjusts up: 6.0 × (75/67.5) = 6.67
    local sdp
    if [ "$(echo "$external > 0" | bc -l)" -eq 1 ]; then
        sdp=$(echo "scale=2; $raw * ($baseline_ext / $external)" | bc)
    else
        sdp="$raw"
    fi

    # Cap adjustment to ±20% to avoid wild swings
    local max_sdp min_sdp
    max_sdp=$(echo "scale=2; $raw * 1.2" | bc)
    min_sdp=$(echo "scale=2; $raw * 0.8" | bc)

    if [ "$(echo "$sdp > $max_sdp" | bc -l)" -eq 1 ]; then
        sdp="$max_sdp"
    elif [ "$(echo "$sdp < $min_sdp" | bc -l)" -eq 1 ]; then
        sdp="$min_sdp"
    fi

    echo "$sdp"
}

# Calculate robustness ratio
calculate_robustness() {
    local raw="$1"
    local sdp="$2"
    local external="$3"
    local baseline_ext="$4"

    # External change percentage
    local ext_change_pct
    if [ "$(echo "$baseline_ext > 0" | bc -l)" -eq 1 ]; then
        ext_change_pct=$(echo "scale=4; (($external - $baseline_ext) / $baseline_ext) * 100" | bc)
    else
        ext_change_pct="0"
    fi

    # Our change (implied from SDP vs raw)
    local our_change_pct
    if [ "$(echo "$raw > 0" | bc -l)" -eq 1 ]; then
        our_change_pct=$(echo "scale=4; (($sdp - $raw) / $raw) * 100" | bc)
    else
        our_change_pct="0"
    fi

    # Robustness = our_change / external_change
    # < 1.0 = SDLC is more robust than model (good)
    # = 1.0 = SDLC tracks model exactly
    # > 1.0 = SDLC is more sensitive than model (fragile)
    local robustness
    local ext_nonzero
    ext_nonzero=$(echo "$ext_change_pct != 0" | bc -l 2>/dev/null || echo "0")
    if [ "$ext_nonzero" = "1" ]; then
        # Robustness = absolute ratio of our change vs external change
        # < 1.0 = SDLC more resilient than model (good)
        # = 1.0 = tracks model exactly
        # > 1.0 = SDLC more sensitive (fragile)
        local abs_our abs_ext
        abs_our=$(echo "${our_change_pct#-}" | bc 2>/dev/null || echo "0")
        abs_ext=$(echo "${ext_change_pct#-}" | bc 2>/dev/null || echo "1")
        robustness=$(echo "scale=2; $abs_our / $abs_ext" | bc 2>/dev/null || echo "1.0")
        # Handle edge cases: empty, dash-only, or extreme values (cap at 5.0)
        if [ -z "$robustness" ] || [ "$robustness" = "-" ]; then
            robustness="1.0"
        elif [ "$(echo "$robustness > 5" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
            robustness="5.0"
        fi
    else
        robustness="1.0"  # No external change = neutral
    fi

    echo "$robustness"
}

# Interpret the results
interpret_result() {
    local delta="$1"
    local external_change="$2"
    local robustness="$3"

    # Remove % sign for comparison
    local ext_change_num
    ext_change_num=$(echo "$external_change" | tr -d '%')

    # Thresholds
    local delta_threshold="0.5"
    local ext_threshold="5"

    local model_status="STABLE"
    local sdlc_status="STABLE"

    # Model status
    if [ "$(echo "$ext_change_num < -$ext_threshold" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        model_status="DEGRADED"
    elif [ "$(echo "$ext_change_num > $ext_threshold" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        model_status="IMPROVED"
    fi

    # SDLC status (based on delta)
    if [ "$(echo "$delta > $delta_threshold" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        sdlc_status="ADJUSTED_UP"
    elif [ "$(echo "$delta < -$delta_threshold" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
        sdlc_status="ADJUSTED_DOWN"
    fi

    # Combined interpretation
    if [ "$model_status" = "DEGRADED" ]; then
        if [ "$(echo "${robustness#-} < 0.8" | bc -l 2>/dev/null || echo 0)" -eq 1 ]; then
            echo "SDLC_ROBUST"
        else
            echo "MODEL_DEGRADED"
        fi
    elif [ "$model_status" = "IMPROVED" ]; then
        echo "MODEL_IMPROVED"
    elif [ "$sdlc_status" = "ADJUSTED_DOWN" ]; then
        echo "SDLC_ISSUE"
    else
        echo "STABLE"
    fi
}

# Main calculation
main() {
    # Get external scores
    local external baseline_ext
    external=$(get_external_score)
    baseline_ext=$(get_baseline_external)

    # Calculate SDP
    local sdp
    sdp=$(calculate_sdp "$RAW_SCORE" "$external" "$baseline_ext")

    # Calculate delta
    local delta
    delta=$(echo "scale=2; $sdp - $RAW_SCORE" | bc)

    # Calculate external change percentage
    local external_change
    if [ "$(echo "$baseline_ext > 0" | bc -l)" -eq 1 ]; then
        external_change=$(echo "scale=1; (($external - $baseline_ext) / $baseline_ext) * 100" | bc)
    else
        external_change="0"
    fi

    # Calculate robustness
    local robustness
    robustness=$(calculate_robustness "$RAW_SCORE" "$sdp" "$external" "$baseline_ext")

    # Get interpretation
    local interpretation
    interpretation=$(interpret_result "$delta" "$external_change" "$robustness")

    # Output all values
    echo "raw=$RAW_SCORE"
    echo "sdp=$sdp"
    echo "delta=$delta"
    echo "external=$external"
    echo "baseline_external=$baseline_ext"
    echo "external_change=${external_change}%"
    echo "robustness=$robustness"
    echo "interpretation=$interpretation"
}

main
