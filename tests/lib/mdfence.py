#!/usr/bin/env python3
"""Markdown fence parsing shared by the GH #513 guards.

Both guards need the same question answered — "is this line inside a fenced
block?" — and they got it wrong in the same way for the same reason: they
special-cased ```` because that was the fence the #513 defect happened to use.
`fence-only-assertions.py` matched only lines starting with four backticks,
which made it silently vacuous the moment those fences were deleted (`outside`
became byte-identical to the document, so its `needle not in outside` test could
never be true). Fence type is incidental; being fenced is the property.

A fence opens on a run of >= 3 backticks or tildes and closes on a run of the
SAME character at least as long, CARRYING NO INFO STRING. That asymmetry is
what lets a ````-block legally contain ```-blocks, and it is why a parser that
just toggles a boolean on every fence line mis-tracks nested examples.

The info-string half is not decoration. Codex round 2 found this parser treating
an inner ````markdown line as a close: the block ended early, the text after it
was published as prose, and the scan desynced so badly that trailing prose was
reported as a block body. Both #513 guards sit on top of this function, so that
one omission could defeat both. `misnumbered_ordered_items` in
tests/test-doc-consistency.sh already carried the rule ("A CLOSING fence carries
no info string") — this file diverged from a solved problem instead of matching
it, which is the DRY failure underneath the bug.

Indentation follows the same source: CommonMark allows 0-3 leading spaces before
a fence; 4 makes it an indented code block, not a fence.

    blocks(text)   -> list of block bodies, each a list of lines
    outside(text)  -> the document with every fenced block removed
    rendered(text) -> the document reduced to text a reader actually SEES

`rendered` exists because #520's canonical-sentence pins were matching raw
bytes, and raw bytes are not guidance. Cross-model review defeated the pins
three times without altering one character of the pinned claims: it wrapped
them in an HTML comment, in `<del>`, and in a fence. Each time the constant was
still there at column 1 and the suite stayed green while the document told the
reader nothing.

Enumerating containers is unbounded — comment, fence, `<del>`, whatever is next.
Projecting once is not: strip everything a Markdown reader does not see, then
let the pins run against what is left. That collapses the whole class into a
single function, which is also the only thing that then needs testing.

Lines are emitted VERBATIM, never reflowed — the pins anchor to column 1 and a
projection that re-wraps would break them.
"""
import re

FENCE = re.compile(r"^( {0,3})(`{3,}|~{3,})(.*)$")
# Every opener/closer a reader does not see, in ONE alternation so the scanner
# walks them in document order. Line-oriented because the claims being guarded
# are whole lines; a partial-line strip would invite the same
# substring-is-not-an-assertion mistake that anchoring just fixed.
# `<del/>` is not a void element, so a renderer treats it as an opener, and a
# closer may carry whitespace before the `>`. Both forms were missed: one
# published struck text, the other suppressed innocent guidance.
TOKEN = re.compile(r"<!--|-->|<del(?:[ \t][^>]*)?/?>|</del[ \t]*>", re.I)
DEL_AT_START = re.compile(r"<del(?:[ \t][^>]*)?/?>", re.I)
# `</del >` is valid; `</ del >` is not — the raw-HTML grammar requires `</`
# immediately followed by the tag name. The wider `</\s*del\s*>` was my own
# overcorrection when `</del >` was added, and it accepted a closer a browser
# ignores, publishing text that is still struck.
DEL_CLOSE = re.compile(r"^</del[ \t]*>$", re.I)
# HTML containers, like fences, only count at 0-3 spaces of indent. Four makes
# an indented code block, where `<!--` is visible text. `lstrip()` accepted any
# indent and swallowed the guidance after a four-space-indented comment.
BLOCK_INDENT = re.compile(r"^ {0,3}(?=\S)")


def _closes(info):
    """True when a fence delimiter's trailing text permits it to CLOSE.

    CommonMark: a closing fence "may be followed only by spaces or tabs".
    `.strip()` accepted every Unicode space, so a closer ending in a
    no-break space published text that is still fenced. Tabs stay allowed —
    that is the spec, and the fixture asserting it guards the overcorrection.
    """
    return info.strip(" \t") == ""


def _fence_open(line):
    """(fence_char, run_length) if `line` OPENS a fence, else None.

    A backtick fence's info string may not itself contain a backtick —
    CommonMark's rule, and without it a line like ``` ```lang`x` ``` reads as an
    unterminated fence and hides the rest of the document. Tilde fences have no
    such restriction.
    """
    m = FENCE.match(line)
    if not m:
        return None
    if m.group(2)[0] == "`" and "`" in m.group(3):
        return None
    return m.group(2)[0], len(m.group(2))


def _scan(text):
    """Yield (line, body_lines_or_None). body is None for lines outside any
    fence and for the fence delimiters themselves."""
    open_fence, body = None, []
    for line in text.split("\n"):
        m = FENCE.match(line)
        if open_fence is None:
            opened = _fence_open(line)
            if opened:
                open_fence = opened
                body = []
            else:
                yield line, None
            continue
        if (m and m.group(2)[0] == open_fence[0]
                and len(m.group(2)) >= open_fence[1]
                and _closes(m.group(3))):           # a close carries no info string
            yield None, body
            open_fence, body = None, []
            continue
        body.append(line)
    if open_fence is not None:      # unterminated fence — still a fenced region
        yield None, body


def blocks(text):
    """Every fenced block's body, in document order."""
    return [b for line, b in _scan(text) if b is not None]


def outside(text):
    """The document with every fenced block (and its delimiters) removed."""
    return "\n".join(line for line, b in _scan(text) if b is None)


def _walk(line, stack):
    """Advance the open-container stack across one line.

    A STACK, not a mode plus a counter. `<del>` nests, and an HTML comment
    nests inside it — inside a comment, `</del>` is text. Tracking only a mode
    let `<!-- </del> -->` close the strike element from inside a comment and
    publish still-struck text, and let `<!-- <del> -->` open one that never
    closed and hid valid guidance.

    Every token on the line is walked, always: `--> <!--` closes and reopens,
    and stopping at the first closer published the claim underneath.
    """
    stack = list(stack)
    for m in TOKEN.finditer(line):
        tok = m.group(0).lower()
        top = stack[-1] if stack else None
        if top == "comment":
            if tok == "-->":
                stack.pop()
            continue                       # inside a comment nothing else is markup
        if tok == "<!--":
            stack.append("comment")
        elif DEL_CLOSE.match(tok):
            if top == "del":
                stack.pop()
        elif tok.startswith("<del"):
            stack.append("del")
    return stack


def _strip_hidden(text, keep_fenced):
    """Drop every line a reader does not see.

    ONE interleaved scanner, not a fence pass followed by a comment pass. The
    two-pass version opened a fence on the ``` inside `<!--\n```\n-->`, never
    saw the comment closer, and swallowed the visible section after it.
    CommonMark has no such ordering: fenced code and HTML blocks are both leaf
    blocks and whichever OPENS FIRST owns the text until it closes.

    THE MODEL IS BLOCK-LEVEL HTML, and that is the whole design. A container
    opens only when a line BEGINS with its opener. Three separate findings
    came from modelling inline HTML instead:

      * a backticked `<del>` mentioned in prose opened del state;
      * so the fix tracked code spans — and an unmatched backtick run then
        established permanent code-span state, blinding the scanner to a real
        `<!--` after it;
      * and an opener anywhere on a line hid the whole line, so appending a
        harmless `<!-- note -->` to a correct sentence deleted it.

    All three are the same mistake. A line beginning with `<!--` shows the
    reader nothing; a line that MENTIONS `<!--` shows the reader everything
    before it. Anchoring the rule to column 1 removes the need to know whether
    a mid-line `<` is markup or prose — which is the question that cannot be
    answered without a full inline parser, and the one every version of this
    scanner got wrong.

    DECLARED BOUND: a mid-line opener with no closer on its line does not hide
    what follows. Modelling that requires code-span tracking, and code-span
    tracking is what produced two of the three findings above. Within the
    threat model here — drift and careless edits, not malice — an unclosed
    mid-line `<!--` is a visibly broken document, not a silent one.

    `keep_fenced` decides what happens to a fence that is itself visible:
    False gives prose only (a claim that exists only inside a fence is a
    quotation, per #513), True keeps it (a formula block is an illustration a
    reader can see). Neither keeps a fence sitting inside a comment.

    Unterminated openers keep swallowing on purpose: that fails CLOSED.
    """
    out = []
    stack = []         # open HTML containers, innermost last
    mode = None        # None | "comment" | "del" | "fence"
    fence = None       # (char, run_length) while mode == "fence"
    for line in text.split("\n"):
        if mode == "fence":
            m = FENCE.match(line)
            closing = (m and m.group(2)[0] == fence[0]
                       and len(m.group(2)) >= fence[1]
                       and _closes(m.group(3)))
            if keep_fenced:
                out.append(line)
            if closing:
                mode, fence = None, None
            continue
        if mode in ("comment", "del"):
            stack = _walk(line, stack)
            mode = stack[-1] if stack else None
            continue
        opened = _fence_open(line)
        if opened:
            mode, fence = "fence", opened
            if keep_fenced:
                out.append(line)
            continue
        indent = BLOCK_INDENT.match(line)
        stripped = line.lstrip() if indent else ""
        low = stripped.lower()
        if low.startswith("<!--") or DEL_AT_START.match(stripped):
            opener = "comment" if low.startswith("<!--") else "del"
            # Skip PAST the opener before walking the rest of the line —
            # rescanning it counted the opening `<del>` a second time and left
            # the element permanently open.
            rest = (stripped[4:] if opener == "comment"
                    else stripped[DEL_AT_START.match(stripped).end():])
            stack = _walk(rest, [opener])
            mode = stack[-1] if stack else None
            continue                      # the line itself shows nothing
        out.append(line)
    return "\n".join(out)


def rendered(text):
    """Prose a reader sees: fenced blocks removed, hidden regions removed.

    This is what the #520 canonical-sentence pins match against. #513 settled
    that fenced content in this repo is a quotation rather than an instruction,
    so a CLAIM that exists only inside a fence is not guidance.
    """
    return _strip_hidden(text, keep_fenced=False)


def visible(text):
    """Everything a reader sees, fenced illustrations included.

    For content that is legitimately fenced — a formula block, a settings
    example — where the question is only "can a reader see this at all". Raw
    matching cannot answer that: cross-model review wrapped the #520 formula
    fence in an HTML comment and all 129 assertions stayed green.
    """
    return _strip_hidden(text, keep_fenced=True)


# --- selftest -------------------------------------------------------------
# Run directly: python3 tests/lib/mdfence.py
# Each fixture is a bug that actually shipped or was caught in review, not a
# hypothetical. Fixture names cite where they came from.
_FIXTURES = [
    # Codex round 2, P1. An inner fence with an info string is CONTENT.
    ("info-string line cannot close",
     "before\n````markdown\ninner1\n````markdown\ninner2\n````\nafter\n",
     [["inner1", "````markdown", "inner2"]], ["before", "after"]),
    # The asymmetry that makes a ````-block able to hold ```-blocks.
    ("shorter run cannot close a longer fence",
     "````\na\n```\nb\n````\nc\n", [["a", "```", "b"]], ["c"]),
    # A ~~~ inside a ``` fence is content; a blind toggle swallows the document.
    ("other fence char is content",
     "```\na\n~~~\nb\n```\nc\n", [["a", "~~~", "b"]], ["c"]),
    # 4 spaces is an indented code block, not a fence.
    ("indent > 3 is not a fence", "before\n    ```\nplain\n", [], ["plain"]),
    ("indent <= 3 is a fence", "before\n   ```\nx\n   ```\nafter\n",
     [["x"]], ["before", "after"]),
    # An unterminated fence must not publish the tail as prose.
    # Guarding the info-string fix against OVERCORRECTION: a close whose only
    # trailing content is whitespace is still a close. Tightening "no info
    # string" into "nothing at all after the run" would silently stop closing
    # real fences, which is the same class of failure in the other direction.
    ("trailing whitespace still closes", "a\n```\nx\n```   \nb\n", [["x"]], ["b"]),
    ("trailing tab still closes", "a\n```\nx\n```\t\nb\n", [["x"]], ["b"]),
    ("a 0-3 space indented close works", "a\n```\nx\n   ```\nb\n", [["x"]], ["b"]),
    # An unterminated fence must not publish the tail as prose. The trailing ""
    # is the final newline's empty split element, not a parser artifact.
    ("unterminated fence swallows the tail",
     "before\n```\ntail\n", [["tail", ""]], ["before"]),
]

# Each of these is an attack that passed 129/129 against the raw-bytes pins.
# (claim, document, must the claim survive the projection?)
_RENDERED_FIXTURES = [
    ("plain prose is visible", "1. **The claim.**\n", True),
    ("html comment hides the claim",
     "<!--\n1. **The claim.**\n-->\n", False),
    ("one-line html comment hides the claim",
     "<!-- 1. **The claim.** -->\n", False),
    ("del element hides the claim",
     "<del>\n1. **The claim.**\n</del>\n", False),
    ("one-line del hides the claim",
     "<del>1. **The claim.**</del>\n", False),
    ("fenced block hides the claim",
     "```\n1. **The claim.**\n```\n", False),
    # Fails CLOSED, not open: an opener with no closer keeps swallowing.
    ("unterminated comment keeps swallowing",
     "<!--\nnoise\n1. **The claim.**\n", False),
    # ...and the projection must not eat the document. A claim AFTER a properly
    # closed comment is still guidance.
    ("claim after a closed comment survives",
     "<!-- note -->\n1. **The claim.**\n", True),
    ("claim after a closed del survives",
     "<del>old</del>\n1. **The claim.**\n", True),
    # Two openers on one line: the first closes, the second does not. Testing
    # "does the line contain a closer" reports this as closed and publishes
    # everything after it. Found by mutation against the shipped skill.
    ("second opener on a closed line still swallows",
     "<!-- hidden --><!--\n1. **The claim.**\n", False),
    # ...and the symmetric overcorrection: two complete comments on one line
    # must NOT leave the scanner stuck open.
    ("two complete comments on one line close cleanly",
     "<!-- a --><!-- b -->\n1. **The claim.**\n", True),
    # Cross-model review, round 6. A line that MENTIONS markup is text a reader
    # sees; scanning it as markup swallowed the claim under it.
    ("inline-code <del> is text, not an opener",
     "A literal `<del>` tag\n1. **The claim.**\n", True),
    ("inline-code comment opener is text, not an opener",
     "Write `<!--` to hide a line\n1. **The claim.**\n", True),
    # THE DECLARED BOUND, pinned so it is a decision rather than an accident:
    # a mid-line opener does not hide what follows. Modelling that needs
    # code-span tracking, and code-span tracking is what produced two separate
    # findings (a backticked <del> opening del state; an unmatched backtick run
    # blinding the scanner permanently).
    ("a mid-line opener does not hide the next line (declared bound)",
     "Use `x` here <!--\n1. **The claim.**\n", True),
    # Cross-model review, round 8. A harmless trailing comment on a correct
    # sentence must not delete it — the opener-anywhere rule did exactly that.
    ("a trailing comment does not delete the sentence it follows",
     "1. **The claim.** <!-- threshold note -->\n", True),
    # Round 8: closing and reopening on one line. Stopping at the first closer
    # published the hidden claim underneath.
    ("close-then-reopen on one line keeps hiding",
     "<!--\n--> <!--\n1. **The claim.**\n-->\n", False),
    # Round 8: an unmatched backtick run is literal text and must not blind the
    # scanner to a real opener after it.
    ("an unmatched backtick run does not blind the scanner",
     "A stray ` tick\n<!--\n1. **The claim.**\n-->\n", False),
    # Cross-model review, round 9. `<del>` nests. Ignoring the inner opener let
    # its closer end the OUTER element and publish still-struck text.
    ("nested del keeps hiding until the outer closer",
     "<del>\n<del>x</del>\n1. **The claim.**\n</del>\n", False),
    ("nested del on one line still closes cleanly",
     "<del><del>x</del></del>\n1. **The claim.**\n", True),
    # Round 9: 4 spaces makes an indented code block, where `<!--` is visible
    # text — the same 0-3 rule fences already follow. lstrip() accepted any
    # indent and swallowed the guidance after it.
    ("a 4-space indented comment opener is visible text",
     "    <!--\n1. **The claim.**\n", True),
    ("a 3-space indented comment opener still opens",
     "   <!--\n1. **The claim.**\n", False),
    # Round 9: a backtick fence's info string may not contain a backtick.
    # Treating it as a fence read the rest of the document as fence body.
    ("backtick in a backtick info string is not a fence",
     "```lang`x`\n1. **The claim.**\n", True),
    ("a tilde info string may contain backticks",
     "~~~lang`x`\nhidden\n~~~\n1. **The claim.**\n", True),
    # Cross-model review, round 10. Inside a comment, `</del>` is text — it
    # must not close the strike element wrapping it.
    ("a commented-out del closer does not end the strike",
     "<del>\n<!-- </del> -->\n1. **The claim.**\n</del>\n", False),
    # ...and the mirror: a commented-out OPENER must not leave an element open
    # that then hides valid guidance.
    ("a commented-out del opener does not open one",
     "<del>\n<!-- <del> -->\n</del>\n1. **The claim.**\n", True),
    # Round 10: `<del/>` is not a void element; a renderer treats it as an
    # opener. Missing it published struck guidance.
    ("<del/> opens the strike element",
     "<del/>\n1. **The claim.**\n</del>\n", False),
    # Round 10: a closer may carry whitespace before the `>`. Missing it left
    # the element open and suppressed innocent guidance after it.
    ("</del > closes the strike element",
     "<del>\nx\n</del >\n1. **The claim.**\n", True),
    # ...and the overcorrection that shipped alongside it: `</ del >` is NOT a
    # closer (raw-HTML grammar requires `</` then the tag name), so the strike
    # element is still open and the claim is still hidden.
    ("</ del > does not close the strike element",
     "<del>\nx\n</ del >\n1. **The claim.**\n", False),
    # Python's \s matches U+00A0; the raw-HTML grammar permits only ASCII
    # space, tab and line endings. An NBSP is indistinguishable on screen and
    # one Option-Space away on macOS, so both directions are real drift: a
    # non-closer read as a closer publishes struck text, and a non-opener read
    # as an opener hides text the reader can plainly see.
    ("</del\u00a0> does not close the strike element",
     "<del>\nx\n</del\u00a0>\n1. **The claim.**\n", False),
    ("<del\u00a0> is not a strike element and hides nothing",
     "<del\u00a0>\n1. **The claim.**\n", True),
    # DECLARED BOUND, pinned so a future change has to disagree deliberately.
    # A column-1 opener inside a MULTI-LINE code span is treated as markup.
    # Detecting it needs code-span tracking, which produced two separate
    # findings before it was deliberately deleted (a backticked <del> opening
    # del state; an unmatched backtick run blinding the scanner permanently).
    # The scanner models BLOCK structure only; inline constructs are out of
    # scope by design, and this fires on zero lines of the real corpus.
    ("a column-1 opener inside a multi-line code span still opens (declared bound)",
     "A literal `code\n<del>\nstill code`\n1. **The claim.**\n", False),
    # Round 10: a fence closer may be followed only by spaces or tabs. A
    # no-break space is not whitespace for this rule, so the fence stays open.
    ("a no-break space after a closer does not close it",
     "```\n1. **The claim.**\n```\u00a0\n", False),
    # A fence body is a quotation: markup inside it is content.
    ("comment opener inside a fence is content",
     "```\n<!--\n```\n1. **The claim.**\n", True),
    # Cross-model review, round 7. Backticks INSIDE a comment are comment
    # content, not a fence. Parsing fences in a pass before comments opened a
    # fence here, never saw the closer, and swallowed the visible claim.
    ("backticks inside a comment are not a fence",
     "<!--\n```\n-->\n1. **The claim.**\n", True),
    # ...and round 7 again: a code span may cross lines. Line-local stripping
    # read this `<del>` as markup and hid the claim — a false positive, which
    # breaks the document for an innocent edit.
    ("a code span may cross lines",
     "A literal `code\nand <del>` span\n1. **The claim.**\n", True),
    ("an unclosed code span does not hide the document",
     "Trailing `tick\n1. **The claim.**\n", True),
]

# `visible` keeps fenced illustrations but must still drop hidden ones.
# (claim, document, must the claim survive visible()?)
_VISIBLE_FIXTURES = [
    ("a plain fence is visible", "```\n1. **The claim.**\n```\n", True),
    # Cross-model review, round 6: this is what raw matching accepted.
    ("a commented-out fence is not visible",
     "<!--\n```\n1. **The claim.**\n```\n-->\n", False),
    ("a struck fence is not visible",
     "<del>\n```\n1. **The claim.**\n```\n</del>\n", False),
    ("prose is visible too", "1. **The claim.**\n", True),
]

if __name__ == "__main__":
    import sys
    # `--rendered FILE` is the projection the #520 pins match against. Separate
    # from the selftest so the shell side stays a single pipe with no parsing.
    if len(sys.argv) == 3 and sys.argv[1] in ("--rendered", "--visible"):
        # `--rendered FILE | awk '...{exit}'` is the intended call shape, and
        # awk exiting at the end of a section closes the pipe mid-write. Python
        # turns that into a BrokenPipeError traceback on stderr; the suite has
        # no `pipefail` so it passed while printing noise that reads as a real
        # error. SIG_DFL makes the write die silently, as any other CLI does.
        import signal
        signal.signal(signal.SIGPIPE, signal.SIG_DFL)
        with open(sys.argv[2], encoding="utf-8") as fh:
            body = fh.read()
        sys.stdout.write(rendered(body) if sys.argv[1] == "--rendered"
                         else visible(body))
        sys.exit(0)
    failed = 0
    for label, fixtures, fn in (("rendered", _RENDERED_FIXTURES, rendered),
                                ("visible", _VISIBLE_FIXTURES, visible)):
        for name, doc, want in fixtures:
            lines = fn(doc).split("\n")
            got = any(line.startswith("1. **The claim.**") for line in lines)
            if got != want:
                print("FAIL %s %s: claim visible=%r want %r in %r"
                      % (label, name, got, want, lines))
                failed += 1
            else:
                print("ok   %s: %s" % (label, name))
    for name, doc, want_blocks, must_be_outside in _FIXTURES:
        got = blocks(doc)
        out = outside(doc)
        if got != want_blocks:
            print("FAIL %s: blocks %r != %r" % (name, got, want_blocks)); failed += 1
        elif any(t not in out.split("\n") for t in must_be_outside):
            print("FAIL %s: %r missing from outside %r" % (name, must_be_outside, out)); failed += 1
        else:
            print("ok   %s" % name)
    sys.exit(1 if failed else 0)
