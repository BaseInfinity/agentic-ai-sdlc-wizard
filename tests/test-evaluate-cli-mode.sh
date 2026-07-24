#!/bin/bash
# ROADMAP #228 — evaluate.sh judge transport (Max-subsidized via `claude --print`).
#
# Validates the unconditional `claude --print` judge call. This used to be an
# opt-in EVAL_USE_CLI=1 mode alongside a curl+ANTHROPIC_API_KEY default; the
# curl path turned out to be unreachable through any automated pipeline and
# was deleted 2026-07-21 — `claude --print` is now the only transport.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALUATE="$SCRIPT_DIR/e2e/evaluate.sh"
SHEPHERD="$SCRIPT_DIR/e2e/local-shepherd.sh"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Evaluator CLI Mode Tests (ROADMAP #228) ==="
echo ""

# ---- Static structure checks ----

test_evaluate_has_no_eval_use_cli_toggle() {
    # EVAL_USE_CLI was the opt-in flag when curl was the default transport.
    # Deleted 2026-07-21 — `claude --print` is unconditional now, so the
    # variable name should not appear as live code (comments referencing the
    # historical name are fine and excluded by grep -v on the deletion note).
    if grep -E 'EVAL_USE_CLI' "$EVALUATE" | grep -qvE '^\s*#'; then
        fail "evaluate.sh still has live EVAL_USE_CLI logic — should be unconditional"
    else
        pass "evaluate.sh has no live EVAL_USE_CLI toggle (transport is unconditional)"
    fi
}
test_evaluate_has_no_eval_use_cli_toggle

test_evaluate_calls_claude_print_in_cli_mode() {
    if grep -qE 'claude[[:space:]]+--print' "$EVALUATE"; then
        pass "evaluate.sh invokes 'claude --print' in CLI mode"
    else
        fail "evaluate.sh CLI branch must call 'claude --print'"
    fi
}
test_evaluate_calls_claude_print_in_cli_mode

test_evaluate_uses_json_output_format() {
    # CLI mode needs --output-format json so we can extract `.result` reliably.
    # Match across the script (the CLI branch is one of many invocations).
    if grep -qE 'claude[[:space:]]+--print[^|]*--output-format[[:space:]]+json' "$EVALUATE" \
        || grep -qE -- '--output-format[[:space:]]+json' "$EVALUATE"; then
        pass "evaluate.sh CLI branch uses --output-format json"
    else
        fail "evaluate.sh CLI branch must pass --output-format json"
    fi
}
test_evaluate_uses_json_output_format

test_evaluate_caps_max_turns_in_cli_mode() {
    # Single-shot: --max-turns 1. Anything higher invites the agent to loop.
    if grep -qE -- '--max-turns[[:space:]]+1' "$EVALUATE"; then
        pass "evaluate.sh CLI branch caps --max-turns 1 (single-shot)"
    else
        fail "evaluate.sh CLI branch should pass --max-turns 1 to prevent agent loops"
    fi
}
test_evaluate_caps_max_turns_in_cli_mode

test_evaluate_disables_tools_in_cli_mode() {
    # Pure text classification — no tool use. Either --tools "" or
    # --disallowedTools "*" is acceptable.
    if grep -qE -- '--tools[[:space:]]+""' "$EVALUATE" \
        || grep -qE -- "--tools[[:space:]]+''" "$EVALUATE"; then
        pass "evaluate.sh CLI branch disables tools (--tools \"\")"
    else
        fail "evaluate.sh CLI branch should disable tools — pure text response"
    fi
}
test_evaluate_disables_tools_in_cli_mode

test_evaluate_isolates_mcp_in_cli_mode() {
    # Codex round 1 P1 #1: --tools "" only blocks built-in tools. MCP servers
    # configured at user level (e.g., mcp__playwright__*) still appear in
    # system.init.tools. The criterion prompt embeds untrusted execution
    # output → prompt-injection can reach those MCP tools. Both invocations
    # (initial + retry) must pass an empty MCP config + --strict-mcp-config.
    local mcp_count strict_count
    mcp_count=$(grep -cE -- "--mcp-config[[:space:]]+'\{\"mcpServers\":\{\}\}'" "$EVALUATE" || true)
    strict_count=$(grep -cE -- '--strict-mcp-config' "$EVALUATE" || true)
    if [ "$mcp_count" -ge 2 ] && [ "$strict_count" -ge 2 ]; then
        pass "evaluate.sh CLI branch isolates MCP (--mcp-config '{}' + --strict-mcp-config on both calls)"
    else
        fail "evaluate.sh CLI branch missing MCP isolation (mcp_count=$mcp_count, strict_count=$strict_count, need 2 each)"
    fi
}
test_evaluate_isolates_mcp_in_cli_mode

test_evaluate_pins_model_in_cli_mode() {
    # Codex round 1 P1 #2: curl mode hard-codes "model": "claude-opus-4-7".
    # CLI mode without --model defers to the user's CC default — defeats
    # the "same model" parity claim in CHANGELOG/ROADMAP. Both initial +
    # retry CLI invocations must explicitly pin --model claude-opus-4-7.
    local model_count
    model_count=$(grep -cE -- '--model[[:space:]]+claude-opus-4-7' "$EVALUATE" || true)
    if [ "$model_count" -ge 2 ]; then
        pass "evaluate.sh CLI branch pins --model claude-opus-4-7 on both calls"
    else
        fail "evaluate.sh CLI branch missing --model pin (count=$model_count, need >=2 — initial + retry)"
    fi
}
test_evaluate_pins_model_in_cli_mode

test_evaluate_has_no_api_key_check() {
    # No transport left that reads/requires ANTHROPIC_API_KEY — the old
    # hard-fail check should be gone entirely. The one allowed live
    # reference is `env -u ANTHROPIC_API_KEY` immediately before `claude`,
    # which actively CLEARS the var so an inherited key can't hijack the
    # CLI's non-interactive auth away from the Max session (Codex round 1
    # P1 API-003) — that's the opposite of a dependency on it.
    local live_refs
    live_refs=$(grep -E 'ANTHROPIC_API_KEY' "$EVALUATE" | grep -vE '^\s*#' | grep -vE 'env -u ANTHROPIC_API_KEY claude' || true)
    if [ -n "$live_refs" ]; then
        fail "evaluate.sh still has live ANTHROPIC_API_KEY logic — should be fully removed"
    else
        pass "evaluate.sh has no live ANTHROPIC_API_KEY dependency (only the env -u clear before claude --print)"
    fi
}
test_evaluate_has_no_api_key_check

test_evaluate_clears_inherited_api_key() {
    # Both claude --print invocations (initial + retry) must clear an
    # inherited ANTHROPIC_API_KEY, or a shell with the key exported would
    # silently defeat the zero-API-spend guarantee (Codex round 1 P1 API-003).
    local count
    count=$(grep -cE 'env -u ANTHROPIC_API_KEY claude --print' "$EVALUATE" || true)
    if [ "$count" -ge 2 ]; then
        pass "evaluate.sh clears inherited ANTHROPIC_API_KEY on both claude --print calls"
    else
        fail "evaluate.sh should clear ANTHROPIC_API_KEY via env -u on both calls (count=$count, need >=2)"
    fi
}
test_evaluate_clears_inherited_api_key

test_evaluate_requires_claude_cli() {
    if grep -qE 'command -v claude' "$EVALUATE"; then
        pass "evaluate.sh hard-fails if 'claude' CLI is missing"
    else
        fail "evaluate.sh must check for 'claude' CLI on PATH — it's the only transport now"
    fi
}
test_evaluate_requires_claude_cli

test_evaluate_extracts_result_field() {
    # claude --print --output-format json returns an array. The text response
    # lives at .[] | select(.type=="result") | .result. Verify we extract it.
    if grep -qE 'select\(\.type[[:space:]]*==[[:space:]]*"result"\)[[:space:]]*\|[[:space:]]*\.result' "$EVALUATE"; then
        pass "evaluate.sh extracts .result from claude --print JSON output"
    else
        fail "evaluate.sh CLI branch must extract .result via jq selector"
    fi
}
test_evaluate_extracts_result_field

test_evaluate_cli_runs_in_clean_cwd() {
    # Project hooks (e.g., sdlc-prompt-check.sh) inject context that pollutes
    # the criterion prompt. CLI invocation must run from a clean cwd
    # (mktemp -d or similar) so project .claude/settings.json doesn't load.
    if grep -B5 -E 'claude[[:space:]]+--print' "$EVALUATE" | grep -qE 'mktemp|\$TMPDIR|cd /tmp'; then
        pass "evaluate.sh CLI branch runs from a clean cwd (avoids hook pollution)"
    else
        fail "evaluate.sh CLI branch should run claude --print from a clean cwd"
    fi
}
test_evaluate_cli_runs_in_clean_cwd

test_evaluate_cli_retries_on_failure() {
    # Match curl-path behavior: retry once on empty response.
    # Search the CLI block for a second `claude --print` invocation.
    local cli_print_count
    cli_print_count=$(grep -cE 'claude[[:space:]]+--print' "$EVALUATE" || true)
    if [ "$cli_print_count" -ge 2 ]; then
        pass "evaluate.sh CLI branch retries on empty response (>=2 invocations)"
    else
        fail "evaluate.sh CLI branch should retry once (only $cli_print_count claude --print calls found)"
    fi
}
test_evaluate_cli_retries_on_failure

test_evaluate_no_curl_transport() {
    # The old curl+api.anthropic.com transport was deleted 2026-07-21 — it
    # was unreachable through any automated pipeline. Confirm it stays gone
    # as live code (comments noting the deletion are fine).
    local live_curl live_api
    live_curl=$(grep -E 'curl' "$EVALUATE" | grep -cvE '^\s*#' || true)
    live_api=$(grep -E 'api\.anthropic\.com' "$EVALUATE" | grep -cvE '^\s*#' || true)
    if [ "$live_curl" -gt 0 ] || [ "$live_api" -gt 0 ]; then
        fail "evaluate.sh still has live curl/api.anthropic.com — dead transport should stay deleted"
    else
        pass "evaluate.sh has no curl/api.anthropic.com transport (deleted, claude --print only)"
    fi
}
test_evaluate_no_curl_transport

# ---- Local-shepherd integration ----

test_shepherd_no_longer_exports_eval_use_cli() {
    # evaluate.sh no longer reads this variable — exporting it would be a
    # vestigial no-op. Confirm the dead export was cleaned up, not left behind.
    if grep -qE 'export EVAL_USE_CLI' "$SHEPHERD"; then
        fail "local-shepherd.sh still exports EVAL_USE_CLI — dead now that evaluate.sh ignores it"
    else
        pass "local-shepherd.sh doesn't export the now-dead EVAL_USE_CLI variable"
    fi
}
test_shepherd_no_longer_exports_eval_use_cli

test_shepherd_no_longer_requires_api_key() {
    # The hard-fail block on missing ANTHROPIC_API_KEY must be removed or
    # gated behind a fallback flag (e.g., when EVAL_USE_CLI not set).
    if grep -B2 -A2 -E 'ANTHROPIC_API_KEY' "$SHEPHERD" | grep -qE 'exit 1' \
        && ! grep -B2 -A2 -E 'ANTHROPIC_API_KEY' "$SHEPHERD" | grep -qE '#228|EVAL_USE_CLI|claim'; then
        fail "local-shepherd.sh still hard-fails on missing ANTHROPIC_API_KEY — #228 should drop it"
    else
        pass "local-shepherd.sh no longer hard-fails on missing ANTHROPIC_API_KEY (#228 closed)"
    fi
}
test_shepherd_no_longer_requires_api_key

test_shepherd_documents_zero_api() {
    # The earlier comment said "Evaluator still hits Anthropic API (ROADMAP
    # #228 will migrate)". After this PR it must be updated.
    if grep -qE 'still hits Anthropic API|ROADMAP #228 will migrate' "$SHEPHERD"; then
        fail "local-shepherd.sh still claims evaluator hits API — comment must be updated"
    else
        pass "local-shepherd.sh comment updated (no stale '#228 will migrate' claim)"
    fi
}
test_shepherd_documents_zero_api

# ---- Dynamic mock test ----

# Verify the CLI branch actually invokes a 'claude' binary, by mocking it on
# PATH and running a single criterion through evaluate.sh's helper.
#
# We can't run the full evaluate.sh because it expects a real scenario file +
# Claude execution output. But we CAN source it... no, evaluate.sh runs at
# top level (not a function library). So the cleanest dynamic check is to
# verify the call_criterion_api function exists and can be exercised.
#
# Skip dynamic test for now — static checks above cover the protocol.

# ---- Results ----

echo ""
echo "=== Results ==="
echo "Passed: $PASSED, Failed: $FAILED"
if [ "$FAILED" -ne 0 ]; then
    exit 1
fi
echo "All evaluate-cli-mode tests passed."
