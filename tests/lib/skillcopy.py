#!/usr/bin/env python3
"""GH #513 — the wizard doc must not carry a second install path for the skill.

CLAUDE_CODE_SDLC_WIZARD.md carried a 639-line ````markdown fence under "Step 6:
Create SDLC Skill" telling the reader to hand-copy it into
`.claude/skills/sdlc/SKILL.md` — the exact file `npx agentic-sdlc-wizard init`
already writes from `skills/sdlc/SKILL.md`. Two install paths, one file: they
diverged to 56,284 bytes against the live skill's 19,356, moving in opposite
directions inside single PRs (#509 shrank the live skill 856 bytes while growing
the fence 1,470).

WHY THIS IS STRUCTURAL AND NOT A LENGTH THRESHOLD. The first version of this
guard measured the longest four-backtick fence and failed above 100 lines. That
check is wrong in both directions, and a reviewer proved all four cases: a
legitimate unrelated 120-line example fails it, a 99-line second install path
passes it, a 639-line copy in an ordinary ```-fence passes with a measured
length of zero, and a copy split across two 80-line blocks passes. Length is not
the property. The property is "this document IS a copy of the skill", so the
guard asks that directly.

THREE RULES, and they do NOT share a unit of analysis. That split is the whole
design, arrived at only after eight rounds of the alternative.

A. One REGION carrying >= HEADING_HITS of the skill's own headings (frontmatter
   worth one hit). Quoting a section or two stays legal; reproducing does not.
B. One REGION carrying the skill's frontmatter AND >= FRONTMATTER_MIN_LINES.
   Rule A keys on heading TEXT, so renaming every heading evades it while the
   file stays a perfectly usable second install path. Frontmatter plus real file
   size does not care what the headings are called.
C. The RAW DOCUMENT reproducing >= max(SPLIT_BODY_FLOOR, SPLIT_BODY_FRACTION of
   the skill's substantive body lines) of that body prose. Markup-blind: no
   fences, no blocks, no regions.

WHY C IS MARKUP-BLIND AND A/B ARE NOT. C used to be block-scoped, and every
block model it wore was itself an attack surface:

  - A verbatim copy INDENTED FOUR SPACES carries no fence at all. `mdfence` sees
    nothing, `copy_blocks` returned nothing, and the copy is byte-identical,
    copyable from source, and a completely usable install path. The escape
    required no obfuscation whatsoever (Fable round 8).
  - The SAME complete renamed copy measured 105 or 131 reproduced body lines
    purely by the attacker's choice of 3- vs 4-backtick wrapper, because the
    skill contains four of its own ``` fences and a 3-backtick wrapper leaks
    content out of the block model. A detection number that moves with the
    attacker's formatting is a design smell, not a tuning problem.
  - A copy in ONE region with renamed headings and no frontmatter had no rule
    left: A keys on heading text, B on frontmatter, and C required two
    body-contributing BLOCKS (Fable round 8).

Raw text kills all three at once, because the property was never "rendered as a
code block" — it is "present in the file the reader has open". A fence, a
four-space indent and plain prose are equally copyable from source.

A and B cannot follow C global. The live document legitimately carries 3 of the
skill's 23 headings at document level (`## Confidence Check (REQUIRED)`,
`## Task`, `### Memory Audit Protocol`) — exactly HEADING_HITS, so a global rule
A fires on a healthy document. B needs a region to size at all. Both are also
load-bearing and not redundant with C: A is the only rule that catches a DRIFTED
copy (the historical fence shares just 4 body lines with today's skill, far under
any C threshold, but 5 heading markers), and B is the only one that catches a
renamed, paraphrased, still-loadable copy.

So A and B keep regions, and `regions()` takes fenced blocks PLUS any run of
blank-or-indented lines, with no CommonMark list-context analysis. That is
deliberately over-inclusive, and safe only because of this asymmetry:

    DETECTION MAY BE CRUDE AND AGGRESSIVE.
    STRIPPING MUST BE PRECISE AND CONSERVATIVE.

A false region costs a loud CI red that a human adjudicates. The same crudeness
inside `without_copies()` would silently strip real prose and turn the assertions
guard into a false-positive machine, which that guard names as worse than no
guard at all. `mdfence` therefore stays a strict fence grammar and feeds only the
stripping path.

MEASURED, on the real files, 2026-08-08. The skill is 19,356 bytes, 254 lines,
23 headings. Of its substantive body, 71 lines are DISTINCTIVE PROSE — template
shapes are subtracted, because 29 of the rest are TodoWrite entries and more are
table rows, boilerplate any document about this workflow legitimately carries.
C's trigger is a preponderance of that corpus: 35. The live document reproduces
1. A complete copy reproduces essentially all 71 whether it is fenced at three
backticks, four, chopped into fragments, or indented four spaces — that
invariance is what markup-blindness buys. `baseline_drift()` reports at half, so
a closing margin surfaces at 18 rather than at 35.

WHAT THIS GUARD IS FOR, which is the question four rule-C redesigns never asked.
These are LINTS in a first-party repo where every author has commit rights and
can edit the guard itself. No payload analysis was ever a security boundary. The
contract:

    EVERY ARTIFACT PRODUCIBLE BY PLAUSIBLE ACCIDENT MUST FIRE LOUDLY, ON SEVERAL
    RULES AT ONCE. ARTIFACTS REQUIRING MULTIPLE DELIBERATE EVASION STEPS ARE THE
    REVIEW PROCESS'S JOB, NOT THIS FILE'S.

Measured against that bar the suite is complete. The realistic recurrence — a
verbatim copy with frontmatter and headings intact, introduced by an instruction
line — trips A, B, C and destination containment simultaneously. The artifact
that beat A, B and C took four deliberate steps: rename every signature heading,
split the frontmatter below rule B's size test, delete 54 of 71 distinctive prose
lines while keeping every operational one, and write an install instruction that
contradicts the do-not-hand-copy paragraph in the same document. That is not an
accident this lint missed; it is sabotage, and it is still caught — by
destination containment, because it had to name where to put the file.

RULE C IS NOT REDESIGNED AGAIN. Four redesigns each answered the newest
counterexample and lost to the next. The exhaustion argument in
destination_mentions() says a fifth cannot succeed, not merely that four did not:
payload-overlap counterexamples above the accident tier are answered by
destination containment and by review, never by a new constant.

RESIDUAL LIMITS, stated rather than papered over. A guard that claims
completeness it does not have is the same defect class as one that silently
cannot fire, so:

- Destination containment is a SUBSTRING scan, so a COMPOSITIONAL path evades it:
  "copy into `.claude/skills/sdlc/` as `SKILL.md`" names the destination without
  ever spelling it as one string. Adjacent prose can also repurpose an allowlisted
  line into an install instruction. Both are review-tier: they need the already
  four-step A/B/C-evasive payload to matter, and neither is producible by accident.
- The allowlist is keyed on normalised line text, so REFORMATTING an allowlisted
  line fails the build loudly, and a legitimate instruction to repair the installed
  file is flagged. Both resolve by editing the allowlist, where a reviewer sees the
  reason. Failing loudly on a legitimate edit is the correct direction here; failing
  silently on an install instruction is not.
- A partial copy reproducing under HALF the skill's distinctive prose escapes
  rules A, B and C. It does NOT escape destination containment if it tells the
  reader where to install it, which is what makes it an install path at all.
  An earlier version of this note claimed every such artifact was "quotation";
  that was false and a reviewer disproved it with a 200-of-254-line usable skill.
- Rule C is bounded by REWRITING. A copy that paraphrases the skill's prose
  reproduces few exact lines and escapes. That is a genuinely different artifact
  from the accidental divergence this guard exists to catch, and no structural
  check distinguishes a paraphrase from independent writing.
- Rule B fires on ANY region of >= FRONTMATTER_MIN_LINES containing a valid
  `name: sdlc` line, with no corroborating skill content required. A long
  troubleshooting block quoting that one line would be flagged. This is a loud,
  human-adjudicated false positive accepted knowingly in exchange for
  rename-proofness — B is the only rule a renamed copy cannot shed.
- A copy that exists ONLY as an unfenced or indented region is detected by A/B/C
  but never STRIPPED by `without_copies()`, so `fence-only-assertions.py` cannot
  see needles inside it. Accepted: any tree containing such a copy is already a
  failing build here, and the assertions guard is defense-in-depth for the same
  event. It never needs to resolve a state this guard has already rejected.

HISTORY OF RULE C, because the same mistake was made four times in different
clothes and the record is worth more than the current design:
  1. Union of markers across >= 2 blocks reaching 3. Fired on two legitimate
     separated examples.
  2. Union >= 6 across CONSECUTIVE blocks. Bought a FALSE NEGATIVE: the real
     skill split into fragments separated by unrelated example blocks rejoins
     byte-identical and scored ZERO. Adjacency was never the property.
  3. Two arms — breadth (>= 2 markers per block, union 6) or a frontmatter
     anchor (union 3). Wrong at both ends again.
  4. Body-prose reproduction, still scoped to blocks and still requiring two
     contributing blocks. Beat every heading attack, then lost to an indented
     copy, a single-region copy, and its own wrapper-width sensitivity.
  5. Markup-blind body prose over the raw document. Fixed all of the above, then
     a 15% threshold fired on ordinary TodoWrite examples; subtracting the
     boilerplate fixed THAT and opened the reverse hole, because in this skill
     the boilerplate is the operational content, so an artifact can keep all of
     it, drop the prose, and still install.
Repairs 1-4 were each fitted to the last counterexample and each trusted a block
model; dropping the block model ended that series. Repair 5 ended a different
one: the remaining counterexample and a legitimate document differ by about 15
lines OF THE SAME KIND, so no payload rule can separate them at all. That is why
there is no repair 6 — see destination_mentions() for the argument, and note it
is a claim that a fifth constant CANNOT work, not that four happened to fail.

`fence-only-assertions.py` imports `copy_blocks` from here so that both #513
guards agree on what "a copy of the skill" means, rather than each carrying its
own approximation of it.

Usage:
    skillcopy.py <repo-root>   check the real files; exit 1 on offenders
    skillcopy.py --selftest    run the behavioral fixtures
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mdfence import _scan, blocks   # noqa: E402  (path set above)

HEADING_HITS = 3
# The live document's legitimate frontmatter stub is 11 lines and elides its body
# as `...rest of skill...`; a real SKILL.md is 250+. 25 clears both by a wide
# margin, so the bound is not sitting on top of either case.
FRONTMATTER_MIN_LINES = 25
# Rule C keys on BODY REPRODUCTION of the RAW DOCUMENT — see the module docstring
# for why four successive block-scoped designs each failed. The threshold is
# max(SPLIT_BODY_FLOOR, floor(SPLIT_BODY_FRACTION x body lines)); on the current
# 128-line body that is floor(19.2) = 19, i.e. 14.8% and not exactly 15%.
#
# MEASURED 2026-08-08: the live document reproduces 5 body lines against that 19.
# A complete copy reproduces all 128 regardless of how it is wrapped. Body overlap
# was CONSIDERED AND REJECTED in an earlier round on the grounds that the
# historical 639-line fence shares only a handful of lines with the current skill.
# That reasoning conflated two objects: the old fence had DRIFTED over months, and
# rule A catches it anyway on 5 heading markers. What rule C must catch is a NEW
# copy of the CURRENT skill, and such a copy shares body text by construction.
# A PREPONDERANCE of the distinctive corpus, not "significant sharing". 15% was
# never a statement about what a copy IS — it operationalised overlap, and genre
# overlap disproved overlap as a signal. What makes an embedded artifact a second
# INSTALL PATH is that it is most of the skill; anything less is quotation, which
# this guard's own philosophy already calls legal. Pinned by acceptance test and
# measured 2026-08-08, not asserted: live overlap 1 of 71 (2.9% of the trigger of
# 35), while every reproduced attack carries ~100% of the corpus by construction.
SPLIT_BODY_FRACTION = 0.5
SPLIT_BODY_FLOOR = 12
BODY_MIN_LEN = 24


def _norm(line):
    """A line reduced to its token stream: stripped, internal whitespace collapsed.
    Comparing raw stripped lines let a complete copy escape by adding ONE extra
    internal space per line — identical tokens, zero matches (Codex round 7).
    Whitespace is formatting, and reformatting is not the paraphrase bound rule C
    documents as its limit."""
    return re.sub(r"\s+", " ", line.strip())


# Shapes that are TEMPLATE, not prose. Enumerated deliberately rather than
# classified: a "distinctiveness classifier" is another thing to be wrong about.
_TEMPLATE = (
    re.compile(r"^\|"),                       # table rows
    re.compile(r"^\{\s*content:"),            # TodoWrite checklist entries
    re.compile(r"^[A-Za-z_-]+:\s"),           # frontmatter / key: value lines
)


def _is_scaffolding(n):
    """A line that is not distinctive PROSE — table rules and rows, TodoWrite
    template entries, `key: value` lines, pure punctuation.

    This is subtraction, and it is load-bearing rather than cosmetic. Rule C
    assumed the skill's body was prose. Measured, 29 of 128 "body" lines were
    TodoWrite entries and more were table rows — boilerplate that ANY document
    about the same workflow legitimately contains, because they are the same
    genre by design. Codex round 9 turned that into a live false positive:
    adding five ordinary TodoWrite entries to the wizard doc raised overlap from
    5 to 10 and failed the guard, and fourteen reached the trigger and branded
    three unrelated regions a split copy. The headroom was never a property of
    the document; it was a property of the document's current contents, and
    ordinary documentation work moved it.

    Subtracting these leaves 71 lines of actual prose, and live overlap falls
    from 5 to 1 — which is what makes "body prose is what a copy IS" true rather
    than merely stated."""
    if any(p.match(n) for p in _TEMPLATE):
        return True
    return not re.search(r"[A-Za-z]", re.sub(r"[|\-:+=*_~\s]", "", n))


def skill_body(skill_text):
    """The skill's substantive prose lines — long enough to be distinctive, not
    headings (rule A already keys on those), and not structural scaffolding."""
    return {n for n in (_norm(l) for l in skill_text.split("\n"))
            if len(n) >= BODY_MIN_LEN and not n.startswith("#")
            and not _is_scaffolding(n)}


def skill_signature(skill_text):
    heads = {n for n in (_norm(l) for l in skill_text.split("\n"))
             if re.match(r"^#{2,3} \S", n)}
    m = re.search(r"""^name:\s*["\']?([^"\'\s#]+)""", skill_text, re.M)
    return heads, (m.group(1) if m else None)


# YAML quotes the value or not, interchangeably: `name: sdlc`, `name: "sdlc"`,
# `name: \'sdlc\'` all load identically. Matching only the bare form let a
# complete, loadable 30-line skill with renamed headings through rule B
# untouched (Codex round 3).
def _has_frontmatter(body, fm):
    if not fm:
        return False
    # Quotes must BALANCE. Making each side independently optional accepted
    # `name: "sdlc'` and `name: 'sdlc"` as valid skill frontmatter (Codex round 4)
    # — forms YAML rejects, so treating them as a loadable skill is wrong in both
    # directions.
    e = re.escape(fm)
    # A trailing `# comment` is valid YAML: `name: sdlc # canonical` parses to
    # {"name": "sdlc"}. Rejecting it let a complete 254-line copy with renamed
    # headings through rule B untouched (Codex round 5).
    #
    # But `#` only OPENS a comment after whitespace. `name: sdlc#canonical` loads
    # as the value "sdlc#canonical" — a different skill — and accepting it fired
    # rule B on an unrelated 31-line block (Codex rounds 6 and 7).
    pat = re.compile(
        r"""^name:\s*(?:%s|"%s"|'%s')(?:\s+#.*)?\s*$""" % (e, e, e))
    return any(pat.match(_norm(l)) for l in body)


def _block_marks(body, heads, fm):
    marks = sorted({_norm(l) for l in body} & heads)
    if _has_frontmatter(body, fm):
        marks.append(f"frontmatter `name: {fm}`")
    return marks


def regions(doc_text):
    """Candidate copy REGIONS for the per-region rules A and B: every fenced block
    first (same order and indices `blocks()` yields, so `without_copies()` can keep
    using those indices unchanged), then every maximal run of blank-or-indented
    lines outside any fence.

    An indented run is included with no CommonMark list-context analysis at all.
    That is deliberately over-inclusive: nested list continuations get swept in
    alongside genuine indented code blocks. It is safe HERE and only here, because
    regions feed threshold rules whose failure is a loud CI red a human
    adjudicates. The same crudeness inside `without_copies()` would silently strip
    real prose and turn the assertions guard into a false-positive machine, which
    is why `mdfence` stays a strict fence grammar and this lives here instead.

    DETECTION MAY BE CRUDE AND AGGRESSIVE; STRIPPING MUST BE PRECISE AND
    CONSERVATIVE. That asymmetry is the design rule, and it is what ends the
    patch-toward-the-last-counterexample cycle rules A/B/C each went through.
    """
    out = list(blocks(doc_text))
    run = []
    for line, body in _scan(doc_text):
        if body is not None:                 # inside a fence; blocks() has it
            # A fence ENDS the pending run. Without this, three separate indented
            # examples divided by unrelated fenced blocks merged into one region
            # and falsely tripped rule A (Codex round 9).
            if any(l.strip() for l in run):
                out.append(run)
            run = []
            continue
        if not line.strip() or line.startswith("    ") or line.startswith("\t"):
            run.append(line)
            continue
        if any(l.strip() for l in run):
            out.append(run)
        run = []
    if any(l.strip() for l in run):
        out.append(run)
    return out


def copy_blocks(doc_text, skill_text):
    """Every region that reproduces the shipped skill, as
    (1-based region index, region lines, matched markers, rule).

    Rules A and B are per-region. Rule C is evaluated on the RAW DOCUMENT TEXT,
    markup-blind: it asks how much of the skill's body prose the file contains,
    not how that content is packaged. A copy is equally usable fenced, indented
    four spaces, or sitting in plain text, and the reader has the source file
    open either way. Two independent escapes died with that change — a verbatim
    4-space-indented copy, which no fence grammar can see at all, and a
    single-region renamed copy, which no split-copy rule can see.

    The measurement that forced it: block-scoped rule C scored the SAME complete
    renamed copy at 105 or 131 body lines purely by the attacker's choice of
    3- vs 4-backtick wrapper, because the skill contains four of its own ```
    fences and a 3-backtick wrapper leaks content out of the block model. A
    detection number that moves with the attacker's formatting is a design smell,
    not a tuning problem. Raw text is wrapper-blind, chop-blind and indent-blind
    in one move.

    Rule A cannot follow it global: the document legitimately carries three of
    the skill's headings at document level (`## Confidence Check (REQUIRED)`,
    `## Task`, `### Memory Audit Protocol`), which equals HEADING_HITS, so a
    global rule A fires on a healthy document. Rule B needs a region to size at
    all. Both keep regions; only C goes global.
    """
    heads, fm = skill_signature(skill_text)
    body_lines = skill_body(skill_text)
    threshold = max(SPLIT_BODY_FLOOR, int(len(body_lines) * SPLIT_BODY_FRACTION))
    found = []
    regs = regions(doc_text)
    for i, body in enumerate(regs, 1):
        marks = _block_marks(body, heads, fm)
        if len(marks) >= HEADING_HITS:
            found.append((i, body, marks, "A"))
        elif _has_frontmatter(body, fm) and len(body) >= FRONTMATTER_MIN_LINES:
            found.append((i, body, marks, "B"))
    already = {j for j, _, _, _ in found}
    reproduced = {_norm(l) for l in doc_text.split("\n")} & body_lines
    if len(reproduced) >= threshold:
        # Attribution stays region-scoped even though detection is global: a
        # region carrying skill body prose or a skill marker is part of the copy.
        # A global breach with no such region attributes nothing, and strips
        # nothing — see the residual limit in the module docstring.
        for i, body in enumerate(regs, 1):
            if i in already:
                continue
            hit = {_norm(l) for l in body} & body_lines
            if hit or _block_marks(body, heads, fm):
                found.append((i, body, sorted(hit)[:4], "C"))
    return sorted(found)


def without_copies(doc_text, skill_text):
    """The document with skill-copy blocks removed and every other block's body
    kept. Positional, so a line appearing both inside a copy and in real prose
    survives — a line-identity filter would strip both."""
    drop = {i for i, _, _, _ in copy_blocks(doc_text, skill_text)}
    kept, n = [], 0
    for line, body in _scan(doc_text):
        if body is None:
            kept.append(line)
            continue
        n += 1
        if n not in drop:
            kept.extend(body)
    return "\n".join(kept)


def _why(rule, marks):
    if rule == "A":
        return "reproduces %d of the shipped skill's headings" % len(marks)
    if rule == "B":
        return "carries the skill's frontmatter at real-file size (rename-proof rule)"
    # Rule C attributes two kinds of block, and reporting both as body-line counts
    # printed "reproduces 1+ body lines" for a block that reproduced none at all
    # (Codex round 7). `marks` is a truncated SAMPLE for rule C, never a count.
    return ("reproduces shipped skill body prose as part of a split copy" if marks
            else "carries a shipped skill marker inside a split copy")


def baseline_drift(doc_text, skill_text):
    """Rule C fires at the threshold; this reports well BEFORE it, at half.

    A guard whose only signal is its own failure gives no warning that the margin
    is closing. The live document reproduces 1 of the skill's 71 DISTINCTIVE prose
    lines against a trigger of 35 (measured 2026-08-08). If ordinary editing walks
    that toward 35, the first anyone hears of it is a red build. Reporting at half
    means growth surfaces at 18 with real room to respond, and it is a claim about
    THIS repo's documents, so it lives in the live check and not in the fixtures."""
    body_lines = skill_body(skill_text)
    threshold = max(SPLIT_BODY_FLOOR, int(len(body_lines) * SPLIT_BODY_FRACTION))
    n = len({_norm(l) for l in doc_text.split("\n")} & body_lines)
    if n * 2 < threshold:
        return []
    return [f"document reproduces {n} of the skill's {len(body_lines)} body "
            f"lines — past half of rule C's threshold of {threshold}. Not a copy "
            f"yet; the margin is closing. Move the shared prose to one home."]


# The install DESTINATION. Rules A/B/C all analyse the payload — which lines the
# document shares with the skill. This does not: it asks whether the document
# tells a reader WHERE TO PUT one.
INSTALL_DESTINATIONS = (".claude/skills/sdlc/SKILL.md", "skills/sdlc/SKILL.md")

# Sites where naming the destination is legitimate, each with its reason. A line
# not on this list is a finding, resolved in review by removing it or adding it
# here — where a reviewer sees it.
DESTINATION_ALLOWLIST = {
    "Run the installer. It writes `.claude/skills/sdlc/SKILL.md` for you:":
        "tells the reader the CLI writes it — the opposite of a hand-copy instruction",
    "canonical, and `skills/sdlc/SKILL.md` ships in the same npm package as this document,":
        "names the canonical source to explain why hand-copying is wrong",
    "version ships as `skills/sdlc/SKILL.md` — installed by `npx agentic-sdlc-wizard init`,":
        "same, in the update path",
    "See `.claude/skills/sdlc/SKILL.md` for the enforced checklist.":
        "a pointer to the installed file, carrying no content to copy",
    "├── .claude/skills/sdlc/SKILL.md          ✓ frontmatter OK":
        "a line of illustrative CLI output, not an instruction",
}


def destination_mentions(doc_text):
    """Lines naming the skill's install destination outside the allowlist.

    WHY THIS EXISTS, and why it is not a fourth payload rule. Rules A, B and C
    all ask which LINES the document shares with the skill. A reviewer built an
    artifact — valid frontmatter, all 29 TodoWrite entries, all tables, headings
    renamed, split across two blocks, 200 of the skill's 254 lines — that is a
    usable install path and shares almost nothing with rule C's distinctive
    corpus. It differs from a document that legitimately quotes the skill heavily
    by about 15 lines OF THE SAME KIND OF CONTENT.

    That is a proof obligation, and it fails. Any payload rule must put a
    separating surface inside those 15 lines. Every candidate is spent: headings
    lose to renaming, frontmatter-plus-mass to splitting, document overlap needs
    a constant fitted in a 15-line window, region density cannot separate (a
    legitimate 30-line excerpt block is 100% skill lines), and order cannot
    (legitimate template reuse arrives in canonical order). Identity, structure,
    mass, density, locality, order — that is the whole space. So:

        WHEN THE LEGITIMATE DOCUMENT AND THE ATTACK ARTIFACT ARE BUILT FROM THE
        SAME LINES, NO FUNCTION OF LINE-SHARING SEPARATES THEM.

    The separating property is therefore not in the payload. What Codex's
    artifact needs, and what heavy quotation never has, is the sentence "Copy
    these blocks into `.claude/skills/sdlc/SKILL.md`". Documentation quotes the
    skill to explain it; an install path must also say where to put it. The
    destination survives every obfuscation the artifact does — rename it and the
    reader cannot follow the instruction, so it stops being an install path. Same
    primitive-selection principle as GH #527: pick the signal that is invariant
    under every disguise the thing can wear and still work.

    The record supports it: the original #513 defect announced itself as
    "Create `.claude/skills/sdlc/SKILL.md`:". Accidents name their destination
    plainly, because accidents are not hiding.
    """
    out = []
    for i, line in enumerate(doc_text.split("\n"), 1):
        if not any(d in line for d in INSTALL_DESTINATIONS):
            continue
        if _norm(line) in {_norm(k) for k in DESTINATION_ALLOWLIST}:
            continue
        out.append(f"line {i} names the skill's install destination outside the "
                   f"allowlist — if this is not a hand-copy instruction, add it to "
                   f"DESTINATION_ALLOWLIST with its reason: {line.strip()[:90]}")
    return out


def offenders(doc_text, skill_text):
    return [
        f"block {i} ({len(body)} lines) [rule {rule}] " + _why(rule, marks)
        + (f": {', '.join(marks[:4])}" if marks else "")
        for i, body, marks, rule in copy_blocks(doc_text, skill_text)
    ]


BODY = "\n".join("distinctive skill prose line number %02d here" % i
                 for i in range(20))

# The fixture skill needs SUBSTANTIVE body lines (>= BODY_MIN_LEN, not headings),
# because rule C keys on body reproduction. An earlier fixture skill used the
# literal word "body", which is 4 characters — so skill_body() was empty and no
# fixture could exercise rule C at all. A fixture corpus that cannot reach the
# rule it names is the vacuity this whole module exists to prevent.
_PROSE = ["This is a distinctive line of shipped skill prose, number %02d." % i
          for i in range(24)]

SKILL_FIXTURE = "---\nname: sdlc\ndescription: full workflow\n---\n" + "\n".join(
    "%s\n%s" % (h, _PROSE[n])
    for n, h in enumerate([
        "## Full SDLC Checklist", "## Confidence Check (REQUIRED)",
        "## Cross-Model Review (REQUIRED for High-Stakes)",
        "## Scope, DRY, Patterns, Legacy", "## Task", "## Plan Mode",
        "## Prove It Gate (New Additions Only)"])) + "\n" + "\n".join(_PROSE[7:])


def _split_copy(n, rename=False, decoy=False, respace=False):
    """SKILL_FIXTURE chopped into n-line fenced fragments — the shape every
    reviewer used to attack rule C."""
    lines = [l for l in SKILL_FIXTURE.split("\n") if l != "---"]
    if rename:
        lines = [re.sub(r"^(#{1,6})\s+.*", r"\1 Renamed", l) for l in lines]
    if respace:
        # One extra internal space per line. The token stream is untouched, so
        # this is reformatting, not the paraphrase rule C's stated bound allows
        # to escape (Codex round 7).
        lines = [l.replace(" ", "  ", 1) for l in lines]
    out = []
    for i in range(0, len(lines), n):
        out.append("```markdown\n%s\n```\n" % "\n".join(lines[i:i + n]))
        out.append("```bash\necho unrelated\n```\n" if decoy else "prose\n")
    return "".join(out)


def _bodyonly_copy():
    """The fixture skill with its frontmatter removed and every heading renamed:
    no heading text for rule A, no `name:` line for rule B. Only rule C is left,
    so any fixture built on this isolates C — which is the point, since the
    escapes Fable found were precisely copies that had shed A's and B's signals."""
    lines = SKILL_FIXTURE.split("\n")
    if lines and lines[0].strip() == "---":
        lines = lines[lines.index("---", 1) + 1:]
    return "\n".join(re.sub(r"^(#{1,6})\s+.*", r"\1 Step", l) for l in lines)


def selftest():
    copy = "\n".join(l for l in SKILL_FIXTURE.split("\n") if l != "---")
    cases = [
        ("four-backtick copy caught",
         "intro\n````markdown\n" + copy + "\n````\n", True),
        ("triple-backtick copy caught",
         "intro\n```markdown\n" + copy + "\n```\n", True),
        # Codex round 2: the previous version of this fixture was INEFFECTIVE —
        # its first block already reached three markers on its own, so rule A
        # caught it and rule C was never exercised. Fragments must each stay under
        # rule A's heading bar for these to test what they claim to test.
        # Rule C: the skill chopped into fragments. MEASURED, so the comment
        # cannot drift from it: of the 6 regions flagged, the first two fire
        # rule A (3 markers each) and the remaining four fire C. The fixture
        # therefore exercises the MIXED A+C path, which is the one that hid a
        # tail from without_copies() in round 8 — not a pure-C path.
        ("copy split into fragments, caught by rule C", _split_copy(6), True),
        ("copy split with every heading RENAMED still caught by rule C",
         _split_copy(6, rename=True), True),
        ("copy split with fragments separated by unrelated examples",
         _split_copy(6, decoy=True), True),
        # Codex round 7: renamed headings plus ONE extra internal space per line
        # reproduced the token stream exactly and scored 3 body hits, because both
        # sides compared raw stripped lines. Whitespace is formatting.
        ("copy split with headings renamed AND every line re-spaced",
         _split_copy(6, rename=True, respace=True), True),
        # Codex round 2: rule A keys on heading TEXT, so a full copy with every
        # heading renamed sails through it while remaining a usable install path.
        ("full copy with every heading renamed, caught by rule B",
         "```markdown\nname: sdlc\n## Step One\n## Step Two\n## Step Three\n"
         + "prose line\n" * 25 + "```\n", True),
        # Codex round 2 raised "a two-signature-heading copy". Mutation-testing
        # showed rule A already catches it, because the frontmatter line is the
        # third marker — so this fixture documents rule A, not rule B. Labelling
        # it "rule B" would be a test asserting something it does not prove.
        ("real-size copy, frontmatter + two headings, caught by rule A",
         "```markdown\nname: sdlc\n## Full SDLC Checklist\n"
         "## Confidence Check (REQUIRED)\n" + "prose line\n" * 25 + "```\n", True),
        # The live doc carries a legitimate 11-line stub that opens `name: sdlc`
        # and elides the body as `...rest of skill...`. Failing on frontmatter
        # alone would flag it, so frontmatter is one hit, not a verdict.
        # Codex round 3: a complete, loadable 30-line skill using valid quoted
        # YAML and renamed headings returned ZERO offenders — rule B matched only
        # the bare `name: sdlc` line.
        ("quoted YAML frontmatter + renamed headings, caught by rule B",
         '```markdown\nname: "sdlc"\n## Alpha\n## Beta\n'
         + "prose line\n" * 30 + "```\n", True),
        ("single-quoted YAML frontmatter also counts",
         "```markdown\nname: \'sdlc\'\n## Alpha\n"
         + "prose line\n" * 30 + "```\n", True),
        # Codex round 3 REPRODUCED the rule-C false positive: two legitimate,
        # separated examples quoting 2 headings and 1 heading summed to 3.
        ("two separated legitimate examples do NOT trip rule C",
         "```\n## Full SDLC Checklist\n## Confidence Check (REQUIRED)\n```\n"
         + "prose\n" * 40
         + "```\n## Cross-Model Review (REQUIRED for High-Stakes)\n```\n", False),
        # Codex round 4: adjacency was the wrong axis. The real skill split into
        # ordered fragments SEPARATED BY UNRELATED EXAMPLES rejoins byte-identical
        # to the skill, and the consecutive-blocks rule reported zero.
        # Codex round 5, both sides of the old single threshold.
        ("seven independent ONE-heading examples do NOT fire",
         "".join("prose\n```markdown\n%s\n```\n" % h for h in
                 ["## Full SDLC Checklist", "## Confidence Check (REQUIRED)",
                  "## Cross-Model Review (REQUIRED for High-Stakes)",
                  "## Scope, DRY, Patterns, Legacy", "## Task", "## Plan Mode",
                  "## Prove It Gate (New Additions Only)"]), False),
        ("valid YAML inline comment is still frontmatter",
         '```markdown\nname: sdlc # canonical skill name\n## Alpha\n'
         + "prose\n" * 30 + "```\n", True),
        # Codex rounds 6 AND 7: `#` only starts a YAML comment after whitespace, so
        # this line loads as {"name": "sdlc#canonical"} — a different skill. Letting
        # it count as frontmatter fired rule B on an unrelated 31-line block.
        ("name: sdlc#canonical is a different value, not a comment",
         '```markdown\nname: sdlc#canonical\n## Alpha\n'
         + "prose\n" * 30 + "```\n", False),
        # Codex round 4: independently-optional quotes accepted forms YAML rejects.
        ("unbalanced frontmatter quotes are NOT valid frontmatter",
         '```markdown\nname: "sdlc\'\n## Alpha\n' + "prose\n" * 30 + "```\n", False),
        ("frontmatter-only stub passes",
         "```yaml\nname: sdlc\ndescription: x\n...rest of skill...\n```\n", False),
        ("frontmatter plus two headings caught",
         "```yaml\nname: sdlc\n## Full SDLC Checklist\n"
         "## Confidence Check (REQUIRED)\n```\n", True),
        ("legitimate 200-line unrelated example passes",
         "```bash\n" + "echo hi\n" * 200 + "```\n", False),
        ("quoting two skill headings passes",
         "```\n## Full SDLC Checklist\n## Confidence Check (REQUIRED)\n```\n", False),
        # Fable round 8, finding 1. A verbatim copy indented four spaces renders
        # as a code block, is copyable from source, and is a fully usable second
        # install path. It carries NO fence, so no fence grammar can see it — the
        # escape needed zero obfuscation and defeated both #513 guards outright.
        ("a VERBATIM copy indented four spaces is caught",
         "Copy this into `.claude/skills/sdlc/SKILL.md`:\n\n"
         + "\n".join("    " + l for l in SKILL_FIXTURE.split("\n")) + "\n", True),
        ("ordinary indented prose is not a copy",
         "Notes:\n\n" + "\n".join("    a plain indented continuation line %d" % i
                                   for i in range(40)) + "\n", False),
        # Fable round 8, finding 5. Rule A keys on heading TEXT and B on
        # frontmatter, so a single region that renames every heading and drops the
        # frontmatter had no rule left: the old rule C required TWO body-
        # contributing blocks and this is one. Global C has no block count to game.
        ("a single-region copy with every heading renamed is caught",
         "````markdown\n" + _bodyonly_copy() + "\n````\n", True),
        # The same copy chopped into small blocks. A BLOCK-scoped rule C scored
        # the identical copy differently depending on the attacker's wrapper
        # width, because a skill containing its own ``` fences leaks content out
        # of the block model. Global C measures raw text and scores both alike.
        ("the same copy chopped into many small blocks is caught",
         "".join("```markdown\n" + "\n".join(_bodyonly_copy().split("\n")[i:i + 6])
                 + "\n```\n\nprose\n\n"
                 for i in range(0, len(_bodyonly_copy().split("\n")), 6)), True),
        ("the same copy indented four spaces, headings renamed, is caught",
         "\n".join("    " + l for l in _bodyonly_copy().split("\n")) + "\n", True),
        # Codex round 10: regions() must FLUSH a pending indented run when a fence
        # interrupts it. Without the flush these three separated one-heading
        # examples merge into a single four-line region and trip rule A.
        # DISTINCT headings on purpose: _block_marks() is a SET, so three copies
        # of one heading count once and the fixture could never discriminate.
        ("separate indented examples divided by fences do NOT merge",
         "".join("    %s\n\n```bash\necho x\n```\n\n" % h for h in _HEADS3), False),
    ]
    bad = 0
    # Destination containment. The artifact that beat rules A, B and C is caught
    # here, and heavy quotation WITHOUT an install instruction stays legal —
    # which is the whole distinction, since the two share most of their lines.
    _SKILLCOPY = _bodyonly_copy()
    for name, doc, want in [
        ("an install instruction naming the destination is caught",
         "Copy these blocks in order into `.claude/skills/sdlc/SKILL.md`\n\n"
         "````markdown\n" + _SKILLCOPY + "\n````\n", True),
        ("the same blocks WITHOUT an install instruction are not a destination finding",
         "````markdown\n" + _SKILLCOPY + "\n````\n", False),
        ("the historical `Create .claude/skills/sdlc/SKILL.md:` header is caught",
         "Create `.claude/skills/sdlc/SKILL.md`:\n\n```markdown\nname: sdlc\n```\n", True),
        ("the canonical source path is caught when it is a NEW mention",
         "Paste this into `skills/sdlc/SKILL.md` to install it.\n", True),
        ("an allowlisted site is legal",
         "See `.claude/skills/sdlc/SKILL.md` for the enforced checklist.\n", False),
    ]:
        got = bool(destination_mentions(doc))
        print(("PASS: " if got == want else "FAIL: ") + name)
        bad += got != want
    # Template subtraction is a CORPUS decision, not a document one, so it needs
    # direct assertions — reverting it left every document fixture green while
    # the live false positive came straight back (Codex round 10).
    for line, want, why in [
        ("| External APIs | YES | Real calls = flaky + expensive |", True, "table row"),
        ("|--------|--------|--------|", True, "table rule"),
        ('{ content: "Run lint/typecheck", status: "pending" },', True, "TodoWrite entry"),
        ("argument-hint: \"[task description]\"", True, "key: value line"),
        ("This is a distinctive line of shipped skill prose, number 01.", False,
         "actual prose"),
    ]:
        got = _is_scaffolding(_norm(line))
        print(("PASS: " if got == want else "FAIL: ")
              + "%s is %sscaffolding" % (why, "" if want else "NOT "))
        bad += got != want
    for name, doc, want in cases:
        got = bool(offenders(doc, SKILL_FIXTURE))
        print(("PASS: " if got == want else "FAIL: ") + name)
        bad += got != want
    bad += _attribution_cases()
    return 1 if bad else 0


# Codex round 7: a mixed construction where rule A absorbs most of the copy. The
# table above only asks "did anything fire", which cannot see this — rule A fires
# on block 1 either way. What matters is whether block 2 is ATTRIBUTED, because
# without_copies() strips only attributed blocks and an unstripped fragment is
# exactly where a fence-only needle survives.
_HEADS3 = ["## Full SDLC Checklist", "## Confidence Check (REQUIRED)",
           "## Cross-Model Review (REQUIRED for High-Stakes)"]


def _mixed(n_in_first):
    return ("```markdown\n" + "\n".join(_HEADS3 + _PROSE[:n_in_first]) + "\n```\n"
            "prose\n"
            "```markdown\n" + _PROSE[11] + "\n```\n")


def _attribution_cases():
    body = len(skill_body(SKILL_FIXTURE))
    threshold = max(SPLIT_BODY_FLOOR, int(body * SPLIT_BODY_FRACTION))
    assert threshold == 12, "fixture skill no longer sits at the floor: %d" % threshold
    bad = 0
    for name, doc, want in [
        # 11 body lines inside the rule-A block + 1 outside == the threshold.
        ("rule-A block's body lines count toward rule C's threshold",
         _mixed(11), True),
        # 10 + 1 is under it, so block 2 must stay unattributed — proves the
        # threshold is doing the work and attribution is not unconditional.
        ("under the threshold, the trailing fragment is NOT attributed",
         _mixed(10), False),
    ]:
        blocks_found = {i for i, _, _, _ in copy_blocks(doc, SKILL_FIXTURE)}
        assert 1 in blocks_found, "%s: rule A should always catch block 1" % name
        got = 2 in blocks_found
        print(("PASS: " if got == want else "FAIL: ") + name)
        bad += got != want
    return bad


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    doc = open(f"{root}/CLAUDE_CODE_SDLC_WIZARD.md", encoding="utf-8").read()
    skill = open(f"{root}/skills/sdlc/SKILL.md", encoding="utf-8").read()
    found = (offenders(doc, skill) + destination_mentions(doc)
             + baseline_drift(doc, skill))
    if found:
        print("\n".join("    " + f for f in found))
        sys.exit(1)
    sys.exit(0)
