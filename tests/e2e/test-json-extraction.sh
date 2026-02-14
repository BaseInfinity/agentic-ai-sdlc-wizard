#!/bin/bash
# Test JSON extraction logic from lib/json-utils.sh
#
# Tests the 7 scenarios from the V1.2 plan:
# 1. Raw JSON
# 2. Markdown code fence
# 3. Preamble text
# 4. Multiline raw JSON
# 5. Markdown + multiline JSON
# 6. Preamble + multiline + trailing text
# 7. Full nested criteria structure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/json-utils.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

PASSED=0
FAILED=0

# Function to test JSON extraction
test_extraction() {
    local test_name="$1"
    local input="$2"
    local expected_score="$3"

    # Use the shared extraction function from lib/json-utils.sh
    EVAL_RESULT=$(extract_json "$input")

    # Try to extract score
    if is_valid_json "$EVAL_RESULT"; then
        SCORE=$(echo "$EVAL_RESULT" | jq -r '.score // 0')
        if [ "$SCORE" = "$expected_score" ]; then
            echo -e "${GREEN}✓${NC} $test_name (score: $SCORE)"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}✗${NC} $test_name - expected score $expected_score, got $SCORE"
            FAILED=$((FAILED + 1))
        fi
    else
        echo -e "${RED}✗${NC} $test_name - failed to extract valid JSON"
        echo "  Input: ${input:0:100}..."
        echo "  Extracted: ${EVAL_RESULT:0:100}..."
        FAILED=$((FAILED + 1))
    fi
}

echo "Testing JSON extraction logic..."
echo ""

# Test 1: Raw JSON
test_extraction "1. Raw JSON" \
    '{"score": 4.5, "summary": "Good", "pass": true}' \
    "4.5"

# Test 2: Markdown code fence
test_extraction "2. Markdown code fence" \
    '```json
{"score": 4.5, "summary": "Good", "pass": true}
```' \
    "4.5"

# Test 3: Preamble text
test_extraction "3. Preamble text" \
    "Here's my evaluation:
{\"score\": 4.5, \"summary\": \"Good\", \"pass\": true}" \
    "4.5"

# Test 4: Multiline raw JSON
test_extraction "4. Multiline raw JSON" \
    '{
  "score": 4.5,
  "summary": "Good",
  "pass": true
}' \
    "4.5"

# Test 5: Markdown + multiline JSON
test_extraction "5. Markdown + multiline JSON" \
    '```json
{
  "score": 4.5,
  "summary": "Good",
  "pass": true
}
```' \
    "4.5"

# Test 6: Preamble + multiline + trailing text
test_extraction "6. Preamble + multiline + trailing text" \
    "Here's my evaluation based on the criteria:

{
  \"score\": 4.5,
  \"summary\": \"Good\",
  \"pass\": true
}

Let me know if you need more details." \
    "4.5"

# Test 7: Full nested criteria structure
test_extraction "7. Full nested criteria structure" \
    '{
  "score": 8.5,
  "criteria": {
    "task_tracking": {"points": 1, "max": 1, "evidence": "Created TodoWrite"},
    "confidence": {"points": 1, "max": 1, "evidence": "Stated HIGH"},
    "plan_mode_outline": {"points": 1, "max": 1, "evidence": "Outlined steps"},
    "plan_mode_tool": {"points": 1, "max": 1, "evidence": "Entered plan mode"},
    "tdd_red": {"points": 2, "max": 2, "evidence": "Wrote test first"},
    "tdd_green_ran": {"points": 1, "max": 1, "evidence": "Tests ran"},
    "tdd_green_pass": {"points": 1, "max": 1, "evidence": "Tests pass"},
    "self_review": {"points": 0.5, "max": 1, "evidence": "Brief review"},
    "clean_code": {"points": 0.5, "max": 1, "evidence": "Clean"}
  },
  "summary": "Good SDLC compliance",
  "pass": true,
  "improvements": ["Run tests sooner"]
}' \
    "8.5"

echo ""
echo "=========================================="
echo "Results: $PASSED passed, $FAILED failed"
echo "=========================================="

if [ $FAILED -gt 0 ]; then
    exit 1
fi
