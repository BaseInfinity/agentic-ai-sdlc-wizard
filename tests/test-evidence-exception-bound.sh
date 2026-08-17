#!/bin/bash
# test-evidence-exception-bound.sh — construction guard for the evidence-exception bound (issue #608).
#
# Originally contributed by @webbrain-one in PR #615; the single-source-of-truth
# design and the self-falsification requirement are theirs. Adapted before merge
# (see that PR for the full list of changes and why).
#
# ---------------------------------------------------------------------------
# WHAT THIS REPLACES, AND WHY IT DIED
#
# The predecessor lived in tests/test-doc-consistency.sh (recoverable at
# 7f11280:tests/test-doc-consistency.sh). It matched the MEANING of the bound
# with a regex over English prose, and it kept losing: three consecutive review
# rounds each found one more unbounded restatement, and TWO of those were
# written by the alignment pass that was fixing the others. A regex over prose
# recognizes a vocabulary, not a meaning.
#
# THE DECOMPOSITION THIS GUARD USES:
#
#   regex    for DETECTION  — finding WHERE the rule is discussed is a
#                             syntactic question, and the old guard's MENTION
#                             pattern is the one part that was never defeated.
#                             It is reused verbatim below.
#   markers  for COMPLIANCE — every mention outside the canonical block must
#                             carry the reference token in its OWN SENTENCE.
#                             Token presence is syntactic. Checkable.
#   verbatim for MEANING    — the rule is stated in exactly ONE marked block
#                             in the shipped doc, and compared byte-for-byte.
#
# STATED LIMIT — read this before extending the guard. A sentence that carries
# the reference token and ALSO misstates the rule passes this check. That is
# deliberate. Judging whether prose means what it says is review's job, not a
# validator's; #588/PR #598 spent 22 rounds proving what happens to a validator
# that takes on that ambition. The guard's job is to make every restatement
# REACHABLE from the one authoritative statement, so a human or reviewer can
# check it in one hop. Do not grow this file toward semantic matching.
#
# WHY THE CANONICAL TEXT IS THE DOC'S WORDING, not PR #615's snippet: the
# snippet said a later invalidation is "handed off for human review". The
# certified rule says a later evidence-only finding "is filed" — and this
# harness's escalation ladder reaches a human LAST, only on reviewer
# disagreement or a twice-failed non-waivable gate. Adopting the snippet
# verbatim would have silently rewritten a rule 13 certified rounds signed off
# on. The canonical block is the shipped doc's own certified sentence.
#
# WHY THE CANONICAL BLOCK LIVES IN THE SHIPPED DOC: docs/ is not in
# package.json's `files` list and is absent from `npm pack --dry-run`, so a
# canonical statement under docs/ reaches no consumer install, and the shipped
# doc would reference a path that does not exist there. CLAUDE_CODE_SDLC_WIZARD.md
# ships; the rule lives in it.
#
# SELF-FALSIFICATION: at the end, ten mutations — the five near-misses that
# defeated the predecessor, each applied BOTH inside the canonical block and as
# new unmarked prose — are written to a temp tree and the checker is RE-RUN
# against each. A mutation that does not make the checker fail means the guard
# is vacuous. The checker runs as a real subprocess against a real file; it does
# not re-grep a string in memory, which would only prove that grep works.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f "$DOC" ] || fail "shipped wizard doc not found at CLAUDE_CODE_SDLC_WIZARD.md"

# ---------------------------------------------------------------------------
# The checker. Takes a doc path, exits non-zero with a reason if it does not
# hold. Extracted so the mutation harness below can re-run the REAL check.
# ---------------------------------------------------------------------------
CHECKER="$(mktemp "${TMPDIR:-/tmp}/evbound-checker.XXXXXX")" || fail "could not create checker temp file"
trap 'rm -f "$CHECKER"' EXIT

cat > "$CHECKER" <<'PYEOF'
import re
import sys

OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"
CLOSE_MARK = "<!-- /CANONICAL:evidence-exception-bound -->"
REF_TOKEN = "[bound: CANONICAL:evidence-exception-bound]"

# The rule, verbatim. Whitespace-normalised, so a statement that wrapped
# across lines is still one string here.
CANONICAL_RULE = (
    "**After those two passes, continue ONLY when the immediately preceding "
    "COMPLETED pass recorded either (a) an open P0/P1 showing a requested "
    "behavior is currently wrong, or (b) the FIRST verification-evidence "
    "invalidation in this root task.** An evidence-only finding authorizes "
    "exactly one additional pass per root task; a later evidence-only finding "
    "is filed."
)

# Every way the exception can be NAMED. Carried over unchanged from the
# predecessor guard, where detection was never the part that failed.
MENTION = re.compile(
    r"(invalidat\w*\s+(its\s+)?(verification[- ])?evidence"
    r"|(verification[- ])?evidence[- ]invalidation"
    r"|evidence-only)",
    re.I,
)

path = sys.argv[1]
text = " ".join(open(path, encoding="utf-8").read().split())
problems = []

# 1. The canonical block exists exactly once.
blocks = [
    (m.start(), m.end())
    for m in re.finditer(
        re.escape(OPEN_MARK) + r"(.*?)" + re.escape(CLOSE_MARK), text, re.S
    )
]
if len(blocks) != 1:
    print(
        "the canonical block must appear exactly once, found %d "
        "(markers: %s ... %s)" % (len(blocks), OPEN_MARK, CLOSE_MARK)
    )
    sys.exit(1)
lo, hi = blocks[0]
block = text[lo:hi]

# 2. The block states the rule verbatim. This is the meaning check, and it is
#    byte-for-byte on purpose — no synonym space is asserted or accepted.
if CANONICAL_RULE not in block:
    problems.append(
        "the canonical block does not contain the rule verbatim; the bound has "
        "been reworded or removed inside the markers"
    )

# 3. The rule is stated ONCE. It must not appear outside the block.
if CANONICAL_RULE in (text[:lo] + text[hi:]):
    problems.append(
        "the canonical rule text appears outside the canonical block — state it "
        "once, reference it elsewhere"
    )

# 4. Every mention outside the block carries the reference token in its OWN
#    sentence. Sentence-scoped, not window-scoped: the predecessor was defeated
#    twice by a mutated clause sitting next to a correctly-bounded sentence,
#    which a proximity window accepted. Proximity is not attachment.
outside = text[:lo] + text[hi:]
sentences = re.split(r"(?<=[.!?])\s+", outside)
unmarked = []
for s in sentences:
    if MENTION.search(s) and REF_TOKEN not in s:
        unmarked.append(s.strip()[:200])
if unmarked:
    problems.append(
        "%d mention(s) of the evidence exception do not carry %s in their own "
        "sentence: %s" % (len(unmarked), REF_TOKEN, " || ".join(unmarked))
    )

if problems:
    print("; ".join(problems))
    sys.exit(1)

# Report the counts so a passing run still shows its work.
marked = sum(
    1 for s in sentences if MENTION.search(s) and REF_TOKEN in s
)
print("OK %d" % marked)
sys.exit(0)
PYEOF

# ---------------------------------------------------------------------------
# The live check.
# ---------------------------------------------------------------------------
if out=$(python3 "$CHECKER" "$DOC"); then
    pass "canonical block stated once, verbatim; ${out#OK } referencing mention(s) all carry the token"
else
    fail "$out"
fi

# ---------------------------------------------------------------------------
# Self-falsification (#608: a replacement guard must be falsified before it is
# believed). The five near-misses that defeated the predecessor, each applied
# two ways: as an edit INSIDE the canonical block, and as new unmarked prose.
# ---------------------------------------------------------------------------
WORK="$(mktemp -d "${TMPDIR:-/tmp}/evbound-mut.XXXXXX")" || fail "could not create mutation temp dir"
trap 'rm -f "$CHECKER"; rm -rf "$WORK"' EXIT

# The five near-misses, recovered from the predecessor's own comments. Each
# reverses or unbinds the rule while keeping its vocabulary — which is exactly
# why a vocabulary regex could not tell them apart.
NEARMISS_1='The evidence-only exception authorizes a pass after the first pass.'
NEARMISS_2='The second verification-evidence invalidation authorizes another pass.'
NEARMISS_3='The first PASS after a verification-evidence invalidation in this root task is allowed.'
NEARMISS_4='Any evidence-only finding authorizes one more re-verification pass.'
NEARMISS_5='Every verification-evidence invalidation buys another pass.'

mutations_run=0
mutations_caught=0

# --- Form A: mutate INSIDE the canonical block (meaning check must fire) ---
# Each replaces the bound's operative words within the markers.
run_mutation() {
    local label="$1" file="$2"
    mutations_run=$((mutations_run + 1))
    if python3 "$CHECKER" "$file" >/dev/null 2>&1; then
        fail "self-falsification: guard still PASSES under mutation [$label] — the guard is vacuous"
    fi
    mutations_caught=$((mutations_caught + 1))
    echo "  caught: $label"
}

# The mutator edits ONLY the text between the canonical markers, so each
# mutation is a reword of the rule itself rather than of incidental prose. It
# refuses to emit a mutant identical to the original: a no-op mutation would
# otherwise be "caught" for the wrong reason and inflate the score.
MUTATOR="$(mktemp "${TMPDIR:-/tmp}/evbound-mutator.XXXXXX")" || fail "could not create mutator temp file"
trap 'rm -f "$CHECKER" "$MUTATOR"; rm -rf "$WORK"' EXIT
cat > "$MUTATOR" <<'PYEOF'
import re
import sys

src, dst, find, replace = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"
CLOSE_MARK = "<!-- /CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
m = re.search(re.escape(OPEN_MARK) + r"(.*?)" + re.escape(CLOSE_MARK), text, re.S)
if not m:
    sys.stderr.write("mutator: canonical block not found in source\n")
    sys.exit(2)

block = m.group(0)
# Whitespace in the doc may wrap mid-phrase, so match across newlines.
pattern = re.compile(r"\s+".join(re.escape(w) for w in find.split()))
mutated_block, n = pattern.subn(replace, block, count=1)
if n == 0:
    sys.stderr.write("mutator: target phrase %r not found inside the canonical block\n" % find)
    sys.exit(2)

out = text[: m.start()] + mutated_block + text[m.end() :]
if out == text:
    sys.stderr.write("mutator: mutation was a no-op\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF

i=0
while IFS='|' read -r find replace; do
    [ -n "$find" ] || continue
    i=$((i + 1))
    m="$WORK/inblock-$i.md"
    python3 "$MUTATOR" "$DOC" "$m" "$find" "$replace" \
        || fail "mutation harness broken: could not apply in-block mutation #$i ($find)"
    run_mutation "in-block reword #$i ($find -> ${replace:-<deleted>})" "$m"
done <<'MUTS'
the FIRST verification-evidence|the SECOND verification-evidence
authorizes exactly one additional pass|authorizes a pass
a later evidence-only finding is filed|a later evidence-only finding authorizes another pass
invalidation in this root task|invalidation in this pass
An evidence-only finding authorizes|
MUTS

# --- Form B: add each near-miss as NEW UNMARKED prose (compliance check must
# fire). Appended immediately after a correctly-marked sentence, which is the
# exact shape that defeated the predecessor's proximity window.
INJECTOR="$(mktemp "${TMPDIR:-/tmp}/evbound-inject.XXXXXX")" || fail "could not create injector temp file"
trap 'rm -f "$CHECKER" "$MUTATOR" "$INJECTOR"; rm -rf "$WORK"' EXIT
cat > "$INJECTOR" <<'PYEOF'
import sys

src, dst, sentence = sys.argv[1], sys.argv[2], sys.argv[3]
REF_TOKEN = "[bound: CANONICAL:evidence-exception-bound]"

text = open(src, encoding="utf-8").read()
# Inject IMMEDIATELY after the first correctly-marked sentence, inside the same
# paragraph. This is the shape that defeated the predecessor: its proximity
# window saw the neighbouring compliant sentence and accepted the mutant.
idx = text.find(REF_TOKEN)
if idx == -1:
    sys.stderr.write("injector: no marked mention found to inject after\n")
    sys.exit(2)
cut = text.find(".", idx + len(REF_TOKEN))
if cut == -1:
    sys.stderr.write("injector: could not find the end of the marked sentence\n")
    sys.exit(2)
cut += 1
out = text[:cut] + " " + sentence + text[cut:]
if out == text:
    sys.stderr.write("injector: injection was a no-op\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF

i=0
for nm in "$NEARMISS_1" "$NEARMISS_2" "$NEARMISS_3" "$NEARMISS_4" "$NEARMISS_5"; do
    i=$((i + 1))
    m="$WORK/unmarked-$i.md"
    python3 "$INJECTOR" "$DOC" "$m" "$nm" \
        || fail "mutation harness broken: could not inject near-miss #$i"
    run_mutation "unmarked near-miss #$i, injected adjacent to a marked sentence" "$m"
done

[ "$mutations_run" -eq 10 ] || fail "expected 10 mutations, ran $mutations_run"
pass "self-falsification: all $mutations_caught/10 mutations make the guard fail"

echo "All evidence-exception-bound checks passed."
