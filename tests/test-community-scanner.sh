#!/bin/bash
# Roadmap #207: community feature-discovery scanner.
# Surfaces NEW slash-command mentions from external sources (Reddit, HN, Discord
# transcripts) that the wizard doesn't already know about. Output is a JSON
# digest the maintainer triages.


# macOS has no C.UTF-8 locale (it is glibc-only). When a caller exports it,
# bash warns on stderr, and every capture below merges stderr via 2>&1 — so the
# warning lands inside the value being asserted and fails unrelated checks.
# Filter the warning specifically; do not force a locale, which would hide
# real stderr from the script under test. (Confirmed: 14 + 2 false failures.)
strip_locale_warning() { grep -v 'warning: setlocale' || true; }

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCANNER="$SCRIPT_DIR/e2e/scan-community.sh"
ALLOWLIST="$SCRIPT_DIR/e2e/known-slash-commands.txt"
FIXTURES="$SCRIPT_DIR/fixtures/community-scanner"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== Community Feature-Discovery Scanner Tests (Roadmap #207) ==="
echo ""

setup_fixtures() {
    mkdir -p "$FIXTURES"
    cat > "$FIXTURES/transcript-newthing.txt" <<'EOF'
Reddit r/ClaudeAI thread, 2026-04-22:
"Did you all see the new /newthing command in CC 2.1.119? It auto-summarizes
the last 50 turns. Way better than /compact for context migration."

Reply: "I tried /help to see the full list, /newthing is also there. Slick."

Another reply: "Also /usage now shows token-by-tool breakdown. Not sure when
that landed but it's been there for a couple releases."
EOF

    cat > "$FIXTURES/transcript-noise.txt" <<'EOF'
Just running my normal workflow today. Used /help, /clear, /model, /effort,
/usage, /compact. Nothing unusual. The wizard's /sdlc skill kept me on track.
EOF

    cat > "$FIXTURES/transcript-multi.txt" <<'EOF'
Mentions of /alpha and /beta in this thread. Then /alpha appears again later.
Also someone mentioned /gamma once. Note: /sdlc is a wizard skill so should be
filtered.
EOF

    cat > "$FIXTURES/transcript-empty.txt" <<'EOF'
This text has no slash commands at all. Just regular prose about the weather.
EOF
}

setup_fixtures

# ---- Tests ----

test_scanner_exists() {
    if [ -x "$SCANNER" ]; then
        pass "scanner script exists and is executable"
    else
        fail "scanner script not found or not executable: $SCANNER"
    fi
}

test_allowlist_exists() {
    if [ -f "$ALLOWLIST" ]; then
        pass "allowlist file exists"
    else
        fail "allowlist file missing: $ALLOWLIST"
    fi
}

test_detects_new_slash_command() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-newthing.txt" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/newthing' in candidates, f'expected /newthing in candidates, got {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner emits /newthing as a candidate"
    else
        fail "scanner missed /newthing. Output: $out"
    fi
}

test_filters_known_commands() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-newthing.txt" 2>&1 | strip_locale_warning)
    # /help and /usage should NOT be in candidates (they are well-known)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/help' not in candidates, f'/help leaked into candidates: {candidates}'
assert '/usage' not in candidates, f'/usage leaked into candidates: {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner filters known CC native commands (/help, /usage) from candidates"
    else
        fail "scanner failed to filter known commands. Output: $out"
    fi
}

# /insights must filter as known after ROADMAP #235b appended it to
# tests/e2e/known-slash-commands.txt. Without this, every weekly run flags
# /insights as a candidate (noise — it's been native CC since v2.1.101).
test_filters_insights_as_known() {
    local fixture="$FIXTURES/transcript-insights.txt"
    # Generate a tiny fixture inline (kept here so the test is self-contained
    # and doesn't depend on an external fixture file existing).
    printf 'Did anyone try /insights yet? Friction counts looked interesting.\n' > "$fixture"
    local out
    out=$(bash "$SCANNER" "$fixture" 2>&1 | strip_locale_warning)
    rm -f "$fixture"
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/insights' not in candidates, f'/insights leaked into candidates (ROADMAP #235b — must be in known-slash-commands.txt allowlist): {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner filters /insights as known (ROADMAP #235b)"
    else
        fail "scanner did not filter /insights — check tests/e2e/known-slash-commands.txt has '/insights' listed. Output: $out"
    fi
}

test_filters_wizard_skills() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-multi.txt" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/sdlc' not in candidates, f'/sdlc leaked into candidates (wizard skill): {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner filters wizard skills (/sdlc) from candidates"
    else
        fail "scanner failed to filter wizard skills. Output: $out"
    fi
}

test_dedupes_and_counts() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-multi.txt" 2>&1 | strip_locale_warning)
    # /alpha appears twice, /beta once, /gamma once. Each should appear once
    # in candidates, with appropriate counts.
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
cand_map = {c['slash']: c['count'] for c in d.get('candidates', [])}
assert cand_map.get('/alpha') == 2, f'/alpha count: {cand_map.get(\"/alpha\")}, expected 2'
assert cand_map.get('/beta') == 1, f'/beta count: {cand_map.get(\"/beta\")}, expected 1'
assert cand_map.get('/gamma') == 1, f'/gamma count: {cand_map.get(\"/gamma\")}, expected 1'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner dedupes and counts correctly (/alpha=2, /beta=1, /gamma=1)"
    else
        fail "dedup/count failed. Output: $out"
    fi
}

test_empty_input_returns_empty_candidates() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-empty.txt" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('candidates', []) == [], f'expected empty candidates, got {d.get(\"candidates\")}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "empty/no-slash-command input returns empty candidates"
    else
        fail "scanner returned non-empty candidates for empty input. Output: $out"
    fi
}

test_outputs_valid_json() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-newthing.txt" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'scan_date' in d, 'missing scan_date'
assert 'candidates' in d, 'missing candidates'
assert isinstance(d['candidates'], list), 'candidates is not a list'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "output is valid JSON with scan_date + candidates fields"
    else
        fail "output is not valid JSON. Output: $out"
    fi
}

test_handles_stdin() {
    local out
    out=$(echo "Try /stdintest in this prompt" | bash "$SCANNER" - 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/stdintest' in candidates, f'expected /stdintest from stdin, got {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner accepts stdin input via '-' arg"
    else
        fail "scanner did not handle stdin. Output: $out"
    fi
}

test_handles_multiple_files() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-newthing.txt" "$FIXTURES/transcript-multi.txt" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
candidates = [c['slash'] for c in d.get('candidates', [])]
assert '/newthing' in candidates and '/alpha' in candidates, f'multi-file scan missed candidates: {candidates}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner aggregates across multiple input files"
    else
        fail "multi-file scan failed. Output: $out"
    fi
}

test_includes_sample_context() {
    local out
    out=$(bash "$SCANNER" "$FIXTURES/transcript-newthing.txt" 2>&1 | strip_locale_warning)
    # Codex round 1 P1: weak assertion. Strengthened to require the slash
    # itself appears in the sample window (case-insensitive).
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
newthing = next((c for c in d['candidates'] if c['slash'] == '/newthing'), None)
assert newthing is not None
assert 'sample' in newthing and len(newthing['sample']) > 0, f'no sample context for /newthing'
assert '/newthing' in newthing['sample'].lower(), f'slash not in sample: {newthing[\"sample\"]}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner includes sample context that contains the matched slash"
    else
        fail "sample context missing or doesn't contain the slash. Output: $out"
    fi
}

test_long_line_sample_includes_slash() {
    # Codex round 1 P1: sample truncation could drop the slash if the line is
    # very long. Build a fixture with /latecommand at the end of a 400-char line.
    local long_fix="$FIXTURES/transcript-long.txt"
    printf '%0.s_' {1..350} > "$long_fix"  # 350 underscores
    printf ' and finally we use /latecommand here in this thread\n' >> "$long_fix"
    local out
    out=$(bash "$SCANNER" "$long_fix" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
late = next((c for c in d['candidates'] if c['slash'] == '/latecommand'), None)
assert late is not None, '/latecommand not detected at all'
assert '/latecommand' in late['sample'].lower(), f'/latecommand not in sample window: {late[\"sample\"]}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "long-line sample window contains the matched slash (no truncation drops it)"
    else
        fail "sample window truncation regression. Output: $out"
    fi
}

test_case_insensitive_extraction() {
    # Codex round 1 P1: extraction was lowercase-only. /Help and /HELP must
    # filter out (allowlisted lowercase), /NewThing must surface as /newthing.
    local case_fix="$FIXTURES/transcript-case.txt"
    cat > "$case_fix" <<'EOF'
The user mentioned /Help and /HELP and also brought up /NewThing.
Note that /newthing also got mentioned with normal casing.
EOF
    local out
    out=$(bash "$SCANNER" "$case_fix" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
slashes = {c['slash']: c['count'] for c in d['candidates']}
assert '/help' not in slashes, f'/Help/HELP leaked into candidates: {slashes}'
# /NewThing and /newthing should both contribute to the same /newthing entry
nt = slashes.get('/newthing', 0)
assert nt == 2, f'/newthing count expected 2 (case-folded /NewThing + /newthing), got {nt}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "case-insensitive extraction: /Help filters, /NewThing folds into /newthing count=2"
    else
        fail "case-insensitive extraction failed. Output: $out"
    fi
}

test_dash_leading_filename() {
    # Codex round 1 P2: cat "$arg" mistakes "-notes.txt" for an option.
    # Now reading via < "$arg" — verify a dash-leading filename works.
    local dash_fix="$FIXTURES/-dashnotes.txt"
    cat > "$dash_fix" <<'EOF'
This dash-leading file mentions /dashtest as a candidate.
EOF
    local out
    out=$(bash "$SCANNER" "$dash_fix" 2>&1 | strip_locale_warning)
    if echo "$out" | python3 -c "
import sys, json
d = json.load(sys.stdin)
slashes = [c['slash'] for c in d['candidates']]
assert '/dashtest' in slashes, f'dash-leading file failed to read; got: {slashes}'
print('ok')
" 2>/dev/null | grep -q ok; then
        pass "scanner reads dash-leading filename (-dashnotes.txt) without treating as option"
    else
        fail "dash-leading filename broken. Output: $out"
    fi
}

test_scanner_exists
test_allowlist_exists
test_detects_new_slash_command
test_filters_known_commands
test_filters_wizard_skills
test_filters_insights_as_known
test_dedupes_and_counts
test_empty_input_returns_empty_candidates
test_outputs_valid_json
test_handles_stdin
test_handles_multiple_files
test_includes_sample_context
test_long_line_sample_includes_slash
test_case_insensitive_extraction
test_dash_leading_filename

echo ""
echo "=== Results ==="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    exit 1
fi
echo "All community-scanner tests passed."
