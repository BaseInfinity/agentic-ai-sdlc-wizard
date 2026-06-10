#!/bin/bash
# SessionStart hook — effort/model nudge.
#
# Behavior (#395 update):
#   CLAUDE_CODE_EFFORT_LEVEL env var takes precedence over effortLevel in settings.
#   CC docs: max is session-only in settings.json — only the env var persists it.
#   Opus 4.6 supports: low, medium, high, max (NO xhigh — falls back to high).
#
#   effort=max   -> silent (only acceptable level)
#   anything else -> LOUD WARNING
#
# Non-blocking: always exits 0.

RECOMMENDED_MODEL="claude-opus-4-6[1m]"

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { cat > /dev/null; exit 0; }

cat > /dev/null

if ! command -v jq > /dev/null 2>&1; then
    exit 0
fi

# Env var takes precedence (CC docs: only way to persist max)
effort="${CLAUDE_CODE_EFFORT_LEVEL:-}"
settings_max=0

if [ -z "$effort" ]; then
    project_dir="${CLAUDE_PROJECT_DIR:-.}"
    for f in "$project_dir/.claude/settings.local.json" "$project_dir/.claude/settings.json" "$HOME/.claude/settings.json"; do
        if [ -f "$f" ]; then
            val=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
            if [ -n "$val" ]; then
                effort="$val"
                [ "$val" = "max" ] && settings_max=1
                break
            fi
        fi
    done
fi

# Only max is acceptable — user preference: always run highest available.
case "$effort" in
    max)
        # Warn if max is in settings (CC ignores it there) without env var
        if [ "$settings_max" -eq 1 ] && [ -z "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
            echo "NOTE: effortLevel: max in settings is session-only (CC ignores it)."
            echo " Persist: add CLAUDE_CODE_EFFORT_LEVEL=max to settings env block."
        fi
        exit 0
        ;;
esac

if [ -z "$effort" ]; then
    effort_display="unset"
else
    effort_display="$effort"
fi

echo "=============================================================================="
echo " WARNING: effort '$effort_display' — SDLC requires max."
echo " Below max = degraded reasoning, shallow TDD, weak self-review."
echo ""
echo " Run: /effort max"
echo " Persist: set CLAUDE_CODE_EFFORT_LEVEL=max in settings env block"
echo ""
echo " recommended model: $RECOMMENDED_MODEL (run: /model $RECOMMENDED_MODEL)"
echo "=============================================================================="

exit 0
