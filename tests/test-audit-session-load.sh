#!/bin/bash
# Quality tests for scripts/audit-session-load.sh — token bloat audit phase 2.
# Tests use isolated fixture directories (no real repo state) so the "trim
# candidate" detection can be proven against known sizes.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$SCRIPT_DIR/../scripts/audit-session-load.sh"

PASSED=0
FAILED=0
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

make_temp() { mktemp -d "${TMPDIR:-/tmp}/audit-session-load-XXXXXX"; }

# Fixture builder: writes a session-loadable file at $1 with $2 chars of 'A'
make_file_with_size() {
    local path="$1" size="$2"
    mkdir -p "$(dirname "$path")"
    awk -v n="$size" 'BEGIN { for (i = 0; i < n; i++) printf "A"; }' > "$path"
}

echo "=== Token bloat audit phase 2 — quality tests ==="
echo ""

test_audit_exists_and_executable() {
    if [ -x "$AUDIT" ]; then
        pass "scripts/audit-session-load.sh exists and is executable"
    else
        fail "audit script missing or not executable: $AUDIT"
    fi
}

test_audit_flags_oversized_skill_as_trim_candidate() {
    local d
    d=$(make_temp)
    make_file_with_size "$d/skills/sdlc/SKILL.md" 25000
    make_file_with_size "$d/hooks/tiny.sh" 100
    local output
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" 2>&1)
    rm -rf "$d"
    if echo "$output" | awk '$4 == "TRIM" && $5 ~ /sdlc\/SKILL\.md/' | grep -q TRIM; then
        pass "audit flags 25K-char SKILL.md as TRIM candidate (proves >=5K-token detection)"
    else
        fail "audit should flag oversized skill as TRIM, got: $output"
    fi
}

test_audit_does_not_flag_small_files() {
    local d
    d=$(make_temp)
    make_file_with_size "$d/CLAUDE.md" 1000
    make_file_with_size "$d/SDLC.md" 500
    local output
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" 2>&1)
    rm -rf "$d"
    if echo "$output" | grep -q "TRIM"; then
        fail "audit should NOT flag <5K-token files as TRIM, got: $output"
    else
        pass "audit does not flag <5K-token files (250-token CLAUDE.md stays OK)"
    fi
}

test_audit_threshold_boundary_inclusive() {
    local d
    d=$(make_temp)
    make_file_with_size "$d/CLAUDE.md" 20000
    local output
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" 2>&1)
    rm -rf "$d"
    if echo "$output" | awk '$4 == "TRIM" && $5 ~ /CLAUDE\.md/' | grep -q TRIM; then
        pass "audit flags file AT threshold (20000 chars / 5000 tokens) as TRIM (inclusive)"
    else
        fail "threshold should be inclusive (>=5000 tokens flags), got: $output"
    fi
}

test_audit_json_output_includes_trim_count() {
    local d output
    d=$(make_temp)
    make_file_with_size "$d/skills/sdlc/SKILL.md" 25000
    make_file_with_size "$d/CLAUDE.md" 500
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" --json 2>&1)
    rm -rf "$d"
    if echo "$output" | grep -q '"trim_candidate_count": 1' \
        && echo "$output" | grep -q '"flag": "TRIM"' \
        && echo "$output" | grep -q '"flag": "OK"'; then
        pass "audit --json emits trim_candidate_count + per-entry flags"
    else
        fail "audit --json should emit machine-readable trim count, got: $output"
    fi
}

test_audit_threshold_override() {
    local d output
    d=$(make_temp)
    make_file_with_size "$d/CLAUDE.md" 10000
    output=$(SDLC_AUDIT_ROOT="$d" SDLC_AUDIT_THRESHOLD_TOKENS=1000 "$AUDIT" 2>&1)
    rm -rf "$d"
    if echo "$output" | awk '$4 == "TRIM" && $5 ~ /CLAUDE\.md/' | grep -q TRIM; then
        pass "audit respects SDLC_AUDIT_THRESHOLD_TOKENS override (1000-token threshold flags 2500-token file)"
    else
        fail "audit should honor threshold override, got: $output"
    fi
}

test_audit_empty_repo_no_crash() {
    local d output rc=0
    d=$(make_temp)
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" 2>&1) || rc=$?
    rm -rf "$d"
    if [ "$rc" -eq 0 ] && echo "$output" | grep -qiE 'no session-loaded assets|0 trim'; then
        pass "audit on empty repo exits cleanly (rc=0, sane message)"
    else
        fail "audit should handle empty repo gracefully (rc=$rc, got: $output)"
    fi
}

test_audit_ranks_by_size_descending() {
    local d output
    d=$(make_temp)
    make_file_with_size "$d/CLAUDE.md" 1000
    make_file_with_size "$d/SDLC.md" 5000
    make_file_with_size "$d/TESTING.md" 3000
    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" 2>&1)
    rm -rf "$d"
    local first second third
    first=$(echo "$output" | awk 'NR==3 {print $5}')
    second=$(echo "$output" | awk 'NR==4 {print $5}')
    third=$(echo "$output" | awk 'NR==5 {print $5}')
    if [[ "$first" == *SDLC.md* ]] \
        && [[ "$second" == *TESTING.md* ]] \
        && [[ "$third" == *CLAUDE.md* ]]; then
        pass "audit ranks entries by size descending (5K SDLC > 3K TESTING > 1K CLAUDE)"
    else
        fail "audit should rank by size DESC (got order: $first, $second, $third)"
    fi
}

# #489: the build gate that used to live here is deleted.
#
# It failed CI whenever a SKILL.md crossed the audit's TRIM threshold, which
# made 20,000 bytes a hard contract on a shipped file. That number was never
# measured: `scripts/audit-session-load.sh` computes it as THRESHOLD_TOKENS
# (5,000, a round number) times 4 (a chars-per-token rule of thumb from a
# different vendor), and the whole thing is tunable by an environment variable.
# Under the CLAIM RULE we cannot enforce a number we never measured.
#
# The cost was real and compounding. With sdlc/SKILL.md sitting at 19,997 of
# 20,000, every subsequent edit had to buy its own bytes by degrading another
# instruction in the same file, and that trading shipped three defects in a
# single session — including invalid JSON and a dropped instruction value.
# A budget that forces a silent trade on every edit is a circling generator.
#
# The audit itself is untouched: it still reports sizes and still raises TRIM,
# because observability was always its job. Only build-red is gone. If a real
# ceiling is ever measured, it belongs here — see #483, which is where such a
# measurement would come from.
#
# Still enforced elsewhere, deliberately: tests/test-cowork-drift.sh keeps
# skills/sdlc/SKILL.md and cowork/skills/sdlc/SKILL.md byte-identical.
#
# One thing the deleted test was doing incidentally, kept below: it was the
# only place that ran a real json.loads over the audit's REAL multi-entry
# output. Cross-model review caught that removing the gate would have taken
# that coverage with it — the other JSON test greps for substrings, so
# stripping the commas between entries left all nine survivors green while
# `python3 -m json.tool` rejected the output.

# Parses the audit's output for THIS repo, which is the only fixture with
# enough entries for a malformed separator to show up. Asserts validity and
# shape only — never sizes, never flags. That distinction is the point: the
# tool's contract is that it emits parseable JSON, not that any file in this
# repo is under some particular number.
test_audit_json_is_parseable_on_real_repo() {
    local repo_root="$SCRIPT_DIR/.."
    local output verdict
    output=$(SDLC_AUDIT_ROOT="$repo_root" "$AUDIT" --json 2>&1)
    verdict=$(printf '%s' "$output" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except json.JSONDecodeError as e:
    print("INVALID_JSON: %s" % e)
    sys.exit(0)
entries = data.get("entries")
if not isinstance(entries, list):
    print("NO_ENTRIES_LIST")
elif len(entries) < 2:
    print("TOO_FEW_ENTRIES: %d" % len(entries))
elif any(k not in e for e in entries for k in ("path", "type", "flag")):
    print("ENTRY_MISSING_KEYS")
elif "trim_candidate_count" not in data:
    print("NO_TRIM_COUNT")
else:
    print("OK")
' 2>/dev/null)
    if [ "$verdict" = "OK" ]; then
        pass "audit --json stays parseable with the real repo's multi-entry output"
    else
        fail "audit --json must parse and carry >=2 well-formed entries, got: $verdict"
    fi
}

test_audit_scans_consumer_install_layout() {
    # Codex strategic review caught a measurement blind spot: the audit
    # scans root `skills/*/SKILL.md`, but `cli/init.js:32-35` copies
    # SKILL.md files to `.claude/skills/<name>/SKILL.md` in real
    # consumer installs. Without parallel scanning, the audit can't
    # see bloat in installed projects — only in dev maintainer repos.
    #
    # Mirrors the existing `.claude/hooks/` consumer-install fallback
    # at `scripts/audit-session-load.sh`. Negative control: deleting
    # the new audit-script block makes this test fail (path won't
    # appear in the JSON output, predicate fails).
    local d output
    d=$(make_temp)
    # Consumer install layout: .claude/skills/<name>/SKILL.md exists,
    # root skills/ does NOT (dev-only path).
    make_file_with_size "$d/.claude/skills/sdlc/SKILL.md" 21000

    output=$(SDLC_AUDIT_ROOT="$d" "$AUDIT" --json 2>&1)
    rm -rf "$d"

    # Strict predicate (per Codex sign-off): require entry whose path
    # ENDS in `.claude/skills/sdlc/SKILL.md` AND has flag "TRIM".
    # Substring match would also accept noise like a real `skills/`
    # path that happens to contain `claude` somewhere in its prefix.
    if echo "$output" | python3 -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except json.JSONDecodeError:
    sys.exit(1)
hit = [
    e for e in data.get("entries", [])
    if e.get("path", "").endswith("/.claude/skills/sdlc/SKILL.md")
    and e.get("flag") == "TRIM"
]
sys.exit(0 if hit else 1)
' 2>/dev/null; then
        pass "audit scans .claude/skills/ in consumer install layout (>5K SKILL.md flagged TRIM)"
    else
        fail "audit did not inventory .claude/skills/sdlc/SKILL.md from consumer-install fixture. Output: $output"
    fi
}

test_audit_exists_and_executable
test_audit_flags_oversized_skill_as_trim_candidate
test_audit_does_not_flag_small_files
test_audit_threshold_boundary_inclusive
test_audit_json_output_includes_trim_count
test_audit_json_is_parseable_on_real_repo
test_audit_threshold_override
test_audit_empty_repo_no_crash
test_audit_ranks_by_size_descending
test_audit_scans_consumer_install_layout

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"
if [ "$FAILED" -gt 0 ]; then exit 1; fi
echo "All token bloat audit tests passed!"
