#!/bin/bash
# Run Tier 2 (5-trial) statistical evaluation
#
# Usage:
#   ./run-tier2-evaluation.sh <scenario> <output_file> [trials]
#
# Arguments:
#   scenario     Scenario file path (required)
#   output_file  Claude execution output file (required)
#   trials       Number of evaluation trials (default: 5)
#
# Output (to stdout):
#   scores=<space-separated scores>
#   score=<mean>
#   ci=<confidence interval string>
#
# Example:
#   ./run-tier2-evaluation.sh tests/e2e/scenarios/version-upgrade.md /tmp/claude-output.json
#   # Output:
#   # scores= 5.1 5.3 5.0 5.2 5.4
#   # score=5.2
#   # ci=5.2 ± 0.2 (95% CI: [5.0, 5.4])

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SCENARIO="${1:?Error: scenario file path required}"
OUTPUT_FILE="${2:?Error: output file path required}"
TRIALS="${3:-5}"

# Verify scenario exists
if [ ! -f "$SCENARIO" ]; then
    echo "Error: Scenario not found: $SCENARIO" >&2
    exit 1
fi

# Verify output file exists
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Output file not found: $OUTPUT_FILE" >&2
    exit 1
fi

# Run evaluations
SCORES=""
for i in $(seq 1 "$TRIALS"); do
    echo "Trial $i/$TRIALS..." >&2
    RESULT=$("$SCRIPT_DIR/evaluate.sh" "$SCENARIO" "$OUTPUT_FILE" --json 2>/dev/null || echo '{"score":0}')
    SCORE=$(echo "$RESULT" | jq -r '.score // 0')
    SCORES="$SCORES $SCORE"
    echo "  Trial $i score: $SCORE" >&2
done

# Calculate statistics
source "$SCRIPT_DIR/lib/stats.sh"
CI_RESULT=$(calculate_confidence_interval "$SCORES")
MEAN=$(get_mean "$SCORES")

# Output in key=value format for easy parsing
echo "scores=$SCORES"
echo "score=$MEAN"
echo "ci=$CI_RESULT"
