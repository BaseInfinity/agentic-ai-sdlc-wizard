#!/bin/bash
# test-evidence-exception-bound.sh — construction guard for the evidence-exception bound (issue #608).
#
# Replaces the deleted regex-over-prose guard that lived in
# tests/test-doc-consistency.sh (recoverable from PR #606 at
# 7f11280209a30f0de7dd0e9728d54f2fae911cd6). A regex over English prose
# recognizes a vocabulary, not a meaning; it was defeated by five
# meaning-reversing near-misses over three review rounds.
#
# This guard works by construction: the rule is stated ONCE, in
# docs/snippets/evidence-exception-bound.md (the canonical line below), and
# every prose restatement in the main doc must either carry the bound
# verbatim or reference the snippet. No natural-language synonym space is
# asserted — only the presence of the canonical line and of the reference.
#
# The script is self-falsifying at the end: two known mutations (the
# canonical line removed; the bound weakened from FIRST to ANY) must each
# make the check fail. If either mutation passes, the guard is vacuous.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
SNIPPET="$REPO_ROOT/docs/snippets/evidence-exception-bound.md"
# Canonical rule line — single source of truth. Keep in step with the snippet.
CANONICAL_RULE='at most one evidence-only re-verification pass may run, and ONLY for the FIRST such invalidation in this root task (FIRST-in-this-root-task)'

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$SNIPPET" ] || fail "canonical snippet not found at docs/snippets/evidence-exception-bound.md"

rule_count=$(grep -cF "$CANONICAL_RULE" "$SNIPPET" || true)
[ "$rule_count" -ge 1 ] || fail "canonical rule line missing from snippet — the bound must be stated once, here"
pass "canonical rule stated once in the snippet"

[ -f "$DOC" ] || fail "main wizard doc not found at CLAUDE_CODE_SDLC_WIZARD.md"

mention_count=$(grep -c 'evidence-only exception' "$DOC" || true)
if [ "$mention_count" -gt 0 ]; then
    canonical_count=$( { grep -F "evidence-only exception" "$DOC" || true; } | grep -EiF -e "$CANONICAL_RULE" -e 'evidence-exception-bound.md' | wc -l | tr -d '[:space:]' )
    [ "$canonical_count" -ge 1 ] || fail "$mention_count restatement(s) of the evidence-only exception in the main doc carry neither the FIRST-in-this-root-task bound nor a reference to the snippet — say it once (docs/snippets/evidence-exception-bound.md) and reference it elsewhere"
    pass "all $mention_count restatement(s) carry the bound or reference the canonical snippet"
else
    pass "no prose restatement of the evidence-only exception in the main doc yet (rule stated once in the snippet)"
fi

ref_count=$(grep -c 'evidence-exception-bound.md' "$DOC" || true)
[ "$ref_count" -ge 1 ] || fail "main doc does not reference the canonical snippet — the rule must be referenceable from the stop-condition section"
pass "main doc references the canonical snippet ($ref_count reference(s))"

# Self-falsification (issue #608: a replacement must be falsified before it
# is believed). Two known mutations must each make the check fail.
_tmpdir=$(mktemp -d)
trap 'rm -rf "$_tmpdir"' EXIT

_mut1=$(sed '/FIRST-in-this-root-task/d' "$SNIPPET")
printf '%s' "$_mut1" | grep -qF "$CANONICAL_RULE" && fail "self-falsification: guard still passes with the canonical bound line removed — guard is vacuous"
_mut2=$(sed 's/FIRST such invalidation/ANY such invalidation/' "$SNIPPET")
printf '%s' "$_mut2" | grep -qF "$CANONICAL_RULE" && fail "self-falsification: guard still passes with the bound weakened from FIRST to ANY — guard is vacuous"
pass "self-falsification: both known mutations make the guard fail"

echo "All evidence-exception-bound checks passed."
