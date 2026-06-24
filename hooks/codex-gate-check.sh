#!/bin/bash
# PreToolUse hook — blocks git commit without cross-model review artifact
# Fires on Bash tool; only acts when the command contains "git commit"

set -e

# Skip gate if explicitly overridden (emergency bypass with logged justification)
[ "${CODEX_GATE_SKIP:-}" = "1" ] && exit 0

TOOL_INPUT=$(cat)

COMMAND=$(printf '%s' "$TOOL_INPUT" \
    | grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed 's/"command"[[:space:]]*:[[:space:]]*"//; s/"$//')

case "$COMMAND" in
    *"git commit"*) ;;
    *) exit 0 ;;
esac

REVIEW_FILE=".reviews/handoff.json"

if [ ! -f "$REVIEW_FILE" ]; then
    echo "CROSS-MODEL REVIEW REQUIRED: No .reviews/handoff.json found. Run Codex cross-model review before committing. Set CODEX_GATE_SKIP=1 to bypass with justification."
    exit 0
fi

STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
    | head -1 \
    | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')

case "$STATUS" in
    CERTIFIED|REVIEWED) exit 0 ;;
    *)
        echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json status is '$STATUS' (need REVIEWED or CERTIFIED). Run Codex cross-model review before committing. Set CODEX_GATE_SKIP=1 to bypass with justification."
        exit 0
        ;;
esac
