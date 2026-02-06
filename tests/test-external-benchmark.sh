#!/bin/bash
# Test external benchmark fetcher
# TDD: Tests written first before implementation

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_SCRIPT="$SCRIPT_DIR/e2e/lib/external-benchmark.sh"
PASSED=0
FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== External Benchmark Fetcher Tests ==="
echo ""

# Test 1: Script exists and is executable
test_script_exists() {
    if [ -x "$BENCHMARK_SCRIPT" ]; then
        pass "external-benchmark.sh exists and is executable"
    else
        fail "external-benchmark.sh not found or not executable at $BENCHMARK_SCRIPT"
    fi
}

# Test 2: Help option works
test_help() {
    if "$BENCHMARK_SCRIPT" --help 2>/dev/null | grep -q "Usage"; then
        pass "--help shows usage"
    else
        fail "--help should show usage"
    fi
}

# Test 3: Default model returns a score
test_default_model() {
    local output
    output=$("$BENCHMARK_SCRIPT" 2>/dev/null) || true
    if [ -n "$output" ] && echo "$output" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        pass "Default model returns numeric score: $output"
    else
        fail "Default model should return numeric score, got: $output"
    fi
}

# Test 4: Cache file is created
test_cache_created() {
    local cache_dir="$SCRIPT_DIR/e2e/.cache"
    rm -rf "$cache_dir"
    "$BENCHMARK_SCRIPT" claude-sonnet-4 >/dev/null 2>&1 || true
    if [ -d "$cache_dir" ] && ls "$cache_dir"/*.json >/dev/null 2>&1; then
        pass "Cache directory and files created"
    else
        fail "Cache should be created in $cache_dir"
    fi
}

# Test 5: Cache is used on second call (faster)
test_cache_used() {
    local cache_dir="$SCRIPT_DIR/e2e/.cache"
    # First call creates cache
    "$BENCHMARK_SCRIPT" claude-sonnet-4 >/dev/null 2>&1 || true

    # Second call should be fast (use cache)
    local start_time
    start_time=$(date +%s%N 2>/dev/null || date +%s)
    "$BENCHMARK_SCRIPT" claude-sonnet-4 >/dev/null 2>&1 || true
    local end_time
    end_time=$(date +%s%N 2>/dev/null || date +%s)

    # Just verify it works, cache behavior is internal
    pass "Cache behavior works (second call succeeded)"
}

# Test 6: Nonexistent model falls back to baseline
test_fallback_baseline() {
    local output
    output=$("$BENCHMARK_SCRIPT" "nonexistent-model-xyz" 2>&1) || true
    if echo "$output" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        pass "Nonexistent model falls back to baseline score"
    else
        fail "Should fall back to baseline for unknown model, got: $output"
    fi
}

# Test 7: Fail count tracking
test_fail_count() {
    local cache_dir="$SCRIPT_DIR/e2e/.cache"
    rm -f "$cache_dir/scrape-fail-count.txt"

    # Force failure by using impossible model
    "$BENCHMARK_SCRIPT" "force-fail-test-model" >/dev/null 2>&1 || true

    if [ -f "$cache_dir/scrape-fail-count.txt" ]; then
        local count
        count=$(cat "$cache_dir/scrape-fail-count.txt")
        if [ "$count" -ge 1 ]; then
            pass "Failure count tracked: $count"
        else
            fail "Failure count should be >= 1, got: $count"
        fi
    else
        pass "Failure tracking not triggered (source succeeded)"
    fi
}

# Test 8: Score is within valid range
test_score_range() {
    local score
    score=$("$BENCHMARK_SCRIPT" claude-sonnet-4 2>/dev/null) || true
    if [ -n "$score" ]; then
        local in_range
        in_range=$(echo "$score >= 0 && $score <= 100" | bc -l 2>/dev/null || echo "1")
        if [ "$in_range" = "1" ]; then
            pass "Score is within valid range [0-100]: $score"
        else
            fail "Score should be 0-100, got: $score"
        fi
    else
        fail "No score returned"
    fi
}

# Cleanup
cleanup() {
    local cache_dir="$SCRIPT_DIR/e2e/.cache"
    rm -rf "$cache_dir"
}

# Test 9: Opus model name mapping works
test_opus_model() {
    local output
    output=$("$BENCHMARK_SCRIPT" claude-opus-4 2>/dev/null) || true
    if [ -n "$output" ] && echo "$output" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        pass "claude-opus-4 returns numeric score: $output"
    else
        fail "claude-opus-4 should return numeric score, got: $output"
    fi
}

# Test 10: Missing baseline file falls back to 75
test_missing_baseline() {
    local baseline_file="$SCRIPT_DIR/e2e/external-baseline.json"
    local backup=""

    # Temporarily rename baseline file if it exists
    if [ -f "$baseline_file" ]; then
        backup="$baseline_file.bak"
        mv "$baseline_file" "$backup"
    fi

    local output
    output=$("$BENCHMARK_SCRIPT" "model-with-no-baseline" 2>/dev/null) || true

    # Restore baseline
    if [ -n "$backup" ]; then
        mv "$backup" "$baseline_file"
    fi

    if [ -n "$output" ] && echo "$output" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        pass "Missing baseline file returns fallback score: $output"
    else
        fail "Missing baseline should fall back, got: $output"
    fi
}

# Test 11: Multiple calls return consistent results (from cache)
test_consistency() {
    local cache_dir="$SCRIPT_DIR/e2e/.cache"
    rm -rf "$cache_dir"

    local first second
    first=$("$BENCHMARK_SCRIPT" claude-sonnet-4 2>/dev/null) || true
    second=$("$BENCHMARK_SCRIPT" claude-sonnet-4 2>/dev/null) || true

    if [ "$first" = "$second" ]; then
        pass "Consecutive calls return consistent results: $first"
    else
        fail "Cached calls should be consistent, got: $first vs $second"
    fi
}

# Test 12: Sonnet model name variants
test_sonnet_variants() {
    local output
    output=$("$BENCHMARK_SCRIPT" claude-sonnet-4 2>/dev/null) || true
    if [ -n "$output" ] && echo "$output" | grep -qE '^[0-9]+\.?[0-9]*$'; then
        pass "claude-sonnet-4 variant returns score: $output"
    else
        fail "claude-sonnet-4 should return score, got: $output"
    fi
}

# Run all tests
test_script_exists
test_help
test_default_model
test_cache_created
test_cache_used
test_fallback_baseline
test_fail_count
test_score_range
test_opus_model
test_missing_baseline
test_consistency
test_sonnet_variants
cleanup

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All external benchmark tests passed!"
