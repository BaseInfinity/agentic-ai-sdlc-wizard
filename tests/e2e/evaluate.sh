#!/bin/bash
# AI-Powered SDLC Evaluation with SDP (Model Degradation) Tracking
#
# Uses Claude to evaluate whether a scenario execution followed SDLC principles.
# Pass/fail is determined by baseline comparison (see baselines.json).
# Also calculates SDP (SDLC Degradation-adjusted Performance) to account for
# external model quality fluctuations.
#
# Usage:
#   ./evaluate.sh <scenario_file> <output_file> [--json]
#
# Requires:
#   - ANTHROPIC_API_KEY environment variable
#   - jq for JSON parsing
#   - curl for API calls
#
# SDP Scoring:
#   - Raw Score: Our E2E result (Layer 2 - SDLC compliance)
#   - External Benchmark: General model quality (Layer 1)
#   - SDP: Raw adjusted for model conditions
#   - Robustness: How well our SDLC holds up vs model changes

set -e

EVAL_START=$(date +%s)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/json-utils.sh"
source "$SCRIPT_DIR/lib/deterministic-checks.sh"
source "$SCRIPT_DIR/lib/eval-validation.sh"
source "$SCRIPT_DIR/lib/eval-criteria.sh"

# SDP scoring script
SDP_SCRIPT="$SCRIPT_DIR/lib/sdp-score.sh"

SCENARIO_FILE="$1"
OUTPUT_FILE="$2"
JSON_OUTPUT="${3:-false}"
BASELINES_FILE="$SCRIPT_DIR/baselines.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <scenario_file> <output_file> [--json]"
    echo ""
    echo "Arguments:"
    echo "  scenario_file  Path to scenario .md file"
    echo "  output_file    Path to Claude's execution output"
    echo "  --json         Output results as JSON (optional)"
    exit 1
}

# Validate inputs
if [ -z "$SCENARIO_FILE" ] || [ -z "$OUTPUT_FILE" ]; then
    usage
fi

if [ ! -f "$SCENARIO_FILE" ]; then
    echo "Error: Scenario file not found: $SCENARIO_FILE"
    exit 1
fi

if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file not found: $OUTPUT_FILE"
    exit 1
fi

if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY environment variable not set"
    exit 1
fi

# Read scenario and output
SCENARIO_CONTENT=$(cat "$SCENARIO_FILE")
OUTPUT_CONTENT=$(head -c 200000 "$OUTPUT_FILE" 2>/dev/null)  # Limit to 200KB

# Run deterministic pre-checks (free, fast, reproducible)
echo "Running deterministic pre-checks..." >&2
DETERMINISTIC_RESULT=$(run_deterministic_checks "$OUTPUT_CONTENT")
DET_TASK=$(echo "$DETERMINISTIC_RESULT" | jq -r '.task_tracking.points')
DET_CONFIDENCE=$(echo "$DETERMINISTIC_RESULT" | jq -r '.confidence.points')
DET_TDD_RED=$(echo "$DETERMINISTIC_RESULT" | jq -r '.tdd_red.points')
DET_TOTAL=$(echo "$DETERMINISTIC_RESULT" | jq -r '.total')
echo "Deterministic scores: task=$DET_TASK confidence=$DET_CONFIDENCE tdd_red=$DET_TDD_RED total=$DET_TOTAL/4" >&2

# Detect scenario type (standard vs UI) for criterion selection
SCENARIO_TYPE="standard"
if echo "$SCENARIO_CONTENT" | grep -qiE 'UI|styling|CSS|component|color|font|visual'; then
    SCENARIO_TYPE="ui"
    echo "Detected UI scenario — including design_system criterion" >&2
fi

# Multi-call LLM judge: each subjective criterion gets its own focused API call
# This reduces score variance compared to the monolithic single-call approach.
LLM_CRITERIA=$(get_llm_criteria "$SCENARIO_TYPE")
echo "Scoring criteria: $LLM_CRITERIA" >&2

# API call helper — takes a prompt, returns response text
# Writes request to temp file to avoid "Argument list too long" with large outputs
call_criterion_api() {
    local prompt="$1"
    local escaped
    escaped=$(echo "$prompt" | jq -Rs .)

    local request_file
    request_file=$(mktemp)
    cat > "$request_file" <<JSONEOF
{
    "model": "claude-opus-4-6",
    "max_tokens": 512,
    "messages": [{
        "role": "user",
        "content": $escaped
    }]
}
JSONEOF

    local response raw_text
    response=$(curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d @"$request_file")
    raw_text=$(echo "$response" | jq -r '.content[0].text // empty')

    # Retry once on failure
    if [ -z "$raw_text" ]; then
        echo "  Retry for criterion..." >&2
        sleep 3
        response=$(curl -s https://api.anthropic.com/v1/messages \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d @"$request_file")
        raw_text=$(echo "$response" | jq -r '.content[0].text // empty')
    fi

    rm -f "$request_file"
    echo "$raw_text"
}

# Score each criterion independently
ACCUMULATED_RESULT="{}"
FAILED_CRITERIA=""

for criterion in $LLM_CRITERIA; do
    echo "Scoring $criterion..." >&2
    CRITERION_PROMPT=$(build_criterion_prompt "$criterion" "$SCENARIO_CONTENT" "$OUTPUT_CONTENT")

    RAW_RESULT=$(call_criterion_api "$CRITERION_PROMPT")

    if [ -z "$RAW_RESULT" ]; then
        echo "  Warning: API call failed for $criterion, using 0 score" >&2
        max_pts=$(get_criterion_max "$criterion")
        RAW_RESULT="{\"points\": 0, \"max\": $max_pts, \"evidence\": \"API call failed\"}"
        FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
    fi

    # Extract JSON from response
    CRITERION_JSON=$(extract_json "$RAW_RESULT")

    # Validate and fix if needed
    if ! is_valid_json "$CRITERION_JSON"; then
        echo "  Warning: Invalid JSON for $criterion, using 0 score" >&2
        max_pts=$(get_criterion_max "$criterion")
        CRITERION_JSON="{\"points\": 0, \"max\": $max_pts, \"evidence\": \"Invalid JSON response\"}"
        FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
    fi

    # Ensure required fields exist
    if ! echo "$CRITERION_JSON" | jq -e 'has("points") and has("max") and has("evidence")' > /dev/null 2>&1; then
        echo "  Warning: Missing fields for $criterion, using 0 score" >&2
        max_pts=$(get_criterion_max "$criterion")
        CRITERION_JSON="{\"points\": 0, \"max\": $max_pts, \"evidence\": \"Missing required fields\"}"
        FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
    fi

    # Clamp points to valid range
    local_max=$(echo "$CRITERION_JSON" | jq '.max')
    local_pts=$(echo "$CRITERION_JSON" | jq '.points')
    if echo "$local_pts $local_max" | awk '{exit !($1 < 0 || $1 > $2)}'; then
        echo "  Warning: Clamping $criterion score ($local_pts -> [0, $local_max])" >&2
        CRITERION_JSON=$(echo "$CRITERION_JSON" | jq '
            .points = (if .points < 0 then 0 elif .points > .max then .max else .points end)
        ')
    fi

    ACCUMULATED_RESULT=$(aggregate_criterion_results "$criterion" "$CRITERION_JSON" "$ACCUMULATED_RESULT")
    echo "  $criterion: $(echo "$CRITERION_JSON" | jq -r '"\(.points)/\(.max)"')" >&2
done

# Finalize LLM results (adds summary + improvements)
EVAL_RESULT=$(finalize_eval_result "$ACCUMULATED_RESULT")

# Report any API failures
if [ -n "$FAILED_CRITERIA" ]; then
    echo "Warning: Some criteria had API failures:$FAILED_CRITERIA" >&2
fi

# Merge deterministic scores (task_tracking, confidence, tdd_red) into LLM-scored
# criteria, recalculate total score.
# Deterministic criteria are grep-based (free, reproducible); LLM scores subjective
# criteria only (plan_mode, tdd_green, self_review, clean_code, design_system).
EVAL_RESULT=$(echo "$EVAL_RESULT" | jq \
    --argjson det "$DETERMINISTIC_RESULT" \
    '
    # Add deterministic criteria into LLM criteria
    .criteria = (.criteria // {}) + {
        task_tracking: $det.task_tracking,
        confidence: $det.confidence,
        tdd_red: $det.tdd_red
    } |
    # Calculate combined score
    .score = ([.criteria[].points] | add) |
    # Calculate max score
    .max_score = ([.criteria[].max] | add)
    ')

# Parse the evaluation result
SCORE=$(echo "$EVAL_RESULT" | jq -r '.score // 0')
SUMMARY=$(echo "$EVAL_RESULT" | jq -r '.summary // "No summary"')

# Get scenario name for baseline lookup
SCENARIO_NAME=$(basename "$SCENARIO_FILE" .md)

# Load baseline if available
BASELINE="5.0"
MIN_ACCEPTABLE="4.0"
TARGET="7.0"
BASELINE_STATUS="pass"

if [ -f "$BASELINES_FILE" ]; then
    BASELINE=$(jq -r --arg name "$SCENARIO_NAME" '.[$name].baseline // 5.0' "$BASELINES_FILE")
    MIN_ACCEPTABLE=$(jq -r --arg name "$SCENARIO_NAME" '.[$name].min_acceptable // 4.0' "$BASELINES_FILE")
    TARGET=$(jq -r --arg name "$SCENARIO_NAME" '.[$name].target // 7.0' "$BASELINES_FILE")
fi

# Determine pass/warn/fail based on baseline comparison
# Pass: score >= baseline
# Warn: score >= min_acceptable but < baseline
# Fail: score < min_acceptable
if [ "$(echo "$SCORE >= $BASELINE" | bc -l)" -eq 1 ]; then
    PASS="true"
    BASELINE_STATUS="pass"
elif [ "$(echo "$SCORE >= $MIN_ACCEPTABLE" | bc -l)" -eq 1 ]; then
    PASS="true"  # Still pass, but warn
    BASELINE_STATUS="warn"
else
    PASS="false"
    BASELINE_STATUS="fail"
fi

# Calculate SDP scores if script is available
SDP_SCORE="$SCORE"
SDP_DELTA="0"
SDP_EXTERNAL="75"
SDP_BASELINE_EXT="75"
SDP_EXTERNAL_CHANGE="0%"
SDP_ROBUSTNESS="1.0"
SDP_INTERPRETATION="STABLE"

if [ -x "$SDP_SCRIPT" ]; then
    SDP_MODEL="${SDP_MODEL:-claude-opus-4-6}"
    SDP_OUTPUT=$("$SDP_SCRIPT" "$SCORE" "$SDP_MODEL" 2>&1) || true
    if [ -n "$SDP_OUTPUT" ] && ! echo "$SDP_OUTPUT" | grep -qi "error"; then
        SDP_SCORE=$(echo "$SDP_OUTPUT" | grep "^sdp=" | cut -d'=' -f2 || echo "$SCORE")
        SDP_DELTA=$(echo "$SDP_OUTPUT" | grep "^delta=" | cut -d'=' -f2 || echo "0")
        SDP_EXTERNAL=$(echo "$SDP_OUTPUT" | grep "^external=" | cut -d'=' -f2 || echo "75")
        SDP_BASELINE_EXT=$(echo "$SDP_OUTPUT" | grep "^baseline_external=" | cut -d'=' -f2 || echo "75")
        SDP_EXTERNAL_CHANGE=$(echo "$SDP_OUTPUT" | grep "^external_change=" | cut -d'=' -f2 || echo "0%")
        SDP_ROBUSTNESS=$(echo "$SDP_OUTPUT" | grep "^robustness=" | cut -d'=' -f2 || echo "1.0")
        SDP_INTERPRETATION=$(echo "$SDP_OUTPUT" | grep "^interpretation=" | cut -d'=' -f2 || echo "STABLE")
    fi
fi

# Output results
if [ "$JSON_OUTPUT" = "--json" ]; then
    # Validate SDP values are numeric before using --argjson
    # Use --arg for non-numeric values
    is_numeric() { echo "$1" | grep -qE '^-?[0-9]+\.?[0-9]*$'; }

    # Ensure numeric values or use defaults
    if [ -z "$SDP_SCORE" ] || ! is_numeric "$SDP_SCORE"; then SDP_SCORE="$SCORE"; fi
    if [ -z "$SDP_DELTA" ] || ! is_numeric "$SDP_DELTA"; then SDP_DELTA="0"; fi
    if [ -z "$SDP_EXTERNAL" ] || ! is_numeric "$SDP_EXTERNAL"; then SDP_EXTERNAL="75"; fi
    if [ -z "$SDP_BASELINE_EXT" ] || ! is_numeric "$SDP_BASELINE_EXT"; then SDP_BASELINE_EXT="75"; fi
    if [ -z "$SDP_ROBUSTNESS" ] || ! is_numeric "$SDP_ROBUSTNESS"; then SDP_ROBUSTNESS="1.0"; fi

    # Calculate evaluation duration
    EVAL_DURATION=$(($(date +%s) - EVAL_START))

    # Enrich the result with baseline comparison, SDP scoring, and duration
    ENRICHED_RESULT=$(echo "$EVAL_RESULT" | jq \
        --arg pass "$PASS" \
        --arg baseline_status "$BASELINE_STATUS" \
        --argjson baseline "$BASELINE" \
        --argjson min_acceptable "$MIN_ACCEPTABLE" \
        --argjson target "$TARGET" \
        --argjson sdp_score "$SDP_SCORE" \
        --argjson sdp_delta "$SDP_DELTA" \
        --argjson sdp_external "$SDP_EXTERNAL" \
        --argjson sdp_baseline_ext "$SDP_BASELINE_EXT" \
        --arg sdp_external_change "$SDP_EXTERNAL_CHANGE" \
        --argjson sdp_robustness "$SDP_ROBUSTNESS" \
        --arg sdp_interpretation "$SDP_INTERPRETATION" \
        --argjson eval_duration "$EVAL_DURATION" \
        --arg eval_prompt_version "$EVAL_PROMPT_VERSION" \
        '. + {
            pass: ($pass == "true"),
            eval_duration: $eval_duration,
            eval_prompt_version: $eval_prompt_version,
            baseline_comparison: {
                status: $baseline_status,
                baseline: $baseline,
                min_acceptable: $min_acceptable,
                target: $target
            },
            sdp: {
                raw: .score,
                adjusted: $sdp_score,
                delta: $sdp_delta,
                external_benchmark: $sdp_external,
                baseline_external: $sdp_baseline_ext,
                external_change: $sdp_external_change,
                robustness: $sdp_robustness,
                interpretation: $sdp_interpretation
            }
        }')
    echo "$ENRICHED_RESULT"
else
    EVAL_DURATION=$(($(date +%s) - EVAL_START))

    echo ""
    echo "=========================================="
    echo "  SDLC Evaluation Results"
    echo "=========================================="
    echo ""
    echo "Scenario: $(basename "$SCENARIO_FILE" .md)"
    echo "Evaluation duration: ${EVAL_DURATION}s"
    echo ""

    # Show criteria breakdown
    echo "--- Criteria Breakdown ---"
    echo "$EVAL_RESULT" | jq -r '.criteria | to_entries[] | "\(.key): \(.value.points)/\(.value.max) - \(.value.evidence)"' 2>/dev/null || echo "Could not parse criteria"
    echo ""

    # Show score with baseline comparison
    echo "--- Final Score ---"
    echo -e "Raw Score: ${BLUE}$SCORE${NC} / 10"
    echo -e "SDP Score: ${BLUE}$SDP_SCORE${NC} / 10 (delta: $SDP_DELTA)"
    echo "Baseline: $BASELINE | Min: $MIN_ACCEPTABLE | Target: $TARGET"
    echo ""

    # Show SDP context
    echo "--- Model Context (SDP) ---"
    echo "External Benchmark: $SDP_EXTERNAL (baseline: $SDP_BASELINE_EXT, change: $SDP_EXTERNAL_CHANGE)"
    echo "Robustness: $SDP_ROBUSTNESS"
    echo "Interpretation: $SDP_INTERPRETATION"
    echo ""

    # Show pass/fail with baseline status
    if [ "$BASELINE_STATUS" = "pass" ]; then
        echo -e "${GREEN}PASSED${NC} (meets or exceeds baseline) - $SUMMARY"
    elif [ "$BASELINE_STATUS" = "warn" ]; then
        echo -e "${YELLOW}WARNING${NC} (below baseline but acceptable) - $SUMMARY"
    else
        echo -e "${RED}FAILED${NC} (regression detected) - $SUMMARY"
    fi

    # Show improvements
    echo ""
    echo "--- Suggested Improvements ---"
    echo "$EVAL_RESULT" | jq -r '.improvements[]? // "None"' 2>/dev/null
    echo ""
fi

# Cleanup temp files (per-criterion temp files cleaned inside call_criterion_api)

# Exit with appropriate code
if [ "$PASS" = "true" ]; then
    exit 0
else
    exit 1
fi
