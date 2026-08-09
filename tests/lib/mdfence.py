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
TOKEN = re.compile(r"<!--|-->|<del(?:\s[^>]*)?>|</del>", re.I)


def _scan(text):
    """Yield (line, body_lines_or_None). body is None for lines outside any
    fence and for the fence delimiters themselves."""
    open_fence, body = None, []
    for line in text.split("\n"):
        m = FENCE.match(line)
        if open_fence is None:
            if m:
                open_fence = (m.group(2)[0], len(m.group(2)))
                body = []
            else:
                yield line, None
            continue
        if (m and m.group(2)[0] == open_fence[0]
                and len(m.group(2)) >= open_fence[1]
                and not m.group(3).strip()):        # a close carries no info string
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


def rendered(text):
    """The document reduced to lines a reader actually sees.

    Fenced blocks are already gone via `outside`. On top of that, drop every
    line touched by an HTML comment or a `<del>` element, including the lines
    that open and close them — a claim sharing a line with `<!--` is commented
    out from that point on, and treating the opening line as visible would
    reopen the hole on a one-line comment.

    Unterminated openers swallow the rest of the document on purpose. That
    matches how a Markdown renderer behaves and, more importantly, fails
    CLOSED: a guard that sees nothing fails loudly, while one that guesses the
    comment ended is back to trusting bytes.
    """
    out, state = [], None          # state: None | "comment" | "del"
    for line in outside(text).split("\n"):
        # Visible only if the line began outside every container AND opens
        # none. A line that opens one is not a place a load-bearing claim may
        # live, even where a renderer would show the text before the opener —
        # the claims guarded here are whole lines.
        #
        # Walk EVERY token on the line rather than testing "does it contain an
        # opener / a closer". The first version tested containment and reported
        # `<!-- x --><!--` as closed, because it found a `-->` after the first
        # opener and stopped looking. Mutation caught it: that exact line hid
        # the shipped skill's guidance with the suite green.
        visible = state is None
        for m in TOKEN.finditer(line):
            tok = m.group(0).lower()
            if state is None:
                if tok == "<!--":
                    state, visible = "comment", False
                elif tok.startswith("<del"):
                    state, visible = "del", False
            elif state == "comment" and tok == "-->":
                state = None
            elif state == "del" and tok == "</del>":
                state = None
        if visible:
            out.append(line)
    return "\n".join(out)


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
]

if __name__ == "__main__":
    import sys
    # `--rendered FILE` is the projection the #520 pins match against. Separate
    # from the selftest so the shell side stays a single pipe with no parsing.
    if len(sys.argv) == 3 and sys.argv[1] == "--rendered":
        with open(sys.argv[2], encoding="utf-8") as fh:
            sys.stdout.write(rendered(fh.read()))
        sys.exit(0)
    failed = 0
    for name, doc, want in _RENDERED_FIXTURES:
        lines = rendered(doc).split("\n")
        got = any(line.startswith("1. **The claim.**") for line in lines)
        if got != want:
            print("FAIL %s: claim visible=%r want %r in %r" % (name, got, want, lines))
            failed += 1
        else:
            print("ok   rendered: %s" % name)
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
