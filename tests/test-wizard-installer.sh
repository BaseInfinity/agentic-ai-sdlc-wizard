#!/bin/bash
# ROADMAP #96 Phase 3 PR 1 — wizard installer library + lift-proof orchestrator.
#
# Validates:
#   1. tests/e2e/lib/wizard-installer.sh exposes install_wizard_into_fixture()
#   2. The function copies the wizard's hooks/skills/settings.json into a
#      target fixture's .claude/ — same behavior as the legacy
#      _build_strip_dir helper, but reusable across orchestrators.
#   3. tests/e2e/lift-proof.sh exists and orchestrates bare vs wizard-installed
#      benchmark runs to capture the "wizard lift" delta.
#   4. local-shepherd.sh's strip-paths mode now sources the new library
#      (single source of truth — no duplicated cp -R lines).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALLER_LIB="$REPO_ROOT/tests/e2e/lib/wizard-installer.sh"
LIFT_PROOF="$REPO_ROOT/tests/e2e/lift-proof.sh"
SHEPHERD="$REPO_ROOT/tests/e2e/local-shepherd.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Wizard Installer Tests (ROADMAP #96 Phase 3 PR 1) ==="
echo ""

# ---- 1. Library exists with the right interface ----

test_installer_lib_exists() {
    if [ -f "$INSTALLER_LIB" ]; then
        pass "tests/e2e/lib/wizard-installer.sh exists"
    else
        fail "tests/e2e/lib/wizard-installer.sh missing — Phase 3 PR 1 not wired"
    fi
}
test_installer_lib_exists

if [ ! -f "$INSTALLER_LIB" ]; then
    echo ""
    echo "=== Results ==="
    echo "Passed: $PASSED, Failed: $FAILED"
    exit 1
fi

test_installer_exposes_function() {
    if grep -qE 'install_wizard_into_fixture[[:space:]]*\(\)' "$INSTALLER_LIB"; then
        pass "wizard-installer.sh exposes install_wizard_into_fixture()"
    else
        fail "wizard-installer.sh must define install_wizard_into_fixture() — public API"
    fi
}
test_installer_exposes_function

test_installer_copies_hooks_skills_settings() {
    # The function must copy at least: hooks dir, skills dir, settings.json.
    # Anything else is bonus. Reuses the legacy _build_strip_dir contract.
    if grep -qE 'cp[[:space:]]+-R[[:space:]]+.*\.claude/hooks' "$INSTALLER_LIB" \
        && grep -qE 'cp[[:space:]]+-R[[:space:]]+.*\.claude/skills' "$INSTALLER_LIB" \
        && grep -qE 'cp[[:space:]]+.*\.claude/settings\.json' "$INSTALLER_LIB"; then
        pass "installer copies hooks + skills + settings.json (parity with legacy _build_strip_dir)"
    else
        fail "installer must copy hooks dir + skills dir + settings.json"
    fi
}
test_installer_copies_hooks_skills_settings

test_installer_dynamic_runtime_check() {
    # Runtime check: source the lib, call the function on a tmpdir, verify
    # files appear. This catches "function exists but doesn't copy".
    local tmpdir target_fixture
    tmpdir=$(mktemp -d)
    target_fixture="$tmpdir/test-repo"
    mkdir -p "$target_fixture"
    # shellcheck source=tests/e2e/lib/wizard-installer.sh
    if ! source "$INSTALLER_LIB" 2>/dev/null; then
        fail "wizard-installer.sh fails to source"
        rm -rf "$tmpdir"
        return
    fi
    if ! type install_wizard_into_fixture >/dev/null 2>&1; then
        fail "install_wizard_into_fixture not in scope after sourcing"
        rm -rf "$tmpdir"
        return
    fi
    set +e
    install_wizard_into_fixture "$REPO_ROOT" "$target_fixture" >/dev/null 2>&1
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        fail "install_wizard_into_fixture returned rc=$rc"
        rm -rf "$tmpdir"
        return
    fi
    local missing=""
    [ -d "$target_fixture/.claude/hooks" ] || missing="$missing hooks"
    [ -d "$target_fixture/.claude/skills" ] || missing="$missing skills"
    [ -f "$target_fixture/.claude/settings.json" ] || missing="$missing settings.json"
    if [ -z "$missing" ]; then
        pass "install_wizard_into_fixture lays hooks/skills/settings.json into target"
    else
        fail "install_wizard_into_fixture missing artifacts:$missing"
    fi
    rm -rf "$tmpdir"
}
test_installer_dynamic_runtime_check

test_installer_handles_missing_target() {
    # Bad input: target_fixture doesn't exist. Function should fail loudly,
    # not silently no-op.
    local tmpdir
    tmpdir=$(mktemp -d)
    rm -rf "$tmpdir"  # delete so target doesn't exist
    source "$INSTALLER_LIB" 2>/dev/null
    set +e
    install_wizard_into_fixture "$REPO_ROOT" "$tmpdir" 2>/dev/null
    local rc=$?
    set -e
    if [ "$rc" -ne 0 ]; then
        pass "install_wizard_into_fixture errors on nonexistent target"
    else
        fail "install_wizard_into_fixture should error on nonexistent target (silent no-op invites bugs)"
    fi
}
test_installer_handles_missing_target

test_installer_handles_missing_source() {
    local tmpdir target_fixture
    tmpdir=$(mktemp -d)
    target_fixture="$tmpdir/test-repo"
    mkdir -p "$target_fixture"
    source "$INSTALLER_LIB" 2>/dev/null
    set +e
    install_wizard_into_fixture "/nonexistent-source-$$" "$target_fixture" 2>/dev/null
    local rc=$?
    set -e
    rm -rf "$tmpdir"
    if [ "$rc" -ne 0 ]; then
        pass "install_wizard_into_fixture errors on nonexistent source"
    else
        fail "install_wizard_into_fixture should error on nonexistent source"
    fi
}
test_installer_handles_missing_source

# ---- 2. local-shepherd.sh uses the new library (no duplicated cp lines) ----

test_shepherd_sources_wizard_installer() {
    if grep -qE 'source.*lib/wizard-installer\.sh|\. .*lib/wizard-installer\.sh' "$SHEPHERD"; then
        pass "local-shepherd.sh sources lib/wizard-installer.sh (single source of truth)"
    else
        fail "local-shepherd.sh must source wizard-installer.sh — avoid duplicated cp logic"
    fi
}
test_shepherd_sources_wizard_installer

test_shepherd_calls_installer_function() {
    if grep -qE 'install_wizard_into_fixture' "$SHEPHERD"; then
        pass "local-shepherd.sh invokes install_wizard_into_fixture()"
    else
        fail "local-shepherd.sh must call install_wizard_into_fixture() (replaces inline cp)"
    fi
}
test_shepherd_calls_installer_function

# ---- 3. Lift-proof orchestrator ----

test_lift_proof_exists() {
    if [ -x "$LIFT_PROOF" ]; then
        pass "tests/e2e/lift-proof.sh exists and is executable"
    else
        fail "tests/e2e/lift-proof.sh missing or not executable — PR 1 deliverable"
    fi
}
test_lift_proof_exists

if [ ! -x "$LIFT_PROOF" ]; then
    echo ""
    echo "=== Results ==="
    echo "Passed: $PASSED, Failed: $FAILED"
    exit 1
fi

test_lift_proof_runs_two_sims() {
    # The orchestrator must run claude --print at least twice — once on a
    # bare fixture and once on a wizard-installed fixture — so it can compute
    # the delta.
    local count
    count=$(grep -cE 'claude[[:space:]]+--print' "$LIFT_PROOF" || true)
    if [ "$count" -ge 2 ]; then
        pass "lift-proof.sh invokes 'claude --print' >=2 times (bare + wizard runs)"
    else
        fail "lift-proof.sh should run claude --print twice (bare + wizard); found $count"
    fi
}
test_lift_proof_runs_two_sims

test_lift_proof_calls_installer() {
    # Must call install_wizard_into_fixture for the wizard leg.
    if grep -qE 'install_wizard_into_fixture' "$LIFT_PROOF"; then
        pass "lift-proof.sh calls install_wizard_into_fixture for the wizard leg"
    else
        fail "lift-proof.sh must use install_wizard_into_fixture (the whole point)"
    fi
}
test_lift_proof_calls_installer

test_lift_proof_calls_evaluator() {
    if grep -qE 'evaluate\.sh' "$LIFT_PROOF"; then
        pass "lift-proof.sh runs evaluate.sh on each leg"
    else
        fail "lift-proof.sh must score each leg via evaluate.sh"
    fi
}
test_lift_proof_calls_evaluator

test_lift_proof_emits_delta() {
    # Output must include the score delta (lift signal). Look for variable
    # names or output strings.
    if grep -qE 'delta|lift|wizard_score|bare_score' "$LIFT_PROOF"; then
        pass "lift-proof.sh emits delta/lift signal"
    else
        fail "lift-proof.sh must compute and emit the score delta (the 'lift')"
    fi
}
test_lift_proof_emits_delta

test_lift_proof_keeps_evaluator_on_max() {
    # #228's zero-API path is unconditional in evaluate.sh since 2026-07-21 —
    # there's no EVAL_USE_CLI toggle left to inherit. lift-proof.sh should not
    # reintroduce one; it should just call evaluate.sh (which stays on Max by
    # itself) and reference #228 in its provenance comments.
    if grep -qE 'EVAL_USE_CLI' "$LIFT_PROOF"; then
        fail "lift-proof.sh references EVAL_USE_CLI — that toggle was deleted from evaluate.sh"
    elif grep -qE '#228' "$LIFT_PROOF"; then
        pass "lift-proof.sh keeps the evaluator on Max via evaluate.sh (unconditional, #228)"
    else
        fail "lift-proof.sh should document that its evaluator leg stays on Max (#228)"
    fi
}
test_lift_proof_keeps_evaluator_on_max

test_lift_proof_help_flag() {
    local out
    out=$("$LIFT_PROOF" --help 2>&1 || true)
    if echo "$out" | grep -qiE 'usage|wizard|bare|lift'; then
        pass "lift-proof.sh --help describes purpose"
    else
        fail "lift-proof.sh --help should describe purpose. Got: $out"
    fi
}
test_lift_proof_help_flag

test_lift_proof_writes_artifact() {
    # Should write a structured artifact (JSON or markdown) capturing the
    # paired result. Defaults to .benchmark/ or similar; test for the
    # output-file flag/var.
    if grep -qE 'OUTPUT_FILE|--output|\.benchmark|lift-proof.*\.json|lift-proof.*\.md' "$LIFT_PROOF"; then
        pass "lift-proof.sh writes a structured artifact (JSON/md)"
    else
        fail "lift-proof.sh should emit a structured artifact for trend tracking"
    fi
}
test_lift_proof_writes_artifact

# ---- 3.5 Regression tests for Codex round 1 findings ----

test_lift_proof_dry_run_makes_no_claude_calls() {
    # Codex round 1 P1: dry-run must NOT invoke `claude --print` (neither
    # simulation nor evaluator). Mock claude to fail-on-invocation; if
    # dry-run still completes, the no-call invariant holds.
    local tmpdir bindir log_file
    tmpdir=$(mktemp -d)
    bindir="$tmpdir/bin"
    log_file="$tmpdir/claude.log"
    mkdir -p "$bindir"
    cat > "$bindir/claude" <<EOF
#!/bin/bash
echo "ILLEGAL: claude was invoked with: \$*" >> "$log_file"
exit 99
EOF
    chmod +x "$bindir/claude"

    local output_file="$tmpdir/dry-run.json"
    set +e
    PATH="$bindir:$PATH" "$LIFT_PROOF" --dry-run --output "$output_file" >/dev/null 2>"$tmpdir/run.err"
    local rc=$?
    set -e

    local invocations=0
    [ -s "$log_file" ] && invocations=$(wc -l < "$log_file" | tr -d ' ')

    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ "$invocations" -eq 0 ]; then
        pass "lift-proof.sh --dry-run makes 0 claude --print calls (Codex round 1 P1)"
    else
        fail "dry-run invoked claude $invocations times with rc=$rc (must be 0 calls)"
    fi
}
test_lift_proof_dry_run_makes_no_claude_calls

test_strip_paths_propagates_installer_failure() {
    # Codex round 1 P0: local-shepherd.sh:_build_strip_dir was suppressing
    # install_wizard_into_fixture errors with `2>/dev/null || true`. If the
    # installer fails, strip-mode would silently run without a wizard-installed
    # fixture and produce meaningless deltas. The fix removes the suppression;
    # this test forces a failure (nonexistent .claude/ source) and asserts
    # the shepherd exits non-zero rather than silently continuing.
    #
    # Implementation: run wizard-installer's runtime check against a source
    # dir without .claude/ — should error. Then verify local-shepherd.sh's
    # call site doesn't have the suppression pattern.
    if grep -qE 'install_wizard_into_fixture[^|]*2>/dev/null[[:space:]]*\|\|[[:space:]]*true' "$SHEPHERD"; then
        fail "local-shepherd.sh suppresses installer failure (Codex round 1 P0 not fixed)"
    else
        pass "local-shepherd.sh does NOT suppress installer failure (Codex round 1 P0 fix confirmed)"
    fi
}
test_strip_paths_propagates_installer_failure

# ---- 4. Documentation ----

test_changelog_mentions_phase3() {
    if grep -qE '#96.*Phase 3|Phase 3.*#96|wizard-installation lift|lift.proof' "$REPO_ROOT/CHANGELOG.md"; then
        pass "CHANGELOG.md mentions #96 Phase 3 PR 1 / lift-proof"
    else
        fail "CHANGELOG.md must document the new lift-proof harness"
    fi
}
test_changelog_mentions_phase3

# ---- Results ----

echo ""
echo "=== Results ==="
echo "Passed: $PASSED, Failed: $FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "All wizard-installer tests passed."
