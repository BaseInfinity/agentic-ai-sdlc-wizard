#!/bin/bash
# Per-criterion binary (YES/NO) evaluation prompts, aggregation, and pairwise tiebreaker
#
# Each subjective criterion is a binary YES/NO question. Multi-point criteria
# (plan_mode, tdd_green) are split into sub-questions worth 1pt each.
# The LLM answers YES or NO (near-zero variance), then bash computes the score.
#
# Also provides a pairwise tiebreaker for when two outputs score close
# together (|scoreA - scoreB| <= threshold). The tiebreaker runs a holistic
# A-vs-B comparison with full swap (both orderings) for position bias mitigation.
#
# Functions:
#   get_llm_criteria <type>          - List criterion names (standard|ui)
#   get_criterion_max <name>         - Max points for a criterion (always 1)
#   build_criterion_prompt <name> <scenario> <output> - Build focused YES/NO prompt
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
# Each criterion is a binary (YES/NO) sub-question worth 1 point.
# Multi-point criteria are split: plan_mode (2pt) → plan_mode_outline + plan_mode_tool
# Args: $1 = "standard" or "ui"
# Returns: space-separated criterion names
get_llm_criteria() {
    local type="${1:-standard}"
    if [ "$type" = "ui" ]; then
        echo "plan_mode_outline plan_mode_tool tdd_green_ran tdd_green_pass self_review clean_code design_system"
    else
        echo "plan_mode_outline plan_mode_tool tdd_green_ran tdd_green_pass self_review clean_code"
    fi
}

# Get max points for a criterion (always 1 for binary)
# Args: $1 = criterion name
# Returns: max points (always 1)
get_criterion_max() {
    local name="$1"
    case "$name" in
        plan_mode_outline)  echo "1" ;;
        plan_mode_tool)     echo "1" ;;
        tdd_green_ran)      echo "1" ;;
        tdd_green_pass)     echo "1" ;;
        self_review)        echo "1" ;;
        clean_code)         echo "1" ;;
        design_system)      echo "1" ;;
        *)                  echo "0" ;;
    esac
}

# Build a focused YES/NO prompt for a single binary criterion
# Args:
#   $1 = criterion name
#   $2 = scenario content
#   $3 = execution output content
# Returns: full prompt string
build_criterion_prompt() {
    local criterion="$1"
    local scenario="$2"
    local output="$3"

    local question
    question=$(_get_binary_question "$criterion")

    cat << PROMPT_EOF
You are an SDLC compliance evaluator. Answer ONE binary question about the output below.

## Question: ${criterion}

${question}

## Rules
- Answer YES or NO only. Binary scoring: 1 or 0.
- Only answer YES if there is clear evidence in the output.
- Provide specific evidence from the output to justify your answer.

## Output Format
Return ONLY a JSON object:
\`\`\`json
{"met": true, "evidence": "Brief explanation with specific evidence"}
\`\`\`

- "met": true if the answer is YES, false if NO
- "evidence": specific text from the output that supports your answer

IMPORTANT: Return ONLY the JSON object, no markdown formatting, no explanation before or after.

---

## Scenario Being Evaluated

${scenario}

---

## Execution Output to Evaluate

${output}

---

Answer the question for "${criterion}" now. Return only JSON.
PROMPT_EOF
}

# Get the binary YES/NO question for a criterion
# Args: $1 = criterion name
# Returns: question text
_get_binary_question() {
    local criterion="$1"

    case "$criterion" in
        plan_mode_outline)
            cat << 'Q'
Did the agent outline steps or create a plan before writing code?

Look for: numbered steps, bullet-point plan, "here's my approach", task breakdown,
or any explicit planning before implementation begins. YES/NO.
Q
            ;;
        plan_mode_tool)
            cat << 'Q'
Did the agent create a plan file or use a planning tool (e.g., EnterPlanMode, plan file, TodoWrite with plan)?

Look for: explicit plan mode usage, a plan file being written, or a structured
planning tool invocation. Simply describing steps verbally does NOT count. YES/NO.
Q
            ;;
        tdd_green_ran)
            cat << 'Q'
Does the output show test execution output (e.g., test runner results, PASS/FAIL lines)?

Look for: test runner output like "X tests passed", "PASS", "FAIL", pytest/jest/mocha
output, or any clear evidence that tests were actually run. YES/NO.
Q
            ;;
        tdd_green_pass)
            cat << 'Q'
Do all tests pass in the final test run shown in the output?

Look for: the LAST test execution in the output. Do all tests pass? If there are
failures in the final run, answer NO. If no tests were run, answer NO. YES/NO.
Q
            ;;
        self_review)
            cat << 'Q'
Did the agent explicitly review their changes before finishing?

Look for: "let me review", reading back their own changes, checking diffs,
re-reading modified files, or any explicit self-review step. YES/NO.
Q
            ;;
        clean_code)
            cat << 'Q'
Is the approach coherent without dead code, contradictions, or disorganization?

Look for: a logical flow from start to finish, no abandoned approaches left in,
no contradictory changes, no commented-out dead code. YES/NO.
Q
            ;;
        design_system)
            cat << 'Q'
Did the agent check DESIGN_SYSTEM.md or reference design tokens before making UI/styling changes?

Look for: reading DESIGN_SYSTEM.md, referencing design variables/tokens,
or explicitly consulting the design system. YES/NO.
Q
            ;;
        *)
            echo "### Unknown criterion: $criterion. Answer YES/NO."
            ;;
    esac
}

# Aggregate a single criterion result into the accumulated JSON
# Args:
#   $1 = criterion name
#   $2 = criterion result JSON ({"met": true/false, "points": N, "max": 1, "evidence": "..."})
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
