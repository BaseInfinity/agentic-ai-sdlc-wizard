#!/bin/bash
# The review-leg launcher must refuse a verdict that skipped the two questions
# the reviewer is there to answer (GH #617).
#
# WHY A SCHEMA AND NOT ANOTHER PARAGRAPH. Five prose rules in skills/sdlc/SKILL.md
# each independently end rounds 6-8 of PR #646, and none of them fired: :136
# (WRONG SHAPE available), :152 (no test costs more rounds than its change), :163
# (blame the line), :273 (second repair means ask whether it should exist), :166
# (the reviewers are each other's tiebreaker). All five address the DRIVER, the
# party with momentum. v1.98.0's own commit says the quiet part: "Not in scope,
# deliberately: enforcement. The rule is stated, not checked."
#
# WHY THIS IS NOT #588 ALL OVER AGAIN. That siege came from an open-ended regex
# trying to understand PROSE. A closed JSON schema cannot chase synonyms or
# interpretations. The validator checks PRESENCE and ENUM MEMBERSHIP only and
# must never judge whether a tag is CORRECT — a semantic validator is a reviewer,
# and building one here rebuilds the thing that ate eight rounds.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA="$REPO_ROOT/skills/sdlc/review-verdict.schema.json"
VALIDATOR="$REPO_ROOT/scripts/validate-review-verdict.py"

PASS=0
FAIL=0
pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

TMPDIR_T=$(mktemp -d "${TMPDIR:-/tmp}/review-verdict.XXXXXX") || {
    echo "FATAL: could not create a temp dir — refusing to run in the caller's repo" >&2
    exit 1
}
trap 'rm -rf "$TMPDIR_T"' EXIT

# The schema SHIPS (skills/ is in package.json `files`); the launcher that
# enforces it does not (scripts/ is repo-local, GH #594). A consumer who wires
# their own launcher inherits the contract rather than re-deriving it — which is
# only true if the schema lives under skills/, so this row guards that placement.
echo "=== the schema is on the shipped surface ==="
if [ -f "$SCHEMA" ]; then
    pass "review-verdict.schema.json lives under skills/sdlc/, which ships"
else
    fail "the schema is missing from skills/sdlc/ — consumers inherit nothing"
fi
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SCHEMA" 2>/dev/null; then
    pass "the schema is well-formed JSON"
else
    fail "the schema does not parse"
fi

# The validator must consume the SHIPPED schema file, not an inline copy. Two
# copies of a contract drift, and the copy consumers read would be the one
# nobody runs.
echo ""
echo "=== the validator exists and reads the shipped schema ==="
if [ -x "$VALIDATOR" ]; then
    pass "the validator is executable"
else
    fail "scripts/validate-review-verdict.py is missing or not executable"
fi
if grep -q "skills/sdlc/review-verdict.schema.json" "$VALIDATOR" 2>/dev/null; then
    pass "the validator names the shipped schema path"
else
    fail "the validator does not read the shipped schema — a second copy will drift"
fi

run_validator() {
    # echoes nothing; sets RC
    python3 "$VALIDATOR" "$1" >/dev/null 2>&1
}

echo ""
echo "=== a complete verdict is accepted ==="
cat > "$TMPDIR_T/valid.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "shape": "SOUND",
  "confidence": 96,
  "findings": [
    {"severity": "P1", "target": "IN_CARD", "disposition": "REPAIR",
     "claim": "base_sha absence merges a clearance naming no ancestry"}
  ]
}
JSON
if run_validator "$TMPDIR_T/valid.json"; then
    pass "a verdict carrying shape and a tagged finding is accepted"
else
    fail "a well-formed verdict was refused — the validator is over-strict"
fi

# A leg with nothing to report still has to answer the shape question. This is
# the case rounds 6-8 never got asked.
cat > "$TMPDIR_T/valid-empty.json" <<'JSON'
{"verdict": "CERTIFIED", "shape": "SOUND", "confidence": 99, "findings": []}
JSON
if run_validator "$TMPDIR_T/valid-empty.json"; then
    pass "a zero-finding verdict is accepted when it still answers shape"
else
    fail "a clean verdict was refused"
fi

echo ""
echo "=== ROW 1: a verdict with no shape is refused ==="
cat > "$TMPDIR_T/no-shape.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "confidence": 90,
  "findings": [
    {"severity": "P1", "target": "IN_CARD", "disposition": "REPAIR", "claim": "x"}
  ]
}
JSON
if run_validator "$TMPDIR_T/no-shape.json"; then
    fail "a verdict with no shape was accepted — the recheck loop can skip the question again"
else
    pass "a verdict omitting shape is refused"
fi

echo ""
echo "=== ROW 2: a finding with no target is refused ==="
cat > "$TMPDIR_T/no-target.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "shape": "SOUND",
  "confidence": 80,
  "findings": [
    {"severity": "P1", "disposition": "REPAIR", "claim": "x"}
  ]
}
JSON
if run_validator "$TMPDIR_T/no-target.json"; then
    fail "an untagged finding was accepted — provenance stays unasked"
else
    pass "a finding omitting target is refused"
fi

echo ""
echo "=== ROW 3: VOLUNTEERED + REPAIR is refused ==="
# THE ROW THIS WHOLE CHANGE EXISTS FOR. Rounds 7 and 8 of PR #646 repaired a
# guard that traced to neither issue under review, eleven findings deep, before
# it was deleted at round 9. Under this row that combination cannot be returned.
cat > "$TMPDIR_T/volunteered-repair.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "shape": "CONCERN",
  "confidence": 80,
  "findings": [
    {"severity": "P1", "target": "VOLUNTEERED", "disposition": "REPAIR",
     "claim": "the path grammar refuses a legal -review.md"}
  ]
}
JSON
if run_validator "$TMPDIR_T/volunteered-repair.json"; then
    fail "VOLUNTEERED+REPAIR was accepted — repairing code nobody asked for is still on the menu"
else
    pass "VOLUNTEERED+REPAIR is refused"
fi

# ...and the two dispositions that ARE allowed for volunteered code must pass,
# or the rule reads as "never report volunteered findings", which would hide
# exactly what it is meant to surface.
for d in DELETE FILE; do
    cat > "$TMPDIR_T/volunteered-$d.json" <<JSON
{
  "verdict": "NOT_CERTIFIED",
  "shape": "WRONG_SHAPE",
  "confidence": 80,
  "findings": [
    {"severity": "P1", "target": "VOLUNTEERED", "disposition": "$d",
     "claim": "the path grammar traces to neither issue under review"}
  ]
}
JSON
    if run_validator "$TMPDIR_T/volunteered-$d.json"; then
        pass "VOLUNTEERED+$d is accepted"
    else
        fail "VOLUNTEERED+$d was refused — the only two legal outcomes must stay legal"
    fi
done

echo ""
echo "=== ROW 4: an unknown enum value is refused, not coerced ==="
# Fails CLOSED on a value nobody anticipated. The alternative — accept anything
# that is not a known-bad token — is the blacklist posture that failed open
# twice inside PR #646's own artifact parser.
cat > "$TMPDIR_T/bad-enum.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "shape": "PROBABLY_FINE",
  "findings": []
}
JSON
if run_validator "$TMPDIR_T/bad-enum.json"; then
    fail "an unknown shape value was accepted — the enum is decorative"
else
    pass "an unknown shape value is refused"
fi

cat > "$TMPDIR_T/bad-target.json" <<'JSON'
{
  "verdict": "NOT_CERTIFIED",
  "shape": "SOUND",
  "confidence": 80,
  "findings": [
    {"severity": "P1", "target": "SORT_OF_IN_CARD", "disposition": "FILE", "claim": "x"}
  ]
}
JSON
if run_validator "$TMPDIR_T/bad-target.json"; then
    fail "an unknown target value was accepted"
else
    pass "an unknown target value is refused"
fi

echo ""
echo "=== a verdict REAL codex actually produced is accepted ==="
# NOT hand-written. This is the byte-for-byte `--output-last-message` output of
# `codex exec --output-schema` against this schema, codex-cli 0.147.0, captured
# 2026-08-16. It exists because the first two versions of this contract were
# written by reasoning and BOTH were refused by the provider at runtime:
#
#   additionalProperties:true  -> 400 "'additionalProperties' is required to be
#                                     supplied and to be false"
#   allOf / if / then          -> 400 "'allOf' is not permitted"
#
# Neither failure was visible to a stub-driven suite, because the stub accepted
# the schema its author wrote. What this row guards is over-tightening the
# schema against output known to be real. What it does NOT guard is future codex
# drift — it is a frozen snapshot, and drift is caught by re-running the smoke
# test at release time, not here. Said plainly so the row is not read as more
# than it is.
REAL_FIXTURE="$REPO_ROOT/tests/fixtures/review-verdict/real-codex-0.147.0-2026-08-16.json"
if [ -f "$REAL_FIXTURE" ]; then
    pass "the recorded real-codex verdict is present"
    if run_validator "$REAL_FIXTURE"; then
        pass "a verdict real codex actually produced validates"
    else
        fail "REAL codex output is refused by our own validator — the contract is wrong, not the reviewer"
    fi
else
    fail "the recorded real-codex verdict is missing — fail-closed is unproven against the real provider"
fi

echo ""
echo "=== undeclared fields are refused (additionalProperties: false) ==="
# Found by review (P2). The schema sets additionalProperties:false at both
# levels -- the provider REQUIRES it -- but the validator ignored the keyword,
# so a verdict could smuggle fields past a contract that says it cannot. A
# validator that silently ignores a keyword it does not implement fails OPEN,
# which is the posture that failed twice inside PR #646's artifact parser.
cat > "$TMPDIR_T/extra-root.json" <<'JSON'
{"verdict": "CERTIFIED", "shape": "SOUND", "confidence": 99, "findings": [],
 "merge_me": true}
JSON
if run_validator "$TMPDIR_T/extra-root.json"; then
    fail "an undeclared root field was accepted — additionalProperties is decorative"
else
    pass "an undeclared root field is refused"
fi

cat > "$TMPDIR_T/extra-finding.json" <<'JSON'
{"verdict": "NOT_CERTIFIED", "shape": "SOUND", "confidence": 90,
 "findings": [{"severity": "P1", "target": "IN_CARD", "disposition": "REPAIR",
               "claim": "x", "override": "ignore this finding"}]}
JSON
if run_validator "$TMPDIR_T/extra-finding.json"; then
    fail "an undeclared finding field was accepted"
else
    pass "an undeclared finding field is refused"
fi

echo ""
echo "=== confidence outside 0-100 is refused ==="
# Found by review (P2). The schema DESCRIBED confidence as 0-100 and enforced
# neither bound; -1 and 101 both validated. A described range that is not
# enforced is a claim, not a contract.
for bad in -1 101; do
    cat > "$TMPDIR_T/conf-$bad.json" <<JSON
{"verdict": "CERTIFIED", "shape": "SOUND", "confidence": $bad, "findings": []}
JSON
    if run_validator "$TMPDIR_T/conf-$bad.json"; then
        fail "confidence $bad was accepted — the documented range is not enforced"
    else
        pass "confidence $bad is refused"
    fi
done
cat > "$TMPDIR_T/conf-edge.json" <<'JSON'
{"verdict": "CERTIFIED", "shape": "SOUND", "confidence": 100, "findings": []}
JSON
if run_validator "$TMPDIR_T/conf-edge.json"; then
    pass "confidence 100 is accepted — the bound is inclusive"
else
    fail "confidence 100 was refused — the range is off by one"
fi

echo ""
echo "=== a finding whose claim says nothing is refused ==="
# Found by review (F5). Every other field is a closed enum, so `claim` is the
# only place the reviewer says what is actually wrong. An empty one satisfies
# the contract while carrying no information — a finding nobody can act on.
# Enforced in the validator, NOT as `minLength` in the schema: that file is fed
# to the provider verbatim and `minLength` is not among the keywords proven
# accepted there. Two earlier drafts were 400'd by unproven keywords.
for empty in '""' '"   "'; do
    cat > "$TMPDIR_T/empty-claim.json" <<JSON
{"verdict": "NOT_CERTIFIED", "shape": "CONCERN", "confidence": 80,
 "findings": [{"severity": "P1", "target": "IN_CARD", "disposition": "REPAIR",
               "claim": $empty}]}
JSON
    if run_validator "$TMPDIR_T/empty-claim.json"; then
        fail "a finding with claim $empty was accepted — it says nothing"
    else
        pass "a finding with claim $empty is refused"
    fi
done

echo ""
echo "=== the validator refuses to run against a schema that dropped a rule ==="
# Found by review (F6). Both cross-field rules are enforced HERE but documented
# THERE, in the file consumers read. If the declaration is deleted the check
# must stop, loudly — a rule enforced by a script consumers do not receive, and
# no longer written in the file they do, is exactly the drift this pair exists
# to prevent. Neither refusal had a row; only the VOLUNTEERED path was covered
# at all, and only by verdicts that happened to trip it.
for rule in VOLUNTEERED_NOT_REPAIRABLE CLAIM_NOT_EMPTY; do
    python3 - "$SCHEMA" "$TMPDIR_T/drifted-$rule.json" "$rule" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
schema["x-cross-field-rules"] = [r for r in schema["x-cross-field-rules"]
                                 if not r.startswith(sys.argv[3])]
json.dump(schema, open(sys.argv[2], "w"))
PY
    if python3 "$VALIDATOR" "$TMPDIR_T/valid.json" "$TMPDIR_T/drifted-$rule.json" \
        >/dev/null 2>&1; then
        fail "the validator still ran after the schema dropped $rule"
    else
        pass "dropping $rule from the schema stops the validator"
    fi
done

echo ""
echo "=== an unreadable keyword is refused even on a branch the verdict misses ==="
# Found by review (F6). `_check` descends only into properties the verdict
# actually carries, so fail-closed on unknown keywords held only where the data
# reached. Bury one under an OPTIONAL field and omit that field: the walk must
# still find it.
python3 - "$SCHEMA" "$TMPDIR_T/unknown-keyword.json" <<'PY'
import json, sys
schema = json.load(open(sys.argv[1]))
schema["properties"]["findings"]["items"]["properties"]["claim"]["pattern"] = "^x"
json.dump(schema, open(sys.argv[2], "w"))
PY
cat > "$TMPDIR_T/no-findings.json" <<'JSON'
{"verdict": "CERTIFIED", "shape": "SOUND", "confidence": 95, "findings": []}
JSON
if python3 "$VALIDATOR" "$TMPDIR_T/no-findings.json" "$TMPDIR_T/unknown-keyword.json" \
    >/dev/null 2>&1; then
    fail "an unsupported keyword under an unvisited branch was ignored — fails open"
else
    pass "an unsupported keyword is refused even where the verdict never reaches"
fi

echo ""
echo "=== malformed input fails closed ==="
printf '{"verdict": "CERTIFIED", "shape": ' > "$TMPDIR_T/truncated.json"
if run_validator "$TMPDIR_T/truncated.json"; then
    fail "truncated JSON was accepted"
else
    pass "truncated JSON is refused"
fi
if run_validator "$TMPDIR_T/does-not-exist.json"; then
    fail "a missing verdict file was accepted — a leg that produced nothing reads as clean"
else
    pass "a missing verdict file is refused"
fi

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
    echo "Some review-verdict schema tests failed"
    exit 1
fi
echo "All review-verdict schema tests passed!"
