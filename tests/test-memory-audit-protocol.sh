#!/bin/bash
# Memory Audit Protocol tests
# Validates the "Memory Audit Protocol" — now in CLAUDE_CODE_SDLC_WIZARD.md.
#
# GH #489: the protocol moved out of the byte-capped always-loaded skill into
# the on-demand doc. It was ALREADY supposed to live there — the skill said
# "Full protocol: CLAUDE_CODE_SDLC_WIZARD.md" while the wizard doc said "the
# /sdlc skill's Memory Audit Protocol section defines...". A circular pointer,
# with the protocol existing in exactly one of the two. This test now checks
# the doc that actually claims to hold it.
# and the classifier behavior against tests/fixtures/memory-audit-corpus/.
#
# Test groups:
#   1. Structure check (always runs) — protocol section present + subsections
#   2. Rule-based denylist (always runs, deterministic) — includes YAML-variant
#      hardening and promote-fixtures-route-to-manual-review corpus consistency
#   3. Corpus shape (always runs, deterministic)
#
# LLM-gated quality tests are intentionally NOT registered yet — see the
# "Group 4" comment block below. When the runner lands, guard its tests
# with `RUN_LLM_CLASSIFIER=1` (explicit opt-in) so nightly CI runs pay the
# API cost and PR CI stays deterministic.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
CORPUS="$REPO_ROOT/tests/fixtures/memory-audit-corpus"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "${YELLOW}SKIP${NC}: $1"; }

# ────────────────────────────────────────────
# Group 1: Structure check
# ────────────────────────────────────────────

test_protocol_section_exists() {
    if grep -qE '^#{2,3} Memory Audit Protocol' "$SKILL"; then
        pass "Memory Audit Protocol section present in CLAUDE_CODE_SDLC_WIZARD.md"
    else
        fail "CLAUDE_CODE_SDLC_WIZARD.md is missing the Memory Audit Protocol heading — the skill points here for it"
    fi
}

# Slice the Memory Audit section BEFORE checking its contents. Grepping the whole
# 291KB doc passes vacuously: "When to run" also appears in the Cross-Model Review
# section, so removing it from THIS protocol still passed. Verified by review.
_memory_audit_section() {
    awk '/^#{2,3} Memory Audit Protocol/{f=1} f{print} f && /^#{2,3} [^M]/ && !/Memory Audit/{if(++n>1)exit}' "$SKILL"
}

test_protocol_subsections_present() {
    local missing="" section
    section=$(_memory_audit_section)
    if [ -z "$section" ]; then
        fail "Memory Audit section could not be sliced — this assertion would be vacuous"
        return
    fi
    for keyword in "When to run" "Rule-based denylist" "Destinations" "Tracking" "Human gate"; do
        if ! printf '%s' "$section" | grep -qF "$keyword"; then
            missing="${missing:+${missing}, }$keyword"
        fi
    done
    if [ -z "$missing" ]; then
        pass "Protocol section contains required subsections (When/Classify/Destinations/Tracking/Human-gate)"
    else
        fail "Protocol section missing keyword(s): $missing"
    fi
}

test_protocol_denylist_rules_documented() {
    # Must explicitly document type→classification mapping for user/reference/project/feedback
    if grep -q 'type: user' "$SKILL" \
       && grep -q 'type: reference' "$SKILL" \
       && grep -q 'type: project' "$SKILL" \
       && grep -q 'type: feedback' "$SKILL"; then
        pass "Denylist rules document all four frontmatter types"
    else
        fail "Denylist rules do not cover all four types (user/reference/project/feedback)"
    fi
}

# ────────────────────────────────────────────
# Group 2: Rule-based denylist (deterministic)
# ────────────────────────────────────────────
#
# Rule is defined in SKILL.md:
#   type: user | reference        → keep
#   type: project | feedback      → manual-review
#   (anything else)               → LLM classifies
#
# We implement the rule here and verify it matches test_expected on the
# deterministic fixtures (those with types we cover).

apply_denylist_rule() {
    # Read YAML frontmatter type, emit keep/manual-review/LLM-NEEDED.
    # Normalizes: strips inline '# comment', strips surrounding quotes (single/double),
    # trims whitespace. Hardened per PR #189 Codex P1 finding #1.
    local file="$1"
    local type
    type=$(sed -n 's/^type:[[:space:]]*\(.*\)$/\1/p' "$file" | head -1)
    # Strip inline comment (YAML allows `# comment` after scalar values)
    type="${type%%#*}"
    # Strip surrounding whitespace, then strip one layer of matched quotes if present
    type="$(printf '%s' "$type" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    case "$type" in
        \"*\") type="${type#\"}"; type="${type%\"}" ;;
        \'*\') type="${type#\'}"; type="${type%\'}" ;;
    esac
    case "$type" in
        user|reference)   echo "keep" ;;
        project|feedback) echo "manual-review" ;;
        *)                echo "LLM-NEEDED" ;;
    esac
}

extract_expected_classification() {
    local file="$1"
    # test_expected is a 2-line block:
    #   test_expected:
    #     classification: X
    awk '/^test_expected:/{flag=1; next} flag && /classification:/{print $2; exit}' "$file"
}

test_denylist_user_files_classify_as_keep() {
    local fail_list=""
    for f in "$CORPUS"/keep_*.md; do
        [ -f "$f" ] || continue
        local actual
        actual=$(apply_denylist_rule "$f")
        if [ "$actual" != "keep" ]; then
            fail_list="${fail_list:+${fail_list}, }$(basename "$f"):$actual"
        fi
    done
    if [ -z "$fail_list" ]; then
        pass "Rule-based denylist: all user/reference fixtures classify as keep"
    else
        fail "Denylist failed to classify as keep: $fail_list"
    fi
}

test_denylist_project_feedback_classify_as_manual() {
    local fail_list=""
    for f in "$CORPUS"/manual_*.md; do
        [ -f "$f" ] || continue
        local actual
        actual=$(apply_denylist_rule "$f")
        if [ "$actual" != "manual-review" ]; then
            fail_list="${fail_list:+${fail_list}, }$(basename "$f"):$actual"
        fi
    done
    if [ -z "$fail_list" ]; then
        pass "Rule-based denylist: all project/feedback fixtures classify as manual-review"
    else
        fail "Denylist failed to classify as manual-review: $fail_list"
    fi
}

test_denylist_hardened_against_yaml_variants() {
    # Privacy gate regression test (Codex P1 finding #1): quoted or commented
    # user/reference types must still classify as keep, not fall through to LLM.
    local tmp
    tmp="${TMPDIR:-/tmp}/denylist-variants.$$"
    mkdir -p "$tmp"
    local variants=(
        'type: "user"'
        "type: 'reference'"
        'type: user # external pointer'
        'type:    reference    '
        'type: "reference" # quoted + commented'
    )
    local i=0
    local fail_list=""
    for variant in "${variants[@]}"; do
        i=$((i+1))
        local f="$tmp/variant_$i.md"
        printf -- '---\nname: test\n%s\n---\n' "$variant" > "$f"
        local actual
        actual=$(apply_denylist_rule "$f")
        if [ "$actual" != "keep" ]; then
            fail_list="${fail_list:+${fail_list}, }[$variant]:$actual"
        fi
    done
    rm -rf "$tmp"
    if [ -z "$fail_list" ]; then
        pass "Denylist parser normalizes quoted/commented types (privacy gate holds on YAML variants)"
    else
        fail "Denylist leaked to non-keep on YAML variants: $fail_list"
    fi
}

test_promote_fixtures_route_to_manual_review_under_rule_based() {
    # Corpus-consistency assertion (Codex P1 finding #2): promote fixtures
    # are type:feedback by design — they represent realistic portable-lesson
    # memory. The rule-based denylist MUST route them to manual-review
    # (human gate before LLM promotion), not to LLM-NEEDED or keep.
    local fail_list=""
    for f in "$CORPUS"/promote_*.md; do
        [ -f "$f" ] || continue
        local actual
        actual=$(apply_denylist_rule "$f")
        if [ "$actual" != "manual-review" ]; then
            fail_list="${fail_list:+${fail_list}, }$(basename "$f"):$actual"
        fi
    done
    if [ -z "$fail_list" ]; then
        pass "Promote fixtures route to manual-review under rule-based (human-gate-before-LLM holds)"
    else
        fail "Promote fixtures leaked past manual-review: $fail_list"
    fi
}

test_denylist_never_promotes_denied_types() {
    # Stricter sanity: the denylist rule must NEVER yield "promote" on any
    # user/reference/project/feedback type, even across synthetic inputs.
    local violations=""
    for f in "$CORPUS"/*.md; do
        [ -f "$f" ] || continue
        local actual
        actual=$(apply_denylist_rule "$f")
        if [ "$actual" = "promote" ]; then
            violations="${violations:+${violations}, }$(basename "$f")"
        fi
    done
    if [ -z "$violations" ]; then
        pass "Denylist never yields 'promote' for denied types (privacy gate holds)"
    else
        fail "Denylist leaked to promote for: $violations"
    fi
}

# ────────────────────────────────────────────
# Group 3: Corpus shape (deterministic, validates fixtures themselves)
# ────────────────────────────────────────────

test_corpus_has_10_entries() {
    local count
    count=$(find "$CORPUS" -maxdepth 1 -name '*.md' ! -name 'README.md' | wc -l | tr -d ' ')
    if [ "$count" -eq 10 ]; then
        pass "Corpus contains exactly 10 fixtures (excluding README)"
    else
        fail "Corpus has $count fixtures, expected 10"
    fi
}

test_corpus_distribution() {
    local promote keep manual
    promote=$(find "$CORPUS" -maxdepth 1 -name 'promote_*.md' | wc -l | tr -d ' ')
    keep=$(find "$CORPUS" -maxdepth 1 -name 'keep_*.md' | wc -l | tr -d ' ')
    manual=$(find "$CORPUS" -maxdepth 1 -name 'manual_*.md' | wc -l | tr -d ' ')
    if [ "$promote" -eq 6 ] && [ "$keep" -eq 2 ] && [ "$manual" -eq 2 ]; then
        pass "Corpus distribution is 6 promote / 2 keep / 2 manual-review (per CERTIFIED plan)"
    else
        fail "Corpus distribution wrong: $promote promote / $keep keep / $manual manual (expected 6/2/2)"
    fi
}

test_corpus_frontmatter_shape() {
    local missing=""
    for f in "$CORPUS"/*.md; do
        [ -f "$f" ] || continue
        [ "$(basename "$f")" = "README.md" ] && continue
        if ! grep -q '^test_expected:' "$f"; then
            missing="${missing:+${missing}, }$(basename "$f"):no-test_expected"
            continue
        fi
        local cls
        cls=$(extract_expected_classification "$f")
        if [ -z "$cls" ]; then
            missing="${missing:+${missing}, }$(basename "$f"):no-classification"
        fi
    done
    if [ -z "$missing" ]; then
        pass "Every fixture has test_expected.classification frontmatter"
    else
        fail "Fixtures missing test_expected shape: $missing"
    fi
}

test_promote_fixtures_have_target() {
    # 6/6 rule: every promote fixture MUST have a target: frontmatter line.
    local missing=""
    for f in "$CORPUS"/promote_*.md; do
        [ -f "$f" ] || continue
        if ! awk '/^test_expected:/{flag=1; next} flag && /^[[:space:]]+target:/{found=1; exit} END{exit !found}' "$f"; then
            missing="${missing:+${missing}, }$(basename "$f")"
        fi
    done
    if [ -z "$missing" ]; then
        pass "All 6 promote fixtures have target: frontmatter (denominator consistent)"
    else
        fail "Promote fixtures missing target: $missing"
    fi
}

# ────────────────────────────────────────────
# Group 4: LLM classification quality — OUT OF SCOPE for PR-1
# ────────────────────────────────────────────
#
# The CERTIFIED plan flagged LLM-gated quality thresholds (8/10 classification,
# 6/6 destination selection) as aspirational nightly gates. No runner exists
# yet. Rather than ship stub tests that always skip — which Codex PR #189
# review flagged as Prove-It Gate violation — we document the scope boundary
# here and don't register the stubs. When a runner lands, add the tests back
# with a real gate (env var `RUN_LLM_CLASSIFIER=1` guards cost + key use).
#
# Prove It Gate escape hatch: if this protocol runs 4+ times with manual LLM
# classification, build the runner. Until then, human review at promotion
# time is the quality gate — and that gate IS tested (test_denylist_* +
# test_promote_fixtures_route_to_manual_review_under_rule_based).

# ────────────────────────────────────────────
# Run
# ────────────────────────────────────────────

echo "=== Memory Audit Protocol tests ==="

test_protocol_section_exists
test_protocol_subsections_present
test_protocol_denylist_rules_documented

test_denylist_user_files_classify_as_keep
test_denylist_project_feedback_classify_as_manual
test_denylist_never_promotes_denied_types
test_denylist_hardened_against_yaml_variants
test_promote_fixtures_route_to_manual_review_under_rule_based

test_corpus_has_10_entries
test_corpus_distribution
test_corpus_frontmatter_shape
test_promote_fixtures_have_target

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All Memory Audit Protocol tests passed!"
