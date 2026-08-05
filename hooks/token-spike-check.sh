#!/bin/bash
# SessionStart hook — token-spike anomaly detection (ROADMAP #220).
#
# Reads CC transcript history, computes per-session token burn, and warns
# if the last completed session's burn deviates >2σ above the rolling median.
# Catches silent CC-side regressions (caching bugs, prompt-inflation defaults)
# that only otherwise surface on the invoice. Reference: Anthropic 2026-04-23
# post-mortem on the dropped-thinking-blocks caching bug.
#
# Gated on `.metrics/` directory existing in the project root — opt-in for
# consumers, on-by-default for the wizard repo (which already maintains
# `.metrics/catches.jsonl` for the effectiveness scoreboard).
#
# Non-blocking: always exits 0.

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { read_stdin_bounded > /dev/null || true; exit 0; }

# Drain stdin (SessionStart sends JSON; we don't need any of it)
read_stdin_bounded > /dev/null || true

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Gate 1: opt-in via .metrics/ directory
[ -d "$ROOT/.metrics" ] || exit 0

# Gate 2: analytics script must exist. Resolve hook-relative first so the
# wizard repo's hook always finds its own analytics regardless of how
# CLAUDE_PROJECT_DIR is set (e.g., test fixtures pointing at a tmp dir).
# Fall back to project-relative for consumer forks that ship the script.
ANALYTICS=""
for candidate in \
    "$HOOK_DIR/../tests/e2e/token-analytics.sh" \
    "$ROOT/tests/e2e/token-analytics.sh"; do
    if [ -x "$candidate" ]; then
        ANALYTICS="$candidate"
        break
    fi
done
[ -n "$ANALYTICS" ] || exit 0

# Gate 3: jq is required by the analytics script
command -v jq > /dev/null 2>&1 || exit 0

ARGS=(--history "$ROOT/.metrics/token-history.jsonl" --ingest --check)

# Test override: SDLC_TOKEN_SPIKE_TRANSCRIPT_DIR points the ingest at a
# fixture directory instead of the real ~/.claude/projects/... path.
if [ -n "$SDLC_TOKEN_SPIKE_TRANSCRIPT_DIR" ]; then
    ARGS+=(--transcript-dir "$SDLC_TOKEN_SPIKE_TRANSCRIPT_DIR" --no-skip-recent)
fi

OUTPUT=$("$ANALYTICS" "${ARGS[@]}" 2>&1) || true
[ -n "$OUTPUT" ] && echo "$OUTPUT"

exit 0
