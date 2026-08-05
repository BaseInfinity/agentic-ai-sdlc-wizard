#!/bin/bash
# PreToolUse hook — blocks git commit without cross-model review artifact
# Fires on Bash tool; only acts when the command contains "git commit"
#
# #436 fix: exit 2 + stderr is what actually denies the tool call in Claude
# Code. The original version exited 0 on every path (including the two
# "CROSS-MODEL REVIEW REQUIRED" branches below), so it printed a warning but
# never blocked anything — the exact bug class this gate exists to prevent.
# Matches the proven blocking pattern in precompact-seam-check.sh.

set -e

HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
# Sourced only for read_stdin_bounded (#491 Class 2). The helper defines
# functions and has no top-level side effects, so this gate's behaviour is
# unchanged apart from no longer being able to block forever on stdin.
source "$HOOK_DIR/_find-sdlc-root.sh"

# Skip gate if explicitly overridden (emergency bypass with logged justification)
[ "${CODEX_GATE_SKIP:-}" = "1" ] && exit 0

TOOL_INPUT=$(read_stdin_bounded) || {
    # Fail CLOSED: unreadable stdin must not become an allow (#491 P0).
    echo "CROSS-MODEL REVIEW GATE: could not read hook input within ${SDLC_HOOK_STDIN_TIMEOUT:-5}s. Refusing to allow an unverified command. Set CODEX_GATE_SKIP=1 to bypass with justification." >&2
    exit 2
}

# Codex review findings (hook-enforcement-436):
# Round 1: extracting the "command" field's value via grep/sed with
# `[^"]*` broke when an earlier quote appeared in the command (e.g. `cd
# "$dir" && git commit ...`) — the class stops at the first literal `"`
# regardless of JSON escaping, truncating the capture before it ever
# reached "git commit" (false negative — review-less commit slipped
# through).
# Round 2: matching "git commit" against the WHOLE raw TOOL_INPUT (the
# round-1 fix) over-corrected — a non-commit command got blocked if any
# OTHER field (e.g. the Bash tool's own "description") happened to mention
# "git commit" in prose (false positive).
# Fix: extract just the "command" field's value with an escape-aware
# pattern — `([^"\\]|\\.)*` consumes an escaped quote (`\"`) as one unit
# instead of treating it as a terminator, so it can't stop early, and it
# still can't run past the field's true (unescaped) closing quote because
# neither alternative in the group can match a bare `"`. Scoped to just
# this field, so unrelated fields containing the phrase can't false-trigger.
# #236(b): under `set -e`, a grep with no match exits 1 and kills the whole
# script with an undefined exit code (a "command" field can be absent, e.g.
# an old-format payload) — `|| true` makes "no match" a clean, deliberate
# empty COMMAND_FIELD instead of a crash.
COMMAND_FIELD=$(printf '%s' "$TOOL_INPUT" \
    | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' || true)

# Codex cross-model review finding (#236(b) round 1, 2026-07-06): a `-c`/`-C`
# value containing a space inside quotes is a real, valid git invocation
# (e.g. `git -c user.name="A B" commit`) but broke the structural match below
# — `\S+` stops at the embedded space, so the flag-value alternative never
# matches and the whole "git ... commit" pattern silently fails, letting the
# commit through unreviewed. Fix: strip COMMAND_FIELD down to just the raw
# value content (COMMAND_VALUE, still JSON-escaped), then collapse every
# quoted sub-span — both JSON-escaped `\"..\"` and plain `'..'` — to a single
# placeholder token before the structural match runs, so a quoted value can
# never look like more than one word to it.
COMMAND_VALUE=$(printf '%s' "$COMMAND_FIELD" \
    | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')
MASKED_COMMAND=$(printf '%s' "$COMMAND_VALUE" \
    | sed -E -e 's/\\"[^\\]*\\"/Q/g' -e "s/'[^']*'/Q/g")

# #236(b): literal substring "git commit" misses git's own global-flag forms
# — `git -C <dir> commit` and `git -c k=v commit` are valid invocations that
# never contain that exact two-word substring, and previously sailed through
# unreviewed. Regex allows any number of -C/-c (with their required value),
# --long-flag, or single-letter-flag tokens between "git" and "commit".
if ! printf '%s' "$MASKED_COMMAND" \
    | grep -qE '\bgit(\s+(-C\s+\S+|-c\s+\S+|--\S+|-[A-Za-z]))*\s+commit\b'; then
    exit 0
fi

REVIEW_FILE=".reviews/handoff.json"

if [ ! -f "$REVIEW_FILE" ]; then
    echo "CROSS-MODEL REVIEW REQUIRED: No .reviews/handoff.json found. Run Codex cross-model review before committing. Set CODEX_GATE_SKIP=1 to bypass with justification." >&2
    exit 2
fi

STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
    | head -1 \
    | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')

case "$STATUS" in
    CERTIFIED|REVIEWED)
        # #437: a CERTIFIED/REVIEWED status string alone doesn't mean the
        # certification is still current — commits made after it was issued
        # would otherwise sail through on the same stale status forever.
        # commit_sha records HEAD at cert time; a mismatch (or a missing
        # field, e.g. an old-format handoff.json predating this fix) means
        # new commits landed since certification, so treat it as stale. This
        # allows exactly one commit after certification (HEAD still equals
        # the recorded SHA at that commit's PreToolUse check) and blocks the
        # next one until re-cert. No legacy-compat fallback for missing SHA.
        COMMIT_SHA=$(grep -o '"commit_sha"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
            | head -1 \
            | sed 's/.*"commit_sha"[[:space:]]*:[[:space:]]*"//; s/"$//')
        CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null) || CURRENT_HEAD=""
        if [ -z "$COMMIT_SHA" ] || [ "$COMMIT_SHA" != "$CURRENT_HEAD" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json certification is stale (commit_sha does not match current HEAD — new commits landed since certification). Re-run Codex cross-model review. Set CODEX_GATE_SKIP=1 to bypass with justification." >&2
            exit 2
        fi
        exit 0
        ;;
    *)
        echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json status is '$STATUS' (need REVIEWED or CERTIFIED). Run Codex cross-model review before committing. Set CODEX_GATE_SKIP=1 to bypass with justification." >&2
        exit 2
        ;;
esac
