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

# Skip gate if explicitly overridden (emergency bypass with logged justification).
#
# #533: this is read from the HOOK's own process environment, which is not the
# shell that runs the blocked command — a PreToolUse hook fires first, so
# `CODEX_GATE_SKIP=1 git commit ...` is blocked identically to the unprefixed
# form. The variable stays (a settings env block can set it); what changed is
# that the messages below no longer instruct callers to take a route that
# cannot work from where they are reading it.
[ "${CODEX_GATE_SKIP:-}" = "1" ] && exit 0

# Named once so all four refusals say the same true thing.
BYPASS_NOTE="Emergency bypass: CODEX_GATE_SKIP=1, set in the hook's own environment (a settings env block) — this hook runs before your shell, so an inline prefix on the command cannot reach it."

TOOL_INPUT=$(read_stdin_bounded) || {
    # Fail CLOSED: unreadable stdin must not become an allow (#491 P0).
    echo "CROSS-MODEL REVIEW GATE: could not read hook input within ${SDLC_HOOK_STDIN_TIMEOUT:-5}s. Refusing to allow an unverified command. $BYPASS_NOTE" >&2
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
    echo "CROSS-MODEL REVIEW REQUIRED: No .reviews/handoff.json found. Run Codex cross-model review before committing. $BYPASS_NOTE" >&2
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
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json certification is stale (commit_sha does not match current HEAD — new commits landed since certification). Re-run Codex cross-model review. $BYPASS_NOTE" >&2
            exit 2
        fi
        exit 0
        ;;
    PENDING_RECHECK)
        # #533: the in-flight review-dialogue lane.
        #
        # The protocol MANDATES this status for the whole duration of a
        # dialogue round, and this case used to fall to the refusal below —
        # so nothing could be committed during exactly the window in which
        # review work is produced, and every round was forced onto an
        # uncommitted working tree. That is the mutable-tree problem the
        # protocol's own "review committed increments" rule exists to
        # prevent, and it cost a real round: on #520 a reviewer read a tree
        # a concurrent harness mutated underneath it and filed a correct P1
        # against a defect that existed only in that mutation.
        #
        # The lane is keyed on a branch the round DECLARES, never on the hook
        # trying to prove the branch is not the remote's default. That proof
        # is unobtainable offline: default-branch-ness is server-side state,
        # and `refs/remotes/*/HEAD` is a cache with no freshness bound
        # (`git remote set-head -a` needs the network). Two review rounds were
        # spent failing to answer that strictly harder question. The round
        # already knows which branch it is about, so it writes it down, and
        # `branch` sits at exactly the trust level `status` and `commit_sha`
        # have always had. This gate is a guardrail against a cooperating but
        # fallible agent, not a sandbox.
        DECLARED_BRANCH=$(grep -o '"branch"[[:space:]]*:[[:space:]]*"[^"]*"' "$REVIEW_FILE" \
            | head -1 \
            | sed 's/.*"branch"[[:space:]]*:[[:space:]]*"//; s/"$//')
        CURRENT_BRANCH=$(git symbolic-ref --quiet --short HEAD 2>/dev/null) || CURRENT_BRANCH=""

        # Fail closed on a handoff that declares nothing — otherwise a stale
        # PENDING_RECHECK would be a forever-pass on every branch. Same
        # posture as #437's missing commit_sha: no legacy-compat fallback.
        if [ -z "$DECLARED_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json is PENDING_RECHECK but declares no 'branch'. An in-flight round must name the branch its work is on. $BYPASS_NOTE" >&2
            exit 2
        fi

        # Detached HEAD (or not a repo at all) leaves nothing to compare, so
        # the equality this lane rests on cannot be evaluated.
        if [ -z "$CURRENT_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: in-flight commits need a checked-out branch to match .reviews/handoff.json's declared branch '$DECLARED_BRANCH' — HEAD is detached or this is not a git repo. $BYPASS_NOTE" >&2
            exit 2
        fi

        if [ "$DECLARED_BRANCH" != "$CURRENT_BRANCH" ]; then
            echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json's in-flight round declares branch '$DECLARED_BRANCH' but HEAD is on '$CURRENT_BRANCH'. This commit is not the round's work. $BYPASS_NOTE" >&2
            exit 2
        fi

        # ---- The two lines below are ACCIDENT-CATCHERS, NOT SOUNDNESS
        # ---- CLAIMS. Stated plainly because an undocumented denylist is how
        # ---- this cycle started, and because the honest framing is what
        # ---- keeps them from being mistaken for a boundary and either
        # ---- trusted or deleted.
        #
        # (1) A handoff that declares `main` would satisfy the equality above
        # and carry in-flight work onto a trunk. Refusing the two literal
        # names catches that accident. It does NOT establish that any other
        # name is safe — a repo whose default branch is `develop` is not
        # covered, and cannot be, per the offline argument above.
        case "$CURRENT_BRANCH" in
            main|master)
                echo "CROSS-MODEL REVIEW REQUIRED: in-flight commits are not allowed on '$CURRENT_BRANCH'. Work the round on a feature branch. $BYPASS_NOTE" >&2
                exit 2
                ;;
        esac

        # (2) This lane compares the handoff against HEAD in the HOOK's cwd,
        # so a command that relocates git elsewhere would be judged by a
        # branch it will not commit to. Refusing a plain relocation token
        # catches that accident. It is deliberately over-strict — the token
        # can appear inside a commit message and refuse a legitimate commit —
        # because the cost of a false match is a refusal, never an allow.
        #
        # Read on the RAW command value, never MASKED_COMMAND: masking exists
        # so DETECTION can ignore quoted prose, and it destroys exactly what
        # this needs to see.
        #
        # Reachability, stated because the alternative is a comment that
        # overpromises: this only ever sees commands DETECTION delivered. A
        # space-separated long flag (`git --work-tree /tmp commit`) fails the
        # structural match upstream and exits 0 before reaching any lane, so
        # this line never runs for it. That hole predates this lane and is
        # filed as #582; the `-C` and `--flag=value` forms do reach here.
        if printf '%s' "$COMMAND_VALUE" | grep -qE '(^|[[:space:]])(-C([[:space:]]|=)|--git-dir|--work-tree)'; then
            echo "CROSS-MODEL REVIEW REQUIRED: an in-flight commit may not carry a git relocation flag (-C / --git-dir / --work-tree) — this lane can only vouch for the branch checked out where the hook runs. $BYPASS_NOTE" >&2
            exit 2
        fi

        exit 0
        ;;
    *)
        echo "CROSS-MODEL REVIEW REQUIRED: .reviews/handoff.json status is '$STATUS' (need REVIEWED, CERTIFIED, or an in-flight PENDING_RECHECK round declaring its branch). Run Codex cross-model review before committing. $BYPASS_NOTE" >&2
        exit 2
        ;;
esac
