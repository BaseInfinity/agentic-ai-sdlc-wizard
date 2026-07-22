#!/bin/bash
# Autocompact Benchmark Harness
# Runs controlled Claude Code sessions at different CLAUDE_AUTOCOMPACT_PCT_OVERRIDE
# thresholds and measures task quality, context preservation (canary facts),
# token cost, and compaction events.
#
# Usage:
#   ./run-benchmark.sh --threshold 75 --task medium --trials 5
#   ./run-benchmark.sh --threshold 60,75,95 --task medium --trials 3
#   ./run-benchmark.sh --dry-run
#
# Prerequisites:
#   - claude CLI (v2.1.85+), authenticated (runs via `claude -p` on the CLI's
#     own session — never touches ANTHROPIC_API_KEY or api.anthropic.com)
#   - jq installed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="$SCRIPT_DIR/results"
TASKS_DIR="$SCRIPT_DIR/tasks"
CANARY_FILE="$SCRIPT_DIR/canary-facts.json"

# Source stats library for CI calculations
source "$REPO_ROOT/tests/e2e/lib/stats.sh"

# ─────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────

THRESHOLDS=""
TASK="medium"
TRIALS=5
DRY_RUN=false
MAX_TURNS=55

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --threshold VALS  Comma-separated thresholds (e.g., 60,75,95). Range: 1-100"
    echo "  --task NAME       Task complexity: short, medium, long (default: medium)"
    echo "  --trials N        Number of trials per condition (default: 5)"
    echo "  --max-turns N     Max turns per session (default: 55)"
    echo "  --dry-run         Validate setup without running Claude sessions"
    echo "  --help            Show this help"
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --threshold) THRESHOLDS="$2"; shift 2 ;;
        --task) TASK="$2"; shift 2 ;;
        --trials) TRIALS="$2"; shift 2 ;;
        --max-turns) MAX_TURNS="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# ─────────────────────────────────────────────────────
# Input validation
# ─────────────────────────────────────────────────────

is_numeric() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

validate_threshold() {
    local val="$1"
    if ! is_numeric "$val"; then
        echo "ERROR: Threshold '$val' is not a number. Must be 1-100."
        exit 1
    fi
    if [ "$val" -lt 1 ] || [ "$val" -gt 100 ]; then
        echo "ERROR: Threshold $val out of range. Must be 1-100."
        exit 1
    fi
}

# Validate thresholds
if [ -n "$THRESHOLDS" ]; then
    IFS=',' read -ra THRESHOLD_ARRAY <<< "$THRESHOLDS"
    for t in "${THRESHOLD_ARRAY[@]}"; do
        validate_threshold "$t"
    done
else
    THRESHOLD_ARRAY=(75)  # Default
fi

# Validate trials
if ! is_numeric "$TRIALS" || [ "$TRIALS" -lt 1 ]; then
    echo "ERROR: Trials must be a positive number, got: $TRIALS"
    exit 1
fi

# Validate task
TASK_FILE="$TASKS_DIR/${TASK}-task.md"
if [ ! -f "$TASK_FILE" ]; then
    echo "ERROR: Task file not found: $TASK_FILE"
    echo "Available tasks: $(ls "$TASKS_DIR"/*.md 2>/dev/null | xargs -I{} basename {} -task.md)"
    exit 1
fi

# ─────────────────────────────────────────────────────
# Dry run — validate setup and exit
# ─────────────────────────────────────────────────────

if $DRY_RUN; then
    echo "=== Autocompact Benchmark — Dry Run ==="
    echo ""
    echo "Validating setup..."
    echo ""

    # Check prerequisites
    CHECKS_PASSED=0
    CHECKS_TOTAL=0

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if command -v claude >/dev/null 2>&1; then
        echo "  [OK] claude CLI found: $(which claude)"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] claude CLI not found"
    fi

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if command -v jq >/dev/null 2>&1; then
        echo "  [OK] jq installed: $(which jq)"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] jq not installed"
    fi

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if command -v bc >/dev/null 2>&1; then
        echo "  [OK] bc installed: $(which bc)"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] bc not installed (needed for arithmetic)"
    fi

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if [ -f "$CANARY_FILE" ]; then
        local_count=$(jq '.facts | length' "$CANARY_FILE" 2>/dev/null || echo "0")
        echo "  [OK] canary-facts.json found ($local_count facts)"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] canary-facts.json not found"
    fi

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if [ -f "$TASK_FILE" ]; then
        echo "  [OK] Task file: $TASK_FILE"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] Task file: $TASK_FILE"
    fi

    CHECKS_TOTAL=$((CHECKS_TOTAL + 1))
    if [ -d "$RESULTS_DIR" ]; then
        echo "  [OK] Results directory: $RESULTS_DIR"
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
    else
        echo "  [MISSING] Results directory: $RESULTS_DIR"
    fi

    echo ""
    echo "Configuration:"
    echo "  Thresholds: ${THRESHOLD_ARRAY[*]}"
    echo "  Task: $TASK"
    echo "  Trials per condition: $TRIALS"
    echo "  Max turns: $MAX_TURNS"
    echo "  Total sessions: $(( ${#THRESHOLD_ARRAY[@]} * TRIALS ))"
    echo ""
    echo "Checks: $CHECKS_PASSED/$CHECKS_TOTAL passed"

    if [ "$CHECKS_PASSED" -lt "$CHECKS_TOTAL" ]; then
        echo ""
        echo "Some prerequisites missing. Fix before running benchmarks."
        exit 1
    fi

    echo ""
    echo "Dry run complete. Ready to benchmark."
    exit 0
fi

# ─────────────────────────────────────────────────────
# Live benchmark execution
# ─────────────────────────────────────────────────────

echo "=== Autocompact Benchmark ==="
echo "Thresholds: ${THRESHOLD_ARRAY[*]}"
echo "Task: $TASK"
echo "Trials: $TRIALS"
echo ""

# Build task prompt with canary facts
build_prompt() {
    local task_content canary_content
    task_content=$(cat "$TASK_FILE")
    canary_content=$(jq -r '.facts[] | "IMPORTANT CONTEXT: \(.fact)"' "$CANARY_FILE" | tr '\n' ' ')

    echo "Before starting the task, please note these important project facts:

$canary_content

Now proceed with the following task:

$task_content"
}

# Build recall prompt
build_recall_prompt() {
    jq -r '"Please answer these questions about the project context I shared earlier:\n" + ([.facts[] | "- " + .recall_prompt] | join("\n"))' "$CANARY_FILE"
}

TASK_PROMPT=$(build_prompt)
RECALL_PROMPT=$(build_recall_prompt)

mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/benchmark-$(date +%Y%m%d-%H%M%S).jsonl"

for threshold in "${THRESHOLD_ARRAY[@]}"; do
    echo "--- Threshold: ${threshold}% ---"

    for trial in $(seq 1 "$TRIALS"); do
        echo "  Trial $trial/$TRIALS..."

        # Set threshold for this session
        export CLAUDE_AUTOCOMPACT_PCT_OVERRIDE="$threshold"

        TRIAL_START=$(date +%s)
        SESSION_OUTPUT=$(mktemp)
        RECALL_OUTPUT=$(mktemp)

        # Phase 1+2: Run task with canary facts (JSON output for machine parsing)
        CLAUDE_EXIT=0
        claude -p "$TASK_PROMPT" --max-turns "$MAX_TURNS" --output-format json > "$SESSION_OUTPUT" 2>&1 || CLAUDE_EXIT=$?

        TRIAL_STATUS="success"
        if [ "$CLAUDE_EXIT" -ne 0 ]; then
            echo "    WARNING: Claude exited with code $CLAUDE_EXIT"
            TRIAL_STATUS="claude_error"
        fi

        # Extract session_id for continuation
        # Note: session_id field location depends on Claude CLI version — verify with:
        #   claude -p "test" --output-format json | jq 'keys'
        SESSION_ID=$(jq -r '.session_id // .sessionId // empty' "$SESSION_OUTPUT" 2>/dev/null || echo "")

        # Phase 3: Resume session for canary recall (if session_id available)
        RECALL_STATUS="skipped"
        if [ -n "$SESSION_ID" ] && [ "$TRIAL_STATUS" = "success" ]; then
            RECALL_EXIT=0
            claude --resume "$SESSION_ID" -p "$RECALL_PROMPT" --output-format json > "$RECALL_OUTPUT" 2>&1 || RECALL_EXIT=$?
            if [ "$RECALL_EXIT" -eq 0 ]; then
                RECALL_STATUS="success"
            else
                echo "    WARNING: Recall phase exited with code $RECALL_EXIT"
                RECALL_STATUS="recall_error"
            fi
        else
            echo "    WARNING: No session_id found — canary recall skipped"
        fi

        TRIAL_END=$(date +%s)
        DURATION=$((TRIAL_END - TRIAL_START))

        # Score task completion
        # Note: Claude CLI JSON output structure varies by version.
        # Common paths: .result, .score, or nested under .messages[-1].content
        # Verify with: claude -p "test" --output-format json | jq 'keys'
        # For now, attempt multiple paths; actual scoring uses evaluate.sh in production
        # -1 = unmeasured (Claude JSON doesn't have a .score field natively)
        # Real scoring requires evaluate.sh integration — future work
        TASK_SCORE=$(jq -r '.score // .result.score // -1' "$SESSION_OUTPUT" 2>/dev/null || echo "-1")

        # Count compaction events
        COMPACTION_EVENTS=$(grep -c 'compact\|compaction\|summariz' "$SESSION_OUTPUT" 2>/dev/null || echo "0")

        # Score canary recall (context-aware: keyword must appear without negation)
        CANARY_RECALLED=0
        if [ -f "$RECALL_OUTPUT" ] && [ -s "$RECALL_OUTPUT" ]; then
            RECALL_TEXT=$(cat "$RECALL_OUTPUT")
            for fact_key in $(jq -r '.facts[].verification_keyword' "$CANARY_FILE" 2>/dev/null); do
                # Match keyword but exclude lines with negation patterns
                if echo "$RECALL_TEXT" | grep -qi "$fact_key" 2>/dev/null; then
                    # Check for negation: "not", "don't", "do not", "no longer" before keyword
                    MATCH_LINE=$(echo "$RECALL_TEXT" | grep -i "$fact_key" | head -1)
                    if echo "$MATCH_LINE" | grep -qiE "not.*$fact_key|don.t.*$fact_key|no longer.*$fact_key|cannot.*$fact_key|unknown|unsure|don.t remember|do not remember" 2>/dev/null; then
                        : # Negated — not recalled
                    else
                        CANARY_RECALLED=$((CANARY_RECALLED + 1))
                    fi
                fi
            done
        fi

        # Write result
        jq -n \
            --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --argjson threshold "$threshold" \
            --arg context_window "200K" \
            --arg task "$TASK" \
            --argjson trial "$trial" \
            --argjson task_score "$TASK_SCORE" \
            --argjson max_score 10 \
            --argjson canary_recall "$CANARY_RECALLED" \
            --argjson canary_total 5 \
            --argjson preservation_rate "$(echo "scale=0; $CANARY_RECALLED * 100 / 5" | bc)" \
            --argjson duration_seconds "$DURATION" \
            --argjson compaction_events "$COMPACTION_EVENTS" \
            --arg session_id "$SESSION_ID" \
            --arg status "$TRIAL_STATUS" \
            --arg recall_status "$RECALL_STATUS" \
            '{
                timestamp: $timestamp,
                threshold: $threshold,
                context_window: $context_window,
                task: $task,
                trial: $trial,
                status: $status,
                recall_status: $recall_status,
                task_score: $task_score,
                max_score: $max_score,
                canary_recall: $canary_recall,
                canary_total: $canary_total,
                preservation_rate: $preservation_rate,
                duration_seconds: $duration_seconds,
                compaction_events: $compaction_events,
                session_id: $session_id
            }' >> "$RESULTS_FILE"

        # Cleanup
        rm -f "$SESSION_OUTPUT" "$RECALL_OUTPUT"

        echo "    Score: $TASK_SCORE/10, Canary: $CANARY_RECALLED/5, Duration: ${DURATION}s"
    done
done

echo ""
echo "Results written to: $RESULTS_FILE"
echo "Run: ./tests/benchmarks/analyze-results.sh $RESULTS_FILE"
