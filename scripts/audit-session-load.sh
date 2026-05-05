#!/bin/bash
# Inventory every asset that gets loaded into a CC session and rank by
# character count. Output: sorted table with trim-candidate flags (>5K tokens
# ≈ 20000 chars per OpenAI's 4-chars-per-token rule of thumb).
#
# Token bloat audit phase 2 (ROADMAP "Next Up" item 8 follow-up):
# Phase 1 (DONE 2026-04-24) fixed the smoking gun — dual-channel hook
# registration causing 2× SDLC BASELINE injections. Phase 2 is observability:
# a mechanical inventory of every file/output that hits a session, so trim
# candidates surface before they bloat the context budget.
#
# Usage:
#   scripts/audit-session-load.sh           # human-readable table
#   scripts/audit-session-load.sh --json    # machine-readable
#
# What's inventoried (when present at $ROOT):
#   - CLAUDE.md / SDLC.md / TESTING.md / ARCHITECTURE.md / MEMORY.md
#   - All hooks/*.sh (dev-repo path) AND .claude/hooks/*.sh (consumer install
#     via cli/init.js). Script size, NOT runtime stdout — that's separately
#     gated by the existing brevity-cap tests in tests/test-hooks.sh.
#   - All skills/*/SKILL.md (dev-repo path) AND .claude/skills/*/SKILL.md
#     (consumer install path; cli/init.js:32-35 copies SKILL.md files there).
#
# Output columns: SIZE_CHARS, EST_TOKENS (chars/4), TYPE, FLAG, PATH
# FLAG = "OK" if <5K tokens, "TRIM" if >=5K tokens.
#
# Trim threshold rationale: 5000 tokens ≈ 20000 chars. CLAUDE.md alone
# routinely runs 8-12K chars in active projects; >20K chars is genuinely
# excessive and worth surgery.

set -e

ROOT="${SDLC_AUDIT_ROOT:-${1:-$PWD}}"
# If the first arg is a flag, treat ROOT as cwd.
case "${1:-}" in
    --json|--help|-h) ROOT="${SDLC_AUDIT_ROOT:-$PWD}" ;;
esac

JSON_MODE=0
for arg in "$@"; do
    [ "$arg" = "--json" ] && JSON_MODE=1
    [ "$arg" = "--help" ] || [ "$arg" = "-h" ] && {
        sed -n '1,30p' "$0" | grep -E '^#' | sed 's/^# *//'
        exit 0
    }
done

# Trim threshold in tokens (chars/4). 5000 tokens = 20000 chars.
THRESHOLD_TOKENS="${SDLC_AUDIT_THRESHOLD_TOKENS:-5000}"
THRESHOLD_CHARS=$(( THRESHOLD_TOKENS * 4 ))

# Collect inventory entries as TSV: SIZE_CHARS\tTYPE\tPATH
ENTRIES=""

add_entry() {
    local path="$1" type="$2"
    [ -f "$path" ] || return 0
    local size
    size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    [ -z "$size" ] && size=0
    # Use printf to avoid echo's interpretation of backslashes
    ENTRIES=$(printf '%s\n%s\t%s\t%s' "$ENTRIES" "$size" "$type" "$path")
}

# Project-level instruction docs
for f in CLAUDE.md SDLC.md TESTING.md ARCHITECTURE.md MEMORY.md; do
    add_entry "$ROOT/$f" "instructions"
done

# Hook scripts (file size — runtime stdout is gated separately)
if [ -d "$ROOT/hooks" ]; then
    for h in "$ROOT/hooks"/*.sh; do
        [ -f "$h" ] && add_entry "$h" "hook"
    done
fi
# Also check .claude/hooks/ if separate (consumer install path)
if [ -d "$ROOT/.claude/hooks" ] && [ "$ROOT/.claude/hooks" != "$ROOT/hooks" ]; then
    for h in "$ROOT/.claude/hooks"/*.sh; do
        [ -f "$h" ] && add_entry "$h" "hook"
    done
fi

# Skill markdown
if [ -d "$ROOT/skills" ]; then
    for s in "$ROOT/skills"/*/SKILL.md; do
        [ -f "$s" ] && add_entry "$s" "skill"
    done
fi
# Also check .claude/skills/ if separate (consumer install path).
# cli/init.js:32-35 copies SKILL.md files to .claude/skills/<name>/SKILL.md
# at install time. Without this scan, the audit silently ignores all
# bloat in real consumer projects. Mirrors the .claude/hooks/ pattern
# above (will double-count in dogfood where .claude/skills/ symlinks
# back to skills/, same trade-off as hooks).
if [ -d "$ROOT/.claude/skills" ] && [ "$ROOT/.claude/skills" != "$ROOT/skills" ]; then
    for skill_dir in "$ROOT/.claude/skills"/*/; do
        [ -d "$skill_dir" ] || continue
        skill_md="${skill_dir}SKILL.md"
        [ -f "$skill_md" ] && add_entry "$skill_md" "skill"
    done
fi

# Strip leading newline from accumulator
ENTRIES=$(printf '%s' "$ENTRIES" | sed '/^$/d')

if [ -z "$ENTRIES" ]; then
    if [ "$JSON_MODE" = "1" ]; then
        echo '{"entries": [], "total_chars": 0, "total_tokens_est": 0, "trim_candidates": []}'
    else
        echo "No session-loaded assets found at $ROOT"
    fi
    exit 0
fi

# Sort by size descending
SORTED=$(printf '%s\n' "$ENTRIES" | sort -rn -t$'\t' -k1)

if [ "$JSON_MODE" = "1" ]; then
    # Emit JSON for tooling / CI consumers
    {
        echo '{'
        echo '  "entries": ['
        first=1
        total_chars=0
        trim_count=0
        printf '%s\n' "$SORTED" | while IFS=$'\t' read -r size type path; do
            [ -z "$size" ] && continue
            tokens=$(( size / 4 ))
            flag="OK"
            [ "$size" -ge "$THRESHOLD_CHARS" ] && flag="TRIM"
            [ "$first" = "0" ] && echo ','
            printf '    {"size_chars": %s, "tokens_est": %d, "type": "%s", "flag": "%s", "path": "%s"}' \
                "$size" "$tokens" "$type" "$flag" "$path"
            first=0
        done
        echo ''
        echo '  ],'
        # Recompute totals (subshell scoping)
        total_chars=$(printf '%s\n' "$SORTED" | awk -F'\t' '{s += $1} END {print s+0}')
        total_tokens=$(( total_chars / 4 ))
        trim_count=$(printf '%s\n' "$SORTED" | awk -F'\t' -v t="$THRESHOLD_CHARS" '$1 >= t {n++} END {print n+0}')
        printf '  "total_chars": %s,\n' "$total_chars"
        printf '  "total_tokens_est": %s,\n' "$total_tokens"
        printf '  "threshold_tokens": %s,\n' "$THRESHOLD_TOKENS"
        printf '  "trim_candidate_count": %s\n' "$trim_count"
        echo '}'
    }
else
    # Human-readable table
    printf '%-10s %-10s %-12s %-6s %s\n' "SIZE_CHARS" "EST_TOKENS" "TYPE" "FLAG" "PATH"
    printf '%-10s %-10s %-12s %-6s %s\n' "----------" "----------" "------------" "------" "----"
    printf '%s\n' "$SORTED" | while IFS=$'\t' read -r size type path; do
        [ -z "$size" ] && continue
        tokens=$(( size / 4 ))
        flag="OK"
        [ "$size" -ge "$THRESHOLD_CHARS" ] && flag="TRIM"
        # Strip $ROOT prefix so paths are relative for readability
        rel="${path#${ROOT}/}"
        printf '%-10s %-10s %-12s %-6s %s\n' "$size" "$tokens" "$type" "$flag" "$rel"
    done
    echo ""
    total_chars=$(printf '%s\n' "$SORTED" | awk -F'\t' '{s += $1} END {print s+0}')
    total_tokens=$(( total_chars / 4 ))
    trim_count=$(printf '%s\n' "$SORTED" | awk -F'\t' -v t="$THRESHOLD_CHARS" '$1 >= t {n++} END {print n+0}')
    printf 'Total: %s chars (~%s tokens). %s trim candidates (>=%s tokens).\n' \
        "$total_chars" "$total_tokens" "$trim_count" "$THRESHOLD_TOKENS"
fi
