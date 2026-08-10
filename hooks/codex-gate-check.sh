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
    echo "CROSS-MODEL REVIEW GATE: could not read hook input within ${SDLC_HOOK_STDIN_TIMEOUT:-5}s. Refusing to allow an unverified command. Human override: relaunch Claude Code with CODEX_GATE_SKIP=1 in its environment — this hook runs before your command, so an inline prefix inside a tool call cannot reach it. Your own terminal is unaffected; this is a Claude Code hook, not a git hook." >&2
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
    echo "CROSS-MODEL REVIEW REQUIRED: No .reviews/handoff.json found. Run Codex cross-model review before committing. Human override: relaunch Claude Code with CODEX_GATE_SKIP=1 in its environment — this hook runs before your command, so an inline prefix inside a tool call cannot reach it. Your own terminal is unaffected; this is a Claude Code hook, not a git hook." >&2
    exit 2
fi

STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
    | head -1 \
    | sed 's/.*"status"[[:space:]]*:[[:space:]]*"//; s/"$//')

# #533: resolve whether we are on the repo's default branch.
#
# The gate's purpose is stopping unreviewed work from reaching the default
# branch — not stopping work from being SAVED. Blocking every in-flight commit
# forced reviewers onto a mutable working tree, and during #520 round 18 a
# reviewer read a tree a mutation harness was concurrently mutating and filed a
# fully-diagnosed P1 against a defect that existed only in the mutation.
#
# Fails STRICT by default: ON_DEFAULT_BRANCH stays 1 unless we can positively
# prove otherwise. Not a repo, detached HEAD (rev-parse --abbrev-ref prints the
# literal "HEAD"), main/master, or no trunk-shaped ref anywhere — all strict.
#
# refs/remotes/origin/HEAD is a LOCAL ref written by git clone, so this is
# entirely offline. init.defaultBranch is deliberately NOT consulted: it names
# the branch for NEW repos, so it can name one this repo never had, which
# would be a false-lenient source.
#
# Two `set -e` landmines, same class as the one memorialised at the top of this
# file: every git capture needs `|| true` (a non-match exits 1 and kills the
# script), and the comparison must be a full `if`, never `[ ... ] && VAR=0`
# (a false test returns 1 and kills the script).
ON_DEFAULT_BRANCH=1
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
DEFAULT_BRANCH="${DEFAULT_BRANCH#origin/}"
case "$CURRENT_BRANCH" in
    ""|HEAD|main|master) ;;
    *)
        if [ -n "$DEFAULT_BRANCH" ]; then
            if [ "$CURRENT_BRANCH" != "$DEFAULT_BRANCH" ]; then ON_DEFAULT_BRANCH=0; fi
        elif git show-ref --verify --quiet refs/heads/main \
            || git show-ref --verify --quiet refs/heads/master \
            || git show-ref --verify --quiet refs/remotes/origin/main \
            || git show-ref --verify --quiet refs/remotes/origin/master; then
            ON_DEFAULT_BRANCH=0
        fi
        ;;
esac

case "$STATUS" in
    PENDING_REVIEW|PENDING_RECHECK)
        # A review round is open. The protocol prescribes exactly these two
        # statuses for its whole duration, so this is the state in which work
        # is actually produced. Let it be committed — but only somewhere it
        # cannot reach the default branch. Round 1 counts as much as round 2:
        # PENDING_REVIEW is what holds while the FIRST reviewer reads, which
        # is precisely the configuration that produced the phantom P1.
        #
        # commit_sha is deliberately not read here: on this lane it is either
        # absent by design (never certified) or stale by design (a round is
        # open). Freshness is lane CERTIFIED/REVIEWED's job, and it keeps it.
        if [ "$ON_DEFAULT_BRANCH" -eq 0 ]; then
            exit 0
        fi
        echo "CROSS-MODEL REVIEW REQUIRED: status is '$STATUS' (a review round is open) and this looks like the default branch${DEFAULT_BRANCH:+ [$DEFAULT_BRANCH]}${CURRENT_BRANCH:+, current [$CURRENT_BRANCH]}. In-flight work may be committed on a non-default branch so reviewers get an immutable SHA instead of a live tree; reaching the default branch still needs a certification bound to that exact HEAD. Human override: relaunch Claude Code with CODEX_GATE_SKIP=1 in its environment — this hook runs before your command, so an inline prefix inside a tool call cannot reach it." >&2
        exit 2
        ;;
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
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json certification is stale (commit_sha does not match current HEAD — new commits landed since certification). Re-run Codex cross-model review. Human override: relaunch Claude Code with CODEX_GATE_SKIP=1 in its environment — this hook runs before your command, so an inline prefix inside a tool call cannot reach it. Your own terminal is unaffected; this is a Claude Code hook, not a git hook." >&2
            exit 2
        fi
        exit 0
        ;;
    *)
        echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json status is '$STATUS' (need REVIEWED or CERTIFIED). Run Codex cross-model review before committing. Human override: relaunch Claude Code with CODEX_GATE_SKIP=1 in its environment — this hook runs before your command, so an inline prefix inside a tool call cannot reach it. Your own terminal is unaffected; this is a Claude Code hook, not a git hook." >&2
        exit 2
        ;;
esac
