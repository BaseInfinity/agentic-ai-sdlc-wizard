#!/usr/bin/env python3
"""GH #513 — find assertions that verify a QUOTATION instead of the document.

CLAUDE_CODE_SDLC_WIZARD.md carried a 639-line ````markdown fence introduced by
"Step 6: Create SDLC Skill" — a second install path for the file the CLI already
writes. Assertions were grepping the DOCUMENT for strings that exist only inside
that fence (`### Release Review Focus`, `gh pr merge --auto`, `no stall watchdog
and no timeout`), so they were verifying a copy of a draft the CLI does not
install, cowork/ does not byte-check, and the #489 ceiling does not cover.

Same defect class as PR #517's fixture, which committed dummy files as the
"pristine gate" while executing the real script: a check that appears to verify
X and actually verifies Y.

MATCHING THE TARGET IS THE WHOLE POINT. The first version matched on the search
STRING alone and flagged `grep -q "CODE_REVIEW_EXCEPTIONS.md" "$WORKFLOW"` — a
test of pr-review.yml that never touches the wizard doc. A guard that cries wolf
gets muted, which is worse than no guard, so a finding requires BOTH that the
needle is fence-only AND that the grep actually targets the wizard document.

WHAT COUNTS AS "INSIDE A FENCE" — TWO WRONG ANSWERS BEFORE THIS ONE.

The first version tracked only lines starting with four backticks, because that
is the fence the #513 copy happened to use. Deleting those fences made the guard
silently vacuous: with zero four-backtick fences left, `outside` came out
byte-identical to `doc`, so `needle in doc and needle not in outside` could never
be true again. (An earlier note gave a byte count for that state; it was measured
mid-development against a document neither `main` nor this branch now has, and no
reachable tree reproduces it, so it is gone rather than left looking checkable.) A guard for the "appears to verify X,
actually verifies Y" defect class had quietly become an instance of it.

The obvious repair — strip EVERY fenced block — overshoots. Measured against the
tree this ships in, it flags 19 live assertions across three suites
(test-doc-consistency.sh, test-hooks.sh, test-self-update.sh), pinning `"verification_checklist"`,
`"You are doing a TARGETED RECHECK`, `CHANGELOG completeness`, `SDLC Harness
Version`, `SDLC Harness Update Check`, `gh issue create`, `issues: write` and
`sparse-checkout` across test-self-update.sh and test-hooks.sh. Those live in a
handoff.json schema example, a recheck-prompt template and workflow examples:
legitimate document content a test SHOULD be able to pin. (An earlier version of
this paragraph said four, counted before the promotion added document-level
content — the argument got stronger and the stated number went stale.)

So the scope is neither "four-backtick blocks" nor "all blocks" but the property
that made the original assertions worthless: the block was a COPY OF THE SKILL.
`skillcopy.copy_blocks` is the single definition of that, shared with the guard
that forbids such blocks outright.

That makes this guard DORMANT while the document is healthy and live the moment a
copy reappears. Dormant-by-precondition is not vacuous-by-accident, and the
difference is demonstrable: `--selftest` runs it against a synthetic document
that HAS a copy, so the detector is exercised on every run rather than only when
the repo is already broken.

HOW IT READS SHELL — six ways the previous version silently missed real
assertions (Codex round 2, all four confirmed by behavioural fixture):

1. A HARD-CODED list of target variable names (WIZARD/WIZARD_DOC/WIZARD_FILE/DOC)
   missed `$MANUAL`. It also missed `$SKILL`, which in
   tests/test-memory-audit-protocol.sh:27 is assigned the WIZARD DOC despite its
   name. Variable names are now RESOLVED
   PER FILE from assignments, so the guard cannot fall behind a rename.
2. Backslash-continued commands were invisible, and `grep ... \` chained with
   `&&` is the dominant multi-condition idiom in this corpus. Continuations are
   joined before matching.
3. `grep -f patterns.txt target` takes its needles from a FILE, so no literal is
   present to check. Skipping it silently is how a whole assertion form
   disappears; it is now REPORTED as unverifiable, which is a true statement
   about the guard's reach rather than a false claim of coverage. Zero instances
   exist in the corpus today, so this cannot cry wolf on arrival.
4. tests/test-doc-consistency.sh was excluded WHOLESALE because it contains
   extractor machinery. Excluding a file to avoid parsing its heredocs discards
   its real assertions too. Heredoc BODIES are now stripped everywhere — the
   machinery is what lives in them — and no file is excluded.
5. Three needle shapes were dropped with NO report: a case-insensitive `grep -i`,
   a needle containing regex metacharacters, and any needle under 12 characters.
   All three were mechanically resolvable from text already in hand, and one of
   them — `grep -A 500 ... | grep -i 'content:.*cross-model review'` — was the
   EXACT assertion this PR deletes, i.e. the shape the guard most exists to keep
   out was invisible to it. Case is now folded, patterns are compiled in the
   dialect grep would use, and the floor is 4 characters (the old 12 did no
   false-positive work: a short needle that also appears OUTSIDE a copy is
   legitimate on the `not in outside` test alone, which is the real
   discriminator).
6. `SECTION=$(awk '...' "$WIZARD")` — the corpus's dominant extraction idiom —
   never resolved, because the assignment pattern stops at the first space and
   captured `$(awk`. Every content check on the extract then passed silently.
   Resolution is by TAINT, not parsing: a variable holding text extracted from
   the wizard doc IS wizard-doc content, so line-level containment is the whole
   rule. Rounds 2 through 8 of this file are all shell-parser patches; taint is
   the last increment that pays.

ACCEPTED LIMITS OF THE SHELL READING, and the decision to stop extending it.
Rounds 2 through 9 of this module are all shell-parser repairs: shell has a rule
this file did not model, a reviewer finds it, the rule gets modelled, the next
round finds the next one. These are known-open and deliberately NOT patched:

- `cat <<E"OF"` is delimiter `EOF` in bash. This reads tag `E`, finds no
  terminator, and consumes to end of file, hiding any assertion after it.
- A quoted string SPANNING LINES that contains `<<EOF` swallows the same way;
  operand blanking is per line by design, because cross-line quote tracking
  mis-syncs on one stray apostrophe and would blank the rest of a file.
- `MANUAL=doc.md some_command` is a TEMPORARY assignment — `MANUAL` is empty
  afterwards — but this treats it as persistent, so a later grep on `$MANUAL`
  can be falsely condemned.
- `2>/dev/null MANUAL=doc.md` IS a persistent assignment, but a leading
  redirection ends prefix position here, so it is missed.

They are open because the FIX IS NOT MORE PARSING. Narrowing to a closed grammar
does not work either: `<<E"OF"` does not look out-of-grammar, it aliases silently
INTO the grammar as tag `E`, so "report what you cannot parse" is unreachable
without parsing shell well enough to know you cannot. GH #527 carries the ruling —
replace all of this with a containment scan on the raw filename plus a sanctioned
helper vocabulary, which is invariant under everything shell can do to disguise a
line. That is a 27-file migration and belongs in its own PR.

Living with them is bounded by the other guard: every one of these requires a
SKILL COPY to be present in the wizard document, and skillcopy.py detects that
markup-blind and fails the build. This module is defense-in-depth for an event
that guard has already rejected, which is why its gaps degrade coverage rather
than open a hole.

WHERE THE UNVERIFIABLE REPORT IS AND IS NOT APPROPRIATE. It is for needles whose
CONTENT this guard cannot know — `grep -f` reads them from another file, and an
interpolated `$VAR` needle is unknown at scan time. Weakness in this guard's own
matcher is NEVER grounds for it: reporting a shape the guard could resolve trades
a silent miss for a noisy one and trains the reader to ignore the channel. The
current tree produces zero offenders AND zero unverifiable reports, which is the
bar any change here has to clear.

Usage:
    fence-only-assertions.py <repo-root>   check the real suites; exit 1 on offenders
    fence-only-assertions.py --selftest    run the behavioural fixtures
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import skillcopy                    # noqa: E402  (path set above)

WIZARD_DOC = "CLAUDE_CODE_SDLC_WIZARD.md"

# grep [flags] [--] "needle" <target>. The target is required and is what makes
# this a wizard-doc assertion rather than some other file's.
FLAGS = r"(?:-[a-zA-Z]+(?:\s+\d+)?\s+)*"
GREP = re.compile(r"""grep\s+(%s)(?:--\s+)?(["'])(.{4,}?)\2\s+(\S+)""" % FLAGS)
# The 90-char ceiling is NOT cosmetic here and must not be removed: this pattern
# has no target to anchor against, so an unbounded needle span walks straight
# through the closing quote and the file argument of an ORDINARY grep, capturing
# `AGENTS\.md" "$WIZARD` as one needle. Removing it produced ~100 false reports
# across the corpus (round 9, self-inflicted while fixing the 12-char floor).
# A grep with NO file argument reads stdin — its target is whatever piped into
# it. `grep -A 500 "## Heading" "$WIZARD" | grep -q "<needle>"` is the exact
# shape of the two bogus assertions this PR deletes; matching only greps that
# carry their own target makes the guard silent on the form most likely to
# come back (Fable round 2, reproduced against the HEAD document).
# The needle span must EXCLUDE its own delimiter. `.{4,90}?` walked straight
# through the closing quote and the file argument of an ordinary grep, so
# `grep -q "HIL" "$WIZARD"` captured `HIL" "$WIZARD` as a stdin needle. It was
# invisible while `_judge` silently dropped anything containing `$`; making
# interpolation reportable surfaced ~100 of them at once (round 9).
GREP_STDIN = re.compile(
    r"""grep\s+(%s)(?:--\s+)?(?:"([^"]{4,90})"|'([^']{4,90})')\s*(?=\||;|&&|\)|$)"""
    % FLAGS, re.M)
# grep -f/-F-with-f style: needles come from a file, so there is no literal here.
GREP_PATTERN_FILE = re.compile(r"""grep\s+((?:-[a-zA-Z]+(?:\s+\d+)?\s+)*)-[a-zA-Z]*f[a-zA-Z]*\s+(\S+)\s+(\S+)""")
# Assignments are found as TOKENS rather than anchored to the start of a line.
# A line-anchored `KEYWORD? NAME=VALUE` regex kept losing real forms one variant
# at a time: first bare-only (missed `local F=`), then keyword-only (missed
# `local -r MANUAL=` and `declare -r`, and misresolved the multi-assignment
# `local OTHER=x MANUAL=...` to OTHER while dropping MANUAL). Scanning for every
# NAME=VALUE token handles flags, keywords and multi-assignment without
# enumerating them, which is the enumeration that kept coming up short.
# The VALUE may concatenate quoted and unquoted pieces: `"$ROOT"/CLAUDE_...md`
# is one path, and a regex that stops at the closing quote captured only "$ROOT"
# and lost the filename (Codex round 5). One-or-more alternating segments.
ASSIGN = re.compile(
    r"""(?:^|[\s;])([A-Za-z_][A-Za-z0-9_]*)="""
    r"""((?:"[^"]*"|'[^']*'|[^\s;|&)]+)+)""", re.M)


def strip_comments(text):
    """Drop `#` comments so `# MANUAL=...` is not read as an assignment. A `#`
    only starts a comment at the start of a line or after whitespace, and never
    inside quotes — `grep "a#b"` and `${VAR#prefix}` must survive."""
    out = []
    for line in text.split("\n"):
        q, i = None, 0
        while i < len(line):
            c = line[i]
            if q:
                # Same escape rule mask_argument_strings() uses: `\` escapes inside
                # double quotes only. Without it an escaped `\"` closed the string
                # early and a later `#` truncated a live line.
                if c == "\\" and q == '"':
                    i += 2
                    continue
                if c == q:
                    q = None
            elif c in "\"'":
                q = c
            elif c == "#" and (i == 0 or line[i - 1].isspace()):
                line = line[:i]
                break
            i += 1
        out.append(line)
    return "\n".join(out)
# `<<<word` is a here-STRING, so `(?!<)` excludes it outright. This pattern is
# deliberately loose otherwise: `x << y` (a shift) and a quoted `'<<EOF'` both
# match it, and no amount of regex tightening reliably tells them from a real
# opener. The pattern is not asked to: strip_heredocs() runs it against a line
# whose quoted spans and `$((...))` arithmetic have been blanked, so neither
# shape is present to match by the time it is applied.
# A heredoc DELIMITER is an arbitrary word, not an identifier. `cat <<'END-AWK'`
# is valid shell, and an identifier-only pattern read that tag as `END`, failed to
# find a terminator, and exposed the whole body (Codex round 9).
HEREDOC = re.compile(r"""(?<!<)<<-?(?!<)\s*(['"]?)([A-Za-z_][-A-Za-z0-9_.]*)\1""")


def join_continuations(text):
    """Join backslash-continued lines so a multi-line `grep ... \\` is one unit."""
    return re.sub(r"\\\n\s*", " ", text)


def _blank_operand_spans(line):
    """`line` with quoted spans and `$((...))` contents blanked to equal-length
    runs of spaces. Used ONLY to locate shell OPERATORS, never to produce text.

    Terminator-existence used to be the heredoc discriminator. It is not one, and
    Codex round 8 broke it three ways: a quoted `'<<EOF'` STEALS a later real
    `cat <<EOF`'s terminator and swallows everything between, an unterminated
    heredoc leaves its body in scan as a false positive, and `cat <<A <<B` exposes
    the second body. All three come from asking "does a terminator exist?" instead
    of "is this text an operator at all?". Blanking operands answers the second
    question directly, and a quoted or arithmetic `<<` simply is not there to match.

    Per line, not across lines: a quoted string spanning a newline is not resolved
    here. That bound is deliberate — cross-line quote tracking mis-syncs on a
    single stray apostrophe and would silently blank the rest of a file.
    """
    out, i, n = list(line), 0, len(line)
    while i < n:
        c = line[i]
        if c in "\"'":
            # `cat <<'AWK'` quotes the TAG to suppress expansion. That quoted span
            # IS the operator's operand, so blanking it erased the tag and the
            # heredoc stopped being recognised at all.
            head = line[:i].rstrip(" \t")
            if head.endswith("<<") or head.endswith("<<-"):
                close = line.find(c, i + 1)
                i = (close + 1) if close != -1 else i + 1
                continue
            k = i + 1
            while k < n:
                if c == '"' and line[k] == "\\":
                    k += 2
                    continue
                if line[k] == c:
                    break
                k += 1
            if k >= n:                       # unterminated on this line
                for j in range(i, n):
                    out[j] = " "
                break
            for j in range(i, k + 1):
                out[j] = " "
            i = k + 1
            continue
        if line.startswith("$((", i):
            k = line.find("))", i + 3)
            k = (k + 2) if k != -1 else n
            for j in range(i, k):
                out[j] = " "
            i = k
            continue
        i += 1
    return "".join(out)


def strip_heredocs(text):
    """Remove heredoc BODIES. Extractor machinery (awk/python) lives in them, and
    excluding whole files to dodge that machinery loses their real assertions.

    Openers are located on the operand-blanked line, and EVERY opener on that line
    is honoured in order, so `cat <<A <<B` consumes both bodies rather than leaving
    the second one in scan. An opener with no terminator consumes to end of file,
    which is what a real shell does — the alternative, keeping its body, put
    assertion-shaped lines back into the scan as false positives.
    """
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        out.append(lines[i])
        i += 1
        for m in HEREDOC.finditer(_blank_operand_spans(lines[i - 1])):
            tag = m.group(2)
            end = next((k for k in range(i, len(lines))
                        if lines[k].strip() == tag), None)
            i = len(lines) if end is None else end + 1
    return "\n".join(out)


# A new simple command begins after these, so assignment-prefix position resumes.
_KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "done",
             "for", "case", "esac", "time", "!", "{", "}"}
# These take assignments as ordinary ARGUMENTS, not just as a command prefix.
_DECLARING = {"local", "declare", "export", "readonly", "typeset"}
_CMD_BREAK = set(";|&()")
_SPACE = set(" \t")


def mask_argument_strings(text):
    """Blank the contents of quoted strings that are ARGUMENTS, keep those that
    are assignment VALUES, and neutralise `NAME=` where shell would not read an
    assignment at all. Consumed only by doc_vars().

    POSITION is what decides, per POSIX 2.9.1: a simple command is a prefix of
    assignments, then the command word, then arguments. So `MANUAL=doc.md cmd` is
    an assignment and `echo MANUAL=doc.md` is not, and no amount of quote analysis
    distinguishes them — round 8's false positive. Prefix position resumes after a
    command separator or a shell keyword, and `local`/`declare`/`export`/
    `readonly`/`typeset` accept assignments in argument position too. Outside those
    positions the `=` is blanked, because ASSIGN scans for NAME=VALUE tokens with
    no sense of position and would otherwise disagree with this function.

    Within a value, quote DELIMITERS are dropped and backslash escapes resolved,
    exactly as shell does. Preserving the delimiters kept `MANUAL=CLAUDE_CODE_
    "SDLC"_WIZARD.md` from ever matching the document name (round 8), since the
    quotes sat inside the value string. A value is any run of quoted and unquoted
    segments in one word: once a word has passed `NAME=`, the rest of it is value.
    """
    out = []
    for line in text.split("\n"):
        buf, i, n = [], 0, len(line)
        in_value = False                # this word already passed `NAME=`
        word = []                       # the current word, quotes resolved
        prefix, declaring = True, False

        def end_word(assigned):
            nonlocal prefix, declaring, word, in_value
            w = "".join(word)
            if not assigned:
                if declaring and w.startswith("-"):
                    pass                        # a flag, e.g. `local -r`
                elif w in _DECLARING:
                    declaring, prefix = True, False
                elif w in _KEYWORDS:
                    prefix, declaring = True, False
                elif w:
                    prefix, declaring = False, False
            word, in_value = [], False

        while i < n:
            c = line[i]
            if c in "\"'":
                j, k = -1, i + 1
                while k < n:
                    if c == '"' and line[k] == "\\":
                        k += 2
                        continue
                    if line[k] == c:
                        j = k
                        break
                    k += 1
                if j == -1:                     # unterminated on this line
                    buf.append(line[i:])
                    break
                span = line[i + 1:j]
                if in_value:
                    buf.append(span)            # delimiters dropped, as shell does
                    word.append(span)
                else:
                    # A masked span must be CONSUMED whole, delimiters included:
                    # emitting only the opening quote left the closing one to be
                    # read as an opener and masked across the newline.
                    buf.append(c + " " * len(span) + c)
                i = j + 1
                continue
            if in_value and c == "\\" and i + 1 < n:
                buf.append(line[i + 1])
                word.append(line[i + 1])
                i += 2
                continue
            if c in _CMD_BREAK:
                end_word(in_value)
                prefix, declaring = True, False
            elif c in _SPACE:
                end_word(in_value)
            elif c == "=" and not in_value:
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", "".join(word)):
                    if prefix or declaring:
                        in_value = True
                    else:
                        buf.append(" ")         # not an assignment; see docstring
                        i += 1
                        continue
            else:
                word.append(c)
            buf.append(c)
            i += 1
        out.append("".join(buf))
    return "\n".join(out)


# `SECTION=$(awk '...' "$WIZARD")`. ASSIGN's value stops at the first space, so
# it captured `$(awk` and SECTION never resolved — yet the corpus's dominant
# extraction idiom is exactly this, and every content check on the extract then
# passed silently (Fable round 8). Taint, not parsing: a variable holding text
# EXTRACTED from the wizard doc is wizard-doc content, so greps against it are
# assertions about the document. Line-level containment is the whole rule; the
# module's history says the next increment of shell-parsing fidelity is where it
# goes to die.
SUBST_ASSIGN = re.compile(r"(?:^|[\s;])([A-Za-z_][A-Za-z0-9_]*)=\$\(")


def doc_vars(text):
    """Shell variables in this file that resolve to the wizard document.
    Resolved from assignments rather than a hard-coded name list — that list is
    what missed $MANUAL, and it would equally have missed $SKILL, which this
    corpus really does assign to the wizard doc."""
    raw = text
    text = mask_argument_strings(text)
    names = set()
    for name, value in ASSIGN.findall(text):
        if WIZARD_DOC in value:
            names.add(name)
    # One indirection: FOO="$WIZARD" where WIZARD already resolves.
    for _ in range(3):
        grew = False
        for name, value in ASSIGN.findall(text):
            if name in names:
                continue
            if any(re.search(r"\$\{?%s\}?\b" % re.escape(n), value) for n in names):
                names.add(name)
                grew = True
        if not grew:
            break
    # Taint runs on the UNMASKED source: inside `$( ... )` the doc reference is a
    # command ARGUMENT, which masking has already blanked by design.
    for _ in range(3):
        grew = False
        for line in raw.split("\n"):
            for name in SUBST_ASSIGN.findall(line):
                if name in names:
                    continue
                if WIZARD_DOC in line or any(
                        re.search(r"\$\{?%s\}?\b" % re.escape(n), line) for n in names):
                    names.add(name)
                    grew = True
        if not grew:
            break
    return names


def targets_doc(target, names):
    if WIZARD_DOC in target:
        return True
    m = re.search(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", target)
    return bool(m and m.group(1) in names)


def scan_source(body, doc, outside, label):
    """Offenders in one shell source. `doc`/`outside` are the wizard document and
    the same document with skill-copy blocks removed.

    Scanned per logical line, because a pipeline's target is established by its
    FIRST command and inherited by everything downstream of the pipe."""
    # Comments FIRST: a `<<EOF` mentioned inside a comment was opening a heredoc
    # and swallowing everything to the next matching tag — 80 lines of
    # tests/test-workflow-triggers.sh, 20 of tests/test-evaluate-bugs.sh. Any
    # assertion added in a swallowed region would be invisible with no warning,
    # which is this guard's own named enemy (Fable round 6).
    body = strip_heredocs(strip_comments(join_continuations(body)))
    names = doc_vars(body)
    found = []
    for line in body.split("\n"):
        explicit = [(f, q, n, t) for f, q, n, t in GREP.findall(line)]
        # Any token in the line that resolves to the wizard doc establishes the
        # pipeline's subject — `sed -n '1,100p' "$WIZARD" | grep -q ...` has no
        # grep target at all, so checking only grep targets misses it.
        line_targets_doc = (WIZARD_DOC in line
                            or any(v in names
                                   for v in re.findall(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?", line)))
        seen = set()
        for flags, quote, needle, target in explicit:
            seen.add(needle)
            if "f" in flags.replace("-", "").replace(" ", ""):
                continue                # handled by GREP_PATTERN_FILE
            if not targets_doc(target, names):
                continue
            found += _judge(needle, doc, outside, label, f"target {target}", flags, quote)
        # Greps with no file argument read stdin. If anything upstream in this
        # pipeline resolves to the wizard doc, the needle is being asserted
        # against the document just as surely as a direct grep.
        if line_targets_doc:
            for flags, dq, sq in GREP_STDIN.findall(line):
                needle, quote = (dq, '"') if dq else (sq, "'")
                if needle in seen:
                    continue
                found += _judge(needle, doc, outside, label,
                                "piped from a wizard-doc command", flags, quote)
        for _, patfile, target in GREP_PATTERN_FILE.findall(line):
            if targets_doc(target, names):
                found.append(f"    {label}: grep -f {patfile} (target {target}) "
                             f"— needles come from a file; this guard cannot verify "
                             f"them. Inline the literals or assert outside a fence.")
    return found


# grep's DIALECT decides what is a metacharacter, and getting this wrong is not a
# detail: `(` is LITERAL in BRE, so treating the needle
# `### Cross-Model Review Loop (REQUIRED` as a pattern reported a plain literal as
# unverifiable — noise in the one channel that must stay trustworthy.
_META_BRE = re.compile(r"[.*\[\]^$\\]")
_META_ERE = re.compile(r"[.*+?\[\]^$(){}|\\]")
_POSIX_CLASS = {"alpha": "a-zA-Z", "digit": "0-9", "alnum": "a-zA-Z0-9",
                "space": " \\t\\n\\r\\f\\v", "blank": " \\t", "upper": "A-Z",
                "lower": "a-z", "xdigit": "0-9A-Fa-f", "word": "a-zA-Z0-9_",
                "punct": "!-/:-@\\[-`{-~", "graph": "!-~", "print": " -~",
                "cntrl": "\\x00-\\x1f\\x7f"}


def _to_python_re(pat, ere):
    """A grep pattern as a Python one. POSIX classes have no Python equivalent,
    and in BRE the characters `(){}+?|` are literal — Python treats every one of
    them as syntax, so they must be escaped rather than passed through."""
    pat = re.sub(r"\[:(\w+):\]",
                 lambda m: _POSIX_CLASS.get(m.group(1), re.escape(m.group(0))), pat)
    if ere:
        return pat
    out, i = [], 0
    while i < len(pat):
        c = pat[i]
        if c == "\\" and i + 1 < len(pat):
            nxt = pat[i + 1]
            # In BRE the ESCAPED form is the operator: `\(` groups, `\+` repeats.
            out.append(nxt if nxt in "(){}+?|" else c + nxt)
            i += 2
            continue
        out.append("\\" + c if c in "(){}+?|" else c)
        i += 1
    return "".join(out)


def _judge(needle, doc, outside, label, how, flags="", quote='"'):
    """Does this needle exist ONLY inside a skill copy?

    "Unverifiable" is reserved for needles whose CONTENT this guard cannot know —
    `grep -f` reads them from another file. Weakness in this matcher is never
    grounds for it, and treating it as such is how three shapes went silently
    missing: a case-insensitive grep, a regex needle, and a short one. Each was
    mechanically resolvable from text already in hand, and one of them —
    `grep -A 500 ... | grep -i 'content:.*cross-model review'` — was the exact
    deleted assertion this guard exists to keep out (Fable round 8).
    """
    # `$` is only INTERPOLATION in a double-quoted or unquoted needle, and only
    # before a name, `{` or `(`. Inside single quotes shell expands nothing, so
    # `'^### Heading[[:space:]]*$'` is a regex ANCHOR — and treating it as
    # interpolation silently skipped four real doc-targeting assertions in this
    # corpus (round 9). Genuine interpolation IS unknowable content, so it earns
    # the unverifiable report rather than a silent skip.
    if quote != "'" and re.search(r"\$[A-Za-z_{(]", needle):
        return [f"    {label}: {needle!r} ({how}) — needle interpolates a shell "
                f"variable, so its content is unknown at scan time; inline the "
                f"literal or assert outside a fence"]
    f = flags.replace("-", "").replace(" ", "")
    ci = "i" in f
    if "F" in f:                        # fixed-string: nothing is a metacharacter
        meta = False
    else:
        meta = bool((_META_ERE if "E" in f else _META_BRE).search(needle))
    if meta:
        try:
            # grep is LINE-oriented: `^` and `$` anchor to a line, not to the file.
            # Without re.M they anchored to the whole document and every
            # anchored pattern silently matched nothing (Codex round 10).
            rx = re.compile(_to_python_re(needle, "E" in f),
                            re.M | (re.I if ci else 0))
        except re.error:
            return [f"    {label}: {needle!r} ({how}) — needle is not a pattern "
                    f"this guard can compile; verify by hand or inline a literal"]
        inside = bool(rx.search(doc)) and not rx.search(outside)
    elif ci:
        inside = needle.lower() in doc.lower() and needle.lower() not in outside.lower()
    else:
        inside = needle in doc and needle not in outside
    if inside:
        return [f"    {label}: {needle!r} ({how}) "
                f"— exists ONLY inside a skill-copy block"]
    return []


def run(root):
    doc = open(os.path.join(root, WIZARD_DOC), encoding="utf-8").read()
    skill = open(os.path.join(root, "skills", "sdlc", "SKILL.md"), encoding="utf-8").read()
    outside = skillcopy.without_copies(doc, skill)
    suites = (glob.glob(os.path.join(root, "tests", "*.sh"))
              + glob.glob(os.path.join(root, "tests", "e2e", "*.sh")))
    found = []
    for path in suites:
        body = open(path, errors="ignore", encoding="utf-8").read()
        found += scan_source(body, doc, outside, os.path.basename(path))
    return sorted(set(found))


# --- selftest -------------------------------------------------------------
# Every fixture is a form a reviewer proved the previous version missed, across
# rounds 2 through 8. The round is named on each one.
_FENCE_ONLY = "### Release Review Focus for the embedded copy"
_DOC = ("real prose\n"
        "````markdown\n"
        "name: sdlc\n"
        "## Full SDLC Checklist\n"
        "## Confidence Check (REQUIRED)\n"
        "## Cross-Model Review (REQUIRED for High-Stakes)\n"
        + _FENCE_ONLY + "\n"
        "tag: r8only\n"          # 9-char needle, under the retired 12 floor
        "````\n"
        "tail prose\n")
_SKILL = skillcopy.SKILL_FIXTURE

_CASES = [
    ("hard-coded name list missed $MANUAL",
     'MANUAL="$REPO/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("a variable named $SKILL that is really the wizard doc",
     'SKILL="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$SKILL"\n' % _FENCE_ONLY, True),
    # Codex round 3: `local VAR=...` is ordinary shell and the bare-assignment
    # regex missed it, hiding the real `local F=...` assertion at
    # tests/test-doc-consistency.sh:1817.
    ("local VAR= declaration resolves",
     'local MANUAL="$REPO/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    # Codex round 4: flags after the keyword, and multi-assignment where the
    # FIRST name is not the document variable.
    # Codex round 5: quoted+unquoted concatenation, and two false-positive shapes.
    ("value concatenating a quoted var and an unquoted path resolves",
     'MANUAL="$ROOT"/CLAUDE_CODE_SDLC_WIZARD.md\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("a commented-out assignment is not an assignment",
     '# MANUAL="$R/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, False),
    ("an assignment-looking string inside a command argument is not one",
     'printf "MANUAL=CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, False),
    # Self-attack on the quoted-span masker before handing it to reviewers. It is
    # new and subtle, and one bug in it (not consuming a kept span, so the closing
    # quote read as an opening one) already masked across a newline.
    ("apostrophe inside a comment does not desync the scan",
     "# don't do this\n"
     'WIZ="CLAUDE_CODE_SDLC_WIZARD.md"\ngrep -q "%s" "$WIZ"\n' % _FENCE_ONLY, True),
    ("a hash inside ${...} is not a comment",
     'X="${P#pre}" WIZ="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$WIZ"\n' % _FENCE_ONLY, True),
    ("an unterminated quote does not swallow the next line",
     'echo "oops\nWIZ="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$WIZ"\n' % _FENCE_ONLY, True),
    ("single quotes nested inside double quotes",
     'echo "it\'s fine"\nWIZ="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$WIZ"\n' % _FENCE_ONLY, True),
    ("local -r with a flag resolves",
     'local -r MANUAL="$R/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("declare -r with a flag resolves",
     'declare -r MANUAL="$R/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("multi-assignment resolves the RIGHT name, not the first",
     'local OTHER=x MANUAL="$R/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("export/readonly declarations resolve",
     'readonly WIZ="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$WIZ"\n' % _FENCE_ONLY, True),
    ("backslash-continued command",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'if grep -q "other" "$WIZARD" \\\n'
     '   && grep -q "%s" "$WIZARD"; then :; fi\n' % _FENCE_ONLY, True),
    ("grep -qf reported as unverifiable rather than skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -qf "$EXPECT" "$WIZARD"\n', True),
    ("assertion in a heredoc body is machinery, not an assertion",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'awk_prog=$(cat <<\'AWK\'\ngrep -q "%s" "$WIZARD"\nAWK\n)\n' % _FENCE_ONLY, False),
    # Codex round 7: `<<` inside a quoted string, and the left-shift operator.
    # Neither has a terminator, so the old stripper swallowed the whole rest of
    # the file — every assertion after it invisible, with no warning.
    ("a quoted <<EOF is not a heredoc opener",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'printf \'%%s\\n\' \'<<EOF\'\n'
     'grep -q "%s" "$WIZARD"\n' % _FENCE_ONLY, True),
    ("a left shift is not a heredoc opener",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'n=$((x << y))\n'
     'grep -q "%s" "$WIZARD"\n' % _FENCE_ONLY, True),
    # Codex round 7: shell concatenation. A quoted span belongs to an assignment
    # VALUE when it is part of the same word as the `=`, not only when it sits
    # immediately after it.
    ("unquoted prefix before the quoted span resolves",
     'MANUAL=prefix"$ROOT/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("quoted, unquoted, quoted concatenation resolves",
     'MANUAL="$ROOT"/middle"/CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    # ...and the other direction: an escaped quote must not end the argument span
    # and expose the text after it as an assignment.
    ("an escaped quote does not expose a false assignment",
     'printf "x \\" MANUAL=CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, False),
    ("needle that also exists OUTSIDE the copy is legitimate",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "real prose and more text here" "$WIZARD"\n', False),
    # Fable round 2, both reproduced against the HEAD document: the numeric flag
    # argument broke the flag regex, and a piped grep carries no target token.
    # These are the exact shape of the two bogus assertions this PR deletes, so
    # they are the likeliest form for the defect to return in.
    ("grep -A 500 on the doc piped into grep (numeric flag arg + pipe)",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -A 500 "## Full SDLC Checklist" "$WIZARD" | grep -q "%s"\n' % _FENCE_ONLY, True),
    ("sed on the doc piped into grep (no grep target at all)",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'sed -n \'1,100p\' "$WIZARD" | grep -q "%s"\n' % _FENCE_ONLY, True),
    ("piped grep on an UNRELATED file stays clean",
     'WORKFLOW=".github/workflows/pr-review.yml"\n'
     'sed -n \'1,100p\' "$WORKFLOW" | grep -q "%s"\n' % _FENCE_ONLY, False),
    ("assertion about a different file is not ours",
     'WORKFLOW=".github/workflows/pr-review.yml"\n'
     'grep -q "%s" "$WORKFLOW"\n' % _FENCE_ONLY, False),
]


# --- Codex round 8 -------------------------------------------------------
# Heredoc openers are now located on the operand-blanked line, so neither a
# quoted `<<TAG` nor an arithmetic shift is present to match. Terminator
# existence is no longer consulted, which is what made all three of these fail.
_CASES += [
    ("a quoted '<<EOF' does not steal a later real terminator",
     "WIZ=\"$REPO/CLAUDE_CODE_SDLC_WIZARD.md\"\n"
     "printf '%%s\\n' '<<EOF'\n"
     'grep -q "%s" "$WIZ"\n'
     "cat <<EOF\nbody\nEOF\n" % _FENCE_ONLY, True),
    ("an arithmetic shift does not steal a later real terminator",
     "WIZ=\"$REPO/CLAUDE_CODE_SDLC_WIZARD.md\"\n"
     "x=$(( 1 << 4 ))\n"
     'grep -q "%s" "$WIZ"\n'
     "cat <<4\nbody\n4\n" % _FENCE_ONLY, True),
    ("two heredocs on one command consume BOTH bodies",
     "WIZ=\"$REPO/CLAUDE_CODE_SDLC_WIZARD.md\"\n"
     "cat <<A <<B\nalpha\nA\n"
     'grep -q "%s" "$WIZ"\n'
     "B\n" % _FENCE_ONLY, False),
    ("an unterminated heredoc consumes to EOF rather than leaving a false one",
     "WIZ=\"$REPO/CLAUDE_CODE_SDLC_WIZARD.md\"\n"
     "cat <<EOF\n"
     'grep -q "%s" "$WIZ"\n' % _FENCE_ONLY, False),
]

# A value concatenated out of quoted and unquoted pieces is ONE token, and shell
# drops the delimiters. Preserving them kept the document name from ever matching.
_CASES += [
    ("a double-quoted segment inside an unquoted value still resolves",
     'MANUAL=CLAUDE_CODE_"SDLC"_WIZARD.md\n'
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("a single-quoted segment inside an unquoted value still resolves",
     "MANUAL=CLAUDE_CODE_'SDLC'_WIZARD.md\n"
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("a backslash-escaped character in a value still resolves",
     "MANUAL=CLAUDE_CODE_SDLC_WIZARD\\.md\n"
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
]

# POSIX 2.9.1: assignments live in the command PREFIX. Outside it, `NAME=` is an
# ordinary argument, and reading it as an assignment fabricated a variable that
# then falsely condemned a later grep on an unrelated `$MANUAL`.
_CASES += [
    ("a NAME= argument after the command word is NOT an assignment",
     "echo MANUAL=CLAUDE_CODE_SDLC_WIZARD.md\n"
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, False),
    ("an env-style assignment PREFIXING a command still resolves",
     "MANUAL=CLAUDE_CODE_SDLC_WIZARD.md run_it\n"
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
    ("assignment position resumes after a shell keyword",
     "if true; then MANUAL=CLAUDE_CODE_SDLC_WIZARD.md; fi\n"
     'grep -q "%s" "$MANUAL"\n' % _FENCE_ONLY, True),
]


# --- Fable round 8: shapes that were SILENTLY skipped ---------------------
# Each was mechanically resolvable from text the guard already had, so each was a
# miss, not an unknowable. The first is the exact deleted assertion this whole
# guard exists to keep out, which had been invisible to it the entire time.
_CASES += [
    ("a case-insensitive grep is folded, not skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -qi "%s" "$WIZARD"\n' % _FENCE_ONLY.upper(), True),
    ("a BRE regex needle is compiled, not skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "### Release Review Focus.*embedded copy" "$WIZARD"\n', True),
    ("an ERE regex needle is compiled, not skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -qE "Release (Review) Focus.+embedded" "$WIZARD"\n', True),
    # `(` is LITERAL in BRE. Reading it as a group reported a plain literal as
    # unverifiable, which is noise in the channel that must stay trustworthy.
    ("an unbalanced paren in a BRE needle is a literal, not a bad pattern",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "### Release Review Focus (unmatched" "$WIZARD"\n', False),
    # Expectation FLIPPED in round 10, and the old one encoded a bug: without
    # re.M this anchored pattern could never match, so it "passed" by matching
    # nothing at all. Per line it correctly finds the copy-only heading.
    ("a POSIX character class resolves, and anchors per line",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -qE "^#+[[:space:]]+Release Review Focus" "$WIZARD"\n', True),
    # The old floor was 12 characters and did no false-positive work: a short
    # needle that also exists outside a copy is legitimate on the `not in outside`
    # test alone, which is the real discriminator.
    ("a short needle below the old 12-char floor is judged, not skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "r8only" "$WIZARD"\n', True),
    # Command substitution: the corpus's dominant extraction idiom. ASSIGN stops
    # at the first space, so SECTION never resolved and every content check on
    # the extract passed silently.
    ("a variable holding text extracted from the doc is tainted",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'SECTION=$(awk \'/^## /{p=1} p\' "$WIZARD")\n'
     'echo "$SECTION" | grep -q "%s"\n' % _FENCE_ONLY, True),
    ("a variable extracted from an UNRELATED file is not tainted",
     'OTHER="README.md"\n'
     'SECTION=$(awk \'/^## /{p=1} p\' "$OTHER")\n'
     'echo "$SECTION" | grep -q "%s"\n' % _FENCE_ONLY, False),
]


# --- Codex round 10: repairs that had NO fixture protecting them -------------
# Every one of these was verified by an ad-hoc script and then left unguarded, so
# reverting the fix left the selftest green. A repair without a fixture is a
# repair that regresses silently, which is this module's own named enemy.
_CASES += [
    # grep is LINE-oriented. Without re.M, `^`/`$` anchored to the whole document
    # and every anchored needle silently matched nothing.
    ("an anchored needle matches per LINE, not per document",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     "grep -q '^%s$' \"$WIZARD\"\n" % _FENCE_ONLY, True),
    ("an anchored ERE needle with a POSIX class matches per line",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -qE \'^[[:punct:]]{3}[[:space:]]Release Review Focus\' "$WIZARD"\n', True),
    # A heredoc DELIMITER is an arbitrary word; the identifier-only pattern read
    # `END-AWK` as `END`, found no terminator, and exposed the body.
    ("a hyphenated heredoc tag is a real opener",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     "cat <<'END-AWK'\n"
     'grep -q "%s" "$WIZARD"\n'
     "END-AWK\n" % _FENCE_ONLY, False),
    # Genuine interpolation is unknowable content and EARNS the report; a
    # single-quoted `$` is a regex anchor and must not be mistaken for it.
    ("a double-quoted interpolated needle is reported, not skipped",
     'WIZARD="CLAUDE_CODE_SDLC_WIZARD.md"\n'
     'grep -q "$some_area" "$WIZARD"\n', True),
]


def selftest():
    outside = skillcopy.without_copies(_DOC, _SKILL)
    assert _FENCE_ONLY in _DOC and _FENCE_ONLY not in outside, \
        "fixture document is not exercising the detector — the copy was not stripped"
    bad = 0
    for name, src, want in _CASES:
        got = bool(scan_source(src, _DOC, outside, "fixture.sh"))
        print(("PASS: " if got == want else "FAIL: ") + name)
        bad += got != want
    return 1 if bad else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    offenders = run(sys.argv[1] if len(sys.argv) > 1 else ".")
    if offenders:
        print("\n".join(offenders))
        sys.exit(1)
    sys.exit(0)
