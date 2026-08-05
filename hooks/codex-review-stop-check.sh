#!/bin/bash
# Stop hook — warns (non-blocking) when the session is about to end with
# significant uncommitted changes and no REVIEWED/CERTIFIED cross-model
# review artifact.
#
# Gap this closes (Fable self-enforcement audit, #436): a full SDLC workflow
# can complete — Claude presents "done, here's what I changed" — without
# ever running `git commit`. codex-gate-check.sh only fires on that one
# Bash command, so it never triggers and cross-model review is silently
# skippable. This hook catches the "never committed, walked away" case.
#
# Non-blocking by design: Stop fires at the end of every turn, not just at
# true session end, and it must never prevent the user from getting their
# response. Fires once per session (sentinel-gated) to avoid nagging on
# every iterative turn while a feature is still in progress.

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { read_stdin_bounded > /dev/null || true; exit 0; }

# Non-blocking hook: degrade to empty rather than stall the response.
STDIN_JSON=$(read_stdin_bounded) || STDIN_JSON=""

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || exit 0

# Changed files: staged + unstaged + untracked, excluding review metadata
# itself (.reviews/ changes describe the review, they aren't the work).
CHANGED=$(git status --porcelain 2>/dev/null | awk '{print $2}' | grep -v '^\.reviews/')
[ -z "$CHANGED" ] && exit 0

# Doc-only changes don't need cross-model review.
SIGNIFICANT=$(printf '%s\n' "$CHANGED" | grep -vE '\.md$|\.txt$|^LICENSE|^CHANGELOG|\.gitignore$|\.gitattributes$')
[ -z "$SIGNIFICANT" ] && exit 0

REVIEW_FILE=".reviews/handoff.json"
if [ -f "$REVIEW_FILE" ]; then
    STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
        | head -1 \
        | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')
    case "$STATUS" in
        CERTIFIED|REVIEWED) exit 0 ;;
    esac
fi

# Once-per-session sentinel — avoid nagging on every Stop event while a
# feature is still in progress within the same session.
SESSION_ID=$(printf '%s' "$STDIN_JSON" \
    | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -1 \
    | sed 's/.*"\([^"]*\)"$/\1/')
if [ -n "$SESSION_ID" ]; then
    CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
    SAFE_SID=$(printf '%s' "$SESSION_ID" | tr -cd 'A-Za-z0-9._-')
    if [ -n "$SAFE_SID" ]; then
        SENTINEL="$CACHE_DIR/stop-review-warned-${SAFE_SID}"
        mkdir -p "$CACHE_DIR" 2>/dev/null || true
        if [ -f "$SENTINEL" ]; then
            exit 0
        fi
        : > "$SENTINEL" 2>/dev/null || true
    fi
fi

# #236(b): on exit 0, stderr is never surfaced (to the user or to Claude) —
# only stdout JSON is. An earlier stderr+exit-0 version of this line was
# silently discarded since the day this hook shipped (#436).
cat << 'EOF'
{"hookSpecificOutput": {"hookEventName": "Stop", "additionalContext": "NOTE: uncommitted changes with no REVIEWED/CERTIFIED cross-model review artifact. If this work is heading to a commit, run Codex review before committing."}}
EOF

exit 0
