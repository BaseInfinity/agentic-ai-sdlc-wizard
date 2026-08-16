#!/usr/bin/env python3
"""Refuse a review-leg verdict that skipped the questions the reviewer is there
to answer (GH #617).

Usage:  validate-review-verdict.py VERDICT_JSON [SCHEMA_JSON]
Exit:   0 valid, 1 invalid (reason on stderr), 2 usage/IO.

WHAT THIS CHECKS, AND THE LINE IT MUST NOT CROSS
------------------------------------------------
PRESENCE and ENUM MEMBERSHIP. Nothing else. It must never judge whether a tag is
CORRECT: deciding that a finding really is VOLUNTEERED is a reading of the diff
against the issues under review, which is a reviewer's job. Build a semantic
validator here and you rebuild the thing that took PR #598 to 22 rounds chasing
regex over prose. A closed enum cannot chase synonyms; an English-meaning check
can, forever.

WHY IT READS THE SHIPPED SCHEMA RATHER THAN HARD-CODING THE RULES
-----------------------------------------------------------------
`skills/sdlc/review-verdict.schema.json` SHIPS to consumers (skills/ is in
package.json `files`). This launcher-side validator does NOT (scripts/ is
repo-local — GH #594). If the rules were duplicated here, the copy consumers
read and the copy that actually runs would drift, and the shipped one is the one
with no test behind it. So the schema file is the single source and this is a
reader of it.

WHY NOT `jsonschema`
--------------------
The package has zero runtime and dev dependencies and that is a shipped promise.
So this implements the narrow draft-07 subset the schema actually uses —
required, type, enum, minimum/maximum, minLength, and the one if/then — and
refuses anything it does not understand rather than passing it. A validator that
silently ignores a keyword it cannot read is a validator that fails OPEN, which
is the posture that failed twice inside PR #646's own artifact parser.
"""

import json
import os
import sys

_SUPPORTED = {
    "$schema", "title", "description", "type", "required", "properties",
    "additionalProperties", "enum", "items", "allOf", "if", "then", "const",
    "minimum", "maximum", "minLength", "x-cross-field-rules",
}

# THE RULE THE SCHEMA CANNOT CARRY.
#
# The schema file is fed verbatim to `codex exec --output-schema`, and the
# provider REFUSES `allOf`/`if`/`then` with a 400 -- measured, not assumed:
#
#   Invalid schema for response_format 'codex_output_schema':
#   In context=('properties','findings','items'), 'allOf' is not permitted.
#
# So the one cross-field constraint that matters cannot be expressed there and
# is enforced here instead. The schema names it in `x-cross-field-rules` and
# this constant names the schema back, so the two cannot drift apart silently:
# _check_cross_field asserts the declaration is present before enforcing it.
_CROSS_FIELD_ID = "VOLUNTEERED_NOT_REPAIRABLE"

_TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "integer": int,
    "boolean": bool,
}


class Invalid(Exception):
    pass


def _unsupported(schema, where):
    unknown = set(schema) - _SUPPORTED
    if unknown:
        # Fail CLOSED on a keyword this reader does not implement. The schema is
        # ours; if someone adds a keyword, they must teach this reader about it
        # rather than discover months later that it was never enforced.
        raise Invalid("%s: schema uses unsupported keyword(s) %s"
                      % (where, ", ".join(sorted(unknown))))


def _matches(value, schema):
    """Does `value` satisfy `schema`? Used only by `if`, which must not raise."""
    try:
        _check(value, schema, "if")
        return True
    except Invalid:
        return False


def _check(value, schema, where):
    _unsupported(schema, where)

    if "const" in schema and value != schema["const"]:
        raise Invalid("%s: expected %r" % (where, schema["const"]))

    expected = schema.get("type")
    if expected is not None:
        py = _TYPES.get(expected)
        if py is None:
            raise Invalid("%s: schema names unsupported type %r" % (where, expected))
        # bool is a subclass of int in Python; a boolean is not an integer here.
        if expected == "integer" and isinstance(value, bool):
            raise Invalid("%s: expected integer, got boolean" % where)
        if not isinstance(value, py):
            raise Invalid("%s: expected %s, got %s"
                          % (where, expected, type(value).__name__))

    if "enum" in schema and value not in schema["enum"]:
        raise Invalid("%s: %r is not one of %s"
                      % (where, value, ", ".join(map(str, schema["enum"]))))

    if "minLength" in schema and len(value) < schema["minLength"]:
        raise Invalid("%s: is empty" % where)
    if "minimum" in schema and value < schema["minimum"]:
        raise Invalid("%s: below minimum %s" % (where, schema["minimum"]))
    if "maximum" in schema and value > schema["maximum"]:
        raise Invalid("%s: above maximum %s" % (where, schema["maximum"]))

    if isinstance(value, dict):
        for key in schema.get("required", []):
            if key not in value:
                raise Invalid("%s: missing required field %r" % (where, key))
        props = schema.get("properties", {})
        for key, sub in props.items():
            if key in value:
                _check(value[key], sub, "%s.%s" % (where, key))

    if isinstance(value, list) and "items" in schema:
        for i, item in enumerate(value):
            _check(item, schema["items"], "%s[%d]" % (where, i))

    for i, sub in enumerate(schema.get("allOf", [])):
        _unsupported(sub, "%s.allOf[%d]" % (where, i))
        cond = sub.get("if")
        if cond is not None:
            if _matches(value, cond):
                _check(value, sub["then"], where)
        else:
            _check(value, sub, where)


def _check_cross_field(verdict, schema):
    """Enforce VOLUNTEERED_NOT_REPAIRABLE, which the provider will not accept
    inside the schema itself.

    Refuses to run silently if the schema stopped declaring the rule: a
    constraint enforced here but no longer documented in the file consumers read
    is a drift this repo has already paid for twice.
    """
    declared = " ".join(schema.get("x-cross-field-rules", []))
    if _CROSS_FIELD_ID not in declared:
        raise Invalid(
            "schema no longer declares %s in x-cross-field-rules, but the "
            "validator still enforces it — the shipped contract and the check "
            "have drifted" % _CROSS_FIELD_ID)

    for i, finding in enumerate(verdict.get("findings", [])):
        if not isinstance(finding, dict):
            continue
        if (finding.get("target") == "VOLUNTEERED"
                and finding.get("disposition") == "REPAIR"):
            raise Invalid(
                "findings[%d]: VOLUNTEERED code cannot be REPAIRed — it admits "
                "DELETE or FILE only. Repairing code that traces to no issue "
                "under review is what turned round 6 of PR #646 into round 9."
                % i)


def main(argv):
    if len(argv) < 2 or len(argv) > 3:
        sys.stderr.write("usage: %s VERDICT_JSON [SCHEMA_JSON]\n" % argv[0])
        return 2

    verdict_path = argv[1]
    if len(argv) == 3:
        schema_path = argv[2]
    else:
        repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        schema_path = os.path.join(
            repo_root, "skills/sdlc/review-verdict.schema.json")

    try:
        with open(schema_path) as fh:
            schema = json.load(fh)
    except (IOError, OSError, ValueError) as exc:
        sys.stderr.write("cannot read schema %s: %s\n" % (schema_path, exc))
        return 2

    # A leg that produced NO verdict file must fail, not pass. By wall clock a
    # hang is identical to a slow review (#590); by exit status, silence must
    # never read as assent.
    try:
        with open(verdict_path) as fh:
            verdict = json.load(fh)
    except (IOError, OSError) as exc:
        sys.stderr.write("no verdict to validate at %s: %s\n" % (verdict_path, exc))
        return 1
    except ValueError as exc:
        sys.stderr.write("verdict at %s is not valid JSON: %s\n" % (verdict_path, exc))
        return 1

    try:
        _check(verdict, schema, "verdict")
        _check_cross_field(verdict, schema)
    except Invalid as exc:
        sys.stderr.write("INCOMPLETE LEG: %s\n" % exc)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
