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
# Judge transport: per-criterion `claude --print --output-format json`
# against the authenticated CLI session's own subscription (Max). Never
# touches api.anthropic.com — no pay-per-token API spend, ever, from this
# script. (Unconditional since 2026-07-21; this used to be gated behind
# EVAL_USE_CLI=1 with a curl+API-key default — ROADMAP #228 closed that
# gap for the local-shepherd path, and the curl fallback turned out to be
# unreachable through any automated pipeline — deleted rather than left
# as dead weight.) Both `claude --print` calls run via `env -u
# ANTHROPIC_API_KEY` — the CLI prefers an inherited key over the
# subscription session in non-interactive --print mode, so a shell with
# the key exported would otherwise silently defeat this zero-API claim
# (Codex round 1 P1 API-003).
#
# Requires:
#   - jq
#   - an authenticated `claude` CLI on PATH
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

if ! command -v claude >/dev/null 2>&1; then
    echo "Error: 'claude' CLI not found on PATH (needed for the judge — no API-key fallback exists)"
    exit 1
fi

# Read scenario and output
SCENARIO_CONTENT=$(cat "$SCENARIO_FILE")
OUTPUT_CONTENT=$(head -c 200000 "$OUTPUT_FILE" 2>/dev/null)  # Limit to 200KB

# Run deterministic pre-checks (free, fast, reproducible)
echo "Running deterministic pre-checks..." >&2
DETERMINISTIC_RESULT=$(run_deterministic_checks "$OUTPUT_CONTENT" "$OUTPUT_FILE")
DET_TASK=$(echo "$DETERMINISTIC_RESULT" | jq -r '.task_tracking.points')
DET_CONFIDENCE=$(echo "$DETERMINISTIC_RESULT" | jq -r '.confidence.points')
DET_TDD_RED=$(echo "$DETERMINISTIC_RESULT" | jq -r '.tdd_red.points')
DET_TOTAL=$(echo "$DETERMINISTIC_RESULT" | jq -r '.total')
echo "Deterministic scores: task=$DET_TASK confidence=$DET_CONFIDENCE tdd_red=$DET_TDD_RED total=$DET_TOTAL/4" >&2

# Detect scenario type (standard vs UI) for criterion selection
SCENARIO_TYPE=$(detect_scenario_type "$SCENARIO_CONTENT")
if [ "$SCENARIO_TYPE" = "ui" ]; then
    echo "Detected UI scenario — including design_system criterion" >&2
fi

# Multi-call LLM judge: each subjective criterion gets its own focused API call
# This reduces score variance compared to the monolithic single-call approach.
LLM_CRITERIA=$(get_llm_criteria "$SCENARIO_TYPE")
echo "Scoring criteria: $LLM_CRITERIA" >&2

# Judge call helper — takes a prompt, returns response text, via
# `claude --print --output-format json` against the CLI's own authenticated
# session. This is the only transport (see header) — never touches
# ANTHROPIC_API_KEY or api.anthropic.com.
#
# Runs from a clean tmpdir cwd (`--setting-sources user`) so this repo's
# `.claude/settings.json` hooks (sdlc-prompt-check, etc.) don't fire and
# pollute the criterion prompt with SDLC baseline reminders.
#
# `--tools ""` only blocks built-in tools — MCP tools (e.g. mcp__playwright__*)
# still appear in `system.init.tools` unless we also pass an empty MCP config
# with `--strict-mcp-config`. The criterion prompt embeds untrusted simulation
# output (per `eval-criteria.sh`), so prompt-injection can otherwise reach
# user-configured MCP servers. (Codex round 1 P1 #1.)
#
# `--model claude-opus-4-7` pins the judge model so scoring stays reproducible
# across runs instead of drifting with the CLI's current default. (Codex
# round 1 P1 #2.)
call_criterion_api() {
    local prompt="$1"
    local clean_cwd
    clean_cwd=$(mktemp -d)
    local cli_output raw_text=""
    set +e
    cli_output=$(cd "$clean_cwd" && env -u ANTHROPIC_API_KEY claude --print \
        --output-format json \
        --max-turns 1 \
        --model claude-opus-4-7 \
        --tools "" \
        --setting-sources user \
        --mcp-config '{"mcpServers":{}}' \
        --strict-mcp-config \
        "$prompt" 2>/dev/null)
    set -e
    if [ -n "$cli_output" ]; then
        # Real `claude --print --output-format json` returns an array of
        # system/assistant/result entries; the response text is on the
        # result-typed entry's `.result` field. Tolerate single-object
        # form too so tests can mock with a flat object without invented
        # array wrapping.
        raw_text=$(echo "$cli_output" | jq -r '
            if type == "array" then
                ([.[] | select(.type == "result") | .result] | first // empty)
            else
                (.result // .content[0].text // empty)
            end
        ' 2>/dev/null)
    fi

    # Retry once on failure
    if [ -z "$raw_text" ]; then
        echo "  Retry CLI call for criterion..." >&2
        sleep 3
        set +e
        cli_output=$(cd "$clean_cwd" && env -u ANTHROPIC_API_KEY claude --print \
            --output-format json \
            --max-turns 1 \
            --model claude-opus-4-7 \
            --tools "" \
            --setting-sources user \
            --mcp-config '{"mcpServers":{}}' \
            --strict-mcp-config \
            "$prompt" 2>/dev/null)
        set -e
        if [ -n "$cli_output" ]; then
            raw_text=$(echo "$cli_output" | jq -r '
                if type == "array" then
                    ([.[] | select(.type == "result") | .result] | first // empty)
                else
                    (.result // .content[0].text // empty)
                end
            ' 2>/dev/null)
        fi
    fi

    rm -rf "$clean_cwd"
    echo "$raw_text"
}

# Score each criterion independently (binary YES/NO)
ACCUMULATED_RESULT="{}"
FAILED_CRITERIA=""

for criterion in $LLM_CRITERIA; do
    echo "Scoring $criterion..." >&2
    CRITERION_PROMPT=$(build_criterion_prompt "$criterion" "$SCENARIO_CONTENT" "$OUTPUT_CONTENT")

    RAW_RESULT=$(call_criterion_api "$CRITERION_PROMPT")

    if [ -z "$RAW_RESULT" ]; then
        echo "  Warning: API call failed for $criterion, using 0 score" >&2
        RAW_RESULT='{"met": false, "evidence": "API call failed"}'
        FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
    fi

    # Extract JSON from response
    CRITERION_JSON=$(extract_json "$RAW_RESULT")

    # Validate and fix if needed — retry once on invalid JSON
    if ! is_valid_json "$CRITERION_JSON"; then
        echo "  Warning: Invalid JSON for $criterion, retrying..." >&2
        sleep 2
        RAW_RESULT=$(call_criterion_api "$CRITERION_PROMPT")
        CRITERION_JSON=$(extract_json "$RAW_RESULT")
        if ! is_valid_json "$CRITERION_JSON"; then
            echo "  Warning: Still invalid JSON for $criterion after retry, using 0 score" >&2
            CRITERION_JSON='{"met": false, "evidence": "Invalid JSON response after retry"}'
            FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
        fi
    fi

    # Ensure required fields exist (binary format: met + evidence)
    if ! echo "$CRITERION_JSON" | jq -e 'has("met") and has("evidence")' > /dev/null 2>&1; then
        echo "  Warning: Missing fields for $criterion, using 0 score" >&2
        CRITERION_JSON='{"met": false, "evidence": "Missing required fields"}'
        FAILED_CRITERIA="$FAILED_CRITERIA $criterion"
    fi

    # Convert binary met → points (bash computes score, not LLM)
    MET_VALUE=$(echo "$CRITERION_JSON" | jq -r '.met')
    EVIDENCE=$(echo "$CRITERION_JSON" | jq -r '.evidence')
    if [ "$MET_VALUE" = "true" ]; then
        POINTS=1
    else
        POINTS=0
    fi

    # Build the scored criterion JSON
    CRITERION_JSON=$(jq -n \
        --argjson met "$MET_VALUE" \
        --argjson points "$POINTS" \
        --arg evidence "$EVIDENCE" \
        '{met: $met, points: $points, max: 1, evidence: $evidence}')

    ACCUMULATED_RESULT=$(aggregate_criterion_results "$criterion" "$CRITERION_JSON" "$ACCUMULATED_RESULT")
    echo "  $criterion: $POINTS/1 (met=$MET_VALUE)" >&2
done

# Consistency guard: tdd_green_pass requires tdd_green_ran
ACCUMULATED_RESULT=$(enforce_tdd_consistency "$ACCUMULATED_RESULT")

# Finalize LLM results (adds summary + improvements)
EVAL_RESULT=$(finalize_eval_result "$ACCUMULATED_RESULT")

# Report any API failures and detect total judge outage
LLM_OUTAGE="false"
if [ -n "$FAILED_CRITERIA" ]; then
    echo "Warning: Some criteria had API failures:$FAILED_CRITERIA" >&2
    LLM_CRITERIA_COUNT=$(echo "$LLM_CRITERIA" | wc -w | tr -d ' ')
    FAILED_COUNT=$(echo "$FAILED_CRITERIA" | wc -w | tr -d ' ')
    if [ "$FAILED_COUNT" -ge "$LLM_CRITERIA_COUNT" ] && [ "$LLM_CRITERIA_COUNT" -gt 0 ]; then
        echo "Error: All $LLM_CRITERIA_COUNT LLM criteria failed — judge outage detected" >&2
        LLM_OUTAGE="true"
        PASS="false"
    fi
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

# Check critical criteria (tdd_red is the sole must-pass (self_review demoted, GH #486))
CRITICAL_RESULT=$(check_critical_criteria "$EVAL_RESULT")
CRITICAL_MISS=$(echo "$CRITICAL_RESULT" | jq -r '.critical_miss')
CRITICAL_FAILURES=$(echo "$CRITICAL_RESULT" | jq -c '.critical_failures')
if [ "$CRITICAL_MISS" = "true" ]; then
    echo "CRITICAL MISS: $CRITICAL_FAILURES" >&2
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
# Pass: score >= baseline AND no critical miss
# Warn: score >= min_acceptable but < baseline
# Fail: score < min_acceptable OR critical miss OR LLM outage
if [ "$CRITICAL_MISS" = "true" ]; then
    PASS="false"
    BASELINE_STATUS="fail"
    echo "FAIL: Critical criteria missed ($CRITICAL_FAILURES) — process failure regardless of score" >&2
elif [ "$LLM_OUTAGE" = "true" ]; then
    BASELINE_STATUS="fail"
elif [ "$(echo "$SCORE >= $BASELINE" | bc -l)" -eq 1 ]; then
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
    SDP_MODEL="${SDP_MODEL:-claude-opus-4-7}"
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
        --argjson critical_miss "$CRITICAL_MISS" \
        --argjson critical_failures "$CRITICAL_FAILURES" \
        '. + {
            pass: ($pass == "true"),
            eval_duration: $eval_duration,
            eval_prompt_version: $eval_prompt_version,
            critical_miss: $critical_miss,
            critical_failures: $critical_failures,
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
    # Inject error flag on LLM judge outage
    if [ "$LLM_OUTAGE" = "true" ]; then
        ENRICHED_RESULT=$(echo "$ENRICHED_RESULT" | jq '. + {error: true, error_reason: "All LLM judge criteria failed — API outage detected"}')
    fi

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

    # Report LLM judge outage (PASS already set to false at detection site)
    if [ "$LLM_OUTAGE" = "true" ]; then
        echo -e "${RED}ERROR: LLM judge outage — all criteria API calls failed${NC}"
    fi

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
