#!/bin/bash
# PreToolUse hook — redirects `gh pr merge` to scripts/merge-pr.sh
#
# Repo-local only (not in hooks/hooks.json, does not ship to consumer repos —
# see CLAUDE_CODE_SDLC_WIZARD.md's CI Feedback Loop section and ROADMAP.md
# for why this stays local to this repo's own contribution workflow).
#
# This hook does ZERO verification itself — it only redirects. All real
# checking (CI status, cross-model clearance, release/policy-adjacency
# denylist, TOCTOU-safe merge) lives in scripts/merge-pr.sh, which is
# TDD-testable as ordinary bash without simulating hook payloads. Keeping
# the hook this dumb also keeps it fast and keeps `gh`/network calls out of
# hook execution, where this repo's own memory notes sandbox/TLS-proxy
# issues are already handled in the normal Bash-tool path instead.
#
# Command extraction mirrors hooks/codex-gate-check.sh verbatim (that
# escape-aware pattern was hardened through two real review rounds: round 1's
# naive `[^"]*` broke on embedded quotes; round 2's raw-TOOL_INPUT match
# false-positived on prose mentioning the target phrase in an unrelated
# field) — reused rather than reinvented, per Fable's explicit design
# guidance not to re-solve an already-solved problem.

set -e

# Skip gate if explicitly overridden (emergency bypass with logged
# justification) — separate from scripts/merge-pr.sh's own bypass; both
# must be set to fully skip the mechanism, intentional friction.
[ "${MERGE_CLEARANCE_SKIP:-}" = "1" ] && exit 0

TOOL_INPUT=$(cat)

COMMAND_FIELD=$(printf '%s' "$TOOL_INPUT" \
    | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' || true)

COMMAND_VALUE=$(printf '%s' "$COMMAND_FIELD" \
    | sed -E 's/^"command"[[:space:]]*:[[:space:]]*"(.*)"$/\1/')

# JSON encodes embedded newlines as the two-character escape `\n`, not a
# real newline — a multi-line command (e.g. one containing a heredoc) still
# arrives here as a single line of text with literal backslash-n sequences.
# The heredoc-stripping step below is line-based (awk), so it needs real
# line breaks to find the heredoc's closing marker on its own line. `%b`
# interprets backslash escapes (\n, \t, etc.); JSON's other escapes (\", \\)
# are left as harmless literal backslash sequences, which downstream
# matching doesn't care about.
COMMAND_VALUE=$(printf '%b' "$COMMAND_VALUE")

# Codex round-1 review (2026-07-21) found the original design's masking step
# (collapsing EVERY quoted span to a placeholder before matching) hid a
# merge command whenever it appeared inside a nested shell invocation, e.g.
# `bash -lc 'gh pr merge 123 --squash'` — the whole single-quoted argument
# got masked away before the phrase check ever ran. Round 1's fix dropped
# masking entirely, but Codex round 2 found that over-corrected: it made
# ANY quoted text matching-eligible, including inert string arguments to
# unrelated commands (`printf '\''...gh pr merge...'\''`, `git commit -m
# '\''...gh pr merge...'\''`) — false positives, the same class as the P2
# heredoc finding, just for quotes instead of heredocs.
#
# Round-2 fix: quoted content is executable — and therefore worth exposing
# to the match — ONLY when it's the argument to a shell-exec wrapper
# (`bash -c`/`-lc`, `sh -c`, `zsh -c`, `eval`). Extract that specific
# content first (EXEC_CONTENT), THEN mask every quoted span in the main
# command (hiding inert data like commit messages/printf args), and check
# both the masked main text and the separately-extracted exec content.
EXEC_CONTENT=$(printf '%s' "$COMMAND_VALUE" | grep -oE "\\b(bash|sh|zsh)[[:space:]]+-l?c[[:space:]]+'([^'\\\\]|\\\\.)*'|\\beval[[:space:]]+'([^'\\\\]|\\\\.)*'|\\b(bash|sh|zsh)[[:space:]]+-l?c[[:space:]]+\"([^\"\\\\]|\\\\.)*\"|\\beval[[:space:]]+\"([^\"\\\\]|\\\\.)*\"" \
    | sed -E "s/^[^'\"]*['\"](.*)['\"]\$/\\1/")

MASKED_COMMAND=$(printf '%s' "$COMMAND_VALUE" \
    | sed -E -e "s/'([^'\\\\]|\\\\.)*'/Q/g" -e 's/"([^"\\]|\\.)*"/Q/g')

# Strip heredoc BODIES specifically (content written to a file via
# `<< 'EOF' ... EOF`, never executed) before matching — this is a separate
# false-positive class from the quote-masking above, since heredoc markers
# (`<<`) aren't quotes. This was Codex's original P2 finding (2026-07-21):
# a preflight doc's own explanatory prose, written via a Bash heredoc,
# false-triggered this hook during this session.
STRIPPED_COMMAND=$(printf '%s' "$MASKED_COMMAND" | awk '
    BEGIN { in_heredoc = 0; marker = "" }
    {
        if (in_heredoc) {
            line = $0
            sub(/^[[:space:]]*/, "", line)
            if (line == marker) { in_heredoc = 0 }
            next
        }
        line = $0
        if (match(line, /<<-?[[:space:]]*["'"'"']?[A-Za-z_][A-Za-z0-9_]*["'"'"']?/)) {
            m = substr(line, RSTART, RLENGTH)
            gsub(/<<-?[[:space:]]*/, "", m)
            gsub(/["'"'"']/, "", m)
            marker = m
            in_heredoc = 1
        }
        print line
    }
')

# Matches "gh" + optional global flags (e.g. -R owner/repo, --repo=...) +
# "pr" + "merge" — Codex round-1 finding: the original regex required "gh"
# immediately adjacent to "pr", missing the common, non-adversarial
# `gh -R owner/repo pr merge` form.
GH_PR_MERGE_RE='\bgh([[:space:]]+(-R[[:space:]]*[^[:space:]]+|--repo(=|[[:space:]]+)[^[:space:]]+))*[[:space:]]+pr[[:space:]]+merge\b'
# Matches hitting the merge REST endpoint directly via `gh api`, bypassing
# the `gh pr merge` phrase entirely — Codex round-1 finding.
GH_API_MERGE_RE='\bgh[[:space:]]+api\b.*pulls/[0-9]+/merge\b'

# Codex round-2 finding: a user-configured `gh` alias (e.g. `gh land` -> `pr
# merge`) bypasses literal-text matching entirely, since the expansion
# happens inside gh itself, invisible in the command text. `gh alias list`
# is local and instant (~50ms, no network — confirmed before adding this),
# so querying it doesn't violate the hook's "stay dumb, no network calls"
# design; it's comparable in cost to reading a local config file. Any alias
# whose expansion contains "pr" and "merge" is treated as equivalent to the
# literal phrase.
ALIAS_MATCH_RE=""
if command -v gh >/dev/null 2>&1; then
    # BSD awk (macOS default) doesn't support \b word-boundary regex —
    # unlike grep -E/GH_PR_MERGE_RE above (which run through a system grep
    # that does support \b), so this pattern uses plain substring matching.
    ALIAS_NAMES=$(gh alias list 2>/dev/null | awk -F': ' '$2 ~ /pr.*merge|merge.*pr/ {print $1}')
    if [ -n "$ALIAS_NAMES" ]; then
        ALIAS_MATCH_RE=$(printf '%s' "$ALIAS_NAMES" | tr '\n' '|' | sed 's/|$//')
    fi
fi

check_merge_match() {
    local text="$1"
    [ -z "$text" ] && return 1
    printf '%s' "$text" | grep -qE "$GH_PR_MERGE_RE" && return 0
    printf '%s' "$text" | grep -qE "$GH_API_MERGE_RE" && return 0
    if [ -n "$ALIAS_MATCH_RE" ] && printf '%s' "$text" | grep -qE "\\bgh[[:space:]]+($ALIAS_MATCH_RE)\\b"; then
        return 0
    fi
    return 1
}

MATCHED_MERGE=0
if check_merge_match "$STRIPPED_COMMAND"; then
    MATCHED_MERGE=1
elif check_merge_match "$EXEC_CONTENT"; then
    MATCHED_MERGE=1
fi

[ "$MATCHED_MERGE" -eq 0 ] && exit 0

# `gh pr merge --auto` (GitHub's own auto-merge-on-green feature) stays
# permanently, unconditionally banned regardless of clearance — never
# presented as something the wrapper can satisfy. Checked against both the
# masked main command and the exec-wrapper content, matching the same two
# surfaces the merge-phrase match itself checks.
if printf '%s\n%s' "$STRIPPED_COMMAND" "$EXEC_CONTENT" | grep -qE '\-\-auto\b'; then
    echo "BLOCKED: 'gh pr merge --auto' is permanently, unconditionally banned (PR #145 incident — auto-merge fires before review feedback can be read). This is not routable through scripts/merge-pr.sh or any other mechanism." >&2
    exit 2
fi

echo "BLOCKED: use scripts/merge-pr.sh <PR#> instead of 'gh pr merge' directly — it enforces CI-green + cross-model clearance + release/policy-adjacency checks that a bare gh invocation skips. See CLAUDE_CODE_SDLC_WIZARD.md's CI Feedback Loop section and ROADMAP.md for why. Set MERGE_CLEARANCE_SKIP=1 to bypass with justification (also required on scripts/merge-pr.sh itself to fully skip)." >&2
exit 2
