#!/bin/bash
# SessionStart hook — effort/model nudge.
#
# Behavior (#434 update — model-aware floor):
#   CLAUDE_CODE_EFFORT_LEVEL env var takes precedence over effortLevel in settings.
#   CC docs: max is session-only in settings.json — only the env var persists it.
#   This hook cannot detect the active model (SessionStart payload has no model
#   field, per ROADMAP #180), so it uses a floor that's correct across models:
#   xhigh is the recommended default for Sonnet 5/Opus 4.8/Fable; max remains
#   the sweet spot on Opus 4.6 (no xhigh support). Blanket max is WRONG for
#   Sonnet 5 (doubles cost, no quality gain per CodeRabbit) and Opus 4.8
#   ("prone to overthinking" per Anthropic effort docs).
#
#   effort=xhigh or max -> silent (both acceptable)
#   anything else        -> LOUD WARNING
#
# Non-blocking: always exits 0.

# Multiple wizard-blessed models — don't nudge to a single one (#403, #434)
RECOMMENDED_MODELS="sonnet, opus, opusplan, or fable (run: /model)"

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

# xhigh is always silent (persists fine via settings.json, no CC quirk).
# max is silent EXCEPT when it's settings-only — CC docs: max is session-only
# in settings.json, only the env var actually persists it.
if [ "$effort" = "xhigh" ]; then
    exit 0
fi
if [ "$effort" = "max" ] && [ "$settings_max" -eq 0 ]; then
    exit 0
fi

if [ "$settings_max" -eq 1 ] && [ -z "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
    effort_display="max (settings-only — CC ignores this)"
elif [ -z "$effort" ]; then
    effort_display="unset"
else
    effort_display="$effort"
fi

echo "=============================================================================="
echo " WARNING: effort '$effort_display' — SDLC requires xhigh or max."
echo " Below xhigh = degraded reasoning, shallow TDD, weak self-review."
echo ""
echo " Run: /effort xhigh"
echo " Avoid persisting via shell-rc env var — silently overrides model"
echo " switches. See AI_SETUP_LANES.md for effort per model."
echo ""
echo " recommended models: $RECOMMENDED_MODELS"
echo "=============================================================================="

exit 0
