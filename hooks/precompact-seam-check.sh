#!/bin/bash
# PreCompact hook - block manual /compact at non-seam boundaries
# Fires on manual /compact only (auto-compact is threshold-driven; blocking
# it could push past 100% context and lose everything). Matcher: "manual"
# in .claude/settings.json.
#
# Requires Claude Code v2.1.105+ (PreCompact event introduced April 13, 2026).
#
# Seam policy: compacting mid-cycle loses evidence the next round needs.
# Block when:
#   (1) .reviews/handoff.json status is PENDING_REVIEW or PENDING_RECHECK
#       → mid-Codex-round, compact after CERTIFIED
#   (2) git rebase/merge/cherry-pick in progress
#       → finish in-progress git operation first
# Allow otherwise.

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
# Use parameter expansion (not `dirname`) so the PATH-restricted gh-missing test
# still works — bash builtin `${var%/*}` is always available.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[ "$HOOK_DIR" = "${BASH_SOURCE[0]}" ] && HOOK_DIR="."
# shellcheck disable=SC1091
source "$HOOK_DIR/_find-sdlc-root.sh"
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || { [ ! -t 0 ] && cat > /dev/null; exit 0; }

[ ! -t 0 ] && INPUT=$(cat) || INPUT=""

# Determine project root: prefer $CLAUDE_PROJECT_DIR, fall back to cwd
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"

HOLD_REASONS=""

# #240: Dry-run / simulation env vars. Let consumers verify hook behavior
# without mutating real .reviews/handoff.json or .git/ state.
#   SDLC_DRY_RUN_HANDOFF_STATUS=<value> — overrides handoff.json status
#                                         lookup (skip the file read entirely)
#   SDLC_DRY_RUN_GIT_STATE=rebase|merge|cherry-pick — simulates an in-flight
#                                                    git operation
# When set, dry-run values short-circuit the real-state checks below. The
# hook still emits the same HOLD/silent decision so consumers can smoke-test
# every code path. No filesystem writes — purely read-only simulation.

# Check 1: Codex review mid-cycle
# Self-heal paths (ordered by preference):
#   (a) #209: handoff has pr_number + gh reports PR MERGED → implicit CERTIFIED (silent)
#   (c) #257: handoff has no pr_number BUT every SHA cited in fixes_applied[]
#       is in HEAD's ancestry AND .reviews/latest-review.md contains CERTIFIED
#       (without "NOT CERTIFIED") → implicit CERTIFIED (silent). Catches the
#       solo-developer pattern: write fixes, commit them, run targeted
#       recheck, see CERTIFIED in latest-review.md, ship — and forget to
#       update handoff.json status. The visible signals (commits landed +
#       review file) already say "done" so blocking is high false-positive.
#   (b) #229: handoff has no pr_number, no SHA-ancestry heal, but mtime >
#       SDLC_HANDOFF_STALE_DAYS days → implicit CERTIFIED with WARN
#       (forgotten artifact; blocking forever is worse UX). Default: 14 days.
HANDOFF="$ROOT/.reviews/handoff.json"
# Validate SDLC_HANDOFF_STALE_DAYS as non-negative integer. Anything else
# (empty, "foo", "-3", "10.5") silently falls back to 14 — we don't want a
# typo in the user's env to leak a bash arithmetic error to stderr every
# time the hook runs (caught by Codex P2 review of PR #227).
STALE_DAYS_RAW="${SDLC_HANDOFF_STALE_DAYS:-14}"
case "$STALE_DAYS_RAW" in
    ''|*[!0-9]*) STALE_DAYS=14 ;;
    *) STALE_DAYS="$STALE_DAYS_RAW" ;;
esac
STALE_WARN=""
# #240: dry-run override skips the real handoff.json read.
if [ -n "${SDLC_DRY_RUN_HANDOFF_STATUS:-}" ]; then
    STATUS="$SDLC_DRY_RUN_HANDOFF_STATUS"
    case "$STATUS" in
        PENDING_REVIEW|PENDING_RECHECK)
            HOLD_REASONS="${HOLD_REASONS}  - Codex review is ${STATUS}. Round-1 evidence lives in this context — compacting now loses what round-2 needs to re-verify.
    Resolve: wait for CERTIFIED (or escalate) before /compact."$'\n'
            ;;
    esac
elif [ -f "$HANDOFF" ]; then
    STATUS=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$HANDOFF" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    case "$STATUS" in
        PENDING_REVIEW|PENDING_RECHECK)
            PR_NUMBER=$(grep -o '"pr_number"[[:space:]]*:[[:space:]]*[0-9][0-9]*' "$HANDOFF" 2>/dev/null | head -1 | grep -o '[0-9][0-9]*$')
            HEALED=0
            if [ -n "$PR_NUMBER" ]; then
                # Path (a): PR-linked self-heal (#209). Applies regardless of mtime —
                # an OPEN PR with old mtime is still a live review.
                if command -v gh >/dev/null 2>&1; then
                    PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq .state 2>/dev/null)
                    [ "$PR_STATE" = "MERGED" ] && HEALED=1
                fi
            else
                # Path (c) #257: SHA-ancestry self-heal. Look for git SHAs cited
                # in fixes_applied[]; if every cited SHA is reachable from HEAD
                # AND .reviews/latest-review.md says CERTIFIED, the review IS
                # closed, the user just forgot to bump status. Silent heal.
                REVIEW_MD="$ROOT/.reviews/latest-review.md"
                if [ -f "$REVIEW_MD" ] \
                    && grep -qE '\bCERTIFIED\b' "$REVIEW_MD" 2>/dev/null \
                    && ! grep -qE '\bNOT CERTIFIED\b' "$REVIEW_MD" 2>/dev/null; then
                    # Extract the fixes_applied[] block via bracket-depth
                    # tracking — naive `/\]/` matching breaks on `]` inside
                    # string literals (e.g. "[x] FIXED in <sha>" markdown
                    # checkboxes), which would let phantom SHAs after the
                    # broken-early bracket leak past path (c) and false-heal.
                    # Codex P1 round 1.
                    FIXES_BLOCK=$(awk '
                        BEGIN { in_block = 0; depth = 0; started = 0 }
                        /"fixes_applied"/ { in_block = 1 }
                        in_block {
                            print
                            in_string = 0
                            escaped = 0
                            for (i = 1; i <= length($0); i++) {
                                c = substr($0, i, 1)
                                # Honor JSON backslash escapes: \" inside a
                                # string is a literal quote, NOT a string
                                # terminator. Without this, a fixes_applied
                                # entry containing `\"]` falsely flips the
                                # in_string flag and exits the array early —
                                # letting later phantom SHAs leak past path
                                # (c) and false-heal (Codex round 2 P1).
                                if (escaped) { escaped = 0; continue }
                                if (c == "\\") { escaped = 1; continue }
                                if (c == "\"") { in_string = !in_string; continue }
                                if (in_string) continue
                                if (c == "[") { depth++; started = 1 }
                                else if (c == "]") { depth-- }
                            }
                            if (started && depth <= 0) in_block = 0
                        }
                    ' "$HANDOFF" 2>/dev/null)
                    if [ -n "$FIXES_BLOCK" ] && [ -d "$ROOT/.git" ]; then
                        # Strip UUIDs (8-4-4-4-12 hex pattern) BEFORE extracting
                        # SHA candidates. UUIDs have a fixed shape; their hex
                        # segments would otherwise match \b[0-9a-f]{7,40}\b and
                        # fail the ancestry check, false-blocking certified
                        # reviews that cite UUIDs in fixes_applied (mission
                        # UUIDs, Linear/Jira ticket IDs, etc.). Codex P2 round 1.
                        # POSIX-compatible: no `\b` (BSD sed doesn't support it).
                        # The hyphenated 8-4-4-4-12 shape is specific enough
                        # that false-stripping a real SHA is implausible.
                        CLEANED=$(echo "$FIXES_BLOCK" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}//g')
                        SHAS=$(echo "$CLEANED" | grep -oE '\b[0-9a-f]{7,40}\b' | sort -u)
                        if [ -n "$SHAS" ]; then
                            # Every cited SHA must be reachable from HEAD —
                            # phantom SHAs (e.g. typos, references to other
                            # repos) correctly fail ancestry and block the heal.
                            ALL_IN_HEAD=1
                            for sha in $SHAS; do
                                if ! git -C "$ROOT" merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
                                    ALL_IN_HEAD=0
                                    break
                                fi
                            done
                            [ "$ALL_IN_HEAD" -eq 1 ] && HEALED=1
                        fi
                    fi
                fi
                # Path (b): stale-handoff auto-expire (#229). Only when no pr_number
                # AND path (c) didn't already heal. We must not short-circuit
                # PR-linked reviews.
            if [ "$HEALED" -ne 1 ]; then
                # Try GNU stat first (Linux: `-c %Y` gives mtime, BSD stat errors out
                # so `||` fires). Then BSD stat (macOS: `-f %m` gives mtime). The
                # reverse order fails on Linux because `stat -f` on GNU means
                # `--file-system` and dumps filesystem info to stdout (non-error).
                MTIME=$(stat -c %Y "$HANDOFF" 2>/dev/null || stat -f %m "$HANDOFF" 2>/dev/null)
                # Numeric guard: if stat fails both flavors or returns junk, skip
                # the stale-check entirely and fall through to HOLD (safe default).
                case "$MTIME" in
                    ''|*[!0-9]*) ;;
                    *)
                        NOW=$(date +%s)
                        AGE_DAYS=$(( (NOW - MTIME) / 86400 ))
                        if [ "$AGE_DAYS" -ge "$STALE_DAYS" ]; then
                            HEALED=1
                            STALE_WARN="WARN: handoff.json is ${STATUS} and ${AGE_DAYS}d old with no pr_number — treating as stale CERTIFIED (override: set SDLC_HANDOFF_STALE_DAYS or close out the review)."
                        fi
                        ;;
                esac
            fi
            fi
            if [ "$HEALED" -ne 1 ]; then
                HOLD_REASONS="${HOLD_REASONS}  - Codex review is ${STATUS}. Round-1 evidence lives in this context — compacting now loses what round-2 needs to re-verify.
    Resolve: wait for CERTIFIED (or escalate) before /compact."$'\n'
            fi
            ;;
    esac
fi

# Check 2: in-progress git operation
# #240: dry-run override simulates a git op without needing a real .git/.
GITDIR="$ROOT/.git"
# Step 1: when dry-run var matches a known scenario, simulate it.
# Otherwise (unset, empty, or unknown value) fall through to the real
# .git/ checks below — this prevents an unintended safety bypass when
# the user typos the env var (e.g. SDLC_DRY_RUN_GIT_STATE=bogus would
# previously skip real checks entirely; Codex P1 round 1).
DRY_RUN_GIT_HANDLED=0
case "${SDLC_DRY_RUN_GIT_STATE:-}" in
    rebase)
        HOLD_REASONS="${HOLD_REASONS}  - Git rebase in progress. Compacting mid-rebase loses the operation's context.
    Resolve: finish or abort the rebase before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
    merge)
        HOLD_REASONS="${HOLD_REASONS}  - Git merge in progress. Compacting mid-merge loses the operation's context.
    Resolve: finish or abort the merge before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
    cherry-pick)
        HOLD_REASONS="${HOLD_REASONS}  - Git cherry-pick in progress. Compacting mid-cherry-pick loses the operation's context.
    Resolve: finish or abort the cherry-pick before /compact."$'\n'
        DRY_RUN_GIT_HANDLED=1
        ;;
esac

# Step 2: real .git/ check fires if dry-run didn't simulate a scenario.
# Empty/unset SDLC_DRY_RUN_GIT_STATE → real check (default behavior).
# Unknown value (e.g. typo "bogus") → also falls through to real check
# rather than silently bypassing safety. The safer-than-the-typo path.
if [ "$DRY_RUN_GIT_HANDLED" -eq 0 ] && [ -d "$GITDIR" ]; then
    # Only the rebase-{merge,apply}/ dir is authoritative for "rebase in progress."
    # .git/REBASE_HEAD is a rebase-related ref (the stopped/replayed commit) that
    # is not authoritative on its own — it can persist as a stale marker after a
    # rebase finishes cleanly: git removes the dir but leaves REBASE_HEAD around
    # for diff/log lookups. Including it in the OR-chain caused false-positive
    # HOLDs that blocked manual /compact for users whose previous rebase had
    # completed (hit live 2026-05-05). `git status` keys on the dirs too.
    if [ -d "$GITDIR/rebase-merge" ] || [ -d "$GITDIR/rebase-apply" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git rebase in progress. Compacting mid-rebase loses the operation's context.
    Resolve: finish or abort the rebase before /compact."$'\n'
    fi
    if [ -e "$GITDIR/MERGE_HEAD" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git merge in progress. Compacting mid-merge loses the operation's context.
    Resolve: finish or abort the merge before /compact."$'\n'
    fi
    if [ -e "$GITDIR/CHERRY_PICK_HEAD" ]; then
        HOLD_REASONS="${HOLD_REASONS}  - Git cherry-pick in progress. Compacting mid-cherry-pick loses the operation's context.
    Resolve: finish or abort the cherry-pick before /compact."$'\n'
    fi
fi

if [ -n "$HOLD_REASONS" ]; then
    {
        echo "HOLD: manual /compact at a non-seam. Compacting mid-cycle loses evidence the next round needs."
        echo ""
        echo "$HOLD_REASONS"
        echo "Natural seams: commit boundary, Codex CERTIFIED, PR merge, ROADMAP item DONE."
        echo "Override: resolve the blocker above, or temporarily disable this hook in .claude/settings.json."
    } >&2
    exit 2
fi

# Stale-handoff unblock: emit a one-line WARN so the user knows the hook
# self-healed over an abandoned PENDING artifact (but still allow /compact).
[ -n "$STALE_WARN" ] && echo "$STALE_WARN" >&2
exit 0
