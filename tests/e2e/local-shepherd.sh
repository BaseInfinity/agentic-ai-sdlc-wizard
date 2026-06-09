#!/bin/bash
# Local-Max E2E Shepherd (ROADMAP #212, #230)
#
# Replaces CI's `claude-code-action@v1` simulation with a local `claude --print`
# run on the maintainer's Max subscription. Preserves parity with the CI config
# (model pin, max-turns, allowed tools, output shape) so scores are comparable.
#
# Scope (from ROADMAP #212 revised architecture):
#   (a) trusted same-repo PRs only — fork PRs stay on CI-API path (trust boundary)
#   (b) simulation leg on Max ($0 after cap)
#   (c) evaluator on Max via `claude --print` (ROADMAP #228 closed; EVAL_USE_CLI=1)
#   (d) GitHub check-run emission so branch protection is satisfied
#   (e) provenance fields on score-history so local/CI rows are distinguishable
#
# ROADMAP #230 — `--compare-baseline` flag:
#   Runs the same scenario on main (via git worktree) AND the current branch,
#   computes the score delta, posts a comparison check-run + PR comment.
#   Unblocks #231 Phase 2 (weekly-update migration). Uses the same scenario
#   for both runs (delta is meaningful only with apples-to-apples comparison).
#
# ROADMAP #231 Phase 2 — `--strip-paths` flag (prove-it pattern, same-commit):
#   Replaces the deleted prove-it-test job from weekly-update.yml. When CC
#   ships native equivalents to our custom hooks/skills, this measures the
#   score delta WITH the custom files intact vs WITHOUT (stripped). Both
#   runs are on the SAME commit (no main worktree); only the candidate's
#   fixture has files removed. Paths must pass the prove-it allowlist
#   (tests/e2e/lib/prove-it.sh) — non-allowlisted paths are rejected to
#   prevent LLM hallucination from deleting arbitrary files. Requires
#   --compare-baseline.
#
# Usage:
#   ./tests/e2e/local-shepherd.sh <PR_NUMBER>
#   ./tests/e2e/local-shepherd.sh <PR_NUMBER> --compare-baseline
#   ./tests/e2e/local-shepherd.sh <PR_NUMBER> --compare-baseline --strip-paths '[".claude/hooks/X"]'
#
# Env overrides (for testing + power users):
#   SDLC_LOCAL_SHEPHERD_DRY_RUN=1   — skip check-run POST + PR comment
#   SDLC_SHEPHERD_HISTORY_FILE=path — override score-history location
#   SDLC_SHEPHERD_EVALUATOR=path    — override evaluator path (for mocks)
#
# Exit codes:
#   0 success
#   1 generic error (missing dep, bad args, eval failure)
#   2 fork-PR abort (trust boundary — do NOT change to 1)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
SCENARIOS_DIR="$SCRIPT_DIR/scenarios"
DEFAULT_HISTORY="$SCRIPT_DIR/score-history.jsonl"
HISTORY_FILE="${SDLC_SHEPHERD_HISTORY_FILE:-$DEFAULT_HISTORY}"
EVALUATOR="${SDLC_SHEPHERD_EVALUATOR:-$SCRIPT_DIR/evaluate.sh}"
GROUND_TRUTH="${SDLC_SHEPHERD_GROUND_TRUTH:-$SCRIPT_DIR/ground-truth.sh}"

# ROADMAP #96 Phase 2: ground-truth gate helper. Runs the fixture's own
# test suite and gates the judge score: tests-fail caps at
# GROUND_TRUTH_FAIL_CAP (default 5). Re-used by single-mode AND compare-
# baseline mode (Codex F-02). Path resolution:
#   - single mode: cwd-relative tests/e2e/fixtures/test-repo
#   - compare-baseline: $BASELINE_DIR/.../test-repo for baseline,
#     $CANDIDATE_DIR/.../test-repo for candidate (Codex F-01).
#
# Usage:  run_gate <fixture_dir> <judge_score>
# Echoes: "tests_run|tests_pass|final_score|gated"
run_gate() {
    local fixture_dir="$1"
    local judge_score="$2"
    local cap="${GROUND_TRUTH_FAIL_CAP:-5}"
    local gt_json='{"tests_run":false,"reason":"ground_truth_disabled"}'
    if [ "${SDLC_SHEPHERD_SKIP_GROUND_TRUTH:-0}" != "1" ] && [ -x "$GROUND_TRUTH" ]; then
        set +e
        gt_json=$("$GROUND_TRUTH" "$fixture_dir" 2>/dev/null)
        local rc=$?
        set -e
        if [ "$rc" -ne 0 ] || ! echo "$gt_json" | jq empty 2>/dev/null; then
            gt_json='{"tests_run":false,"reason":"ground_truth_error"}'
        fi
    fi
    local tr tp final gated
    tr=$(echo "$gt_json" | jq -r '.tests_run // false')
    tp=$(echo "$gt_json" | jq -r '.tests_pass // false')
    final="$judge_score"
    gated=false
    if [ "$tr" = "true" ] && [ "$tp" = "false" ] && [ "$judge_score" -gt "$cap" ]; then
        final="$cap"
        gated=true
    fi
    echo "$tr|$tp|$final|$gated"
}

usage() {
    cat >&2 <<EOF
Usage: $0 <PR_NUMBER> [--compare-baseline] [--strip-paths '<json-array>']

Runs E2E simulation on the user's Max subscription (via 'claude --print'),
scores with evaluate.sh, appends to score-history.jsonl with provenance,
then posts a GitHub check-run + PR comment.

Flags:
  --compare-baseline    Also run on main (via git worktree) and post the
                        score delta. Same scenario for both runs.
  --strip-paths JSON    Prove-it mode (requires --compare-baseline): instead
                        of comparing against main, compare current branch's
                        intact fixture (baseline) vs stripped fixture
                        (candidate). JSON is an array of paths from the
                        prove-it allowlist (tests/e2e/lib/prove-it.sh).
                        Same-commit comparison.

Requirements: claude CLI (authed for sim + evaluator on Max), gh CLI (authed), jq.

Env:
  SDLC_LOCAL_SHEPHERD_DRY_RUN=1   skip post-run side effects (check-run, comment)
  SDLC_SHEPHERD_HISTORY_FILE=path override score-history.jsonl location
  SDLC_SHEPHERD_EVALUATOR=path    override evaluator binary

Exits: 0=success, 1=error, 2=fork-PR-abort.
EOF
    exit 1
}

# Parse args: positional PR_NUMBER + optional --compare-baseline / --strip-paths.
PR_NUMBER=""
COMPARE_BASELINE=0
STRIP_PATHS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --compare-baseline) COMPARE_BASELINE=1; shift ;;
        --strip-paths)
            shift
            if [ $# -eq 0 ] || [ -z "$1" ]; then
                echo "Error: --strip-paths requires a JSON array argument (e.g., '[\".claude/hooks/X\"]')" >&2
                exit 1
            fi
            STRIP_PATHS="$1"
            shift
            ;;
        --strip-paths=*)
            STRIP_PATHS="${1#--strip-paths=}"
            # Codex P1 #2 round 1: reject the empty `--strip-paths=` form.
            # The bare-flag form already rejects empty at line 94 above; the
            # equals form silently set STRIP_PATHS="" which, combined with
            # the `-n "$STRIP_PATHS"` check below, let a meaningless invocation
            # fall through to single-run mode.
            if [ -z "$STRIP_PATHS" ]; then
                echo "Error: --strip-paths= requires a JSON array argument (e.g., --strip-paths='[\".claude/hooks/X\"]')" >&2
                exit 1
            fi
            shift
            ;;
        --help|-h) usage ;;
        --) shift; break ;;
        -*) echo "Error: unknown flag: $1" >&2; exit 1 ;;
        *)
            if [ -z "$PR_NUMBER" ]; then
                PR_NUMBER="$1"
            fi
            shift
            ;;
    esac
done
[ -z "$PR_NUMBER" ] && usage

# --strip-paths requires --compare-baseline. Lone --strip-paths has no
# meaningful comparison context; bail fast with a clear error rather than
# silently falling through to single-run mode.
if [ -n "$STRIP_PATHS" ] && [ "$COMPARE_BASELINE" != "1" ]; then
    echo "Error: --strip-paths requires --compare-baseline (prove-it semantics need a baseline to compare against)" >&2
    exit 1
fi

# Dependency checks
for bin in claude gh jq git; do
    command -v "$bin" >/dev/null 2>&1 || { echo "Error: $bin CLI not found on PATH" >&2; exit 1; }
done

# Trust boundary: fork PRs do NOT run locally (P0 from Codex review of #212).
# Running a fork PR here would expose the maintainer's GitHub session + Claude
# auth to untrusted code.
IS_FORK=$(gh pr view "$PR_NUMBER" --json headRepository --jq '.headRepository.isFork // "true"' 2>/dev/null || echo "true")
if [ "$IS_FORK" = "true" ]; then
    echo "Abort: PR #$PR_NUMBER is from a fork. Local shepherd only runs same-repo PRs (Codex P0 trust boundary). Fork PRs stay on the CI-API path." >&2
    exit 2
fi

# HEAD-SHA verification (Codex LS-001 P0): the shepherd scores + posts a
# check-run against the PR's head SHA from GitHub. If the local worktree is
# on a different commit, we would certify the wrong code as passing. Require
# the user to check out the PR branch first (`gh pr checkout $PR`).
PR_HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq .headRefOid 2>/dev/null)
LOCAL_HEAD_SHA=$(git rev-parse HEAD 2>/dev/null)
if [ -z "$PR_HEAD_SHA" ] || [ -z "$LOCAL_HEAD_SHA" ]; then
    echo "Error: could not resolve HEAD SHAs (pr=$PR_HEAD_SHA local=$LOCAL_HEAD_SHA)" >&2
    exit 1
fi
if [ "${SDLC_SHEPHERD_SKIP_SHA_CHECK:-0}" != "1" ] && [ "$PR_HEAD_SHA" != "$LOCAL_HEAD_SHA" ]; then
    echo "Error: local HEAD ($LOCAL_HEAD_SHA) does not match PR #$PR_NUMBER head ($PR_HEAD_SHA)." >&2
    echo "       Check out the PR branch first:  gh pr checkout $PR_NUMBER" >&2
    echo "       Or set SDLC_SHEPHERD_SKIP_SHA_CHECK=1 (not recommended)." >&2
    exit 1
fi

# Evaluator runs on Max via `claude --print` (ROADMAP #228 closed).
# EVAL_USE_CLI=1 swaps evaluate.sh's per-criterion judge transport from
# curl-to-API to `claude --print --output-format json`. No API key required.
# The shepherd is now honestly zero-API for the maintainer's path.
export EVAL_USE_CLI=1

# Pick scenario round-robin by PR number (same logic as CI).
# shellcheck source=lib/scenario-selector.sh
source "$SCRIPT_DIR/lib/scenario-selector.sh"
SCENARIO_FILE=$(select_scenario "$SCENARIOS_DIR" "$PR_NUMBER")
SCENARIO_NAME=$(basename "$SCENARIO_FILE" .md)
echo "PR #$PR_NUMBER → scenario: $SCENARIO_NAME" >&2

# ---- Parity with CI (.github/workflows/ci.yml:327-361) ----
# These values MUST match what `claude-code-action@v1` uses in CI. Changing
# any of them without a matching CI change creates a silent score-drift risk.
# The parity-audit test (tests/test-local-shepherd.sh) diffs these against
# the CI block to catch drift.
# Model is NOT pinned explicitly — CI relies on the action's default model,
# so shepherd does too. If Anthropic changes the default, both paths shift
# together. Wizard recommends Opus 4.6 max locally (v1.80.0+).
PARITY_MAX_TURNS=55
PARITY_ALLOWED_TOOLS='Read,Edit,Write,Bash(npm *),Bash(node *),Bash(git *),Glob,Grep,TodoWrite,TaskCreate,Task'

TMPRUN=$(mktemp -d)
trap 'rm -rf "$TMPRUN"' EXIT
OUTPUT_FILE="$TMPRUN/claude-execution-output.json"

# Relative scenario path, fixtures working dir — match CI prompt structure
# (pr-branch is CI artifact path; locally we use repo-root relative).
REL_SCENARIO="tests/e2e/scenarios/$SCENARIO_NAME.md"
FIXTURES_REL="tests/e2e/fixtures/test-repo"

# Neutral task prompt (#96 Phase 1, ROADMAP fix). The previous version
# coached the agent on every scored behavior — which is why the benchmark
# saturated at 10/10 and the v1.32.0 cross-model audit rated it 2/10
# NOT CERTIFIED. Removing the cheat sheet measures whether agents
# practice SDLC organically. A wizard-installed fixture (Phase 3,
# future) will then demonstrate that wizard installation lifts
# organic-low scores back up. Test #96-Phase-1 in
# tests/test-local-shepherd.sh asserts cheat-sheet phrases do not
# resurrect — that's why this comment paraphrases instead of quoting.
#
# bash 3.2 on macOS has a heredoc-in-$() parsing bug when the body
# contains backticks (even inside a 'PROMPT'-quoted delimiter), so we
# write the prompt to a temp file line-by-line and read it back. Ugly
# but bash-3.2 safe.
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

# ---- Provenance fields (computed once, reused for baseline + candidate rows) ----
HOST_OS=$(uname -s 2>/dev/null || echo "unknown")
CLI_VERSION=$(claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
[ -z "$CLI_VERSION" ] && CLI_VERSION="unknown"
CLAUDE_CODE_VERSION="$CLI_VERSION"
AUTH_MODE="subscription"
EXECUTION_PATH="local-max"

# ---- ROADMAP #230: --compare-baseline — run baseline FIRST ----
# Two modes:
#   default (no --strip-paths): cross-commit comparison via git worktree of main
#   --strip-paths: same-commit prove-it via fixture-strip helpers
BASELINE_SCORE=""
BASELINE_MAX=""
CANDIDATE_DIR=""
if [ "$COMPARE_BASELINE" = "1" ]; then
    if [ -n "$STRIP_PATHS" ]; then
        # ROADMAP #231 Phase 2: same-commit prove-it. Build BASELINE_DIR with
        # an intact fixture and CANDIDATE_DIR with a stripped fixture. Both
        # mimic the CI prove-it-test layout (fixture's .claude/ populated
        # from the wizard's custom features).
        # shellcheck source=lib/prove-it.sh
        source "$SCRIPT_DIR/lib/prove-it.sh"

        # Allowlist validation — prevents LLM hallucination from deleting
        # arbitrary files. Single source of truth: REMOVABLE_ALLOWLIST in
        # tests/e2e/lib/prove-it.sh.
        VALID_STRIP=$(validate_removable_paths "$STRIP_PATHS")
        if [ -z "$VALID_STRIP" ]; then
            echo "Error: --strip-paths contained no allowlisted paths." >&2
            echo "       Allowlist source: tests/e2e/lib/prove-it.sh (REMOVABLE_ALLOWLIST)." >&2
            echo "       Got: $STRIP_PATHS" >&2
            exit 1
        fi
        echo "Strip-paths mode: same-commit prove-it. Stripping (allowlisted): $(echo "$VALID_STRIP" | tr '\n' ' ')" >&2

        # Codex P1 #1 round 1: install the cleanup trap BEFORE creating any
        # tmpdirs, so an early failure (failed cp, oom, signal) doesn't leak.
        # All three vars start empty so the cleanup function is safe to call
        # before they're set. Late-binding: the function reads the current
        # values at trap-fire time, not at trap-set time.
        BASELINE_DIR=""
        CANDIDATE_DIR=""
        STRIPPED_STAGE=""
        cleanup_strip_dirs() {
            [ -n "${BASELINE_DIR:-}" ]   && [ -d "$BASELINE_DIR" ]   && rm -rf "$BASELINE_DIR"
            [ -n "${CANDIDATE_DIR:-}" ]  && [ -d "$CANDIDATE_DIR" ]  && rm -rf "$CANDIDATE_DIR"
            [ -n "${STRIPPED_STAGE:-}" ] && [ -d "$STRIPPED_STAGE" ] && rm -rf "$STRIPPED_STAGE"
        }
        trap 'cleanup_strip_dirs; rm -rf "$TMPRUN"' EXIT

        # ROADMAP #96 Phase 3 PR 1: extracted the wizard-install logic to
        # lib/wizard-installer.sh:install_wizard_into_fixture so lift-proof.sh
        # and any future orchestrator can reuse the same install semantic.
        # shellcheck source=lib/wizard-installer.sh
        source "$SCRIPT_DIR/lib/wizard-installer.sh"

        # Helper: lay out a project-root tmpdir so claude --print finds
        # tests/e2e/{scenarios,fixtures,lib} from cwd, just like the worktree
        # path does. Also installs the wizard into the fixture's .claude/.
        _build_strip_dir() {
            local dst="$1"
            mkdir -p "$dst/tests/e2e"
            cp -R "$REPO_ROOT/tests/e2e/scenarios" "$dst/tests/e2e/scenarios"
            cp -R "$REPO_ROOT/tests/e2e/lib"       "$dst/tests/e2e/lib"
            cp -R "$REPO_ROOT/tests/e2e/fixtures"  "$dst/tests/e2e/fixtures"
            # Install the wizard into the fixture's .claude/ — matches CI
            # prove-it: hooks/skills/settings copied from $REPO_ROOT/.claude.
            # Codex round 1 P0: do NOT suppress errors here. If the installer
            # fails, strip-paths comparisons would silently run without a
            # wizard-installed fixture and produce meaningless deltas. Hard-fail.
            install_wizard_into_fixture "$REPO_ROOT" "$dst/tests/e2e/fixtures/test-repo"
        }

        BASELINE_DIR=$(mktemp -d -t sdlc-baseline-strip.XXXXXX)
        _build_strip_dir "$BASELINE_DIR"

        CANDIDATE_DIR=$(mktemp -d -t sdlc-candidate-strip.XXXXXX)
        _build_strip_dir "$CANDIDATE_DIR"
        # Apply the strip to CANDIDATE_DIR's fixture only. create_stripped_fixture
        # copies SRC→DST and removes the requested paths + prunes settings.json
        # hook entries that reference removed hook files.
        STRIPPED_STAGE=$(mktemp -d -t sdlc-cand-stage.XXXXXX)
        rmdir "$STRIPPED_STAGE" 2>/dev/null || rm -rf "$STRIPPED_STAGE"
        create_stripped_fixture \
            "$CANDIDATE_DIR/tests/e2e/fixtures/test-repo" \
            "$STRIPPED_STAGE" \
            "$STRIP_PATHS"
        rm -rf "$CANDIDATE_DIR/tests/e2e/fixtures/test-repo"
        mv "$STRIPPED_STAGE" "$CANDIDATE_DIR/tests/e2e/fixtures/test-repo"
        # mv consumed the dir — clear the var so cleanup doesn't try again.
        STRIPPED_STAGE=""
    else
        # ROADMAP #230 default: cross-commit via main worktree.
        BASELINE_DIR=$(mktemp -d -t sdlc-baseline.XXXXXX)
        # `git worktree add` requires the path NOT to exist, so remove the empty
        # mktemp dir first. Race-window: a concurrent shepherd run could collide,
        # but that's a pathological case (two compare-baseline runs in the same
        # second) — accept the tiny window over `--force` which silently overwrites.
        rmdir "$BASELINE_DIR" 2>/dev/null || rm -rf "$BASELINE_DIR"
        # Detach so we don't lock main as a branch; --force handles a stale lock
        # left behind by a previous failed run.
        if ! git worktree add --detach --force "$BASELINE_DIR" main 2>"$TMPRUN/worktree.err"; then
            # Fallback to origin/main if the local main ref is missing.
            if ! git worktree add --detach --force "$BASELINE_DIR" origin/main 2>>"$TMPRUN/worktree.err"; then
                echo "Error: could not create main worktree (tried 'main' and 'origin/main')" >&2
                sed -n '1,5p' "$TMPRUN/worktree.err" >&2
                exit 1
            fi
        fi
        # Cleanup: prune the worktree on exit. `git worktree remove` may fail if
        # the dir was deleted out-of-band; fall back to rm + prune so subsequent
        # runs don't trip on a stale worktree entry.
        cleanup_baseline_worktree() {
            if [ -n "${BASELINE_DIR:-}" ] && [ -d "$BASELINE_DIR" ]; then
                git worktree remove --force "$BASELINE_DIR" 2>/dev/null \
                    || { rm -rf "$BASELINE_DIR"; git worktree prune 2>/dev/null || true; }
            fi
        }
        # Replace the existing TMPRUN-only trap with a combined one.
        trap 'cleanup_baseline_worktree; rm -rf "$TMPRUN"' EXIT
    fi

    # Codex P1 #2: nest BASELINE_TMPRUN under TMPRUN so the existing trap
    # (which now also runs the mode-specific cleanup) covers it. Previously
    # mktemp -d created a sibling dir that leaked on early failures.
    BASELINE_TMPRUN="$TMPRUN/baseline"
    mkdir -p "$BASELINE_TMPRUN"
    BASELINE_OUTPUT="$BASELINE_TMPRUN/claude-execution-output.json"
    if [ -n "$STRIP_PATHS" ]; then
        echo "Running baseline simulation in $BASELINE_DIR (intact fixture): max-turns=$PARITY_MAX_TURNS" >&2
    else
        echo "Running baseline simulation in $BASELINE_DIR (main): max-turns=$PARITY_MAX_TURNS" >&2
    fi
    set +e
    ( cd "$BASELINE_DIR" && claude --print \
        --max-turns "$PARITY_MAX_TURNS" \
        --allowedTools "$PARITY_ALLOWED_TOOLS" \
        --add-dir "tests/e2e" \
        --output-format json \
        "$PARITY_PROMPT" > "$BASELINE_OUTPUT" 2>"$BASELINE_TMPRUN/claude.err" )
    BASELINE_CLAUDE_RC=$?
    set -e
    if [ "$BASELINE_CLAUDE_RC" -ne 0 ]; then
        echo "Error: baseline simulation failed (rc=$BASELINE_CLAUDE_RC)" >&2
        [ -s "$BASELINE_TMPRUN/claude.err" ] && sed -n '1,5p' "$BASELINE_TMPRUN/claude.err" >&2
        exit 1
    fi
    if [ ! -s "$BASELINE_OUTPUT" ]; then
        echo "Error: baseline simulation output empty" >&2
        exit 1
    fi
    set +e
    BASELINE_EVAL=$("$EVALUATOR" "$SCENARIO_FILE" "$BASELINE_OUTPUT" --json 2>"$BASELINE_TMPRUN/eval.err")
    BASELINE_EVAL_RC=$?
    set -e
    if [ "$BASELINE_EVAL_RC" -ne 0 ] || ! echo "$BASELINE_EVAL" | jq empty 2>/dev/null; then
        echo "Error: baseline evaluator failed (rc=$BASELINE_EVAL_RC)" >&2
        [ -s "$BASELINE_TMPRUN/eval.err" ] && sed -n '1,5p' "$BASELINE_TMPRUN/eval.err" >&2
        exit 1
    fi
    BASELINE_SCORE=$(echo "$BASELINE_EVAL" | jq -r '.score // 0')
    BASELINE_MAX=$(echo "$BASELINE_EVAL" | jq -r '.max_score // 10')
    BASELINE_CRIT=$(echo "$BASELINE_EVAL" | jq -c '.criteria // {}')
    case "$BASELINE_SCORE" in ''|*[!0-9]*) BASELINE_SCORE=0 ;; esac
    case "$BASELINE_MAX" in ''|*[!0-9]*) BASELINE_MAX=10 ;; esac
    [ -z "$BASELINE_CRIT" ] && BASELINE_CRIT='{}'

    # ROADMAP #96 Phase 2 (Codex F-01/F-02): ground-truth gate on baseline.
    # Path resolves relative to $BASELINE_DIR (which contains a fresh
    # checkout — for non-strip mode) or the intact-fixture sibling (strip
    # mode). Fixture lives at tests/e2e/fixtures/test-repo within either.
    BASELINE_ORIGINAL_SCORE="$BASELINE_SCORE"
    BASELINE_GT_FIXTURE="${SDLC_SHEPHERD_BASELINE_FIXTURE_DIR:-$BASELINE_DIR/tests/e2e/fixtures/test-repo}"
    BASELINE_GATE_RESULT=$(run_gate "$BASELINE_GT_FIXTURE" "$BASELINE_SCORE")
    BASELINE_TESTS_RUN=$(echo "$BASELINE_GATE_RESULT" | cut -d'|' -f1)
    BASELINE_TESTS_PASS=$(echo "$BASELINE_GATE_RESULT" | cut -d'|' -f2)
    BASELINE_SCORE=$(echo "$BASELINE_GATE_RESULT" | cut -d'|' -f3)
    BASELINE_GATED=$(echo "$BASELINE_GATE_RESULT" | cut -d'|' -f4)
    if [ "$BASELINE_GATED" = "true" ]; then
        echo "Baseline ground-truth gate: tests failed → score capped (judge gave $BASELINE_ORIGINAL_SCORE/$BASELINE_MAX)" >&2
    fi

    # Codex P1 #1: do NOT append the baseline row here. Defer to after the
    # candidate sim+eval succeeds — otherwise a candidate failure leaves an
    # orphan baseline row in history with no comparison partner. Both rows
    # are written together at the end, or neither is.
    if [ -n "$STRIP_PATHS" ]; then
        echo "Baseline score: $BASELINE_SCORE/$BASELINE_MAX (intact fixture)" >&2
    else
        echo "Baseline score: $BASELINE_SCORE/$BASELINE_MAX (main)" >&2
    fi
fi

echo "Running simulation: max-turns=$PARITY_MAX_TURNS" >&2
# LS-002: hard-fail on claude error. Previously `|| true` swallowed failures,
# so a crashed sim still produced score=0 as if it had completed. Now a
# non-zero claude exit propagates to the shepherd's exit.
# In --strip-paths mode, the candidate runs in CANDIDATE_DIR (fixture stripped)
# instead of REPO_ROOT, so the agent's view of the project mirrors the prove-it
# semantic. Default mode runs in REPO_ROOT (current branch's working tree).
set +e
if [ -n "$CANDIDATE_DIR" ] && [ -d "$CANDIDATE_DIR" ]; then
    ( cd "$CANDIDATE_DIR" && claude --print \
        --max-turns "$PARITY_MAX_TURNS" \
        --allowedTools "$PARITY_ALLOWED_TOOLS" \
        --add-dir "tests/e2e" \
        --output-format json \
        "$PARITY_PROMPT" > "$OUTPUT_FILE" 2>"$TMPRUN/claude.err" )
else
    claude --print \
        --max-turns "$PARITY_MAX_TURNS" \
        --allowedTools "$PARITY_ALLOWED_TOOLS" \
        --add-dir "tests/e2e" \
        --output-format json \
        "$PARITY_PROMPT" > "$OUTPUT_FILE" 2>"$TMPRUN/claude.err"
fi
CLAUDE_RC=$?
set -e
if [ "$CLAUDE_RC" -ne 0 ]; then
    echo "Error: claude simulation failed (rc=$CLAUDE_RC)" >&2
    [ -s "$TMPRUN/claude.err" ] && sed -n '1,5p' "$TMPRUN/claude.err" >&2
    exit 1
fi

# ---- Score (LS-002: hard-fail on evaluator error) ----
# Previously the evaluator's non-zero exit silently became score=0/10 + an
# empty criteria object, indistinguishable from a real failing simulation.
# Now evaluator failures propagate: the shepherd exits 1 and nothing is
# appended to score-history. Set SDLC_SHEPHERD_SOFT_FAIL=1 to restore the
# old permissive behavior (useful for smoke testing, not for CI).
if [ ! -x "$EVALUATOR" ]; then
    echo "Error: evaluator not executable at $EVALUATOR" >&2
    exit 1
fi
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "Error: simulation output is empty — cannot evaluate" >&2
    exit 1
fi

set +e
EVAL_JSON=$("$EVALUATOR" "$SCENARIO_FILE" "$OUTPUT_FILE" --json 2>"$TMPRUN/eval.err")
EVAL_RC=$?
set -e
if [ "$EVAL_RC" -ne 0 ]; then
    if [ "${SDLC_SHEPHERD_SOFT_FAIL:-0}" = "1" ]; then
        echo "Warning: evaluator rc=$EVAL_RC — continuing in soft-fail mode" >&2
        EVAL_JSON='{}'
    else
        echo "Error: evaluator failed (rc=$EVAL_RC)" >&2
        [ -s "$TMPRUN/eval.err" ] && sed -n '1,5p' "$TMPRUN/eval.err" >&2
        exit 1
    fi
fi
# Validate JSON; if jq rejects (e.g., stdout mixed with stderr), hard-fail
# unless soft-fail is on.
if ! echo "$EVAL_JSON" | jq empty 2>/dev/null; then
    if [ "${SDLC_SHEPHERD_SOFT_FAIL:-0}" = "1" ]; then
        EVAL_JSON='{}'
    else
        echo "Error: evaluator emitted non-JSON output" >&2
        exit 1
    fi
fi
SCORE=$(echo "$EVAL_JSON" | jq -r '.score // 0' 2>/dev/null)
MAX_SCORE=$(echo "$EVAL_JSON" | jq -r '.max_score // 10' 2>/dev/null)
CRIT=$(echo "$EVAL_JSON" | jq -c '.criteria // {}' 2>/dev/null)
case "$SCORE" in ''|*[!0-9]*) SCORE=0 ;; esac
case "$MAX_SCORE" in ''|*[!0-9]*) MAX_SCORE=10 ;; esac
[ -z "$CRIT" ] && CRIT='{}'

# ---- ROADMAP #96 Phase 2: ground-truth gate (candidate / single-mode) ----
# Path resolves to $CANDIDATE_DIR/.../test-repo in compare-baseline mode
# (Codex F-01) or cwd-relative in single-mode. Override with
# SDLC_SHEPHERD_FIXTURE_DIR for tests.
ORIGINAL_SCORE="$SCORE"
if [ "$COMPARE_BASELINE" = "1" ] && [ -n "$CANDIDATE_DIR" ]; then
    # --strip-paths mode: candidate sim ran in $CANDIDATE_DIR (Codex F-01).
    # The fixture's there too; the agent's edits don't touch the working repo.
    GT_FIXTURE_DIR="${SDLC_SHEPHERD_FIXTURE_DIR:-$CANDIDATE_DIR/tests/e2e/fixtures/test-repo}"
else
    # Single mode OR default --compare-baseline: candidate sim runs in REPO_ROOT
    # (current branch's working tree) → cwd-relative fixture path.
    GT_FIXTURE_DIR="${SDLC_SHEPHERD_FIXTURE_DIR:-tests/e2e/fixtures/test-repo}"
fi
GATE_RESULT=$(run_gate "$GT_FIXTURE_DIR" "$SCORE")
TESTS_RUN=$(echo "$GATE_RESULT" | cut -d'|' -f1)
TESTS_PASS=$(echo "$GATE_RESULT" | cut -d'|' -f2)
SCORE=$(echo "$GATE_RESULT" | cut -d'|' -f3)
GROUND_TRUTH_GATED=$(echo "$GATE_RESULT" | cut -d'|' -f4)
if [ "$GROUND_TRUTH_GATED" = "true" ]; then
    echo "Ground-truth gate: tests failed → score capped (judge gave $ORIGINAL_SCORE/$MAX_SCORE)" >&2
fi

# Provenance fields were computed once before the baseline run (see above).
# Append history rows. When --compare-baseline is set, both baseline AND
# candidate rows are written here (deferred from the baseline block per
# Codex P1 #1 — atomic so a candidate failure can't leave an orphan row).
# Single-run mode omits comparison_role for backward compat.
mkdir -p "$(dirname "$HISTORY_FILE")"
if [ "$COMPARE_BASELINE" = "1" ]; then
    # Baseline row first (deferred from baseline block). Includes ground-
    # truth telemetry from the per-row gate (Codex F-02).
    jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg scenario "$SCENARIO_NAME" \
        --argjson score "$BASELINE_SCORE" \
        --argjson max_score "$BASELINE_MAX" \
        --argjson criteria "$BASELINE_CRIT" \
        --arg execution_path "$EXECUTION_PATH" \
        --arg host_os "$HOST_OS" \
        --arg cli_version "$CLI_VERSION" \
        --arg claude_code_version "$CLAUDE_CODE_VERSION" \
        --arg auth_mode "$AUTH_MODE" \
        --arg comparison_role "baseline" \
        --argjson pr_number "$PR_NUMBER" \
        --argjson original_judge_score "$BASELINE_ORIGINAL_SCORE" \
        --argjson tests_run "$BASELINE_TESTS_RUN" \
        --argjson tests_pass "$BASELINE_TESTS_PASS" \
        --argjson ground_truth_gated "$BASELINE_GATED" \
        '{timestamp:$ts, scenario:$scenario, score:$score, max_score:$max_score, criteria:$criteria, execution_path:$execution_path, host_os:$host_os, cli_version:$cli_version, claude_code_version:$claude_code_version, auth_mode:$auth_mode, comparison_role:$comparison_role, pr_number:$pr_number, original_judge_score:$original_judge_score, tests_run:$tests_run, tests_pass:$tests_pass, ground_truth_gated:$ground_truth_gated}' \
        >> "$HISTORY_FILE"
    # Candidate row second.
    jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg scenario "$SCENARIO_NAME" \
        --argjson score "$SCORE" \
        --argjson max_score "$MAX_SCORE" \
        --argjson criteria "$CRIT" \
        --arg execution_path "$EXECUTION_PATH" \
        --arg host_os "$HOST_OS" \
        --arg cli_version "$CLI_VERSION" \
        --arg claude_code_version "$CLAUDE_CODE_VERSION" \
        --arg auth_mode "$AUTH_MODE" \
        --arg comparison_role "candidate" \
        --argjson pr_number "$PR_NUMBER" \
        --argjson original_judge_score "$ORIGINAL_SCORE" \
        --argjson tests_run "$TESTS_RUN" \
        --argjson tests_pass "$TESTS_PASS" \
        --argjson ground_truth_gated "$GROUND_TRUTH_GATED" \
        '{timestamp:$ts, scenario:$scenario, score:$score, max_score:$max_score, criteria:$criteria, execution_path:$execution_path, host_os:$host_os, cli_version:$cli_version, claude_code_version:$claude_code_version, auth_mode:$auth_mode, comparison_role:$comparison_role, pr_number:$pr_number, original_judge_score:$original_judge_score, tests_run:$tests_run, tests_pass:$tests_pass, ground_truth_gated:$ground_truth_gated}' \
        >> "$HISTORY_FILE"
else
    jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg scenario "$SCENARIO_NAME" \
        --argjson score "$SCORE" \
        --argjson max_score "$MAX_SCORE" \
        --argjson criteria "$CRIT" \
        --arg execution_path "$EXECUTION_PATH" \
        --arg host_os "$HOST_OS" \
        --arg cli_version "$CLI_VERSION" \
        --arg claude_code_version "$CLAUDE_CODE_VERSION" \
        --arg auth_mode "$AUTH_MODE" \
        --argjson pr_number "$PR_NUMBER" \
        --argjson original_score "$ORIGINAL_SCORE" \
        --argjson tests_run "$TESTS_RUN" \
        --argjson tests_pass "$TESTS_PASS" \
        --argjson ground_truth_gated "$GROUND_TRUTH_GATED" \
        '{timestamp:$ts, scenario:$scenario, score:$score, max_score:$max_score, criteria:$criteria, execution_path:$execution_path, host_os:$host_os, cli_version:$cli_version, claude_code_version:$claude_code_version, auth_mode:$auth_mode, pr_number:$pr_number, original_judge_score:$original_score, tests_run:$tests_run, tests_pass:$tests_pass, ground_truth_gated:$ground_truth_gated}' \
        >> "$HISTORY_FILE"
fi

echo "Score $SCORE/$MAX_SCORE appended to $HISTORY_FILE" >&2

# ---- ROADMAP #230: comparison summary (compare-baseline mode) ----
if [ "$COMPARE_BASELINE" = "1" ]; then
    DELTA=$((SCORE - BASELINE_SCORE))
    DELTA_SIGN="+"
    [ "$DELTA" -lt 0 ] && DELTA_SIGN=""
    if [ -n "$STRIP_PATHS" ]; then
        echo "Comparison (prove-it, same-commit): intact-fixture=$BASELINE_SCORE/$BASELINE_MAX, stripped-fixture=$SCORE/$MAX_SCORE, delta=${DELTA_SIGN}${DELTA}" >&2
    else
        echo "Comparison: baseline=$BASELINE_SCORE/$BASELINE_MAX, candidate=$SCORE/$MAX_SCORE, delta=${DELTA_SIGN}${DELTA}" >&2
    fi
fi

# ---- Dry-run: stop before side effects ----
if [ "${SDLC_LOCAL_SHEPHERD_DRY_RUN:-0}" = "1" ]; then
    echo "DRY_RUN: skipping check-run POST + PR comment" >&2
    exit 0
fi

# ---- Post GitHub check-run (Codex P1 #4) ----
# Use a dedicated check name (`e2e-local-shepherd`) — don't collide with CI's
# `e2e-quick-check`. Branch protection can opt-in by adding this name to its
# required-checks list.
REPO_NWO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || echo "BaseInfinity/claude-sdlc-wizard")
HEAD_SHA=$(gh pr view "$PR_NUMBER" --json headRefOid --jq .headRefOid 2>/dev/null || echo "")

CONCLUSION="success"
if [ "$SCORE" -lt 5 ]; then CONCLUSION="failure"; fi

if [ -z "$HEAD_SHA" ]; then
    echo "Error: could not resolve PR head SHA for check-run POST" >&2
    exit 1
fi

# Build check-run + PR-comment fields. Three modes — single-run, cross-commit
# compare-baseline (main vs PR), and same-commit strip-paths (intact vs stripped).
# Codex P1 #3 round 1: strip mode must NOT label as "main"/"PR" because both
# runs are on the same commit; the variable is the fixture's contents.
PRETTY_STRIPPED=""
if [ -n "$STRIP_PATHS" ]; then
    PRETTY_STRIPPED=$(echo "$VALID_STRIP" | tr '\n' ',' | sed 's/,$//;s/,/, /g')
fi
if [ "$COMPARE_BASELINE" = "1" ] && [ -n "$STRIP_PATHS" ]; then
    CHECKRUN_TITLE="E2E Shepherd (prove-it): ${SCORE}/${MAX_SCORE} stripped vs baseline ${BASELINE_SCORE}/${BASELINE_MAX} intact (${DELTA_SIGN}${DELTA})"
    CHECKRUN_SUMMARY="Local-Max E2E prove-it comparison for PR #$PR_NUMBER on scenario \`$SCENARIO_NAME\`. Baseline (intact fixture): ${BASELINE_SCORE}/${BASELINE_MAX}. Candidate (stripped fixture: ${PRETTY_STRIPPED}): ${SCORE}/${MAX_SCORE}. Delta: ${DELTA_SIGN}${DELTA}. Same-commit comparison. Execution path: local-max ($HOST_OS, claude $CLI_VERSION)."
elif [ "$COMPARE_BASELINE" = "1" ]; then
    CHECKRUN_TITLE="E2E Shepherd: ${SCORE}/${MAX_SCORE} vs baseline ${BASELINE_SCORE}/${BASELINE_MAX} (${DELTA_SIGN}${DELTA})"
    CHECKRUN_SUMMARY="Local-Max E2E comparison for PR #$PR_NUMBER on scenario \`$SCENARIO_NAME\`. Baseline (main): ${BASELINE_SCORE}/${BASELINE_MAX}. Candidate (PR): ${SCORE}/${MAX_SCORE}. Delta: ${DELTA_SIGN}${DELTA}. Execution path: local-max ($HOST_OS, claude $CLI_VERSION)."
else
    CHECKRUN_TITLE="E2E Shepherd: $SCORE/$MAX_SCORE ($SCENARIO_NAME)"
    CHECKRUN_SUMMARY="Local-Max E2E simulation for PR #$PR_NUMBER scored $SCORE/$MAX_SCORE on scenario \`$SCENARIO_NAME\`. Execution path: local-max ($HOST_OS, claude $CLI_VERSION)."
fi

# LS-002: check-run POST failure is hard-fail. If branch protection is
# waiting on e2e-local-shepherd, a silent warning isn't enough — we must
# surface that the gate was never satisfied. Set SDLC_SHEPHERD_SOFT_FAIL=1
# to downgrade to a warning (for debugging).
set +e
gh api "repos/$REPO_NWO/check-runs" \
    --method POST \
    --field "name=e2e-local-shepherd" \
    --field "head_sha=$HEAD_SHA" \
    --field "status=completed" \
    --field "conclusion=$CONCLUSION" \
    --field "output[title]=$CHECKRUN_TITLE" \
    --field "output[summary]=$CHECKRUN_SUMMARY" \
    >"$TMPRUN/checkrun.out" 2>"$TMPRUN/checkrun.err"
CHECKRUN_RC=$?
set -e
if [ "$CHECKRUN_RC" -ne 0 ]; then
    if [ "${SDLC_SHEPHERD_SOFT_FAIL:-0}" = "1" ]; then
        echo "Warning: check-run POST failed (rc=$CHECKRUN_RC) — continuing in soft-fail mode" >&2
    else
        echo "Error: check-run POST failed (rc=$CHECKRUN_RC)" >&2
        [ -s "$TMPRUN/checkrun.err" ] && sed -n '1,5p' "$TMPRUN/checkrun.err" >&2
        exit 1
    fi
fi

# ---- Post PR comment ----
COMMENT_FILE="$TMPRUN/comment.md"
if [ "$COMPARE_BASELINE" = "1" ] && [ -n "$STRIP_PATHS" ]; then
    cat > "$COMMENT_FILE" <<EOF
## Local-Max E2E Shepherd — Prove-It (Intact vs Stripped Fixture)

**Scenario:** \`$SCENARIO_NAME\` (same scenario, same commit, both runs)
**Baseline (intact fixture):** ${BASELINE_SCORE}/${BASELINE_MAX}
**Candidate (stripped fixture):** ${SCORE}/${MAX_SCORE}
**Stripped paths:** \`${PRETTY_STRIPPED}\`
**Delta:** **${DELTA_SIGN}${DELTA}**

<details><summary>Provenance</summary>

- host: \`$HOST_OS\`
- claude: \`$CLI_VERSION\`
- auth: \`$AUTH_MODE\` (sim + evaluator, ROADMAP #228 closed v1.59.0)
- execution_path: \`$EXECUTION_PATH\`
- comparison_role: \`baseline\` + \`candidate\` (rows tagged in score-history.jsonl)
- mode: same-commit prove-it (no main worktree)

</details>

> One-run-per-side delta — useful as advisory signal, not statistical evidence.
> For variance-aware comparison, see ROADMAP #212 (i) Prove-It Gate (paired N=15 runs).
> Run: \`tests/e2e/local-shepherd.sh $PR_NUMBER --compare-baseline --strip-paths '$STRIP_PATHS'\`
EOF
elif [ "$COMPARE_BASELINE" = "1" ]; then
    cat > "$COMMENT_FILE" <<EOF
## Local-Max E2E Shepherd — Baseline vs Candidate

**Scenario:** \`$SCENARIO_NAME\` (same scenario for both runs)
**Baseline (main):** ${BASELINE_SCORE}/${BASELINE_MAX}
**Candidate (PR):** ${SCORE}/${MAX_SCORE}
**Delta:** **${DELTA_SIGN}${DELTA}**

<details><summary>Provenance</summary>

- host: \`$HOST_OS\`
- claude: \`$CLI_VERSION\`
- auth: \`$AUTH_MODE\` (sim + evaluator, ROADMAP #228 closed v1.59.0)
- execution_path: \`$EXECUTION_PATH\`
- comparison_role: \`baseline\` + \`candidate\` (rows tagged in score-history.jsonl)

</details>

> One-run-per-side delta — useful as advisory signal, not statistical evidence.
> For variance-aware comparison, see ROADMAP #212 (i) Prove-It Gate (paired N=15 runs).
> Run: \`tests/e2e/local-shepherd.sh $PR_NUMBER --compare-baseline\`
EOF
else
    cat > "$COMMENT_FILE" <<EOF
## Local-Max E2E Shepherd

**Scenario:** \`$SCENARIO_NAME\`
**Score:** **$SCORE/$MAX_SCORE** ($CONCLUSION)
**Execution path:** \`local-max\` — simulation on Max subscription, zero API for sim leg.

<details><summary>Provenance</summary>

- host: \`$HOST_OS\`
- claude: \`$CLI_VERSION\`
- auth: \`$AUTH_MODE\` (sim + evaluator, ROADMAP #228 closed v1.59.0)
- execution_path: \`$EXECUTION_PATH\`

</details>

> Run: \`tests/e2e/local-shepherd.sh $PR_NUMBER\`
EOF
fi

gh pr comment "$PR_NUMBER" --body-file "$COMMENT_FILE" >/dev/null 2>&1 || \
    echo "Warning: PR comment failed (non-fatal)" >&2

if [ "$COMPARE_BASELINE" = "1" ] && [ -n "$STRIP_PATHS" ]; then
    echo "Done: stripped-fixture $SCORE/$MAX_SCORE, intact-fixture $BASELINE_SCORE/$BASELINE_MAX, delta ${DELTA_SIGN}${DELTA} (prove-it, same-commit)" >&2
elif [ "$COMPARE_BASELINE" = "1" ]; then
    echo "Done: candidate $SCORE/$MAX_SCORE, baseline $BASELINE_SCORE/$BASELINE_MAX, delta ${DELTA_SIGN}${DELTA}" >&2
else
    echo "Done: score $SCORE/$MAX_SCORE, conclusion=$CONCLUSION" >&2
fi
exit 0
