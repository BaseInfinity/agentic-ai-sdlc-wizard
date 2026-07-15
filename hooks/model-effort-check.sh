#!/bin/bash
# SessionStart hook — effort/model nudge.
#
# Behavior (#440 update — medium joins the floor):
#   CLAUDE_CODE_EFFORT_LEVEL env var takes precedence over effortLevel in settings.
#   CC docs: max is session-only in settings.json — only the env var persists it.
#   This hook cannot detect the active model (SessionStart payload has no model
#   field, per ROADMAP #180), so it uses a floor that's correct across models:
#   `medium` is Sonnet 5's documented default (CodeRabbit testing: most of the
#   upside at the lowest cost — escalate high -> xhigh for hard tasks); `high`
#   is Fable's default; xhigh is Opus 4.8's floor; max remains the sweet spot
#   on Opus 4.6 (no xhigh support). Blanket max is WRONG for Sonnet 5/Opus 4.8
#   (wastes tokens for no quality gain — see AI_SETUP_LANES.md per-model table).
#
#   effort=medium, high, xhigh, or max -> silent (all acceptable — model-dependent)
#   anything else                       -> LOUD WARNING
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

# medium/high/xhigh are always silent (persist fine via settings.json, no CC
# quirk). max is silent EXCEPT when it's settings-only — CC docs: max is
# session-only in settings.json, only the env var actually persists it.
if [ "$effort" = "medium" ] || [ "$effort" = "high" ] || [ "$effort" = "xhigh" ]; then
    exit 0
fi
if [ "$effort" = "max" ] && [ "$settings_max" -eq 0 ]; then
    exit 0
fi

# #236(b): unset (no env var, no settings entry) is CC's own current default —
# not a problem state on its own (e.g. a deliberate Fable-session config).
# Only warn on an EXPLICITLY set low-effort value or the settings-only-max
# quirk below (CC silently ignores settings.json's "max" — genuinely
# non-obvious, worth keeping).
if [ -z "$effort" ]; then
    exit 0
fi

if [ "$settings_max" -eq 1 ] && [ -z "${CLAUDE_CODE_EFFORT_LEVEL:-}" ]; then
    effort_display="max (settings-only — CC ignores this)"
else
    effort_display="$effort"
fi

echo "=============================================================="
echo " WARNING: effort '$effort_display' — below the SDLC floor (medium)."
echo " Degraded reasoning, shallow TDD, weak self-review."
echo " Run: /effort medium (Sonnet 5) or your model's floor — see AI_SETUP_LANES.md"
echo " Avoid shell-rc env persistence — overrides model switches."
echo " recommended models: $RECOMMENDED_MODELS"
echo "=============================================================="

exit 0
