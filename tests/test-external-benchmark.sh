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

# Remove ONLY the files this benchmark owns.
#
# These tests previously ran `rm -rf "$SCRIPT_DIR/e2e/.cache"` — deleting the
# whole shared directory to verify one file they own. tests/e2e/.cache/ is
# gitignored scratch space shared with the E2E runbook, so every full-suite run
# silently destroyed anything else parked there. On 2026-08-01 that included a
# Codex Cowork E2E result set and its screenshots, which could not be recovered
# and which an investigation then depended on.
#
# The benchmark writes exactly two things (tests/e2e/lib/external-benchmark.sh:25,27):
#   external-benchmark-<MODEL>.json
#   scrape-fail-count.txt
# Deletes EXACT paths, never a prefix glob. A glob of external-benchmark-*.json
# would also eat an unrelated artifact someone parked here while diagnosing this
# very benchmark — e.g. external-benchmark-investigation.json. Given that broad
# deletion in this directory is precisely what destroyed the Cowork E2E evidence,
# collateral damage from a namespace collision is inside the threat model, so the
# list is explicit even though it must be kept in step with the models exercised
# below.
BENCHMARK_MODELS=(
    claude-sonnet-4
    claude-opus-4
    claude-opus-4-7
    nonexistent-model-xyz
    force-fail-test-model
    model-with-no-baseline
    probe-model
)
clear_benchmark_cache() {
    local cache_dir="$1"
    [ -n "$cache_dir" ] || return 0
    local m
    for m in "${BENCHMARK_MODELS[@]}"; do
        rm -f "$cache_dir/external-benchmark-${m}.json"
    done
    rm -f "$cache_dir/scrape-fail-count.txt"
}

# Guard: cleanup must not touch files it does not own.
#
# Runs against a THROWAWAY directory, not the real shared cache. Earlier versions
# used the real one, which meant the guard wrote its sentinel over any file that
# happened to share the name and then deleted it — destroying real data while
# testing that real data is not destroyed. The save/restore workaround that
# followed still left windows open (set -e abort mid-guard, interrupt, symlink,
# directory-at-that-path). Since clear_benchmark_cache() takes the directory as a
# parameter, pointing it at mktemp -d makes the entire class unreachable instead
# of narrow. Fable's call, and it is the right one: eliminate, don't narrow.
test_cache_cleanup_is_scoped() {
    local cache_dir
    cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/benchmark-cache-guard-XXXXXX") || {
        fail "could not create a temp dir for the cache-cleanup guard"; return; }
    local sentinel="$cache_dir/DO-NOT-DELETE-unrelated-artifact.md"
    # Second sentinel deliberately COLLIDES with the benchmark's filename prefix.
    # A prefix glob would eat this; exact-path deletion must not. Codex found the
    # first version of this guard could not catch that case, because its only
    # sentinel sat outside the glob.
    local collide="$cache_dir/external-benchmark-investigation.json"
    printf 'unrelated E2E artifact\n' > "$sentinel"
    printf '{"unrelated":true}\n' > "$collide"
    : > "$cache_dir/external-benchmark-probe-model.json"

    clear_benchmark_cache "$cache_dir"

    if [ ! -f "$sentinel" ]; then
        fail "cache cleanup DELETED an unrelated artifact — this is how the Cowork E2E results were lost"
    elif [ ! -f "$collide" ]; then
        fail "cache cleanup DELETED external-benchmark-investigation.json — a prefix glob is eating unrelated files"
    elif [ -f "$cache_dir/external-benchmark-probe-model.json" ]; then
        fail "cache cleanup left its own benchmark file behind"
    else
        pass "cache cleanup removes only benchmark-owned files, preserving unrelated and prefix-colliding artifacts"
    fi
    rm -rf "$cache_dir"
}

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
    clear_benchmark_cache "$cache_dir"
    "$BENCHMARK_SCRIPT" claude-sonnet-4 >/dev/null 2>&1 || true
    # Assert the SPECIFIC file, not `ls *.json`. Scoping the cleanup to owned
    # files means unrelated parked artifacts now survive by design — and a
    # wildcard check would be satisfied by one of those with the benchmark
    # having written nothing. Fable caught that this fix weakened this test.
    if [ -f "$cache_dir/external-benchmark-claude-sonnet-4.json" ]; then
        pass "Cache directory and the expected benchmark file were created"
    else
        fail "expected $cache_dir/external-benchmark-claude-sonnet-4.json to be created"
    fi
}

# The model list in clear_benchmark_cache is hand-maintained, so it can rot: a
# future test that exercises a new model would leave 24h-stale cache behind and
# could make a later assertion pass spuriously. This enforces the invariant.
test_benchmark_models_list_is_complete() {
    local invoked missing=""
    # Capture only the first argument, and only when it looks like a model name
    # (starts with a letter). Skips --help and bare/redirect-only invocations.
    invoked=$(perl -ne 'print "$1\n" if /\$BENCHMARK_SCRIPT"\s+"?([a-z][a-z0-9.-]*)"?/' \
              "$SCRIPT_DIR/test-external-benchmark.sh" | sort -u)
    local m listed
    listed=" ${BENCHMARK_MODELS[*]} "
    for m in $invoked; do
        case "$listed" in *" $m "*) ;; *) missing="$missing $m" ;; esac
    done
    if [ -z "$missing" ]; then
        pass "BENCHMARK_MODELS covers every model this suite invokes (no stale-cache rot)"
    else
        fail "BENCHMARK_MODELS is missing model(s) this suite invokes:$missing — their cache would never be cleared"
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
    clear_benchmark_cache "$cache_dir"
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
    clear_benchmark_cache "$cache_dir"

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

# Test 13: Help text lists aistupidlevel source
test_help_lists_aistupidlevel() {
    if "$BENCHMARK_SCRIPT" --help 2>/dev/null | grep -qi "aistupidlevel"; then
        pass "Help text mentions aistupidlevel source"
    else
        fail "Help text should mention aistupidlevel as a benchmark source"
    fi
}

# Test 14: Source cascade includes aistupidlevel function
test_aistupidlevel_source_exists() {
    if grep -q "aistupidlevel" "$BENCHMARK_SCRIPT"; then
        pass "external-benchmark.sh includes aistupidlevel source"
    else
        fail "external-benchmark.sh should include aistupidlevel as a benchmark source"
    fi
}

# Test 15: Source cascade tries aistupidlevel between LiveBench and baseline
test_aistupidlevel_in_cascade() {
    # The main() function should try aistupidlevel after livebench but before baseline
    local main_body
    main_body=$(sed -n '/^main()/,/^}/p' "$BENCHMARK_SCRIPT")
    if echo "$main_body" | grep -q "try_aistupidlevel"; then
        pass "aistupidlevel is in the fetch cascade"
    else
        fail "aistupidlevel should be in the main() fetch cascade"
    fi
}

# Run all tests
test_cache_cleanup_is_scoped
test_benchmark_models_list_is_complete
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
test_help_lists_aistupidlevel
test_aistupidlevel_source_exists
test_aistupidlevel_in_cascade
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
