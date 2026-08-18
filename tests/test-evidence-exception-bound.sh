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
#                             pattern is the one part no review round in
#                             #588, #598 or #608 defeated. It is a
#                             vocabulary, and its limit is stated below.
#                             It is reused verbatim below.
#   markers  for COMPLIANCE — every mention outside the canonical block must
#                             carry the reference token in its OWN SENTENCE.
#                             Token presence is syntactic. Checkable.
#   verbatim for MEANING    — the rule is stated in exactly ONE marked block
#                             in the shipped doc, and compared VERBATIM after
#                             whitespace normalisation. Not byte-for-byte: an
#                             earlier header said that, and it was an
#                             overclaim (seat 1, round 6). Line wrapping and
#                             indentation are free to change, because the
#                             markdown source is reflowed by ordinary edits
#                             and a reflow does not change the rule. Every
#                             word, and the order of every word, is fixed.
#
# STATED LIMIT — read this before extending the guard. A sentence that carries
# the reference token and ALSO misstates the rule passes this check. That is
# deliberate. Judging whether prose means what it says is review's job, not a
# validator's; #588/PR #598 spent 22 rounds proving what happens to a validator
# that takes on that ambition. The guard's job is to make each restatement it
# DETECTS reachable from the one authoritative statement, so a human or
# reviewer can check it in one hop. Do not grow this file toward semantic
# matching.
#
# Read that limit together with the word REACHABLE above: this guard makes
# every DETECTED restatement carry a pointer. It does not, and cannot, make
# every restatement detected — MENTION is a vocabulary, so a paraphrase that
# avoids every one of its alternatives is neither flagged nor bound. Seat 1
# raised the gap between those two readings in round 6. The honest claim is
# the narrow one: what this guard finds, it binds.
#
# SECOND STATED LIMIT — RENDER CAPTURE IS OUT OF SCOPE. This guard reads the
# document's SOURCE TEXT. It does not render it, and it does not try to prove
# what a markdown renderer will wrap the rule in. A raw HTML element opened
# before the block — seat 1's canonical example is `<section hidden>`, which
# renders the rule under html>body>section[hidden]>p>strong while every check
# here passes — is NOT detected, by decision.
#
# The reason is a threat model, not an oversight. Anyone who can add
# `<section hidden>` to this document already has commit access, and someone
# with commit access can simply DELETE the rule. Review is the control for a
# committer-adversary; this guard is not. What it is for is catching ACCIDENTS
# — a stray fence, a dropped marker, a drifting restatement — and binding the
# restatements it detects to one authoritative statement.
#
# It does NOT keep every honest edit reachable, and an earlier draft of this
# header said it did. Seat 1 falsified that in round 7 with an unbound
# paraphrase ("Stale evidence buys another pass") that MENTION does not
# match, so nothing flags it. That is stated limit #1 above working as
# documented, not a defect — but the header may not promise past it.
#
# This limit is recorded because three consecutive review rounds were spent
# adding invariants to close render-capture, and each one was falsified by the
# next render. Every remaining check in this file is falsifiable in render-space
# by construction; that is a property of source-text checking a rendered format,
# not a defect in any one check. A new render-capture finding is a finding
# against this named non-goal.
#
# THIRD STATED LIMIT — NO CONTAINER-BLOCK MODELING. Check 1b requires every
# fence opened before the rule to be EXPLICITLY CLOSED in the source. That is
# stricter than CommonMark, which closes a container-nested fence at the end of
# its container. A fence left unclosed inside a list item is rejected here even
# though a renderer would not let it reach the rule. That is a decision, not an
# oversight: the alternative is a container-block parser, and the alternative
# to THAT is a full markdown implementation. See 1b for the reasoning.
#
# NAMED NON-GOAL, so it is not rediscovered as a defect. A reversal welded to
# the token by an em dash, a parenthetical, a colon, a list-item line break or
# an adjacent table cell passes. Seat 1 raised this as a P1 repair in round 2;
# it was DISPUTED and the dispute was measured, not argued. Widening the clause
# split to cover those forms splits the reference token at its own colon
# ("[bound:" | "CANONICAL...]") and produces eight false violations in the
# current document. No punctuation class is an attachment boundary in English,
# so each one added is a step on the treadmill that killed the predecessor. The
# token still does its job in these cases: it carries the pointer a reader can
# follow to the authoritative block.
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
# SELF-FALSIFICATION: at the end, 20 mutations are written to a temp tree and
# the checker is RE-RUN against each. A mutation that does not make the checker
# fail means the guard is vacuous. The checker runs as a real subprocess against
# a real file; it does not re-grep a string in memory, which would only prove
# that grep works. The set is:
#
#   Form A (5)  the five predecessor near-misses, reworded INSIDE the block
#   Form B (5)  the same five injected as unmarked prose, each placed
#               immediately after a clause that carries both a mention and the
#               token — the shape the predecessor's proximity window accepted
#   Form C (4)  the four bypasses seat 1 demonstrated in round 1
#   Form D (3)  the three seat 1 raised in round 2 (stray closing marker,
#               stray opening marker, block swallowed by an unclosed fence)
#   Form E (1)  seat 1's round-3 reproduction: the rule captured by a
#               strikethrough span, so it renders inside <del> — retracted —
#               while the normalised body is byte-identical
#   Form G (1)  seat 1's round-5 reproduction: the block swallowed by an
#               unclosed `~~~` fence, which the fence check missed while it
#               counted only backticks
#   Form H (1)  seat 1's round-6 reproduction: an unclosed ```` block whose
#               inner ``` line does not close it, which the fence check missed
#               while it counted prefix-shaped lines instead of tracking fence
#               state
#
# Forms C, D, E, G and H are kept permanently: a bypass fixed without a test is
# a bypass that comes back.
#
# There are also THREE must-PASS fixtures, which are not mutations and are not
# counted above. Both guard against a check being WRONG IN THE OTHER
# DIRECTION, which no must-fail mutation can detect:
#
#   1. a harmless closed `<kbd>Ctrl</kbd>` before the block must be ACCEPTED.
#      A deleted check leaves no trace, so the round-5 overbreadth could
#      silently return; this fails the suite if it does.
#   2. a properly CLOSED ```` block containing a literal ``` line must be
#      ACCEPTED. The round-6 prefix counter rejected that valid document.
#   3. a TAB-indented literal ``` line must be ACCEPTED — a tab is 4 columns,
#      so that line is indented code, not a fence. The round-8 scanner measured
#      indent in characters and rejected that valid document.
#
# Each mutation declares WHICH check must reject it, and run_mutation FAILS if a
# different check does. Reporting the reason was not enough: seat 1 found in
# round 4 that Form C bypass #1 had drifted onto the marker-isolation check
# while the summary still claimed every mutation failed for its intended
# reason. A mutation that drifts has stopped testing what it was written for,
# and nothing said so. Every fixture also asserts its own preconditions, so it
# cannot quietly degrade into a weaker test than its label claims.

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

# The rule, verbatim and COMPLETE — including the "Otherwise STOP." default,
# which is part of the certified sentence. Whitespace-normalised, so a
# statement that wrapped across lines is still one string here.
#
# The default is inside the block deliberately. Cross-model review (seat 1,
# 2026-08-17) demonstrated that with the block closed before it, flipping the
# excluded "Otherwise STOP." to "Otherwise CONTINUE." reversed the rule and the
# guard still passed.
CANONICAL_RULE = (
    "**After those two passes, continue ONLY when the immediately preceding "
    "COMPLETED pass recorded either (a) an open P0/P1 showing a requested "
    "behavior is currently wrong, or (b) the FIRST verification-evidence "
    "invalidation in this root task.** An evidence-only finding authorizes "
    "exactly one additional pass per root task; a later evidence-only finding "
    "is filed. Otherwise STOP."
)

# Every way the exception can be NAMED. The predecessor's pattern is the first
# three alternatives; detection was the part of it that survived. The fourth
# was added after seat 1 defeated the original with "Invalid verification
# evidence always authorizes another pass." — `invalidat\w*` does not match
# "Invalid".
#
# STATED LIMIT ON DETECTION: this is a vocabulary, and a vocabulary can always
# be evaded by a paraphrase that shares no listed token. That is a real hole
# and it is not closable by adding alternatives forever — "Stale evidence buys
# another pass" uses the rule's own vocabulary and matches nothing listed here.
# It is bounded, though, in a way the predecessor's MEANING regex was not:
# evading detection requires avoiding the listed token patterns, whereas the
# predecessor could be evaded while quoting the rule verbatim. Extend this
# pattern when a real evasion is observed; do not speculatively grow it.
MENTION = re.compile(
    r"(invalidat\w*\s+(its\s+)?(verification[- ])?evidence"
    r"|(verification[- ])?evidence[- ]invalidation"
    r"|evidence-only"
    r"|invalid\w*\s+(verification\s+)?evidence)",
    re.I,
)

path = sys.argv[1]
raw = open(path, encoding="utf-8").read()
text = " ".join(raw.split())
problems = []

# 1. The canonical block exists exactly once — and so does each marker.
#    Counting matched PAIRS is not enough: seat 1 appended a bare closing
#    marker at EOF and the pair count stayed 1, so the check passed while the
#    document contained a stray marker that a later edit could pair with.
if raw.count(OPEN_MARK) != 1 or raw.count(CLOSE_MARK) != 1:
    print(
        "each canonical marker must appear exactly once: found %d opening and "
        "%d closing (a stray unmatched marker can be paired by a later edit)"
        % (raw.count(OPEN_MARK), raw.count(CLOSE_MARK))
    )
    sys.exit(1)

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

# 1b. Every code fence opened before the canonical block must be EXPLICITLY
#     CLOSED in the source, before the block.
#
#     Read that as written. It is a SOURCE-LEVEL rule, and it is deliberately
#     STRICTER than CommonMark. CommonMark closes an unclosed fence at the end
#     of its containing block, so a fence opened inside a list item is closed
#     by the end of that list item and cannot reach the rule. This check does
#     not model container blocks and does not know that; it requires the
#     closing fence to be written. A fence left unclosed inside a list item is
#     therefore REJECTED here, and that is the rule firing, not a false
#     positive — it is a shape this document can simply not write.
#
#     Why strict rather than accurate: the accurate version is a container-block
#     parser, and the accurate version of the NEXT question is a full markdown
#     implementation. Rounds 3 through 5 of this PR were spent proving that a
#     source-text checker cannot win an argument about rendering. A claim about
#     what the SOURCE contains is exact and settleable; a claim about what a
#     renderer does with it is falsifiable forever. So this check makes the
#     source claim, and the accident it exists for — a stray fence that runs on
#     and swallows the rule — is caught by it either way.
#
#     What IS tracked, per CommonMark, is which fence lines pair with which: a
#     closing fence must use the SAME character as its opener and be AT LEAST
#     as long, it carries no info string, and while a fence is open every other
#     line — including a shorter or differently-charactered fence line — is
#     literal content. Seat 1 demonstrated in round 6 that counting look-alike
#     prefixes instead gets this wrong in BOTH directions. CommonMark defines
#     exactly two fence characters, so that part is closed by spec.
before = raw[: raw.index(OPEN_MARK)]
open_char = None
open_len = 0
for ln in before.splitlines():
    stripped = ln.lstrip()
    # An indent of 4+ COLUMNS is an indented code block, not a fence. Columns,
    # not characters: a tab advances to the next 4-column tab stop, so a single
    # leading tab is already 4 columns and its line is indented code. Seat 1
    # found (round 8) that measuring characters here rejected a valid document
    # whose literal ``` line was tab-indented.
    indent = 0
    for ich in ln[: len(ln) - len(stripped)]:
        indent = indent + 4 - (indent % 4) if ich == "\t" else indent + 1
    if indent >= 4:
        continue
    ch = stripped[:1]
    if ch not in ("`", "~"):
        continue
    n = len(stripped) - len(stripped.lstrip(ch))
    if n < 3:
        continue
    info = stripped[n:].strip()
    if open_char is None:
        # A backtick info string may not itself contain a backtick.
        if ch == "`" and "`" in info:
            continue
        open_char, open_len = ch, n
    elif ch == open_char and n >= open_len and not info:
        open_char, open_len = None, 0

if open_char is not None:
    print(
        "a %s code fence opened before the canonical block (%d %r) is never "
        "explicitly closed in the source. This guard requires explicit closure "
        "and does not model container blocks, so it is stricter than CommonMark "
        "here by design — write the closing fence"
        % ("tilde" if open_char == "~" else "backtick", open_len, open_char)
    )
    sys.exit(1)

# 1c. Each marker owns its line, and the block is separated by blank lines.
#     Seat 1 demonstrated (round 3, with a cmark-gfm render) that inlining the
#     CLOSING marker into surrounding prose and opening a `~~` span before the
#     block makes the whole rule render inside <del> — struck through, i.e.
#     retracted — while the normalised body is byte-identical and the checker
#     exits 0.
#
#     Chasing `~~` alone would be the treadmill again: the next GFM inline
#     construct does the same job. The structural invariant closes that class
#     instead. GFM INLINE SPANS cannot cross a blank line, so a block that is
#     line-isolated and paragraph-separated cannot be captured by an inline
#     span opened outside it.
#
#     That claim is scoped to GFM inline spans and to nothing else. RAW HTML
#     IS NOT AN INLINE SPAN, it does cross blank lines, and it is explicitly
#     OUT OF SCOPE here — see the second STATED LIMIT in the header. An
#     earlier revision of this file claimed 1c stopped "any inline construct";
#     that was an overclaim, seat 1 falsified it with a render, and the
#     wording is now bounded to what the check actually proves.
lines = raw.splitlines()
open_lines = [i for i, ln in enumerate(lines) if OPEN_MARK in ln]
close_lines = [i for i, ln in enumerate(lines) if CLOSE_MARK in ln]
for label, idxs, mark in (("opening", open_lines, OPEN_MARK), ("closing", close_lines, CLOSE_MARK)):
    if len(idxs) != 1 or lines[idxs[0]].strip() != mark:
        print(
            "the %s canonical marker must be alone on its own line (found: %r) "
            "— an inlined marker lets an inline span opened outside the block "
            "capture the rule, so it renders struck through or as code while "
            "the text is byte-identical"
            % (label, lines[idxs[0]] if idxs else None)
        )
        sys.exit(1)

o, c = open_lines[0], close_lines[0]
if o == 0 or lines[o - 1].strip() != "" or c + 1 >= len(lines) or lines[c + 1].strip() != "":
    print(
        "the canonical block must be surrounded by blank lines — GFM inline "
        "spans cannot cross a blank line, and that separation is what stops a "
        "span opened outside the block from capturing the rule"
    )
    sys.exit(1)

if "~~" in raw[raw.index(OPEN_MARK) : raw.index(CLOSE_MARK)]:
    print("the canonical block contains a strikethrough delimiter")
    sys.exit(1)

# 1d is DELETED. It banned every raw HTML element name before the block. Seat
#     1 falsified it from both sides in one round: too narrow, because
#     `<section hidden>` is not in any hand-written element list and a `~~~`
#     fence captures the block using no element name at all; and too broad,
#     because a harmless closed `<kbd>Ctrl</kbd>` — which can capture nothing —
#     failed the suite. Three consecutive rounds each closed one render-capture
#     hole and each opened another. That is the treadmill this file's header
#     warns about, and the exit is a scope decision, not a fourth patch: see
#     the second STATED LIMIT in the header. A render can falsify a claim about
#     what a check catches; it cannot falsify a decision about what the check
#     is for.

lo, hi = blocks[0]
block = text[lo:hi]

# 2. The block IS the rule — exactly, and nothing else. Containment is not
#    enough: seat 1 inserted "But every evidence-only finding authorizes another
#    pass." immediately before the closing marker and a containment check still
#    passed, because the rule was still in there, sitting next to its own
#    contradiction. Equality is what makes the block authoritative.
body = block[len(OPEN_MARK) : -len(CLOSE_MARK)].strip()
if body != CANONICAL_RULE:
    problems.append(
        "the canonical block is not EXACTLY the rule — nothing may be added, "
        "removed or reworded between the markers. Got: %r" % (body[:400],)
    )

# 3. The rule is stated ONCE. It must not appear outside the block.
if CANONICAL_RULE in (text[:lo] + text[hi:]):
    problems.append(
        "the canonical rule text appears outside the canonical block — state it "
        "once, reference it elsewhere"
    )

# 4. Every mention outside the block carries the reference token in its OWN
#    CLAUSE. Clause-scoped, not window-scoped: the predecessor was defeated
#    twice by a mutated clause sitting next to a correctly-bounded sentence,
#    which a proximity window accepted. Proximity is not attachment.
#
#    The split includes ';' because seat 1 defeated a sentence-only split with
#    "... no more [bound: ...]; nevertheless every later evidence-only finding
#    authorizes another pass." A semicolon joins two independent clauses, so a
#    sentence boundary is not an attachment boundary.
outside = text[:lo] + text[hi:]
sentences = re.split(r"(?<=[.!?;])\s+", outside)
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
# Reports the REASON each mutation was rejected, not merely that it was. A
# mutation that fails for an unrelated reason (a garbled splice, a parse error)
# is not evidence the guard works — seat 1 found exactly that on 2026-08-17,
# where a mis-spliced fixture failed on mangled text rather than on the
# violation it was named for. Printing the reason makes that visible instead of
# silent.
# Rejects a mutation AND asserts WHICH check rejected it.
#
# Reporting the reason was not enough. Seat 1 found in round 4 that Form C
# bypass #1 had silently started failing on the marker-isolation check rather
# than the canonical-equality check it was written for — so the summary line
# claiming "each for its intended reason" was false while every mutation was
# still being caught. A mutation that drifts onto a different check has stopped
# testing what it was written to test, and nothing said so.
#
# $3 is a substring that MUST appear in the checker's rejection message.
run_mutation() {
    local label="$1" file="$2" expect="$3" reason
    mutations_run=$((mutations_run + 1))
    if reason=$(python3 "$CHECKER" "$file" 2>&1); then
        fail "self-falsification: guard still PASSES under mutation [$label] — the guard is vacuous"
    fi
    case "$reason" in
        *"$expect"*) ;;
        *)
            fail "self-falsification: mutation [$label] was rejected, but by the WRONG check. Expected a reason containing '$expect', got: $reason"
            ;;
    esac
    mutations_caught=$((mutations_caught + 1))
    echo "  caught: $label"
    echo "    reason: ${reason:0:150}"
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
    run_mutation "in-block reword #$i ($find -> ${replace:-<deleted>})" "$m" "not EXACTLY the rule"
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
import re
import sys

src, dst, sentence = sys.argv[1], sys.argv[2], sys.argv[3]
REF_TOKEN = "[bound: CANONICAL:evidence-exception-bound]"
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"
CLOSE_MARK = "<!-- /CANONICAL:evidence-exception-bound -->"
MENTION = re.compile(
    r"(invalidat\w*\s+(its\s+)?(verification[- ])?evidence"
    r"|(verification[- ])?evidence[- ]invalidation"
    r"|evidence-only"
    r"|invalid\w*\s+(verification\s+)?evidence)",
    re.I,
)

text = open(src, encoding="utf-8").read()

# Inject IMMEDIATELY after a clause that is genuinely COMPLIANT — one that both
# mentions the rule and carries the token. This is the shape that defeated the
# predecessor: its proximity window saw the neighbouring compliant clause and
# accepted the mutant.
#
# The previous version of this injector took the first REF_TOKEN occurrence and
# then the next ".", which landed on the dot in "test-evidence-exception-bound.sh"
# inside an explanatory paragraph. It spliced mid-filename and produced garbage
# that failed for an unrelated reason. Seat 1 caught that on 2026-08-17. Hence
# the assertions below: this script now refuses to emit a mutant that does not
# realise the scenario it is named for.
blk = re.search(re.escape(OPEN_MARK) + r".*?" + re.escape(CLOSE_MARK), text, re.S)
if not blk:
    sys.stderr.write("injector: canonical block not found\n")
    sys.exit(2)

target = None
for m in re.finditer(r"[^.!?;]*[.!?;]", text):
    clause = m.group(0)
    if blk.start() <= m.start() < blk.end():
        continue  # inside the canonical block
    if MENTION.search(clause) and REF_TOKEN in clause:
        target = m
        break
if target is None:
    sys.stderr.write("injector: no compliant clause (MENTION + token) found to inject after\n")
    sys.exit(2)

cut = target.end()
out = text[:cut] + " " + sentence + text[cut:]

# Assert the scenario actually holds, rather than trusting the splice.
if out == text:
    sys.stderr.write("injector: injection was a no-op\n")
    sys.exit(2)
preceding = out[target.start() : target.end()]
if REF_TOKEN not in preceding or not MENTION.search(preceding):
    sys.stderr.write("injector: the clause preceding the injection is not compliant\n")
    sys.exit(2)
injected = out[cut + 1 : cut + 1 + len(sentence)]
if injected != sentence:
    sys.stderr.write("injector: injected text was mangled by the splice\n")
    sys.exit(2)
if not MENTION.search(injected):
    sys.stderr.write("injector: injected near-miss does not match MENTION, so it tests nothing\n")
    sys.exit(2)
if REF_TOKEN in injected:
    sys.stderr.write("injector: injected near-miss carries the token, so it is not a violation\n")
    sys.exit(2)

open(dst, "w", encoding="utf-8").write(out)
PYEOF

i=0
for nm in "$NEARMISS_1" "$NEARMISS_2" "$NEARMISS_3" "$NEARMISS_4" "$NEARMISS_5"; do
    i=$((i + 1))
    m="$WORK/unmarked-$i.md"
    python3 "$INJECTOR" "$DOC" "$m" "$nm" \
        || fail "mutation harness broken: could not inject near-miss #$i"
    run_mutation "unmarked near-miss #$i, injected adjacent to a marked sentence" "$m" "do not carry"
done

# --- Form C: the four bypasses seat 1 demonstrated against the first version
# of this guard on 2026-08-17. Each one PASSED then. They are kept as
# permanent regression mutations, because a bypass that is fixed without a test
# is a bypass that comes back.
i=0
while IFS='|' read -r anchor injected expect; do
    [ -n "$anchor" ] || continue
    i=$((i + 1))
    m="$WORK/bypass-$i.md"
    if ! python3 - "$DOC" "$m" "$anchor" "$injected" <<'PYEOF'
import sys

src, dst, anchor, injected = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(src, encoding="utf-8").read()
if anchor not in text:
    sys.stderr.write("bypass fixture: anchor %r not found\n" % anchor)
    sys.exit(2)
out = text.replace(anchor, injected, 1)
if out == text:
    sys.stderr.write("bypass fixture: replacement was a no-op\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
    then
        fail "mutation harness broken: could not build bypass fixture #$i"
    fi
    run_mutation "seat-1 bypass #$i" "$m" "$expect"
done <<'BYPASSES'
Otherwise STOP.|Otherwise STOP. But every evidence-only finding authorizes another pass.|not EXACTLY the rule
Otherwise STOP.|Otherwise CONTINUE.|not EXACTLY the rule
and no more [bound: CANONICAL:evidence-exception-bound].|and no more [bound: CANONICAL:evidence-exception-bound]; nevertheless every later evidence-only finding authorizes another pass.|do not carry
Below-bar and out-of-scope findings are filed|Invalid verification evidence always authorizes another pass. Below-bar and out-of-scope findings are filed|do not carry
BYPASSES

# --- Form D: round-2 findings. A stray unmatched marker (either end), and the
# canonical block swallowed by an unclosed code fence.
i=0
while IFS='|' read -r anchor injected expect; do
    [ -n "$anchor" ] || continue
    i=$((i + 1))
    m="$WORK/r2-$i.md"
    if ! python3 - "$DOC" "$m" "$anchor" "$injected" <<'PYEOF'
import sys

src, dst, anchor, injected = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(src, encoding="utf-8").read()
if anchor not in text:
    sys.stderr.write("r2 fixture: anchor %r not found\n" % anchor)
    sys.exit(2)
out = text.replace(anchor, injected, 1)
if out == text:
    sys.stderr.write("r2 fixture: replacement was a no-op\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
    then
        fail "mutation harness broken: could not build round-2 fixture #$i"
    fi
    run_mutation "seat-1 round-2 finding #$i" "$m" "$expect"
done <<'R2FIXTURES'
Below-bar and out-of-scope findings are filed|<!-- /CANONICAL:evidence-exception-bound --> Below-bar and out-of-scope findings are filed|must appear exactly once
Below-bar and out-of-scope findings are filed|<!-- CANONICAL:evidence-exception-bound --> Below-bar and out-of-scope findings are filed|must appear exactly once
R2FIXTURES

# The unclosed-code-fence fixture needs an embedded newline, which the '|'
# table above cannot carry, so it is built on its own.
m="$WORK/r2-fence.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
ANCHOR = "**SCOPE RULE.** One review and one verify"
text = open(src, encoding="utf-8").read()
if ANCHOR not in text:
    sys.stderr.write("fence fixture: anchor not found\n")
    sys.exit(2)
# One stray opening fence before the rule, closed by nothing.
out = text.replace(ANCHOR, "```\n" + ANCHOR, 1)
if out == text:
    sys.stderr.write("fence fixture: replacement was a no-op\n")
    sys.exit(2)
before = out[: out.index("<!-- CANONICAL:evidence-exception-bound -->")]
fences = len([ln for ln in before.splitlines() if ln.lstrip().startswith("```")])
if fences % 2 == 0:
    sys.stderr.write("fence fixture: parity is still even (%d), fixture is inert\n" % fences)
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the unclosed-fence fixture"
fi
run_mutation "seat-1 round-2: canonical block inside an unclosed code fence" "$m" "backtick code fence opened before the canonical block"

# Seat 1's round-3 reproduction, verified by it with a cmark-gfm render: inline
# the CLOSING marker into the following prose and open a strikethrough span
# before the block. The normalised body is byte-identical, so the equality
# check passes — but the whole rule renders inside <del>, i.e. retracted.
m="$WORK/r3-strikethrough.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"
CLOSE_MARK = "<!-- /CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
if OPEN_MARK not in text or CLOSE_MARK not in text:
    sys.stderr.write("strikethrough fixture: markers not found\n")
    sys.exit(2)

# `~~` opened before the block and closed after it, with the closing marker
# pulled inline so no blank line separates the span from the rule.
out = text.replace(OPEN_MARK, "~~\n" + OPEN_MARK, 1)
out = out.replace("\n" + CLOSE_MARK + "\n", " " + CLOSE_MARK + " ~~ ", 1)
if out == text:
    sys.stderr.write("strikethrough fixture: replacement was a no-op\n")
    sys.exit(2)

# The fixture is only meaningful if the canonical body still normalises
# identically — that is the whole point of the attack.
norm_before = " ".join(text[text.index(OPEN_MARK) : text.index(CLOSE_MARK)].split())
norm_after = " ".join(out[out.index(OPEN_MARK) : out.index(CLOSE_MARK)].split())
if norm_before != norm_after:
    sys.stderr.write("strikethrough fixture: body changed, so it does not test the reported hole\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the strikethrough fixture"
fi
run_mutation "seat-1 round-3: rule captured by a strikethrough span (renders as <del>)" "$m" "alone on its own line"

# Form G. Seat 1's round-5 reproduction: an unclosed `~~~` fence swallows the
# block and renders the rule under html>body>pre>code, while the fence check
# saw nothing because it counted only backtick fences. CommonMark defines
# exactly two fence characters, so closing this closes the class by spec.
m="$WORK/r5-tilde-fence.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
# One stray opening tilde fence before the rule, closed by nothing.
out = text.replace("\n\n" + OPEN_MARK, "\n\n~~~\n\n" + OPEN_MARK, 1)
if out == text:
    sys.stderr.write("tilde-fence fixture: replacement was a no-op\n")
    sys.exit(2)

before = out[: out.index(OPEN_MARK)]
tildes = len([ln for ln in before.splitlines() if ln.lstrip().startswith("~~~")])
if tildes % 2 == 0:
    sys.stderr.write("tilde-fence fixture: parity is still even (%d), fixture is inert\n" % tildes)
    sys.exit(2)
# Backtick parity must stay untouched, or the fixture would be caught by the
# wrong half of the check and prove nothing about tilde fences.
ticks = len([ln for ln in before.splitlines() if ln.lstrip().startswith("```")])
if ticks % 2 != 0:
    sys.stderr.write("tilde-fence fixture: backtick parity is odd (%d), fixture tests the wrong thing\n" % ticks)
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the unclosed-tilde-fence fixture"
fi
run_mutation "seat-1 round-5: canonical block inside an unclosed ~~~ fence" "$m" "tilde code fence opened before the canonical block"

# Form H. Seat 1's round-6 reproduction, the must-FAIL half: a four-backtick
# block that is never closed, containing a literal ``` line. The predecessor
# check counted prefix-shaped lines, so the inner ``` "closed" the block on
# paper and the capture went undetected. Under real fence tracking a shorter
# fence is literal content while a longer one is open, and this is caught.
m="$WORK/r6-fourtick-unclosed.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
stray = "\n\n````\nnot a closing fence:\n```\n"
out = text.replace("\n\n" + OPEN_MARK, stray + "\n" + OPEN_MARK, 1)
if out == text:
    sys.stderr.write("fourtick fixture: replacement was a no-op\n")
    sys.exit(2)
before = out[: out.index(OPEN_MARK)]
# The whole point: naive prefix PARITY sees an even number and is fooled.
ticks = len([ln for ln in before.splitlines() if ln.lstrip().startswith("```")])
if ticks % 2 != 0:
    sys.stderr.write(
        "fourtick fixture: prefix parity is odd (%d), so a naive counter would also "
        "catch it and the fixture proves nothing about fence tracking\n" % ticks
    )
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the unclosed-four-backtick fixture"
fi
run_mutation "seat-1 round-6: unclosed \`\`\`\` block whose inner \`\`\` does not close it" "$m" "backtick code fence opened before the canonical block"

[ "$mutations_run" -eq 20 ] || fail "expected 20 mutations, ran $mutations_run"
pass "self-falsification: all $mutations_caught/20 mutations make the guard fail"

# ---------------------------------------------------------------------------
# MUST-PASS fixture (not a mutation, not counted above).
#
# Check 1d used to ban every raw HTML element name appearing before the block.
# Seat 1 showed in round 5 that this failed the suite on `<kbd>Ctrl</kbd>` — a
# closed element that captures nothing and threatens nothing. The check was
# deleted, and render capture is now a STATED LIMIT (see the header). A deleted
# check leaves no trace, so nothing would stop that overbreadth from being
# reintroduced by a future round chasing the same hole. This fixture does: it
# fails the suite if a harmless closed element ever makes the checker reject.
m="$WORK/mustpass-kbd.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
out = text.replace("\n\n" + OPEN_MARK, "\n\nPress <kbd>Ctrl</kbd> to continue.\n\n" + OPEN_MARK, 1)
if out == text:
    sys.stderr.write("kbd fixture: replacement was a no-op\n")
    sys.exit(2)
if "<kbd>" not in out[: out.index(OPEN_MARK)]:
    sys.stderr.write("kbd fixture: element did not land before the block\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the kbd must-pass fixture"
fi
if ! reason=$(python3 "$CHECKER" "$m" 2>&1); then
    fail "false positive: a harmless closed <kbd>Ctrl</kbd> before the block made the guard REJECT. The round-5 overbreadth has returned. Reason given: $reason"
fi
pass "no false positive: a harmless closed HTML element before the block is accepted"

# MUST-PASS fixture #2 — the other half of seat 1's round-6 P1. A four-backtick
# block that IS properly closed, containing a literal ``` line. The predecessor
# prefix counter rejected this valid document. Fence tracking must accept it.
m="$WORK/mustpass-fourtick-closed.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
block = "\n\n````\nnot a closing fence:\n```\n````\n"
out = text.replace("\n\n" + OPEN_MARK, block + "\n" + OPEN_MARK, 1)
if out == text:
    sys.stderr.write("closed-fourtick fixture: replacement was a no-op\n")
    sys.exit(2)
before = out[: out.index(OPEN_MARK)]
ticks = len([ln for ln in before.splitlines() if ln.lstrip().startswith("```")])
if ticks % 2 == 0:
    sys.stderr.write(
        "closed-fourtick fixture: prefix parity is even (%d), so a naive counter would "
        "also accept it and the fixture proves nothing\n" % ticks
    )
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the closed-four-backtick fixture"
fi
if ! reason=$(python3 "$CHECKER" "$m" 2>&1); then
    fail "false positive: a properly CLOSED \`\`\`\` block containing a literal \`\`\` line made the guard REJECT. The check is counting prefixes again instead of tracking fence state. Reason given: $reason"
fi
pass "no false positive: a closed \`\`\`\` block containing a literal \`\`\` line is accepted"

# MUST-PASS fixture #3 — seat 1's round-8 P1. A TAB-indented literal ``` line
# is indented code, not a fence, because a tab advances to the next 4-column
# tab stop. Measuring indent in characters instead of columns rejected this
# valid document. Locked in here rather than left to the fix, because indent
# arithmetic is exactly the kind of thing a later edit re-simplifies.
m="$WORK/mustpass-tab-indent.md"
if ! python3 - "$DOC" "$m" <<'PYEOF'
import sys

src, dst = sys.argv[1], sys.argv[2]
OPEN_MARK = "<!-- CANONICAL:evidence-exception-bound -->"

text = open(src, encoding="utf-8").read()
out = text.replace("\n\n" + OPEN_MARK, "\n\n\t```\n\n" + OPEN_MARK, 1)
if out == text:
    sys.stderr.write("tab-indent fixture: replacement was a no-op\n")
    sys.exit(2)
if "\n\t```" not in out[: out.index(OPEN_MARK)]:
    sys.stderr.write("tab-indent fixture: tab-indented line did not land before the block\n")
    sys.exit(2)
open(dst, "w", encoding="utf-8").write(out)
PYEOF
then
    fail "mutation harness broken: could not build the tab-indent must-pass fixture"
fi
if ! reason=$(python3 "$CHECKER" "$m" 2>&1); then
    fail "false positive: a TAB-indented literal \`\`\` line made the guard REJECT. Indent is being measured in characters again instead of columns. Reason given: $reason"
fi
pass "no false positive: a tab-indented literal \`\`\` line is indented code, not a fence"


echo "All evidence-exception-bound checks passed."
