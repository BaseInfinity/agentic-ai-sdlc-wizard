#!/bin/bash
# Score Analytics — reads score-history.jsonl and outputs insights
#
# Usage:
#   ./score-analytics.sh                              # console output
#   ./score-analytics.sh --report                     # markdown for SCORE_TRENDS.md
#   ./score-analytics.sh --history path/to/file.jsonl  # custom history file
#
# Reads score-history.jsonl (JSON-lines) with format:
#   { timestamp, scenario, score, max_score, criteria: { name: { points, max } } }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HISTORY_FILE="$SCRIPT_DIR/score-history.jsonl"
REPORT_MODE=false

# Parse arguments
while [ $# -gt 0 ]; do
    case "$1" in
        --history)
            HISTORY_FILE="$2"
            shift 2
            ;;
        --report)
            REPORT_MODE=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

# Check jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# Read valid JSON lines (skip malformed)
read_valid_entries() {
    local file="$1"
    while IFS= read -r line; do
        if echo "$line" | jq -e '.' > /dev/null 2>&1; then
            echo "$line"
        fi
    done < "$file"
}

# Count valid entries
VALID_ENTRIES=$(read_valid_entries "$HISTORY_FILE" | wc -l | tr -d ' ')

# Handle empty/no data
if [ "$VALID_ENTRIES" -eq 0 ]; then
    if [ "$REPORT_MODE" = true ]; then
        echo "# Score Trends"
        echo ""
        echo "_Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
        echo ""
        echo "No history data available. Run E2E evaluations to populate score-history.jsonl."
        echo ""
        echo "0 entries in history."
    else
        echo "No history data available (0 entries)."
        echo "Run E2E evaluations to populate $HISTORY_FILE"
    fi
    exit 0
fi

# Extract all scores into a temp file
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

read_valid_entries "$HISTORY_FILE" > "$WORK_DIR/valid.jsonl"

# --- Compute overall stats ---
SCORES=$(jq -r '.score' "$WORK_DIR/valid.jsonl")
TOTAL_SUM=$(echo "$SCORES" | awk '{s+=$1} END {printf "%.1f", s}')
OVERALL_AVG=$(echo "$SCORES" | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n; else print "0"}')
SCORE_MIN=$(echo "$SCORES" | sort -n | head -1)
SCORE_MAX=$(echo "$SCORES" | sort -n | tail -1)
SCORE_COUNT=$(echo "$SCORES" | wc -l | tr -d ' ')

# Median
MEDIAN=$(echo "$SCORES" | sort -n | awk '{a[NR]=$1} END {if(NR%2==1) printf "%.1f", a[(NR+1)/2]; else printf "%.1f", (a[NR/2]+a[NR/2+1])/2}')

# --- Trend: compare last 5 vs previous entries ---
TREND_TEXT="stable"
if [ "$SCORE_COUNT" -ge 5 ]; then
    RECENT_AVG=$(echo "$SCORES" | tail -5 | awk '{s+=$1; n++} END {printf "%.2f", s/n}')
    if [ "$SCORE_COUNT" -ge 10 ]; then
        OLDER_AVG=$(echo "$SCORES" | head -$((SCORE_COUNT - 5)) | awk '{s+=$1; n++} END {printf "%.2f", s/n}')
    else
        OLDER_AVG=$(echo "$SCORES" | head -$((SCORE_COUNT - 5)) | awk '{s+=$1; n++} END {if(n>0) printf "%.2f", s/n; else printf "%.2f", 0}')
    fi

    DIFF=$(echo "$RECENT_AVG - $OLDER_AVG" | bc -l 2>/dev/null || echo "0")
    if [ "$(echo "$DIFF > 0.3" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        TREND_TEXT="improving (+$(printf '%.1f' "$DIFF"))"
    elif [ "$(echo "$DIFF < -0.3" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        TREND_TEXT="declining ($(printf '%.1f' "$DIFF"))"
    else
        TREND_TEXT="stable ($(printf '%.1f' "$DIFF"))"
    fi
fi

# --- Per-criterion averages ---
# Extract all criterion names
CRITERIA_NAMES=$(jq -r '.criteria | keys[]' "$WORK_DIR/valid.jsonl" 2>/dev/null | sort -u)

# Build criterion stats
CRITERION_STATS=""
WEAKEST_NAME=""
WEAKEST_PCT=100
for crit in $CRITERIA_NAMES; do
    CRIT_SUM=$(jq -r ".criteria.\"$crit\".points // 0" "$WORK_DIR/valid.jsonl" | awk '{s+=$1} END {printf "%.1f", s}')
    CRIT_MAX_SUM=$(jq -r ".criteria.\"$crit\".max // 0" "$WORK_DIR/valid.jsonl" | awk '{s+=$1} END {printf "%.1f", s}')
    if [ "$(echo "$CRIT_MAX_SUM > 0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        CRIT_AVG=$(echo "scale=2; $CRIT_SUM / $SCORE_COUNT" | bc -l)
        CRIT_MAX=$(jq -r ".criteria.\"$crit\".max // 0" "$WORK_DIR/valid.jsonl" | head -1)
        CRIT_PCT=$(echo "scale=0; $CRIT_SUM * 100 / $CRIT_MAX_SUM" | bc -l)
        CRITERION_STATS="$CRITERION_STATS|$crit|$CRIT_AVG|$CRIT_MAX|${CRIT_PCT}%|
"
        if [ "$CRIT_PCT" -lt "$WEAKEST_PCT" ]; then
            WEAKEST_PCT="$CRIT_PCT"
            WEAKEST_NAME="$crit"
        fi
    fi
done

# --- Per-scenario averages ---
SCENARIO_NAMES=$(jq -r '.scenario' "$WORK_DIR/valid.jsonl" | sort -u)
SCENARIO_STATS=""
for scenario in $SCENARIO_NAMES; do
    SCEN_AVG=$(jq -r "select(.scenario == \"$scenario\") | .score" "$WORK_DIR/valid.jsonl" | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n; else print "N/A"}')
    SCEN_COUNT=$(jq -r "select(.scenario == \"$scenario\") | .score" "$WORK_DIR/valid.jsonl" | wc -l | tr -d ' ')
    SCENARIO_STATS="$SCENARIO_STATS|$scenario|$SCEN_AVG|$SCEN_COUNT|
"
done

# --- Score distribution (simple histogram) ---
DIST_LOW=$(echo "$SCORES" | awk '$1 < 5 {n++} END {print n+0}')
DIST_MED=$(echo "$SCORES" | awk '$1 >= 5 && $1 < 7 {n++} END {print n+0}')
DIST_HIGH=$(echo "$SCORES" | awk '$1 >= 7 && $1 < 9 {n++} END {print n+0}')
DIST_EXCELLENT=$(echo "$SCORES" | awk '$1 >= 9 {n++} END {print n+0}')

# --- Spark chart (last 20 scores) ---
spark_char() {
    local val="$1"
    local int_val
    int_val=$(printf "%.0f" "$val")
    case "$int_val" in
        0|1|2) echo -n "_" ;;
        3|4)   echo -n "." ;;
        5|6)   echo -n "-" ;;
        7|8)   echo -n "=" ;;
        9|10)  echo -n "#" ;;
        *)     echo -n "?" ;;
    esac
}

SPARK=""
LAST_SCORES=$(echo "$SCORES" | tail -20)
for s in $LAST_SCORES; do
    SPARK="${SPARK}$(spark_char "$s")"
done

# ============================================================
# OUTPUT
# ============================================================

if [ "$REPORT_MODE" = true ]; then
    # --- Markdown report for SCORE_TRENDS.md ---
    echo "# Score Trends"
    echo ""
    echo "_Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)_"
    echo ""
    echo "## Overview"
    echo ""
    echo "| Metric | Value |"
    echo "|--------|-------|"
    echo "| Total evaluations | $SCORE_COUNT |"
    echo "| Overall average | $OVERALL_AVG / 10 |"
    echo "| Median | $MEDIAN |"
    echo "| Range | $SCORE_MIN - $SCORE_MAX |"
    echo "| Trend direction | $TREND_TEXT |"
    echo ""
    if [ -n "$SPARK" ]; then
        echo "## Score Evolution (last 20)"
        echo ""
        echo "\`\`\`"
        echo "$SPARK"
        echo "\`\`\`"
        echo "_Legend: \`_\`=0-2  \`.\`=3-4  \`-\`=5-6  \`=\`=7-8  \`#\`=9-10_"
        echo ""
    fi
    echo "## Score Distribution"
    echo ""
    echo "| Range | Count | Bar |"
    echo "|-------|-------|-----|"
    echo "| 0-4 (Low) | $DIST_LOW | $(printf '%*s' "$DIST_LOW" | tr ' ' '#') |"
    echo "| 5-6 (Medium) | $DIST_MED | $(printf '%*s' "$DIST_MED" | tr ' ' '#') |"
    echo "| 7-8 (High) | $DIST_HIGH | $(printf '%*s' "$DIST_HIGH" | tr ' ' '#') |"
    echo "| 9-10 (Excellent) | $DIST_EXCELLENT | $(printf '%*s' "$DIST_EXCELLENT" | tr ' ' '#') |"
    echo ""
    echo "## Per-Criterion Averages"
    echo ""
    echo "| Criterion | Avg Points | Max | Rate |"
    echo "|-----------|-----------|-----|------|"
    echo -n "$CRITERION_STATS"
    echo ""
    if [ -n "$WEAKEST_NAME" ]; then
        echo "## Weakest Areas"
        echo ""
        echo "**Lowest scoring criterion:** \`$WEAKEST_NAME\` (${WEAKEST_PCT}% of max)"
        echo ""
        echo "Improvement suggestions:"
        case "$WEAKEST_NAME" in
            clean_code)   echo "- Focus on code quality: consistent naming, no unused variables, clear logic" ;;
            self_review)  echo "- Always perform a self-review pass before finishing" ;;
            tdd_red)      echo "- Write failing tests BEFORE implementation" ;;
            tdd_green_ran)    echo "- Run tests during implementation" ;;
            tdd_green_pass)   echo "- Ensure all tests pass after implementation" ;;
            plan_mode_outline) echo "- Outline steps before writing code" ;;
            plan_mode_tool)    echo "- Use plan mode tool for medium/hard tasks" ;;
            confidence)   echo "- Always state confidence level explicitly" ;;
            task_tracking) echo "- Use TodoWrite or TaskCreate to track work" ;;
            *)            echo "- Review SDLC practices for $WEAKEST_NAME" ;;
        esac
        echo ""
    fi
    echo "## Scenario Difficulty Ranking"
    echo ""
    echo "| Scenario | Avg Score | Runs |"
    echo "|----------|-----------|------|"
    echo -n "$SCENARIO_STATS"
    echo ""
    echo "---"
    echo "_Data from \`score-history.jsonl\` ($SCORE_COUNT entries)_"
else
    # --- Console output ---
    echo "=== Score Analytics ==="
    echo ""
    echo "Entries: $SCORE_COUNT"
    echo "Overall average: $OVERALL_AVG / 10"
    echo "Median: $MEDIAN"
    echo "Range: min=$SCORE_MIN  max=$SCORE_MAX"
    echo "Distribution: low=$DIST_LOW  medium=$DIST_MED  high=$DIST_HIGH  excellent=$DIST_EXCELLENT"
    echo "Trend direction: $TREND_TEXT"
    echo ""
    if [ -n "$SPARK" ]; then
        echo "Score evolution (last 20): $SPARK"
        echo "  Legend: _=0-2  .=3-4  -=5-6  ==7-8  #=9-10"
        echo ""
    fi
    echo "--- Per-Criterion Averages ---"
    printf "%-20s %8s %5s %6s\n" "Criterion" "Avg" "Max" "Rate"
    for crit in $CRITERIA_NAMES; do
        CRIT_SUM=$(jq -r ".criteria.\"$crit\".points // 0" "$WORK_DIR/valid.jsonl" | awk '{s+=$1} END {printf "%.1f", s}')
        CRIT_MAX_SUM=$(jq -r ".criteria.\"$crit\".max // 0" "$WORK_DIR/valid.jsonl" | awk '{s+=$1} END {printf "%.1f", s}')
        if [ "$(echo "$CRIT_MAX_SUM > 0" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
            CRIT_AVG=$(echo "scale=2; $CRIT_SUM / $SCORE_COUNT" | bc -l)
            CRIT_MAX=$(jq -r ".criteria.\"$crit\".max // 0" "$WORK_DIR/valid.jsonl" | head -1)
            CRIT_PCT=$(echo "scale=0; $CRIT_SUM * 100 / $CRIT_MAX_SUM" | bc -l)
            printf "%-20s %8s %5s %5s%%\n" "$crit" "$CRIT_AVG" "$CRIT_MAX" "$CRIT_PCT"
        fi
    done
    echo ""
    if [ -n "$WEAKEST_NAME" ]; then
        echo "Weakest criterion: $WEAKEST_NAME (${WEAKEST_PCT}% of max) — improve this first"
        echo ""
    fi
    echo "--- Scenario Ranking ---"
    printf "%-30s %8s %6s\n" "Scenario" "Avg" "Runs"
    for scenario in $SCENARIO_NAMES; do
        SCEN_AVG=$(jq -r "select(.scenario == \"$scenario\") | .score" "$WORK_DIR/valid.jsonl" | awk '{s+=$1; n++} END {if(n>0) printf "%.1f", s/n; else print "N/A"}')
        SCEN_COUNT=$(jq -r "select(.scenario == \"$scenario\") | .score" "$WORK_DIR/valid.jsonl" | wc -l | tr -d ' ')
        printf "%-30s %8s %6s\n" "$scenario" "$SCEN_AVG" "$SCEN_COUNT"
    done
fi
