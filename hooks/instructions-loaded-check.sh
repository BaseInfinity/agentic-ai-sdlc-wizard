#!/bin/bash
# InstructionsLoaded hook - validates SDLC files exist at session start
# Fires when Claude loads instructions (session start/resume)
# Available since Claude Code v2.1.69
# Note: no set -e — this hook must always exit 0 to not block session start

# Walk up from CWD to find nearest SDLC.md + TESTING.md (#171: monorepo support)
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HOOK_DIR/_find-sdlc-root.sh"

# Token-bloat fix: when both project + plugin register this hook, plugin yields.
dedupe_plugin_or_project "${BASH_SOURCE[0]}" || exit 0

# CWD walk-up finds nearest SDLC project (#173: silent exit for non-SDLC dirs)
# #236(b): the missing-SDLC.md/TESTING.md warning that used to live here was
# removed — sdlc-prompt-check.sh already fires the same "SETUP NOT COMPLETE"
# warning, louder and on every prompt (this hook only fires at session
# start/resume), making this copy pure duplicate context.
if find_sdlc_root; then
    PROJECT_DIR="$SDLC_ROOT"
elif find_partial_sdlc_root; then
    PROJECT_DIR="$SDLC_ROOT"
else
    # Not an SDLC project at all — exit silently
    exit 0
fi

# Version update check (non-blocking, best-effort).
# Fetches npm latest at most once per 24h (ROADMAP #196). Prints a stronger
# multi-line nudge when the gap is ≥3 minor versions — the one-liner gets
# skipped after weeks of ignoring it (user feedback 2026-04-18).
SDLC_MD="$PROJECT_DIR/SDLC.md"
# Strict x.y.z semver — rejects whitespace, "junk", "1.alpha.0", etc.
SEMVER_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

# semver_lt A B → exit 0 if A < B, exit 1 otherwise. Both args validated semver.
# Used so a stale-but-fresh cache from before an upgrade ("latest" < installed)
# doesn't fire a reverse-direction nudge (#254 Bug 2 / #239).
semver_lt() {
    local a_major a_minor a_patch b_major b_minor b_patch
    a_major=$(echo "$1" | awk -F. '{print $1+0}')
    a_minor=$(echo "$1" | awk -F. '{print $2+0}')
    a_patch=$(echo "$1" | awk -F. '{print $3+0}')
    b_major=$(echo "$2" | awk -F. '{print $1+0}')
    b_minor=$(echo "$2" | awk -F. '{print $2+0}')
    b_patch=$(echo "$2" | awk -F. '{print $3+0}')
    if [ "$a_major" -lt "$b_major" ]; then return 0; fi
    if [ "$a_major" -gt "$b_major" ]; then return 1; fi
    if [ "$a_minor" -lt "$b_minor" ]; then return 0; fi
    if [ "$a_minor" -gt "$b_minor" ]; then return 1; fi
    if [ "$a_patch" -lt "$b_patch" ]; then return 0; fi
    return 1
}

if [ -f "$SDLC_MD" ]; then
    INSTALLED_VERSION=$(grep -o 'SDLC Harness Version: [0-9.]*' "$SDLC_MD" | head -1 | sed 's/SDLC Harness Version: //')
    if [ -n "$INSTALLED_VERSION" ] && [[ "$INSTALLED_VERSION" =~ $SEMVER_RE ]]; then
        VERSION_CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
        VERSION_CACHE_FILE="$VERSION_CACHE_DIR/latest-version"
        LATEST_VERSION=""
        NPM_FAILED=0

        # Use cache if present, <24h old, contents are valid semver, AND cached
        # version is not strictly older than installed (#239: post-upgrade
        # cache poison sanity check — if cache says "latest=1.41.1" but
        # installed=1.43.0, the cache is poisoned, force a refetch).
        if [ -f "$VERSION_CACHE_FILE" ]; then
            if stat -f %m "$VERSION_CACHE_FILE" > /dev/null 2>&1; then
                CACHE_MTIME=$(stat -f %m "$VERSION_CACHE_FILE")
            else
                CACHE_MTIME=$(stat -c %Y "$VERSION_CACHE_FILE" 2>/dev/null || echo 0)
            fi
            CACHE_AGE=$(( $(date +%s) - CACHE_MTIME ))
            if [ "$CACHE_AGE" -lt 86400 ]; then
                CACHE_CONTENT=$(cat "$VERSION_CACHE_FILE" 2>/dev/null) || CACHE_CONTENT=""
                if [[ "$CACHE_CONTENT" =~ $SEMVER_RE ]]; then
                    # Sanity check: cached "latest" must be >= installed.
                    if ! semver_lt "$CACHE_CONTENT" "$INSTALLED_VERSION"; then
                        LATEST_VERSION="$CACHE_CONTENT"
                    fi
                fi
            fi
        fi

        # Fetch from npm if cache miss / stale / malformed / poisoned
        if [ -z "$LATEST_VERSION" ] && command -v npm > /dev/null 2>&1; then
            NPM_RESULT=$(npm view agentic-sdlc-wizard version 2>/dev/null)
            NPM_RC=$?
            if [ "$NPM_RC" -ne 0 ] || ! [[ "$NPM_RESULT" =~ $SEMVER_RE ]]; then
                NPM_FAILED=1
            else
                LATEST_VERSION="$NPM_RESULT"
                mkdir -p "$VERSION_CACHE_DIR" 2>/dev/null || true
                printf '%s' "$LATEST_VERSION" > "$VERSION_CACHE_FILE" 2>/dev/null || true
            fi
        fi

        # #239: surface npm failure once when cache miss + npm fails. Without
        # this, the version-check block produces no output and the user has
        # no way to know the staleness nudge is broken.
        if [ -z "$LATEST_VERSION" ] && [ "$NPM_FAILED" -eq 1 ]; then
            echo "npm view failed — version check unavailable (run 'npm view agentic-sdlc-wizard version' to debug)"
        fi

        # #254 Bug 2: only nudge when installed < latest (semver direction).
        # Equality `!=` previously fired reverse nudges post-upgrade.
        if [ -n "$LATEST_VERSION" ] && semver_lt "$INSTALLED_VERSION" "$LATEST_VERSION"; then
            # Minor-version delta: 1.25.0 vs 1.34.0 → 9
            INSTALLED_MINOR=$(echo "$INSTALLED_VERSION" | awk -F. '{print $2+0}')
            LATEST_MINOR=$(echo "$LATEST_VERSION" | awk -F. '{print $2+0}')
            INSTALLED_MAJOR=$(echo "$INSTALLED_VERSION" | awk -F. '{print $1+0}')
            LATEST_MAJOR=$(echo "$LATEST_VERSION" | awk -F. '{print $1+0}')
            MINOR_DELTA=0
            if [ "$INSTALLED_MAJOR" = "$LATEST_MAJOR" ]; then
                MINOR_DELTA=$(( LATEST_MINOR - INSTALLED_MINOR ))
            else
                # Major bump: treat as a very large delta
                MINOR_DELTA=99
            fi

            if [ "$MINOR_DELTA" -ge 3 ]; then
                echo ""
                echo "!! WARNING: SDLC Harness is ${MINOR_DELTA} minor versions behind !!"
                echo "   Installed: ${INSTALLED_VERSION}"
                echo "   Latest:    ${LATEST_VERSION}"
                echo "   You're missing bug fixes and features shipped across ${MINOR_DELTA} releases."
                echo "   Strongly recommend running /claude-update-wizard before starting new work."
                echo ""
            else
                echo "SDLC Harness update available: ${INSTALLED_VERSION} → ${LATEST_VERSION} (run /claude-update-wizard)"
            fi
        fi
    fi
fi

# Cross-model review staleness check (non-blocking, best-effort)
if command -v codex > /dev/null 2>&1 && [ -d "$PROJECT_DIR/.reviews" ]; then
    REVIEW_FILE="$PROJECT_DIR/.reviews/latest-review.md"
    if [ -f "$REVIEW_FILE" ]; then
        # Get file modification time (macOS stat -f %m, Linux stat -c %Y)
        if stat -f %m "$REVIEW_FILE" > /dev/null 2>&1; then
            REVIEW_MTIME=$(stat -f %m "$REVIEW_FILE")
        else
            REVIEW_MTIME=$(stat -c %Y "$REVIEW_FILE" 2>/dev/null || echo "0")
        fi
        NOW=$(date +%s)
        REVIEW_AGE=$(( (NOW - REVIEW_MTIME) / 86400 ))
        # Count commits since last review
        COMMITS_SINCE=$(git -C "$PROJECT_DIR" log --oneline --after="@${REVIEW_MTIME}" 2>/dev/null | wc -l | tr -d ' ') || true
        if [ "$REVIEW_AGE" -gt 3 ] && [ "${COMMITS_SINCE:-0}" -gt 5 ]; then
            echo "WARNING: ${COMMITS_SINCE} commits over ${REVIEW_AGE}d since last cross-model review — reviews may not be running. Verify: codex exec \"echo test\""
        fi
    fi
fi

# Model/effort upgrade check is delegated to hooks/model-effort-check.sh
# (single source of truth per ROADMAP #217). Don't duplicate the logic here —
# this hook and model-effort-check.sh both fire on SessionStart, so two checks
# would double-print the nudge and risk drifting out of sync.

# Autocompact effective-trigger check (#207, retargeted by #520).
#
# Verified against decompiled Claude Code v2.1.221 (functions EX, CCo, F0s, ZJu,
# fEe, kO); evidence recorded on GH #520:
#
#   window    = min(model_window, clamp(WINDOW_env, 100000..1000000))    [EX]
#   threshold = min(floor(window x pct/100), window - 13000)             [CCo]
#   ...with up to 20000 tokens of system overhead subtracted first       [fEe]
#
# This check originally fired on "both vars set" (#207). That was the wrong
# signature in both directions, and #520 corrects it:
#
#   FALSE POSITIVE — setting both is multiplication, not a misconfiguration.
#   35% of a 1000000 window is a ~350000 trigger, which is a sane deliberate
#   choice for anyone compacting early on purpose (context quality, #483). The
#   old check called that a misconfig, so the hook warned against a working
#   config every session.
#
#   FALSE NEGATIVE — the surprising setting was invisible. A window below
#   200000 makes compaction fire SOONER, and the consumer setting it usually
#   wants exactly that, so this reports rather than warns. (This comment used to
#   claim such a window DISABLED autocompact. It does not: the live path is
#   LXy -> jUe -> zJu, with no bIe gate. ZJu, one letter-case away, arms the
#   precomputed summary and is where that gate actually lives.)
#
# So the signature is the effective trigger landing below 200000, whichever
# vars produced it — not the number of vars set.
# VERIFICATION BASELINE: Claude Code v2.1.221.
#
# Every constant and rule below was read out of that binary, not inferred from
# behaviour: the 13000 hard-compact margin and 20000 overhead (`CCo`, `fEe`),
# the 100000..1000000 clamp (`EX`), the 1/true/yes/on truthy set and its trim
# (`rr`), the merged-settings read (`kO`, `au`), and the divide-before-multiply
# order of the trigger (`CCo`). Naming the baseline is the point: it turns the
# next audit into a diff against one version instead of a re-derivation, which
# is what ends these review rounds rather than restarting them.
AC_FLOOR=200000

# `kO` is checked BEFORE any trigger arithmetic: with compaction off, every
# sentence below about when it "fires" is false. DISABLE_AUTO_COMPACT is read
# from the live env, autoCompactEnabled from settings.
AC_OFF=""
# 1 only when the live env said so. The env is authoritative for its own
# variables; a settings FILE is not, because `kO` reads MERGED settings and
# settings.local.json outranks the project file. This hook cannot resolve that
# precedence, so a file-derived disable is reported conditionally rather than
# asserted — see the reporting block.
AC_OFF_SURE=""
# `bp()`, `rr()` and `qfr()` all trim before doing anything else, so trimming
# here is parity, not politeness: " true " disables compaction in the binary,
# and " 150000 " is a perfectly ordinary window.
_ac_trim() { printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }
# `rr()` is String(e).toLowerCase().trim() and accepts 1/true/yes/on. It
# lowercased but did not trim, so a padded value read as "compaction is on"
# while the binary had already returned.
_ac_truthy() {
    case "$(_ac_trim "${1:-}" | tr 'A-Z' 'a-z')" in 1|true|yes|on) return 0 ;; esac
    return 1
}
if _ac_truthy "${DISABLE_AUTO_COMPACT:-}" || _ac_truthy "${DISABLE_COMPACT:-}"; then
    AC_OFF=1
    AC_OFF_SURE=1
fi

# THE CLAIM DOMAIN.
#
# Everything below computes a token figure, and a wrong figure is worse than no
# figure — it is the exact failure #520 exists to stop. The binary parses with
# `parseFloat` and `bp()`, which accept "1e4", "5.", "1,000,000" and "150k"
# (the last two via a parseInt fallback that silently truncates). Shell cannot
# express those grammars, and three review rounds each found another form.
#
# So the hook declares what it evaluates and refuses to guess at the rest:
#   integers:  ^[0-9]+$        (window, max-output-tokens)
#   decimals:  ^[0-9]+(\.[0-9]+)?$  (percentage — parseFloat honours 30.5)
# Anything else that is SET is named on screen with no number attached. The
# guarantee is then finite and checkable: no input produces a false figure, and
# unsupported input produces no figure.
_ac_is_int() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; return 0; }
_ac_is_dec() { case "$1" in ''|*[!0-9.]*|*.*.*|.*|*.) return 1 ;; esac; return 0; }
# Values that are set but outside the domain. Any entry here suppresses EVERY
# figure, not just the one it came from: an unreadable max-output makes the
# overhead unknowable, which makes the trigger unknowable too.
AC_UNREAD=""

# Overhead is min(max_output_tokens, 20000) [fEe/qfr]. 20000 is the default; a
# lower CLAUDE_CODE_MAX_OUTPUT_TOKENS reduces it and moves the trigger LATER,
# so it is read rather than assumed.
AC_OVH=20000
# "Was the env var set", tracked SEPARATELY from the resulting overhead. The
# result used to double as the sentinel — `AC_OVH -eq 20000` meant "unset" —
# so a live value of 20000 or more, which legitimately caps AT 20000, was
# indistinguishable from no value at all and lost to a stale settings entry.
# That inverted this hook's own live-env-first rule. An env var that is present
# and non-empty settles the question even when the binary then rejects its
# value: the file describes the next session, not this one.
AC_OVH_SET=""
AC_MO_RAW=$(_ac_trim "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}")
if [ -n "$AC_MO_RAW" ]; then
    AC_OVH_SET=1
    if _ac_is_int "$AC_MO_RAW"; then
        # `ABe` rejects 0, so a zero here is ignored and the model default
        # applies — which means the FULL 20000 comes off, not none of it.
        if [ "$((10#$AC_MO_RAW))" -gt 0 ] && [ "$((10#$AC_MO_RAW))" -lt 20000 ]; then
            AC_OVH=$((10#$AC_MO_RAW))
        fi
    else
        AC_UNREAD="CLAUDE_CODE_MAX_OUTPUT_TOKENS='${AC_MO_RAW}'"
    fi
fi

# READ THE LIVE ENV FIRST, settings.json only as a fallback.
#
# An earlier version of this check read `.claude/settings.json` alone, and I
# argued a session hook could not see the environment because it was fixed at
# launch. That was wrong, and cross-model review disproved it by probe: a hook
# is a CHILD PROCESS and inherits the exported variables, so it can read their
# effective values even though it cannot know their source or unset them.
#
# This matters because the env is what actually governs the session, while
# settings.json is only a claim about it. The incident behind #520 was exactly
# that gap — a value inherited from the user's GLOBAL settings, invisible in
# the project file, with the operator reading the file and seeing nothing.
AC_PCT=$(_ac_trim "${CLAUDE_AUTOCOMPACT_PCT_OVERRIDE:-}")
AC_WIN=$(_ac_trim "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}")
AC_SRC="the live environment"
SETTINGS_JSON="$PROJECT_DIR/.claude/settings.json"

# Second half of the kO check: SETTINGS_JSON is only defined here, so reading it
# any earlier tested an empty path and silently found nothing. Both keys get the
# same live-env-first, settings-fallback treatment as the two vars below —
# reading only the live env made a settings-block consumer invisible.
# `kO` reads MERGED settings, so a global autoCompactEnabled:false is just as
# binding as a project one. Checking only the project file under-detected OFF
# and then printed a trigger for compaction that never fires.
for _ac_sf in "$SETTINGS_JSON" "$HOME/.claude/settings.json"; do
    [ -z "$AC_OFF" ] && [ -f "$_ac_sf" ] || continue
    if grep -q '"autoCompactEnabled"[[:space:]]*:[[:space:]]*false' "$_ac_sf" \
       || grep -qiE '"(DISABLE_AUTO_COMPACT|DISABLE_COMPACT)"[[:space:]]*:[[:space:]]*"(1|true|yes|on)"' "$_ac_sf"; then
        AC_OFF=1
        # deliberately NOT AC_OFF_SURE — see its declaration
    fi
done
if [ -z "$AC_OVH_SET" ] && [ -f "$SETTINGS_JSON" ]; then
    AC_MO=$(grep -o '"CLAUDE_CODE_MAX_OUTPUT_TOKENS"[[:space:]]*:[[:space:]]*"[0-9]*"' "$SETTINGS_JSON" \
        | head -1 | sed 's/.*"\([0-9]*\)"$/\1/')
    case "$AC_MO" in
        ''|*[!0-9]*) ;;
        *) if [ "$((10#$AC_MO))" -gt 0 ] && [ "$((10#$AC_MO))" -lt 20000 ]; then AC_OVH=$((10#$AC_MO)); fi ;;
    esac
fi
if [ -z "$AC_PCT" ] && [ -z "$AC_WIN" ] && [ -f "$SETTINGS_JSON" ]; then
    AC_SRC=".claude/settings.json"
    # The sed had to widen with the grep: it still captured [0-9]* only, so a
    # decimal survived the pattern and was then thrown away by the extraction.
    # Capture ANY string value, not just digits. A digits-only pattern made an
    # out-of-domain file value disappear at the grep, which is indistinguishable
    # from "not configured" — the operator then reads the file, sees the key,
    # and sees the hook say nothing about it. Domain filtering happens once,
    # below, for both sources.
    AC_PCT=$(grep -o '"CLAUDE_AUTOCOMPACT_PCT_OVERRIDE"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_JSON" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    AC_WIN=$(grep -o '"CLAUDE_CODE_AUTO_COMPACT_WINDOW"[[:space:]]*:[[:space:]]*"[^"]*"' "$SETTINGS_JSON" \
        | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    AC_PCT=$(_ac_trim "$AC_PCT")
    AC_WIN=$(_ac_trim "$AC_WIN")
fi
# DOMAIN FILTER — one place, both sources, both variables.
#
# In domain: keep the raw string (awk does the arithmetic, so 30.5 survives).
# Out of domain but SET: record it in AC_UNREAD and clear it, which suppresses
# every figure below. Genuinely unset: nothing to say.
#
# PCT=0 and WINDOW=0 are IN domain and read as unset on purpose: `CCo` and
# `ABe` both reject zero and fall back to the model default, so reporting a
# zero-token trigger would be the confident-wrong-number failure this hook
# exists to stop. A leading zero would also make $(( )) read the value as
# octal, so every figure below uses 10#.
if [ -n "$AC_PCT" ]; then
    if _ac_is_dec "$AC_PCT"; then
        # LC_ALL=C on every awk call. parseFloat is locale-independent; awk's
        # numeric conversion is not guaranteed to be, and some awks honour
        # LC_NUMERIC. Not reproduced on the BSD awk this was developed against
        # — the observable difference there is output formatting, which this
        # hook never relies on — but a consumer running an awk that parses
        # "30.5" as 30 under a comma-decimal locale would get a wrong figure
        # introduced by the very fix that made the arithmetic exact.
        if LC_ALL=C awk -v v="$AC_PCT" 'BEGIN{exit !(v+0 == 0)}'; then AC_PCT=""; fi
    else
        AC_UNREAD="${AC_UNREAD:+$AC_UNREAD, }CLAUDE_AUTOCOMPACT_PCT_OVERRIDE='${AC_PCT}'"
        AC_PCT=""
    fi
fi
if [ -n "$AC_WIN" ]; then
    if _ac_is_int "$AC_WIN"; then
        if [ "$((10#$AC_WIN))" -le 0 ]; then AC_WIN=""; else AC_WIN=$((10#$AC_WIN)); fi
    else
        AC_UNREAD="${AC_UNREAD:+$AC_UNREAD, }CLAUDE_CODE_AUTO_COMPACT_WINDOW='${AC_WIN}'"
        AC_WIN=""
    fi
fi

if [ -n "$AC_OFF" ]; then
    if [ -n "$AC_WIN" ] || [ -n "$AC_PCT" ] || [ -n "$AC_UNREAD" ]; then
        if [ -n "$AC_OFF_SURE" ]; then
            echo "NOTE: auto-compaction is OFF — DISABLE_AUTO_COMPACT / DISABLE_COMPACT is set in the environment, so the window and percentage vars have no effect and the session runs to the hard limit. Nothing can unset an env var in a live process; you need claude --resume (#520)."
        else
            echo "NOTE: a settings file sets autoCompactEnabled false (or a disable var), which would make the window and percentage vars inert. Claude Code merges settings and settings.local.json outranks the project file, so confirm with /config before trusting it. Flipping the key back takes effect immediately (#520)."
        fi
    fi
elif [ -n "$AC_UNREAD" ]; then
    # A value is set that this hook does not evaluate. Print NO figure: the
    # binary would accept it, so any number computed by pretending it is unset
    # would be confidently wrong. Name it instead, so the operator can see the
    # hook read it and declined, rather than wondering whether it was noticed.
    echo "NOTE: ${AC_UNREAD} (from ${AC_SRC}) — this hook evaluates plain integers only (plus a decimal percentage), so it is computing no trigger. Claude Code DOES read 1e4, 5. and 150k — and a suffix is not its human meaning: 150k parses as 150. Use a plain integer (#520)."
elif [ -n "$AC_WIN" ]; then
    # ONE computation, not one per branch. The previous shape had a
    # sub-200000 branch ahead of a both-set branch, so WINDOW=150000 with
    # PCT=30 printed 117000 while the binary computed min(30% x 130000,
    # 117000) = 39000: an active percentage was dropped purely by which elif
    # won. Any branch that computes its own figure eventually disagrees with
    # its sibling, so there is now a single arithmetic path and the branching
    # is confined to WORDING.
    #
    #   window    = min(model_window, clamp(WINDOW, 100000..1000000))  [EX]
    #   effective = window - min(max_output_tokens, 20000)             [fEe]
    #   trigger   = min(effective x pct/100, effective - 13000)        [CCo]
    #
    # The clamp is load-bearing in both directions: 15% of a stated 2000000
    # looks like 300000, but the window caps at 1000000 so the real figure is
    # 150000; and 50000 is raised to 100000, so its trigger is 67000 and not
    # the smaller number a raw subtraction gives.
    AC_WIN_EFF="$AC_WIN"
    [ "$AC_WIN_EFF" -gt 1000000 ] && AC_WIN_EFF=1000000
    [ "$AC_WIN_EFF" -lt 100000 ] && AC_WIN_EFF=100000
    AC_WIN_EFF=$(( AC_WIN_EFF - AC_OVH ))
    AC_CAP=$(( AC_WIN_EFF - 13000 ))
    AC_TRIGGER="$AC_CAP"
    if [ -n "$AC_PCT" ]; then
        # awk, because parseFloat accepts 30.5 and shell arithmetic does not.
        AC_TRIGGER=$(LC_ALL=C awk -v w="$AC_WIN_EFF" -v p="$AC_PCT" -v c="$AC_CAP" \
            'BEGIN{t=int(w*(p/100)); if (t>c) t=c; print t}')
    fi
    # The hook cannot know which model will run and a smaller model's window
    # wins the min(), so it also evaluates the SAME formula at 200000 and
    # reports that as fact. An earlier version said "roughly a third" instead,
    # which is wrong for most inputs, and pairing a wrong ratio with "not an
    # error" approved a trigger it had mis-stated. Do NOT compare this figure
    # against AC_FLOOR: a 200K window caps at 187000, so the floor would flag
    # every user of this branch.
    AC_WIN_200=$(( 200000 - AC_OVH ))
    [ "$AC_WIN_200" -gt "$AC_WIN_EFF" ] && AC_WIN_200="$AC_WIN_EFF"
    AC_CAP_200=$(( AC_WIN_200 - 13000 ))
    AC_TRIG_200="$AC_CAP_200"
    if [ -n "$AC_PCT" ]; then
        AC_TRIG_200=$(LC_ALL=C awk -v w="$AC_WIN_200" -v p="$AC_PCT" -v c="$AC_CAP_200" \
            'BEGIN{t=int(w*(p/100)); if (t>c) t=c; print t}')
    fi
    AC_VARS="CLAUDE_CODE_AUTO_COMPACT_WINDOW=${AC_WIN}"
    # Keep the SOONER framing for a sub-200000 window. That range was
    # previously reported as DISABLED, with advice to raise the value — advice
    # that moved the trigger LATER for someone whose config already did what
    # they wanted. The correction is the point, so it survives the merge of the
    # two branches into one.
    AC_TAIL=""
    if [ "$AC_WIN" -lt "$AC_FLOOR" ]; then
        AC_TAIL=" A window this size compacts SOONER, not never — nothing in that range switches compaction off."
    fi
    # `CCo` ignores any percentage outside 0-100 and falls back to the cap. The
    # min() already made the FIGURE right by coincidence; the sentence still
    # said the two vars "multiply", which is a false claim about the mechanism
    # standing next to a true number. Under a no-false-claims invariant the
    # mechanism is a claim too.
    if [ -n "$AC_PCT" ]; then
        if LC_ALL=C awk -v v="$AC_PCT" 'BEGIN{exit !(v+0 > 100)}'; then
            AC_VARS="CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=${AC_PCT} is outside 0-100 and ignored, leaving ${AC_VARS}, so"
        else
            AC_VARS="CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=${AC_PCT} and ${AC_VARS} multiply, so"
        fi
    fi
    if [ "$AC_TRIGGER" -lt "$AC_FLOOR" ]; then
        echo "WARNING: autocompact fires at ${AC_TRIGGER} tokens or less — ${AC_VARS} (from ${AC_SRC}). On a 200K-window model: ${AC_TRIG_200}. Raise the product past 200000 or drop either (#207, #520).${AC_TAIL}"
    else
        echo "NOTE: autocompact fires at ${AC_TRIGGER} tokens AT MOST — ${AC_VARS} (from ${AC_SRC}). On a 200K-window model the same setting fires at ${AC_TRIG_200}. Setting CLAUDE_CODE_AUTO_COMPACT_WINDOW alone is steadier (#520).${AC_TAIL}"
    fi
fi

# Dual-channel install check (#181) — nudge when CLI skills + Claude plugin both present.
# #238: silenced once the user opts in via an ack sentinel. Sentinel is per-host
# (lives under $SDLC_WIZARD_CACHE_DIR/dual-channel-acknowledged) since the dual
# install is always a $HOME-scoped condition.
DUAL_CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
DUAL_ACK_FILE="$DUAL_CACHE_DIR/dual-channel-acknowledged"
if [ -d "$PROJECT_DIR/.claude/skills/update" ] && [ ! -f "$DUAL_ACK_FILE" ]; then
    for plugin_path in "$HOME/.claude/plugins-local/sdlc-wizard-wrap" "$HOME/.claude/plugins/cache/sdlc-wizard-local"; do
        if [ -d "$plugin_path" ]; then
            echo "WARNING: dual-install detected — CLI skills in .claude/skills/ AND Claude plugin at:"
            echo "  $plugin_path"
            echo "  Duplicate /claude-update-wizard commands come from running both channels. Pick one:"
            echo "    - Keep plugin: remove .claude/skills/ from this project"
            echo "    - Keep CLI:    /plugin uninstall sdlc-wizard (or remove plugin dir)"
            echo "    - Keep both:   mkdir -p \"$DUAL_CACHE_DIR\" && touch \"$DUAL_ACK_FILE\"  (silences this nudge)"
            break
        fi
    done
fi

# API feature review nudge (#100) — surface open 'api-review-needed' issues
# opened by .github/workflows/weekly-api-update.yml so the session picks up
# new API features without waiting for manual discovery.
#
# Gated on LOCAL presence of the detector workflow: the CLI distributes this
# hook to consumer projects, and we don't want to pester those users with
# upstream-wizard issues. The nudge only fires when the current repo owns
# the detector (= the wizard repo or a fork of it).
if [ -f "$PROJECT_DIR/.github/workflows/weekly-api-update.yml" ] && \
   command -v gh > /dev/null 2>&1; then
    # Query the current repo (not hardcoded upstream) — in a fork, users see
    # their own detector's issues, not ours.
    API_REVIEW_COUNT=$(gh issue list \
        --state open \
        --label "api-review-needed" \
        --limit 1 \
        --json number \
        --jq 'length' 2>/dev/null) || API_REVIEW_COUNT=""
    if [[ "$API_REVIEW_COUNT" =~ ^[0-9]+$ ]] && [ "$API_REVIEW_COUNT" -gt 0 ]; then
        echo "Anthropic API features pending review: ${API_REVIEW_COUNT} open issue(s) with label 'api-review-needed' (see .github/workflows/weekly-api-update.yml)"
    fi
fi

# Claude Code release review nudge (#85) — surface open 'auto-update' PRs
# opened by .github/workflows/weekly-update.yml so new CC releases get triaged
# before they bit-rot (relevance-HIGH PRs can sit for days otherwise).
#
# Gated on LOCAL presence of weekly-update.yml: the CLI distributes this hook
# to consumer projects, which don't own the detector — don't pester them with
# upstream-wizard PRs.
if [ -f "$PROJECT_DIR/.github/workflows/weekly-update.yml" ] && \
   command -v gh > /dev/null 2>&1; then
    CC_UPDATE_COUNT=$(gh pr list \
        --state open \
        --label "auto-update" \
        --limit 1 \
        --json number \
        --jq 'length' 2>/dev/null) || CC_UPDATE_COUNT=""
    if [[ "$CC_UPDATE_COUNT" =~ ^[0-9]+$ ]] && [ "$CC_UPDATE_COUNT" -gt 0 ]; then
        echo "Claude Code update pending review: ${CC_UPDATE_COUNT} open auto-update PR(s) (see .github/workflows/weekly-update.yml)"
    fi
fi

# Claude Code version check (non-blocking, best-effort)
# Gate on CLAUDE_PROJECT_DIR — only Claude Code sets this. Without it, we're
# running under Codex/OpenCode where a CC update nudge is misleading (#375).
# #236(b): was an uncached npm network call on every session start with a
# bare `!=` comparison (fires in either direction, including when local is
# actually AHEAD of the cached/published "latest") — the exact bug class
# already fixed above for the wizard's own version check (#254 Bug 2). Now
# reuses the same 24h cache + semver_lt direction check.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && command -v claude > /dev/null 2>&1 && command -v npm > /dev/null 2>&1; then
    CC_LOCAL=$(claude --version 2>/dev/null | grep -o '[0-9][0-9.]*' | head -1) || true
    if [ -n "$CC_LOCAL" ] && [[ "$CC_LOCAL" =~ $SEMVER_RE ]]; then
        CC_CACHE_DIR="${SDLC_WIZARD_CACHE_DIR:-$HOME/.cache/sdlc-wizard}"
        CC_CACHE_FILE="$CC_CACHE_DIR/latest-cc-version"
        CC_LATEST=""

        if [ -f "$CC_CACHE_FILE" ]; then
            if stat -f %m "$CC_CACHE_FILE" > /dev/null 2>&1; then
                CC_CACHE_MTIME=$(stat -f %m "$CC_CACHE_FILE")
            else
                CC_CACHE_MTIME=$(stat -c %Y "$CC_CACHE_FILE" 2>/dev/null || echo 0)
            fi
            CC_CACHE_AGE=$(( $(date +%s) - CC_CACHE_MTIME ))
            if [ "$CC_CACHE_AGE" -lt 86400 ]; then
                CC_CACHE_CONTENT=$(cat "$CC_CACHE_FILE" 2>/dev/null) || CC_CACHE_CONTENT=""
                if [[ "$CC_CACHE_CONTENT" =~ $SEMVER_RE ]] && ! semver_lt "$CC_CACHE_CONTENT" "$CC_LOCAL"; then
                    CC_LATEST="$CC_CACHE_CONTENT"
                fi
            fi
        fi

        if [ -z "$CC_LATEST" ]; then
            CC_NPM_RESULT=$(npm view @anthropic-ai/claude-code version 2>/dev/null) || true
            if [[ "$CC_NPM_RESULT" =~ $SEMVER_RE ]]; then
                CC_LATEST="$CC_NPM_RESULT"
                mkdir -p "$CC_CACHE_DIR" 2>/dev/null || true
                printf '%s' "$CC_LATEST" > "$CC_CACHE_FILE" 2>/dev/null || true
            fi
        fi

        if [ -n "$CC_LATEST" ] && semver_lt "$CC_LOCAL" "$CC_LATEST"; then
            # Do NOT name a single install channel here (GH #476). The old text
            # named the global npm install unconditionally.
            # Stated precisely, because the earlier fix overstated it: the docs
            # do NOT ban a non-sudo global npm install — they mark the native
            # install "Recommended", warn specifically against `sudo npm -g`
            # (it creates the ownership problems that break later updates), and
            # this hook cannot tell which channel installed the running binary.
            # Naming npm therefore risks telling a Homebrew/apt/WinGet user to
            # switch channels, which is its own breakage. `claude update` covers
            # native and npm; package-managed installs must go through their
            # manager, which `claude update` reports as already current.
            echo "Claude Code update available: ${CC_LOCAL} → ${CC_LATEST} (native or npm: run 'claude update'; installed via a package manager such as brew/apt/dnf/apk/winget: update through that manager)"
        fi
    fi
fi

exit 0
