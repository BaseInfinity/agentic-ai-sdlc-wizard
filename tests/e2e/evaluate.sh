#!/bin/bash
# AI-Powered SDLC Evaluation
#
# Uses Claude to evaluate whether a scenario execution followed SDLC principles.
# Returns a score 0-10, with pass threshold of 7.0.
#
# Usage:
#   ./evaluate.sh <scenario_file> <output_file> [--json]
#
# Requires:
#   - ANTHROPIC_API_KEY environment variable
#   - jq for JSON parsing
#   - curl for API calls

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/json-utils.sh"

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

PASS_THRESHOLD=7.0

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
OUTPUT_CONTENT=$(head -c 50000 "$OUTPUT_FILE" 2>/dev/null)  # Limit to 50KB

# Build evaluation prompt
EVAL_PROMPT=$(cat << 'PROMPT_END'
You are an SDLC compliance evaluator. Analyze the execution output and score it against the SDLC criteria.

## Scoring Criteria (10 points total)

| Criterion | Points | What to look for |
|-----------|--------|------------------|
| TodoWrite/TaskCreate | 1 | Did they create a task list to track work? |
| Confidence stated | 1 | Did they state HIGH/MEDIUM/LOW confidence? |
| Plan mode (if needed) | 2 | For complex tasks, did they enter plan mode first? |
| TDD RED phase | 2 | Did they write failing tests BEFORE implementation? |
| TDD GREEN phase | 2 | Did tests pass after implementation? |
| Self-review | 1 | Did they review their work before presenting? |
| Clean code | 1 | Is the output coherent and well-structured? |

## Evaluation Rules

1. **Be strict about TDD order**: Tests MUST be written before implementation for full points
2. **Complexity matters**: Simple tasks don't need plan mode, but should still track work
3. **Partial credit**: If they did some steps but not perfectly, give partial points
4. **Evidence required**: Only give points for things clearly demonstrated in output

## Output Format

Return ONLY a JSON object:
```json
{
  "score": 8.5,
  "criteria": {
    "task_tracking": {"points": 1, "max": 1, "evidence": "Created TodoWrite with 4 tasks"},
    "confidence": {"points": 1, "max": 1, "evidence": "Stated MEDIUM confidence"},
    "plan_mode": {"points": 2, "max": 2, "evidence": "Entered plan mode, created plan file"},
    "tdd_red": {"points": 2, "max": 2, "evidence": "Wrote test first, showed it failing"},
    "tdd_green": {"points": 1.5, "max": 2, "evidence": "Tests pass but ran late"},
    "self_review": {"points": 0.5, "max": 1, "evidence": "Brief mention of review"},
    "clean_code": {"points": 0.5, "max": 1, "evidence": "Some rough spots"}
  },
  "summary": "Good SDLC compliance. TDD followed but could be cleaner.",
  "pass": true,
  "improvements": ["Run tests immediately after writing", "More thorough self-review"]
}
```

IMPORTANT: Return ONLY the JSON object, no markdown formatting, no explanation before or after.
PROMPT_END
)

# Build the full prompt with scenario and output
FULL_PROMPT="$EVAL_PROMPT

---

## Scenario Being Evaluated

$SCENARIO_CONTENT

---

## Execution Output to Evaluate

$OUTPUT_CONTENT

---

Now evaluate the execution output against the scenario requirements. Return only JSON."

# Make API call to Claude
# Escape the prompt for JSON
ESCAPED_PROMPT=$(echo "$FULL_PROMPT" | jq -Rs .)

API_RESPONSE=$(curl -s https://api.anthropic.com/v1/messages \
    -H "Content-Type: application/json" \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -d "{
        \"model\": \"claude-sonnet-4-20250514\",
        \"max_tokens\": 2048,
        \"messages\": [{
            \"role\": \"user\",
            \"content\": $ESCAPED_PROMPT
        }]
    }")

# Extract the response text
RAW_RESULT=$(echo "$API_RESPONSE" | jq -r '.content[0].text // empty')

if [ -z "$RAW_RESULT" ]; then
    if [ "$JSON_OUTPUT" = "--json" ]; then
        # Output valid JSON so CI can parse it (errors go to stderr)
        echo '{"score":0,"pass":false,"summary":"Claude API call failed - check API key and rate limits","criteria":{},"baseline_comparison":{"status":"fail","baseline":5.0,"min_acceptable":4.0,"target":7.0}}'
        exit 0  # Don't fail - let CI handle the zero score
    else
        echo "Error: Failed to get evaluation from Claude API" >&2
        echo "API Response: $API_RESPONSE" >&2
        exit 1
    fi
fi

# Clean Claude's response - extract JSON even if wrapped in markdown or has preamble
# See lib/json-utils.sh for implementation details
EVAL_RESULT=$(extract_json "$RAW_RESULT")

# Validate we got valid JSON
if ! is_valid_json "$EVAL_RESULT"; then
    # Debug: log what Claude actually returned
    echo "Warning: Claude returned non-JSON or malformed response" >&2
    echo "Raw response (first 500 chars): ${RAW_RESULT:0:500}" >&2

    if [ "$JSON_OUTPUT" = "--json" ]; then
        echo '{"score":0,"pass":false,"summary":"Claude returned invalid JSON response","criteria":{},"baseline_comparison":{"status":"fail","baseline":5.0,"min_acceptable":4.0,"target":7.0}}'
        exit 0
    else
        echo "Error: Could not extract valid JSON from Claude's response" >&2
        exit 1
    fi
fi

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

# Output results
if [ "$JSON_OUTPUT" = "--json" ]; then
    # Enrich the result with baseline comparison
    ENRICHED_RESULT=$(echo "$EVAL_RESULT" | jq \
        --arg pass "$PASS" \
        --arg baseline_status "$BASELINE_STATUS" \
        --argjson baseline "$BASELINE" \
        --argjson min_acceptable "$MIN_ACCEPTABLE" \
        --argjson target "$TARGET" \
        '. + {pass: ($pass == "true"), baseline_comparison: {status: $baseline_status, baseline: $baseline, min_acceptable: $min_acceptable, target: $target}}')
    echo "$ENRICHED_RESULT"
else
    echo ""
    echo "=========================================="
    echo "  SDLC Evaluation Results"
    echo "=========================================="
    echo ""
    echo "Scenario: $(basename "$SCENARIO_FILE" .md)"
    echo ""

    # Show criteria breakdown
    echo "--- Criteria Breakdown ---"
    echo "$EVAL_RESULT" | jq -r '.criteria | to_entries[] | "\(.key): \(.value.points)/\(.value.max) - \(.value.evidence)"' 2>/dev/null || echo "Could not parse criteria"
    echo ""

    # Show score with baseline comparison
    echo "--- Final Score ---"
    echo -e "Score: ${BLUE}$SCORE${NC} / 10"
    echo "Baseline: $BASELINE | Min: $MIN_ACCEPTABLE | Target: $TARGET"
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

# Exit with appropriate code
if [ "$PASS" = "true" ]; then
    exit 0
else
    exit 1
fi
