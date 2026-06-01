#!/bin/bash
# /goal SDLC discipline gate (ROADMAP #360).
#
# UserPromptSubmit hook. When the user invokes `/goal <condition>`, scan the
# prior assistant text for a HIGH 95% confidence statement AND check the
# condition for a DLC binding (`/sdlc`, `/gdlc`, `/ldlc`, etc.). Emit loud
# warnings on either gap so the SDLC-discipline gap surfaces BEFORE the goal
# evaluator starts rubber-stamping flailing as progress.
#
# PR #355 (v1.77.0) added the guidance text in skills/sdlc/SKILL.md. This
# hook is the enforcement layer per #360. Non-blocking soft nudge — same
# pattern as model-effort-check.sh.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/_find-sdlc-root.sh"

# Plugin + project copies both register this hook → plugin yields (#236).
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || exit 0

# Must be invoked via hook (stdin JSON), not interactively.
[ -t 0 ] && exit 0
STDIN_JSON=$(cat)
[ -z "$STDIN_JSON" ] && exit 0
command -v jq > /dev/null 2>&1 || exit 0

PROMPT=$(printf '%s' "$STDIN_JSON" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[ -z "$PROMPT" ] && exit 0

# Only act on `/goal <condition>` invocations. `/goal` alone (status) and
# `/goal clear` (reset) must stay silent — those aren't discipline events.
case "$PROMPT" in
    "/goal")           exit 0 ;;
    "/goal "[[:space:]]*) exit 0 ;;
    "/goal clear")     exit 0 ;;
    "/goal clear "*)   exit 0 ;;
    "/goal "*)         ;;
    *)                 exit 0 ;;
esac

CONDITION="${PROMPT#/goal }"

# === Confidence gate ===
# Read transcript_path, slurp JSONL, find last assistant message with text
# content, scan for HIGH-95% confidence pattern. Silent on missing/unreadable
# transcript — better to under-warn than crash a soft nudge.
TRANSCRIPT_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.transcript_path // empty' 2>/dev/null) || TRANSCRIPT_PATH=""
HAS_CONFIDENCE=0
if [ -n "$TRANSCRIPT_PATH" ] && [ -r "$TRANSCRIPT_PATH" ]; then
    LAST_ASSISTANT_TEXT=$(jq -rs '
        [.[] | select(.type == "assistant")]
        | last
        | if . == null then ""
          else (.message.content // []) | map(select(.type == "text") | .text) | join("\n")
          end
    ' "$TRANSCRIPT_PATH" 2>/dev/null) || LAST_ASSISTANT_TEXT=""
    if printf '%s' "$LAST_ASSISTANT_TEXT" | grep -qiE 'HIGH \(?95%|confidence:?[[:space:]]+HIGH|HIGH[[:space:]]+95%|95%[[:space:]]+confidence'; then
        HAS_CONFIDENCE=1
    fi
fi

if [ "$HAS_CONFIDENCE" -eq 0 ]; then
    echo ""
    echo "!! /GOAL CONFIDENCE GATE: prior turn did not state HIGH 95% confidence !!"
    echo "   The /goal Haiku evaluator rubber-stamps flailing as progress below 95%."
    echo "   Recommendation: /goal clear → do research → state HIGH 95% confidence → re-issue /goal."
    echo "   (Source: skills/sdlc/SKILL.md Long-Running Goals section, ROADMAP #360.)"
    echo ""
fi

# === DLC binding gate ===
# Condition MUST name a DLC (`/sdlc`, `/gdlc`, `/ldlc`, etc.) so the
# evaluator anchors on "doing it right" not just "doing it".
if ! printf '%s' "$CONDITION" | grep -qiE '/[a-z]+dlc'; then
    echo ""
    echo "!! /GOAL DLC-BINDING GATE: condition does not name a DLC (/sdlc, /gdlc, /ldlc) !!"
    echo "   The evaluator needs a discipline anchor to judge 'doing it right' vs flailing."
    echo "   Recommendation: rewrite condition to include 'following /sdlc' (or /gdlc/etc)."
    echo "   (Source: skills/sdlc/SKILL.md Long-Running Goals section, ROADMAP #360.)"
    echo ""
fi

exit 0
