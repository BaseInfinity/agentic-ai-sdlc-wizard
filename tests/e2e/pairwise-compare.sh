#!/bin/bash
# Pairwise tiebreaker comparison for SDLC evaluation
#
# Only triggers when two outputs have close pointwise scores
# (|scoreA - scoreB| <= threshold). Runs a holistic A-vs-B comparison
# with full swap (both orderings) to mitigate position bias.
#
# Usage:
#   ./pairwise-compare.sh <output_a> <output_b> <scenario> <score_a> <score_b> [--no-api] [threshold]
#
# Arguments:
#   output_a    Path to first output file
#   output_b    Path to second output file
#   scenario    Scenario description text (or path to scenario file)
#   score_a     Pointwise score for output A
#   score_b     Pointwise score for output B
#   --no-api    Skip API calls (for testing — outputs deterministic result only)
#   threshold   Score difference threshold (default: 1.0)
#
# Output: JSON to stdout
#
# Requires:
#   - ANTHROPIC_API_KEY (unless --no-api)
#   - jq

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/eval-criteria.sh"

OUTPUT_FILE_A="$1"
OUTPUT_FILE_B="$2"
SCENARIO="$3"
SCORE_A="$4"
SCORE_B="$5"

# Parse optional flags
NO_API=false
THRESHOLD="1.0"
shift 5 || true
while [ $# -gt 0 ]; do
    case "$1" in
        --no-api) NO_API=true ;;
        *) THRESHOLD="$1" ;;
    esac
    shift
done

# Validate inputs
if [ -z "$OUTPUT_FILE_A" ] || [ -z "$OUTPUT_FILE_B" ] || [ -z "$SCORE_A" ] || [ -z "$SCORE_B" ]; then
    echo "Usage: $0 <output_a> <output_b> <scenario> <score_a> <score_b> [--no-api] [threshold]" >&2
    exit 1
fi

if [ ! -f "$OUTPUT_FILE_A" ]; then
    echo "Error: Output file A not found: $OUTPUT_FILE_A" >&2
    exit 1
fi

if [ ! -f "$OUTPUT_FILE_B" ]; then
    echo "Error: Output file B not found: $OUTPUT_FILE_B" >&2
    exit 1
fi

# Check if pairwise is needed
if ! should_run_pairwise "$SCORE_A" "$SCORE_B" "$THRESHOLD"; then
    # Not triggered — winner is the higher-scoring output
    local_verdict="A"
    if echo "$SCORE_A $SCORE_B" | awk '{exit !($2 > $1)}'; then
        local_verdict="B"
    fi

    jq -n \
        --arg reason "score_difference_exceeds_threshold" \
        --argjson score_a "$SCORE_A" \
        --argjson score_b "$SCORE_B" \
        --arg verdict "$local_verdict" \
        '{
            triggered: false,
            reason: $reason,
            score_a: $score_a,
            score_b: $score_b,
            verdict: $verdict
        }'
    exit 0
fi

# Pairwise triggered — read output files
OUTPUT_A=$(cat "$OUTPUT_FILE_A")
OUTPUT_B=$(cat "$OUTPUT_FILE_B")

# Read scenario from file if it's a path
if [ -f "$SCENARIO" ]; then
    SCENARIO=$(cat "$SCENARIO")
fi

if [ "$NO_API" = "true" ]; then
    # No-API mode: return triggered result with TIE verdict (can't compare without LLM)
    jq -n \
        --argjson score_a "$SCORE_A" \
        --argjson score_b "$SCORE_B" \
        '{
            triggered: true,
            reason: "score_difference_within_threshold",
            score_a: $score_a,
            score_b: $score_b,
            verdict: "TIE",
            note: "no-api mode: skipped LLM comparison"
        }'
    exit 0
fi

# Require API key for actual comparison
if [ -z "$ANTHROPIC_API_KEY" ]; then
    echo "Error: ANTHROPIC_API_KEY required for pairwise comparison" >&2
    exit 1
fi

echo "Pairwise tiebreaker triggered (|$SCORE_A - $SCORE_B| <= $THRESHOLD)" >&2

# API call helper (reuses evaluate.sh pattern)
_pairwise_api_call() {
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

    rm -f "$request_file"
    echo "$raw_text"
}

# Run comparison in both orderings for bias mitigation
echo "  Running AB ordering..." >&2
PROMPT_AB=$(build_holistic_pairwise_prompt "$OUTPUT_A" "$OUTPUT_B" "$SCENARIO" "AB")
RAW_AB=$(_pairwise_api_call "$PROMPT_AB")

echo "  Running BA ordering..." >&2
PROMPT_BA=$(build_holistic_pairwise_prompt "$OUTPUT_A" "$OUTPUT_B" "$SCENARIO" "BA")
RAW_BA=$(_pairwise_api_call "$PROMPT_BA")

# Extract JSON from responses (handle markdown wrapping)
source "$SCRIPT_DIR/lib/json-utils.sh"
RESULT_AB=$(extract_json "$RAW_AB")
RESULT_BA=$(extract_json "$RAW_BA")

# Validate results
if ! validate_pairwise_result "$RESULT_AB" 2>/dev/null; then
    echo "  Warning: Invalid AB result, defaulting to TIE" >&2
    RESULT_AB='{"winner": "TIE", "reasoning": "Invalid response from AB ordering"}'
fi

if ! validate_pairwise_result "$RESULT_BA" 2>/dev/null; then
    echo "  Warning: Invalid BA result, defaulting to TIE" >&2
    RESULT_BA='{"winner": "TIE", "reasoning": "Invalid response from BA ordering"}'
fi

# For BA ordering, the labels are swapped. If BA says "A wins", that means
# the output in position A (which was actually B) wins. We need to remap.
WINNER_BA=$(echo "$RESULT_BA" | jq -r '.winner')
case "$WINNER_BA" in
    A) RESULT_BA=$(echo "$RESULT_BA" | jq '.winner = "B"') ;;
    B) RESULT_BA=$(echo "$RESULT_BA" | jq '.winner = "A"') ;;
esac

# Compute verdict
VERDICT_JSON=$(compute_pairwise_verdict "$RESULT_AB" "$RESULT_BA")

# Build final output
VERDICT=$(echo "$VERDICT_JSON" | jq -r '.verdict')
CONSISTENT=$(echo "$VERDICT_JSON" | jq -r '.consistent')

echo "  Verdict: $VERDICT (consistent: $CONSISTENT)" >&2

jq -n \
    --argjson score_a "$SCORE_A" \
    --argjson score_b "$SCORE_B" \
    --argjson comparison "$VERDICT_JSON" \
    --arg verdict "$VERDICT" \
    '{
        triggered: true,
        reason: "score_difference_within_threshold",
        score_a: $score_a,
        score_b: $score_b,
        comparison: $comparison.comparison,
        consistent: $comparison.consistent,
        verdict: $verdict
    }'
