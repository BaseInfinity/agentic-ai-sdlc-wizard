#!/bin/bash
# Statistical functions for E2E evaluation
#
# Usage: source this file in your script
#   source "$(dirname "$0")/lib/stats.sh"

# Calculate 95% confidence interval using t-distribution
# Inspired by aistupidlevel.info methodology
#
# Args:
#   $1 - Space-separated scores (e.g., "5.1 5.3 5.0 5.2 5.4")
#
# Output:
#   Formatted string: "mean ± margin (95% CI: [lower, upper])"
#
# Example:
#   CI_RESULT=$(calculate_confidence_interval "5.1 5.3 5.0 5.2 5.4")
#   # Output: "5.2 ± 0.2 (95% CI: [5.0, 5.4])"
#
calculate_confidence_interval() {
    local scores="$1"
    local n
    n=$(echo "$scores" | wc -w | tr -d ' ')

    # Need at least 2 data points for meaningful CI
    if [ "$n" -lt 2 ]; then
        local single_score
        single_score=$(echo "$scores" | awk '{print $1}')
        printf "%.1f (n=1, no CI)" "$single_score"
        return
    fi

    # t-values for 95% CI (two-tailed)
    # df=1: 12.706 (very wide), df=2: 4.303, df=3: 3.182, df=4: 2.776
    local t_val
    case $((n - 1)) in
        1) t_val="12.706" ;;
        2) t_val="4.303" ;;
        3) t_val="3.182" ;;
        4) t_val="2.776" ;;
        *) t_val="2.571" ;;  # df>=5, approximate
    esac

    # Calculate mean
    local mean
    mean=$(echo "$scores" | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; printf "%.4f", sum/NF}')

    # Calculate sample standard deviation
    local std
    std=$(echo "$scores" | awk -v m="$mean" '{
        sum=0
        for(i=1;i<=NF;i++) sum+=($i-m)^2
        printf "%.4f", sqrt(sum/(NF-1))
    }')

    # Standard error of the mean
    local se
    se=$(echo "$std $n" | awk '{printf "%.4f", $1/sqrt($2)}')

    # Margin of error
    local margin
    margin=$(echo "$t_val $se" | awk '{printf "%.4f", $1 * $2}')

    # Calculate bounds
    local lower upper
    lower=$(echo "$mean $margin" | awk '{printf "%.1f", $1 - $2}')
    upper=$(echo "$mean $margin" | awk '{printf "%.1f", $1 + $2}')

    # Format output
    printf "%.1f ± %.1f (95%% CI: [%.1f, %.1f])" "$mean" "$margin" "$lower" "$upper"
}

# Get just the mean from scores
#
# Args:
#   $1 - Space-separated scores
#
# Output:
#   Mean value formatted to 1 decimal place
#
get_mean() {
    local scores="$1"
    echo "$scores" | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; printf "%.1f", sum/NF}'
}

# Get the lower bound of 95% CI
#
# Args:
#   $1 - Space-separated scores
#
# Output:
#   Lower CI bound formatted to 1 decimal place
#
get_ci_lower() {
    local scores="$1"
    local n
    n=$(echo "$scores" | wc -w | tr -d ' ')

    if [ "$n" -lt 2 ]; then
        echo "$scores" | awk '{printf "%.1f", $1}'
        return
    fi

    local t_val
    case $((n - 1)) in
        1) t_val="12.706" ;;
        2) t_val="4.303" ;;
        3) t_val="3.182" ;;
        4) t_val="2.776" ;;
        *) t_val="2.571" ;;
    esac

    echo "$scores" | awk -v t="$t_val" '{
        sum=0; for(i=1;i<=NF;i++) sum+=$i; mean=sum/NF
        sq_sum=0; for(i=1;i<=NF;i++) sq_sum+=($i-mean)^2
        std=sqrt(sq_sum/(NF-1))
        se=std/sqrt(NF)
        margin=t*se
        printf "%.1f", mean - margin
    }'
}

# Get the upper bound of 95% CI
#
# Args:
#   $1 - Space-separated scores
#
# Output:
#   Upper CI bound formatted to 1 decimal place
#
get_ci_upper() {
    local scores="$1"
    local n
    n=$(echo "$scores" | wc -w | tr -d ' ')

    if [ "$n" -lt 2 ]; then
        echo "$scores" | awk '{printf "%.1f", $1}'
        return
    fi

    local t_val
    case $((n - 1)) in
        1) t_val="12.706" ;;
        2) t_val="4.303" ;;
        3) t_val="3.182" ;;
        4) t_val="2.776" ;;
        *) t_val="2.571" ;;
    esac

    echo "$scores" | awk -v t="$t_val" '{
        sum=0; for(i=1;i<=NF;i++) sum+=$i; mean=sum/NF
        sq_sum=0; for(i=1;i<=NF;i++) sq_sum+=($i-mean)^2
        std=sqrt(sq_sum/(NF-1))
        se=std/sqrt(NF)
        margin=t*se
        printf "%.1f", mean + margin
    }'
}

# Determine statistical verdict by comparing CI bounds
# Uses the overlapping CI method (correct for comparing two uncertain measurements)
#
# Args:
#   $1 - Baseline scores (space-separated)
#   $2 - Candidate scores (space-separated)
#
# Output:
#   One of: IMPROVED, STABLE, REGRESSION
#
# Logic:
#   - IMPROVED: candidate_lower > baseline_upper (no overlap, candidate wins)
#   - REGRESSION: candidate_upper < baseline_lower (no overlap, baseline wins)
#   - STABLE: CIs overlap (can't distinguish statistically)
#
compare_ci() {
    local baseline_scores="$1"
    local candidate_scores="$2"

    local baseline_upper candidate_lower candidate_upper baseline_lower
    baseline_upper=$(get_ci_upper "$baseline_scores")
    baseline_lower=$(get_ci_lower "$baseline_scores")
    candidate_lower=$(get_ci_lower "$candidate_scores")
    candidate_upper=$(get_ci_upper "$candidate_scores")

    # Check if candidate is statistically better (no overlap, candidate wins)
    if echo "$candidate_lower $baseline_upper" | awk '{exit !($1 > $2)}'; then
        echo "IMPROVED"
    # Check if candidate is statistically worse (no overlap, baseline wins)
    elif echo "$candidate_upper $baseline_lower" | awk '{exit !($1 < $2)}'; then
        echo "REGRESSION"
    # CIs overlap - can't distinguish
    else
        echo "STABLE"
    fi
}
