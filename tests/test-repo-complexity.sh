#!/bin/bash
# Test cli/lib/repo-complexity.js heuristic
# Heuristic decides whether a repo is "simple" (good fit for Setup B —
# Sonnet 5, Simple/One-Off) or "complex" (Setup A — Opus 5, recommended
# default as of 2026-07-24 — for genuine autonomous/agentic work).
#
# Roadmap #233: introduces repo_complexity signal so setup wizard can suggest
# Setup B for trivial/CRUD repos and reserve Setup A (Opus 5) for
# fixture-deep, multi-workflow, secrets-touching repos.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../cli/lib/repo-complexity.js"
FIXTURES="$SCRIPT_DIR/fixtures/complexity"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Repo Complexity Heuristic Tests (Roadmap #233) ==="
echo ""

# ---- Setup fixtures ----

setup_simple_repo() {
    local dir="$FIXTURES/simple-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src"
    cat > "$dir/src/main.js" <<'EOF'
function add(a, b) { return a + b; }
module.exports = { add };
EOF
    cat > "$dir/package.json" <<'EOF'
{ "name": "tiny", "version": "0.1.0" }
EOF
}

setup_complex_repo() {
    local dir="$FIXTURES/complex-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src" "$dir/tests" "$dir/.claude/hooks" "$dir/.claude/skills" "$dir/.github/workflows"
    # Many test files
    for i in $(seq 1 35); do
        echo "describe('test $i', () => { it('works', () => {}); });" > "$dir/tests/spec-$i.test.js"
    done
    # Many hooks
    for h in pre-commit pre-push prepare-commit lint-check format-check tdd-check; do
        echo "#!/bin/bash" > "$dir/.claude/hooks/$h.sh"
        chmod +x "$dir/.claude/hooks/$h.sh"
    done
    # Many workflows
    for wf in ci pr-review release deploy weekly-update monthly-research; do
        echo "name: $wf" > "$dir/.github/workflows/$wf.yml"
    done
    # Decent LOC
    for i in $(seq 1 50); do
        for j in $(seq 1 20); do
            echo "function fn_${i}_${j}(x) { return x * $j; }"
        done
    done > "$dir/src/main.js"
    cat > "$dir/package.json" <<'EOF'
{ "name": "complex-repo", "version": "0.1.0" }
EOF
}

setup_stakes_repo() {
    local dir="$FIXTURES/stakes-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src"
    echo "function noop() {}" > "$dir/src/main.js"
    # .env file forces complex regardless of size
    cat > "$dir/.env" <<'EOF'
API_KEY=fake
DATABASE_URL=postgres://fake
EOF
    cat > "$dir/package.json" <<'EOF'
{ "name": "stakes-tiny", "version": "0.1.0" }
EOF
}

# Codex finding #2: stakes detection must work at any depth.
setup_nested_stakes_repo() {
    local dir="$FIXTURES/nested-stakes-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src" "$dir/config" "$dir/app/secrets"
    echo "function noop() {}" > "$dir/src/main.js"
    cat > "$dir/config/.env" <<'EOF'
API_KEY=fake-nested
EOF
    cat > "$dir/app/secrets/token.txt" <<'EOF'
fake-token
EOF
}

# Codex finding #3: just-below-threshold repo must classify as simple.
# Per docs: simple = LOC<10K AND tests<30 AND hooks<5 AND workflows<5 AND no stakes.
# Hits 4 mid signals; total score=4 but no high signals → simple.
setup_boundary_simple_repo() {
    local dir="$FIXTURES/boundary-simple-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src" "$dir/tests" "$dir/.claude/hooks" "$dir/.github/workflows"
    # 29 tests (just below high threshold of 30)
    for i in $(seq 1 29); do
        echo "describe('test $i', () => { it('works', () => {}); });" > "$dir/tests/spec-$i.test.js"
    done
    # 4 hooks (just below high threshold of 5)
    for h in pre-commit pre-push lint format; do
        echo "#!/bin/bash" > "$dir/.claude/hooks/$h.sh"
    done
    # 4 workflows (just below high threshold of 5)
    for wf in ci pr-review release deploy; do
        echo "name: $wf" > "$dir/.github/workflows/$wf.yml"
    done
    # ~9000 LOC (just below high threshold of 10000)
    for i in $(seq 1 450); do echo "// line filler $i: const x = $i;"; done > "$dir/src/main.js"
}

# Boundary complex: bump just one signal over its threshold → must classify as complex.
setup_boundary_complex_repo() {
    local dir="$FIXTURES/boundary-complex-repo"
    rm -rf "$dir"
    mkdir -p "$dir/src" "$dir/tests"
    # 30 tests = high → complex
    for i in $(seq 1 30); do
        echo "describe('test $i', () => { it('works', () => {}); });" > "$dir/tests/spec-$i.test.js"
    done
    echo "function tiny() {}" > "$dir/src/main.js"
}

setup_simple_repo
setup_complex_repo
setup_stakes_repo
setup_nested_stakes_repo
setup_boundary_simple_repo
setup_boundary_complex_repo

# ---- Tests ----

test_lib_exists() {
    if [ -f "$LIB" ]; then
        pass "cli/lib/repo-complexity.js exists"
    else
        fail "cli/lib/repo-complexity.js not found"
    fi
}

test_simple_repo_classified_simple() {
    local out tier
    out=$(node "$LIB" "$FIXTURES/simple-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "simple" ]; then
        pass "simple repo classified as 'simple' (got: $tier)"
    else
        fail "simple repo classified as '$tier' (expected 'simple'). Output: $out"
    fi
}

test_complex_repo_classified_complex() {
    local out tier
    out=$(node "$LIB" "$FIXTURES/complex-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "complex" ]; then
        pass "complex repo classified as 'complex' (got: $tier)"
    else
        fail "complex repo classified as '$tier' (expected 'complex'). Output: $out"
    fi
}

test_stakes_repo_forces_complex() {
    local out tier reasons
    out=$(node "$LIB" "$FIXTURES/stakes-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "complex" ] && echo "$out" | /usr/bin/grep -qiE 'env|stake|secret'; then
        pass "stakes repo (with .env) forced to 'complex' with reason"
    else
        fail "stakes repo got '$tier' without env/stakes reason. Output: $out"
    fi
}

test_outputs_valid_json() {
    local out
    out=$(node "$LIB" "$FIXTURES/simple-repo" 2>&1)
    if echo "$out" | python3 -c "import sys, json; json.load(sys.stdin)" 2>/dev/null; then
        pass "outputs valid JSON"
    else
        fail "output is not valid JSON: $out"
    fi
}

test_includes_signals() {
    local out
    out=$(node "$LIB" "$FIXTURES/complex-repo" 2>&1)
    if echo "$out" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'signals' in d and isinstance(d['signals'], list); assert len(d['signals']) > 0; print('ok')" 2>/dev/null | /usr/bin/grep -q ok; then
        pass "output includes non-empty signals array"
    else
        fail "output missing signals or empty. Output: $out"
    fi
}

test_handles_missing_dir_gracefully() {
    local out exit_code
    out=$(node "$LIB" "/nonexistent-path-12345" 2>&1) || exit_code=$?
    if [ "${exit_code:-0}" -ne 0 ] || echo "$out" | /usr/bin/grep -qi error; then
        pass "missing dir is reported as error (exit $exit_code or 'error' in output)"
    else
        fail "missing dir did not produce error. Output: $out, exit: ${exit_code:-0}"
    fi
}

test_nested_env_forces_complex() {
    local out tier signals
    out=$(node "$LIB" "$FIXTURES/nested-stakes-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "complex" ] && echo "$out" | /usr/bin/grep -q "config/.env" && echo "$out" | /usr/bin/grep -qE "stakes:dir:.*secrets"; then
        pass "nested .env (config/.env) and nested secrets/ dir detected and force complex"
    else
        fail "nested stakes not detected. tier=$tier. Output: $out"
    fi
}

test_boundary_simple_classified_simple() {
    # Per docs: LOC<10K, tests<30, hooks<5, workflows<5, no stakes → simple
    # Even if all four signals are mid-band (additive score=4), no high → simple.
    local out tier
    out=$(node "$LIB" "$FIXTURES/boundary-simple-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "simple" ]; then
        pass "boundary-simple repo (29 tests, 4 hooks, 4 workflows, ~9K LOC) → simple"
    else
        fail "boundary-simple repo classified as '$tier' (expected 'simple'). Output: $out"
    fi
}

test_boundary_complex_classified_complex() {
    # 30 tests crosses the high threshold → must classify as complex.
    local out tier
    out=$(node "$LIB" "$FIXTURES/boundary-complex-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "complex" ]; then
        pass "boundary-complex repo (30 tests = high threshold) → complex"
    else
        fail "boundary-complex repo classified as '$tier' (expected 'complex'). Output: $out"
    fi
}

test_cli_complexity_subcommand() {
    # Codex finding #1: docs reference `npx agentic-sdlc-wizard complexity .` — must work via the CLI bin
    local cli="$SCRIPT_DIR/../cli/bin/sdlc-wizard.js"
    local out tier
    out=$(node "$cli" complexity "$FIXTURES/simple-repo" 2>&1)
    tier=$(echo "$out" | /usr/bin/grep -oE '"tier"[[:space:]]*:[[:space:]]*"[a-z]+"' | head -1 | /usr/bin/grep -oE '"[a-z]+"$' | tr -d '"')
    if [ "$tier" = "simple" ]; then
        pass "CLI subcommand 'complexity' works and returns valid output"
    else
        fail "CLI subcommand 'complexity' did not return tier=simple. Output: $out"
    fi
}

test_lib_exists
test_simple_repo_classified_simple
test_complex_repo_classified_complex
test_stakes_repo_forces_complex
test_nested_env_forces_complex
test_boundary_simple_classified_simple
test_boundary_complex_classified_complex
test_cli_complexity_subcommand
test_outputs_valid_json
test_includes_signals
test_handles_missing_dir_gracefully

echo ""
echo "=== Results ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    exit 1
fi
echo "All tests passed."
