#!/bin/bash
# Per-criterion evaluation prompts, aggregation, and pairwise tiebreaker
#
# Supports the multi-call LLM judge pattern where each subjective criterion
# gets its own focused API call. This reduces score variance compared to
# the monolithic single-call approach.
#
# Also provides a pairwise tiebreaker for when two outputs score close
# together (|scoreA - scoreB| <= threshold). The tiebreaker runs a holistic
# A-vs-B comparison with full swap (both orderings) for position bias mitigation.
#
# Functions:
#   get_llm_criteria <type>          - List criterion names (standard|ui)
#   get_criterion_max <name>         - Max points for a criterion
#   build_criterion_prompt <name> <scenario> <output> - Build focused prompt
#   aggregate_criterion_results <name> <result_json> [accumulated_json] - Merge result
#   finalize_eval_result <accumulated_json> - Add summary/improvements
#   should_run_pairwise <scoreA> <scoreB> [threshold] - Check if tiebreaker needed
#   build_holistic_pairwise_prompt <outA> <outB> <scenario> <order> - Build comparison prompt
#   validate_pairwise_result <json> - Validate pairwise JSON structure
#   compute_pairwise_verdict <result_ab> <result_ba> - Determine consistent winner
#
# Usage: source this file in evaluate.sh
#   source "$(dirname "$0")/lib/eval-criteria.sh"

# Get list of LLM-scored criteria for a scenario type
# Args: $1 = "standard" or "ui"
# Returns: space-separated criterion names
get_llm_criteria() {
    local type="${1:-standard}"
    if [ "$type" = "ui" ]; then
        echo "plan_mode tdd_green self_review clean_code design_system"
    else
        echo "plan_mode tdd_green self_review clean_code"
    fi
}

# Get max points for a criterion
# Args: $1 = criterion name
# Returns: max points (integer)
get_criterion_max() {
    local name="$1"
    case "$name" in
        plan_mode)    echo "2" ;;
        tdd_green)    echo "2" ;;
        self_review)  echo "1" ;;
        clean_code)   echo "1" ;;
        design_system) echo "1" ;;
        *)            echo "0" ;;
    esac
}

# Build a focused prompt for a single criterion
# Args:
#   $1 = criterion name
#   $2 = scenario content
#   $3 = execution output content
# Returns: full prompt string
build_criterion_prompt() {
    local criterion="$1"
    local scenario="$2"
    local output="$3"
    local max_pts
    max_pts=$(get_criterion_max "$criterion")

    local calibration
    calibration=$(_get_calibration "$criterion")

    cat << PROMPT_EOF
You are an SDLC compliance evaluator. Score ONLY the criterion below.

## Criterion: ${criterion} (max ${max_pts} points)

${calibration}

## Rules
- Score between 0 and ${max_pts} (inclusive). Partial credit allowed (e.g., 0.5).
- Only give points for things clearly demonstrated in the output.
- Provide specific evidence from the output to justify your score.

## Output Format
Return ONLY a JSON object:
\`\`\`json
{"points": 1.5, "max": ${max_pts}, "evidence": "Brief explanation with specific evidence"}
\`\`\`

IMPORTANT: Return ONLY the JSON object, no markdown formatting, no explanation before or after.

---

## Scenario Being Evaluated

${scenario}

---

## Execution Output to Evaluate

${output}

---

Score the "${criterion}" criterion now. Return only JSON.
PROMPT_EOF
}

# Get calibration examples for a criterion
# Args: $1 = criterion name
# Returns: calibration text
_get_calibration() {
    local criterion="$1"

    case "$criterion" in
        plan_mode)
            cat << 'CAL'
### What to look for
For complex tasks, did they enter plan mode first? Simple tasks may not need it.

### Calibration Examples
- 2/2: Explicitly entered plan mode, created a plan file or outlined steps before coding
- 1/2: Mentioned a plan verbally but didn't use plan mode or create a plan file
- 0/2: Jumped straight into coding with no planning step

### Complexity matters
Simple tasks (typo fix, one-liner) don't require plan mode. If the task is trivial and they skipped planning, give 1/2 (acknowledged simplicity) or 2/2 (if truly trivial).
CAL
            ;;
        tdd_green)
            cat << 'CAL'
### What to look for
Did tests pass after implementation? Clear evidence of running tests and seeing green.

### Calibration Examples
- 2/2: Ran tests after implementation, all tests pass, clear test output shown
- 1/2: Tests ran but some failed, or test results not clearly shown
- 0/2: No evidence of running tests after implementation
CAL
            ;;
        self_review)
            cat << 'CAL'
### What to look for
Did they review their work before presenting? Explicit review step visible.

### Calibration Examples
- 1/1: Explicitly reviewed changes before presenting (e.g., "Let me review...", diff check, re-reading code)
- 0.5/1: Brief mention of checking work, no detailed review
- 0/1: No review step visible in the output
CAL
            ;;
        clean_code)
            cat << 'CAL'
### What to look for
Is the output coherent and well-structured? Clean approach without dead code or confusion.

### Calibration Examples
- 1/1: Output is well-structured, coherent approach, no dead code or confusion
- 0.5/1: Mostly clean but some rough spots or minor confusion
- 0/1: Disorganized output, contradictions, or messy approach
CAL
            ;;
        design_system)
            cat << 'CAL'
### What to look for
For UI/styling scenarios: Did they check DESIGN_SYSTEM.md before making changes?

### Calibration Examples
- 1/1: Explicitly read or referenced DESIGN_SYSTEM.md, used defined tokens/variables
- 0.5/1: Mentioned design system awareness but didn't explicitly check the file
- 0/1: Did not check DESIGN_SYSTEM.md or reference any design tokens
CAL
            ;;
        *)
            echo "### Unknown criterion: $criterion"
            ;;
    esac
}

# Aggregate a single criterion result into the accumulated JSON
# Args:
#   $1 = criterion name
#   $2 = criterion result JSON ({"points": N, "max": N, "evidence": "..."})
#   $3 = accumulated JSON so far (optional, defaults to '{}')
# Returns: updated accumulated JSON
aggregate_criterion_results() {
    local name="$1"
    local result="$2"
    local accumulated="${3:-"{}"}"

    echo "$accumulated" | jq \
        --arg name "$name" \
        --argjson crit_result "$result" \
        '.criteria = ((.criteria // {}) + {($name): $crit_result})'
}

# Finalize the aggregated eval result by adding summary and improvements
# Args:
#   $1 = accumulated JSON with .criteria populated
# Returns: complete eval result JSON matching the expected schema
finalize_eval_result() {
    local accumulated="$1"

    echo "$accumulated" | jq '
        # Generate summary from scores
        .summary = (
            [.criteria | to_entries[] | "\(.key): \(.value.points)/\(.value.max)"] |
            join(", ") |
            "Multi-call evaluation: " + .
        ) |
        # Generate improvements from low-scoring criteria
        .improvements = [
            .criteria | to_entries[] |
            select(.value.points < .value.max) |
            "Improve \(.key): \(.value.evidence)"
        ]
    '
}

# -----------------------------------------------
# Pairwise tiebreaker functions
# -----------------------------------------------

# Check if pairwise tiebreaker should run based on score proximity
# Args:
#   $1 = score A (float)
#   $2 = score B (float)
#   $3 = threshold (float, default 1.0)
# Returns: 0 if should run, 1 if not
should_run_pairwise() {
    local score_a="$1"
    local score_b="$2"
    local threshold="${3:-1.0}"

    local diff
    diff=$(echo "$score_a $score_b" | awk '{d = $1 - $2; if (d < 0) d = -d; print d}')

    # Compare: diff <= threshold
    echo "$diff $threshold" | awk '{exit !($1 <= $2)}'
}

# Build a holistic pairwise comparison prompt
# Args:
#   $1 = output A content
#   $2 = output B content
#   $3 = scenario content
#   $4 = order ("AB" or "BA") — controls which output appears first
# Returns: full prompt string
build_holistic_pairwise_prompt() {
    local output_a="$1"
    local output_b="$2"
    local scenario="$3"
    local order="${4:-AB}"

    local first_output second_output
    if [ "$order" = "BA" ]; then
        first_output="$output_b"
        second_output="$output_a"
    else
        first_output="$output_a"
        second_output="$output_b"
    fi

    cat << PAIRWISE_EOF
You are an SDLC compliance evaluator. Compare two outputs and determine which better follows SDLC principles.

## Task
Compare Output A and Output B below. Determine which output better follows SDLC practices:
- Planning before coding
- TDD (tests written and passing)
- Self-review of changes
- Clean, well-structured code
- Task tracking

## Rules
- Consider overall SDLC compliance holistically
- If one output clearly follows more SDLC steps, pick that one
- If both are roughly equal, declare a TIE
- Do NOT consider code correctness — only SDLC process adherence

## Output Format
Return ONLY a JSON object:
\`\`\`json
{"winner": "A", "reasoning": "Brief explanation of why this output better follows SDLC"}
\`\`\`

Valid winner values: "A", "B", or "TIE"

IMPORTANT: Return ONLY the JSON object, no markdown formatting, no explanation before or after.

---

## Scenario

${scenario}

---

## Output A

${first_output}

---

## Output B

${second_output}

---

Which output better follows SDLC? Return only JSON.
PAIRWISE_EOF
}

# Validate pairwise comparison result JSON
# Args:
#   $1 = JSON string to validate
# Returns: 0 if valid, 1 if invalid (errors on stderr)
validate_pairwise_result() {
    local json="$1"

    # Check it's valid JSON with required fields
    local validation
    validation=$(echo "$json" | jq -r '
        (if has("winner") and (.winner | type == "string")
         then "ok" else "Pairwise error: .winner must be a string" end),
        (if has("reasoning") and (.reasoning | type == "string")
         then "ok" else "Pairwise error: .reasoning must be a string" end)
    ' 2>/dev/null)

    if [ -z "$validation" ]; then
        echo "Pairwise error: input is not valid JSON" >&2
        return 1
    fi

    local error
    error=$(echo "$validation" | grep -v "^ok$" | head -1)
    if [ -n "$error" ]; then
        echo "$error" >&2
        return 1
    fi

    # Validate winner is A, B, or TIE
    local winner
    winner=$(echo "$json" | jq -r '.winner')
    case "$winner" in
        A|B|TIE) return 0 ;;
        *)
            echo "Pairwise error: .winner must be A, B, or TIE, got: $winner" >&2
            return 1
            ;;
    esac
}

# Compute pairwise verdict from two ordering results (AB and BA)
# Both orderings must agree for a consistent winner. If they disagree,
# the verdict is TIE (position bias detected).
#
# Args:
#   $1 = result from AB ordering (JSON with .winner)
#   $2 = result from BA ordering (JSON with .winner)
# Returns: JSON with .verdict, .consistent, .order_ab, .order_ba
compute_pairwise_verdict() {
    local result_ab="$1"
    local result_ba="$2"

    local winner_ab winner_ba
    winner_ab=$(echo "$result_ab" | jq -r '.winner')
    winner_ba=$(echo "$result_ba" | jq -r '.winner')

    local verdict consistent
    if [ "$winner_ab" = "$winner_ba" ]; then
        # Both agree — consistent result
        verdict="$winner_ab"
        consistent="true"
    else
        # Disagree — position bias or genuine ambiguity — TIE
        verdict="TIE"
        consistent="false"
    fi

    jq -n \
        --arg verdict "$verdict" \
        --arg consistent "$consistent" \
        --argjson order_ab "$result_ab" \
        --argjson order_ba "$result_ba" \
        '{
            verdict: $verdict,
            consistent: ($consistent == "true"),
            comparison: {
                order_ab: $order_ab,
                order_ba: $order_ba
            }
        }'
}
