#!/bin/bash
# SessionStart hook — effort/model nudge.
#
# Behavior (per ROADMAP #217):
#   effort=max    -> silent (preferred default, above floor)
#   effort=xhigh  -> silent (minimum floor on Opus 4.8)
#   effort=high|medium|low (or unset) -> LOUD WARNING:
#     Opus 4.8 needs xhigh floor for SDLC compliance (TDD, self-review, deep reasoning).
#     Recommends `/effort max`. Also reminds about recommended model `opus[1m]`.
#
# CC does not expose the current model to hooks, so the model nudge is emitted as
# guidance for Claude to compare against its own system prompt.
#
# Non-blocking: always exits 0.

RECOMMENDED_MODEL="opus[1m]"

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { cat > /dev/null; exit 0; }

# Drain stdin (SessionStart sends JSON but model field isn't in it)
cat > /dev/null

if ! command -v jq > /dev/null 2>&1; then
    exit 0
fi

effort=""
project_dir="${CLAUDE_PROJECT_DIR:-.}"
for f in "$project_dir/.claude/settings.local.json" "$project_dir/.claude/settings.json" "$HOME/.claude/settings.json"; do
    if [ -f "$f" ]; then
        val=$(jq -r '.effortLevel // empty' "$f" 2>/dev/null)
        if [ -n "$val" ]; then
            effort="$val"
            break
        fi
    fi
done

# At or above floor — silent.
case "$effort" in
    max|xhigh)
        exit 0
        ;;
esac

# Below floor OR unset — LOUD warning.
# Note: test_model_effort_size_cap asserts output < 500 chars. Keep copy terse.
if [ -z "$effort" ]; then
    effort_display="unset"
else
    effort_display="$effort"
fi

echo "=============================================================================="
echo " WARNING: effort '$effort_display' breaks SDLC compliance on Opus 4.8."
echo " Below xhigh = shallow reasoning, skipped TDD, dropped self-review."
echo ""
echo " Run: /effort max    (preferred, full SDLC compliance)"
echo " Or:  /effort xhigh  (minimum floor)"
echo ""
echo " recommended model: $RECOMMENDED_MODEL (run: /model $RECOMMENDED_MODEL)"
echo "=============================================================================="

exit 0
