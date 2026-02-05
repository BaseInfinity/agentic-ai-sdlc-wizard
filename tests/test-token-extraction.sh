#!/bin/bash
# Tests for token extraction logic used in CI workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

PASSED=0
FAILED=0

pass() {
  echo "  ✓ $1"
  PASSED=$((PASSED + 1))
}

fail() {
  echo "  ✗ $1"
  echo "    Expected: $2"
  echo "    Got: $3"
  FAILED=$((FAILED + 1))
}

echo "Testing token extraction logic..."
echo ""

# ============================================
# Test 1: Standard .usage format
# ============================================
echo "Test 1: Extract tokens from .usage format"

cat > "$TEMP_DIR/output1.json" << 'EOF'
{
  "result": "success",
  "usage": {
    "input_tokens": 12345,
    "output_tokens": 8901
  }
}
EOF

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/output1.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/output1.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "12345" ] && [ "$OUTPUT_TOKENS" = "8901" ]; then
  pass "Standard .usage format"
else
  fail "Standard .usage format" "input=12345, output=8901" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Test 2: Alternative .token_usage format
# ============================================
echo "Test 2: Extract tokens from .token_usage format"

cat > "$TEMP_DIR/output2.json" << 'EOF'
{
  "result": "success",
  "token_usage": {
    "input_tokens": 5000,
    "output_tokens": 3000
  }
}
EOF

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/output2.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/output2.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "5000" ] && [ "$OUTPUT_TOKENS" = "3000" ]; then
  pass "Alternative .token_usage format"
else
  fail "Alternative .token_usage format" "input=5000, output=3000" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Test 3: Top-level tokens format
# ============================================
echo "Test 3: Extract tokens from top-level format"

cat > "$TEMP_DIR/output3.json" << 'EOF'
{
  "result": "success",
  "input_tokens": 1000,
  "output_tokens": 500
}
EOF

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/output3.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/output3.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "1000" ] && [ "$OUTPUT_TOKENS" = "500" ]; then
  pass "Top-level tokens format"
else
  fail "Top-level tokens format" "input=1000, output=500" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Test 4: Fallback to N/A when tokens not present
# ============================================
echo "Test 4: Fallback to N/A when tokens not present"

cat > "$TEMP_DIR/output4.json" << 'EOF'
{
  "result": "success",
  "messages": ["hello"]
}
EOF

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/output4.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/output4.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "N/A" ] && [ "$OUTPUT_TOKENS" = "N/A" ]; then
  pass "Fallback to N/A when tokens not present"
else
  fail "Fallback to N/A when tokens not present" "input=N/A, output=N/A" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Test 5: Cost calculation math
# ============================================
echo "Test 5: Cost calculation math"

# Using same pricing as ci.yml: ~$3/1M input, ~$15/1M output
INPUT_TOKENS=12345
OUTPUT_TOKENS=8901
EXPECTED_COST="0.1706"  # (12345 * 0.000003) + (8901 * 0.000015) = 0.037035 + 0.133515 = 0.17055 ≈ 0.1706

COST=$(echo "scale=4; ($INPUT_TOKENS * 0.000003) + ($OUTPUT_TOKENS * 0.000015)" | bc -l)
# Compare first 4 digits
COST_TRIMMED=$(printf "%.4f" "$COST")

if [ "$COST_TRIMMED" = "$EXPECTED_COST" ]; then
  pass "Cost calculation math"
else
  fail "Cost calculation math" "$EXPECTED_COST" "$COST_TRIMMED"
fi

# ============================================
# Test 6: Total tokens calculation
# ============================================
echo "Test 6: Total tokens calculation"

INPUT_TOKENS=12345
OUTPUT_TOKENS=8901
EXPECTED_TOTAL=21246

TOTAL_TOKENS=$(echo "$INPUT_TOKENS + $OUTPUT_TOKENS" | bc -l | cut -d. -f1)

if [ "$TOTAL_TOKENS" = "$EXPECTED_TOTAL" ]; then
  pass "Total tokens calculation"
else
  fail "Total tokens calculation" "$EXPECTED_TOTAL" "$TOTAL_TOKENS"
fi

# ============================================
# Test 7: Tokens per point calculation
# ============================================
echo "Test 7: Tokens per point calculation"

TOTAL_TOKENS=21246
SCORE=10
EXPECTED_TPP=2124

TOKENS_PER_POINT=$(echo "scale=0; $TOTAL_TOKENS / $SCORE" | bc -l 2>/dev/null || echo "N/A")

if [ "$TOKENS_PER_POINT" = "$EXPECTED_TPP" ]; then
  pass "Tokens per point calculation"
else
  fail "Tokens per point calculation" "$EXPECTED_TPP" "$TOKENS_PER_POINT"
fi

# ============================================
# Test 8: Tokens per point with zero score
# ============================================
echo "Test 8: Tokens per point with zero score handles gracefully"

TOTAL_TOKENS=21246
SCORE=0

# When score is 0, we should get N/A (avoid division by zero)
if [ "$SCORE" = "0" ] || [ "$SCORE" = "" ]; then
  TOKENS_PER_POINT="N/A"
else
  TOKENS_PER_POINT=$(echo "scale=0; $TOTAL_TOKENS / $SCORE" | bc -l 2>/dev/null || echo "N/A")
fi

if [ "$TOKENS_PER_POINT" = "N/A" ]; then
  pass "Tokens per point with zero score"
else
  fail "Tokens per point with zero score" "N/A" "$TOKENS_PER_POINT"
fi

# ============================================
# Test 9: Handle invalid JSON gracefully
# ============================================
echo "Test 9: Handle invalid JSON gracefully"

echo "not valid json" > "$TEMP_DIR/output9.json"

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/output9.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/output9.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "N/A" ] && [ "$OUTPUT_TOKENS" = "N/A" ]; then
  pass "Handle invalid JSON gracefully"
else
  fail "Handle invalid JSON gracefully" "input=N/A, output=N/A" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Test 10: Handle missing file gracefully
# ============================================
echo "Test 10: Handle missing file gracefully"

INPUT_TOKENS=$(jq -r '.usage.input_tokens // .token_usage.input_tokens // .input_tokens // "N/A"' "$TEMP_DIR/nonexistent.json" 2>/dev/null || echo "N/A")
OUTPUT_TOKENS=$(jq -r '.usage.output_tokens // .token_usage.output_tokens // .output_tokens // "N/A"' "$TEMP_DIR/nonexistent.json" 2>/dev/null || echo "N/A")

if [ "$INPUT_TOKENS" = "N/A" ] && [ "$OUTPUT_TOKENS" = "N/A" ]; then
  pass "Handle missing file gracefully"
else
  fail "Handle missing file gracefully" "input=N/A, output=N/A" "input=$INPUT_TOKENS, output=$OUTPUT_TOKENS"
fi

# ============================================
# Summary
# ============================================
echo ""
echo "========================================"
echo "Token Extraction Tests: $PASSED passed, $FAILED failed"
echo "========================================"

if [ $FAILED -gt 0 ]; then
  exit 1
fi

echo "All token extraction tests passed!"
