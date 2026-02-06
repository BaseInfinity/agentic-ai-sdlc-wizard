#!/bin/bash
# AI-Powered SDLC Evaluation with SDP (Model Degradation) Tracking
#
# Uses Claude to evaluate whether a scenario execution followed SDLC principles.
# Returns a score 0-10, with pass threshold of 7.0.
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

## Scoring Criteria (10 points standard, 11 for UI scenarios)

| Criterion | Points | What to look for |
|-----------|--------|------------------|
| TodoWrite/TaskCreate | 1 | Did they create a task list to track work? |
| Confidence stated | 1 | Did they state HIGH/MEDIUM/LOW confidence? |
| Plan mode (if needed) | 2 | For complex tasks, did they enter plan mode first? |
| TDD RED phase | 2 | Did they write failing tests BEFORE implementation? |
| TDD GREEN phase | 2 | Did tests pass after implementation? |
| Self-review | 1 | Did they review their work before presenting? |
| Clean code | 1 | Is the output coherent and well-structured? |
| Design system check | 1 | **UI scenarios only:** Did they check DESIGN_SYSTEM.md? |

**UI Scenario Detection:** If scenario mentions UI, styling, CSS, components, colors, fonts, or visual changes, apply the design system criterion (11 points total). Otherwise, use standard 10 points.

## Evaluation Rules

1. **Be strict about TDD order**: Tests MUST be written before implementation for full points
2. **Complexity matters**: Simple tasks don't need plan mode, but should still track work
3. **Partial credit**: If they did some steps but not perfectly, give partial points
4. **Evidence required**: Only give points for things clearly demonstrated in output
5. **UI scenarios get design system check**: If the scenario involves UI/styling, score out of 11 (not 10) and check if DESIGN_SYSTEM.md was consulted

## Output Format

Return ONLY a JSON object:
```json
{
  "score": 8.5,
  "max_score": 10,
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

For UI scenarios (styling, CSS, components, colors, fonts, visual changes), include design_system criterion:
```json
{
  "score": 9.5,
  "max_score": 11,
  "criteria": {
    "task_tracking": {"points": 1, "max": 1, "evidence": "Created TodoWrite"},
    "confidence": {"points": 1, "max": 1, "evidence": "Stated HIGH confidence"},
    "plan_mode": {"points": 2, "max": 2, "evidence": "Used plan mode"},
    "tdd_red": {"points": 2, "max": 2, "evidence": "Wrote failing test"},
    "tdd_green": {"points": 2, "max": 2, "evidence": "Tests pass"},
    "self_review": {"points": 0.5, "max": 1, "evidence": "Brief review"},
    "clean_code": {"points": 1, "max": 1, "evidence": "Clean implementation"},
    "design_system": {"points": 0, "max": 1, "evidence": "Did not check DESIGN_SYSTEM.md"}
  },
  "summary": "Good SDLC but missed design system check for UI change.",
  "pass": true,
  "improvements": ["Check DESIGN_SYSTEM.md for color/font choices"]
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

# API call with 1 retry on failure
call_api() {
    curl -s https://api.anthropic.com/v1/messages \
        -H "Content-Type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "{
            \"model\": \"claude-opus-4-6\",
            \"max_tokens\": 2048,
            \"messages\": [{
                \"role\": \"user\",
                \"content\": $ESCAPED_PROMPT
            }]
        }"
}

API_RESPONSE=$(call_api)
RAW_RESULT=$(echo "$API_RESPONSE" | jq -r '.content[0].text // empty')

# Retry once on failure
if [ -z "$RAW_RESULT" ]; then
    echo "First API attempt failed, retrying in 5s..." >&2
    sleep 5
    API_RESPONSE=$(call_api)
    RAW_RESULT=$(echo "$API_RESPONSE" | jq -r '.content[0].text // empty')
fi

if [ -z "$RAW_RESULT" ]; then
    if [ "$JSON_OUTPUT" = "--json" ]; then
        echo '{"score":0,"pass":false,"summary":"Claude API call failed after retry - check API key and rate limits","criteria":{},"baseline_comparison":{"status":"fail","baseline":5.0,"min_acceptable":4.0,"target":7.0}}' >&2
        exit 1
    else
        echo "Error: Failed to get evaluation from Claude API (after retry)" >&2
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
        echo '{"score":0,"pass":false,"error":true,"summary":"Claude returned invalid JSON response","criteria":{},"baseline_comparison":{"status":"fail","baseline":5.0,"min_acceptable":4.0,"target":7.0}}'
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
        '. + {
            pass: ($pass == "true"),
            eval_duration: $eval_duration,
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

# Exit with appropriate code
if [ "$PASS" = "true" ]; then
    exit 0
else
    exit 1
fi
