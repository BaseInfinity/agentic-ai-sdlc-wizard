#!/bin/bash
# Wizard Lift-Proof Orchestrator — ROADMAP #96 Phase 3 PR 1.
#
# The "does the wizard work?" test. Runs the same E2E benchmark scenario
# twice — once on a BARE fixture (no wizard installed) and once on a
# WIZARD-installed fixture — then computes the score delta. A positive
# delta means installing the wizard lifts organic SDLC behavior. That's
# the load-bearing claim of the entire harness.
#
# Phase 1 (v1.57.0) de-coached the prompt so the agent isn't told what's
# scored. Phase 2 (v1.58.0) added a ground-truth gate so the judge can't
# pass broken code. Phase 3 (this) measures the wizard's contribution
# directly.
#
# Honestly zero-API: simulation and evaluator both run on Max via
# `claude --print` (#228; evaluate.sh's API-key fallback was later deleted
# entirely — 2026-07-21 — since it was unreachable through any automated
# path here).
#
# Usage:
#   ./tests/e2e/lift-proof.sh [--scenario <name>] [--output <file>]
#
# Flags:
#   --scenario NAME   Which scenario to run (default: add-feature)
#   --output FILE     Where to write the JSON artifact (default:
#                     .benchmark/lift-proof-<timestamp>.json)
#   --dry-run         Skip the live claude --print runs (used by CI tests)
#   -h | --help       Show this help text and exit
#
# Output artifact (JSON):
#   { timestamp, scenario, bare_score, bare_max, wizard_score, wizard_max,
#     delta, host_os, cli_version, claude_code_version, eval_use_cli }
#
# Exit codes:
#   0 success
#   1 missing dep, bad args, simulation failed, evaluator failed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
EVALUATOR="${SDLC_LIFT_EVALUATOR:-$SCRIPT_DIR/evaluate.sh}"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"

# Parity with local-shepherd.sh — keep both paths comparable.
PARITY_MAX_TURNS="${SDLC_LIFT_MAX_TURNS:-55}"
PARITY_ALLOWED_TOOLS='Read,Edit,Write,Bash(npm *),Bash(node *),Bash(git *),Glob,Grep,TodoWrite,TaskCreate,Task'

usage() {
    cat >&2 <<EOF
Usage: $0 [--scenario <name>] [--output <file>] [--dry-run]

Runs the same E2E benchmark scenario on a BARE fixture (no wizard) and on
a WIZARD-installed fixture, then emits the score delta — the "wizard lift"
proof. Both legs run on Max via 'claude --print', so this costs nothing
on the API canary.

Flags:
  --scenario NAME   scenario to run (default: add-feature)
  --output FILE     where to write the JSON artifact
                    (default: .benchmark/lift-proof-<timestamp>.json)
  --dry-run         skip live runs (CI smoke; tests use this)
  -h | --help       show this help

Exit: 0 success; 1 dep/arg/sim/eval failure.
EOF
    exit 1
}

# ---- arg parse ----
SCENARIO="add-feature"
OUTPUT_FILE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --scenario)
            shift; [ $# -eq 0 ] && { echo "Error: --scenario requires a name" >&2; exit 1; }
            SCENARIO="$1"; shift ;;
        --output)
            shift; [ $# -eq 0 ] && { echo "Error: --output requires a file" >&2; exit 1; }
            OUTPUT_FILE="$1"; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage ;;
        *) echo "Error: unknown flag: $1" >&2; exit 1 ;;
    esac
done

SCENARIO_FILE="$SCENARIOS_DIR/$SCENARIO.md"
if [ ! -f "$SCENARIO_FILE" ]; then
    echo "Error: scenario file not found: $SCENARIO_FILE" >&2
    echo "Available: $(ls "$SCENARIOS_DIR" 2>/dev/null | sed 's/\.md$//' | tr '\n' ' ')" >&2
    exit 1
fi

# ---- deps ----
for bin in jq; do
    command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin CLI not found" >&2; exit 1; }
done
if [ "$DRY_RUN" -ne 1 ]; then
    command -v claude >/dev/null 2>&1 \
        || { echo "Error: claude CLI not found (needed for live runs; --dry-run skips this)" >&2; exit 1; }
fi
if [ ! -x "$EVALUATOR" ]; then
    echo "Error: evaluator not executable at $EVALUATOR" >&2
    exit 1
fi

# Source the wizard installer library — single source of truth for what
# "the wizard installed into a project" looks like (#96 Phase 3 PR 1).
# shellcheck source=lib/wizard-installer.sh
source "$SCRIPT_DIR/lib/wizard-installer.sh"

# ---- provenance ----
HOST_OS=$(uname -s 2>/dev/null || echo "unknown")
# Dry-run: skip even `claude --version` so this is a 0-claude-call path
# (Codex round 1 P1 reinforcement). Tests can mock claude to fail on any
# invocation and dry-run must still complete.
if [ "$DRY_RUN" -eq 1 ]; then
    CLI_VERSION="dry-run-stub"
else
    CLI_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$CLI_VERSION" ] && CLI_VERSION="unknown"
fi

# Default output path
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="$REPO_ROOT/.benchmark/lift-proof-$(date -u +%Y%m%dT%H%M%SZ).json"
fi
mkdir -p "$(dirname "$OUTPUT_FILE")"

TMPRUN=$(mktemp -d)
trap 'rm -rf "$TMPRUN"' EXIT

# Build a fixture-style cwd. Both legs need tests/e2e/{scenarios,lib,fixtures}
# laid out from cwd so claude --print finds them via --add-dir.
build_run_dir() {
    local dst="$1"
    mkdir -p "$dst/tests/e2e"
    cp -R "$REPO_ROOT/tests/e2e/scenarios" "$dst/tests/e2e/scenarios"
    cp -R "$REPO_ROOT/tests/e2e/lib"       "$dst/tests/e2e/lib"
    cp -R "$REPO_ROOT/tests/e2e/fixtures"  "$dst/tests/e2e/fixtures"
}

REL_SCENARIO="tests/e2e/scenarios/$SCENARIO.md"
FIXTURES_REL="tests/e2e/fixtures/test-repo"

# Neutral task prompt — same shape as local-shepherd.sh (#96 Phase 1).
PROMPT_FILE="$TMPRUN/parity-prompt.txt"
{
    printf '%s\n' "You are completing a coding task in a real working directory."
    printf '%s\n' ""
    printf '%s\n' "Working directory: $FIXTURES_REL"
    printf '%s\n' "Scenario file: $REL_SCENARIO"
    printf '%s\n' ""
    printf '%s\n' "Read the scenario file for the task spec. Complete it however you'\''d"
    printf '%s\n' "normally complete a coding task — using whatever practices your tooling,"
    printf '%s\n' "skills, or instructions teach you. The result will be evaluated"
    printf '%s\n' "independently."
    printf '%s\n' ""
    printf '%s\n' "Constraints:"
    printf '%s\n' "- All files you need are in the working directory; do not search elsewhere."
    printf '%s\n' "- Do NOT use EnterPlanMode or ExitPlanMode — plan inline in messages."
    printf '%s\n' "- Be efficient — execute, don'\''t just plan."
} > "$PROMPT_FILE"
PARITY_PROMPT=$(cat "$PROMPT_FILE")

run_one_leg() {
    local leg="$1"           # "bare" or "wizard"
    local run_dir="$2"
    local output_file="$run_dir/claude-execution-output.json"

    if [ "$DRY_RUN" -eq 1 ]; then
        # Codex round 1 P1: dry-run must NOT call any model — neither the
        # simulation leg nor the evaluator (the evaluator would re-invoke
        # `claude --print` per criterion, ~12 calls). Synthesize
        # deterministic stub eval JSON and skip both calls entirely. Tests can
        # mock claude to fail-on-invocation and assert dry-run still succeeds.
        printf '{"type":"result","result":"DRY_RUN","total_cost_usd":0}\n' > "$output_file"
        # Bare leg gets a slightly lower stub score than wizard so artifact
        # generation produces a non-zero delta — exercises lift_signed code path.
        local stub_score=4
        if [ "$leg" = "wizard" ]; then stub_score=7; fi
        printf '{"score": %s, "max_score": 10, "criteria": {}, "summary": "dry-run stub"}\n' "$stub_score"
        return
    fi

    echo "Running $leg leg in $run_dir (max-turns=$PARITY_MAX_TURNS)" >&2
    ( cd "$run_dir" && claude --print \
        --max-turns "$PARITY_MAX_TURNS" \
        --allowedTools "$PARITY_ALLOWED_TOOLS" \
        --add-dir "tests/e2e" \
        --output-format json \
        "$PARITY_PROMPT" > "$output_file" 2>"$run_dir/claude.err" )
    local rc=$?
    if [ "$rc" -ne 0 ] || [ ! -s "$output_file" ]; then
        echo "Error: $leg simulation failed (rc=$rc)" >&2
        [ -s "$run_dir/claude.err" ] && sed -n '1,5p' "$run_dir/claude.err" >&2
        exit 1
    fi

    local eval_json eval_rc=0
    set +e
    eval_json=$("$EVALUATOR" "$SCENARIO_FILE" "$output_file" --json 2>"$run_dir/eval.err")
    eval_rc=$?
    set -e
    if [ "$eval_rc" -ne 0 ] || ! echo "$eval_json" | jq empty 2>/dev/null; then
        echo "Error: $leg evaluator failed (rc=$eval_rc)" >&2
        [ -s "$run_dir/eval.err" ] && sed -n '1,5p' "$run_dir/eval.err" >&2
        exit 1
    fi
    echo "$eval_json"
}

# ---- BARE leg ----
BARE_DIR="$TMPRUN/bare"
mkdir -p "$BARE_DIR"
build_run_dir "$BARE_DIR"
# Belt-and-braces: ensure the fixture's .claude is empty (no wizard).
rm -rf "$BARE_DIR/tests/e2e/fixtures/test-repo/.claude"
mkdir -p "$BARE_DIR/tests/e2e/fixtures/test-repo/.claude"

BARE_EVAL=$(run_one_leg "bare" "$BARE_DIR")
BARE_SCORE=$(echo "$BARE_EVAL" | jq -r '.score // 0')
BARE_MAX=$(echo "$BARE_EVAL" | jq -r '.max_score // 10')
case "$BARE_SCORE" in ''|*[!0-9]*) BARE_SCORE=0 ;; esac
case "$BARE_MAX" in ''|*[!0-9]*) BARE_MAX=10 ;; esac
echo "Bare leg: $BARE_SCORE/$BARE_MAX" >&2

# ---- WIZARD leg ----
WIZARD_DIR="$TMPRUN/wizard"
mkdir -p "$WIZARD_DIR"
build_run_dir "$WIZARD_DIR"
install_wizard_into_fixture "$REPO_ROOT" "$WIZARD_DIR/tests/e2e/fixtures/test-repo"

WIZARD_EVAL=$(run_one_leg "wizard" "$WIZARD_DIR")
WIZARD_SCORE=$(echo "$WIZARD_EVAL" | jq -r '.score // 0')
WIZARD_MAX=$(echo "$WIZARD_EVAL" | jq -r '.max_score // 10')
case "$WIZARD_SCORE" in ''|*[!0-9]*) WIZARD_SCORE=0 ;; esac
case "$WIZARD_MAX" in ''|*[!0-9]*) WIZARD_MAX=10 ;; esac
echo "Wizard leg: $WIZARD_SCORE/$WIZARD_MAX" >&2

DELTA=$((WIZARD_SCORE - BARE_SCORE))

# ---- emit artifact ----
jq -nc \
    --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg scenario "$SCENARIO" \
    --argjson bare_score "$BARE_SCORE" \
    --argjson bare_max "$BARE_MAX" \
    --argjson wizard_score "$WIZARD_SCORE" \
    --argjson wizard_max "$WIZARD_MAX" \
    --argjson delta "$DELTA" \
    --arg host_os "$HOST_OS" \
    --arg cli_version "$CLI_VERSION" \
    --argjson eval_use_cli 1 \
    --argjson dry_run "$DRY_RUN" \
    '{timestamp:$ts, scenario:$scenario,
      bare_score:$bare_score, bare_max:$bare_max,
      wizard_score:$wizard_score, wizard_max:$wizard_max,
      delta:$delta, lift:$delta,
      host_os:$host_os, cli_version:$cli_version,
      claude_code_version:$cli_version,
      eval_use_cli:($eval_use_cli == 1),
      dry_run:($dry_run == 1)}' \
    > "$OUTPUT_FILE"

DELTA_SIGN="+"
[ "$DELTA" -lt 0 ] && DELTA_SIGN=""
echo "Lift: ${DELTA_SIGN}${DELTA} (wizard=$WIZARD_SCORE/$WIZARD_MAX vs bare=$BARE_SCORE/$BARE_MAX)" >&2
echo "Artifact: $OUTPUT_FILE" >&2
echo "$OUTPUT_FILE"
