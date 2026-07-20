#!/bin/bash
# Quality test: Step 7.8 must catch a Fable-as-driver misconfig, not just a bare pin.
#
# ROADMAP #452: a user picked Fable 5 as their main driver, hit safeguard
# auto-switches mid-session on medical content, and only discovered afterward
# that the wizard's own docs never recommend Fable-as-driver — Setup A/B both
# use Fable only as advisorModel. Before this fix, Step 7.8 only fired when a
# model pin existed with NO advisorModel; a Fable-driver pin that already had
# advisorModel set (e.g. from an earlier /setup run, model changed later via
# /model) sailed through silently. Codex xhigh review round 1 (#452) also
# caught: the original "no pin at all" case guaranteed silence even though
# an unpersisted /model pick (the incident's actual scenario) leaves no pin;
# the advisorModel-only migration case had its "write only advisorModel"
# instruction accidentally deleted during a char-budget trim, risking a
# Claude following the block overwriting an existing driver; and the "less
# quota" claim was unqualified, drifting from AI_SETUP_LANES.md's hedged
# wording. This test locks in all of those, plus the original three findings.

set -e

SKILL="${SKILL:-skills/update/SKILL.md}"
PASSED=0
FAILED=0

pass() { echo "PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$SKILL" ]; then
    echo "FAIL: $SKILL not found"
    exit 1
fi

# Extract the Step 7.8 block only — every assertion below must scope to this
# block, not the whole skill, so a mention elsewhere (e.g. AI_SETUP_LANES.md
# cross-references, unrelated advisorModel prose) can't produce a false GREEN.
step_block=$(awk '
  /^### Step 7\.8:/ { flag=1; next }
  /^### Step [0-9]/ && flag { flag=0 }
  flag { print }
' "$SKILL")

if [ -z "$step_block" ]; then
    echo "FAIL: Step 7.8 block not found in $SKILL"
    exit 1
fi

# Extract ONLY the case-1 (Fable-driver) line — scoping test 1 to just this
# line, not the whole block, so removing the trigger spelling from case 1
# can't hide behind an unrelated "fable" mention elsewhere (e.g. case 2's
# `advisorModel: "fable"` suggestion). This is the exact vacuous-test bug
# Codex round 1 caught in the prior version of this test.
case1_line=$(echo "$step_block" | grep -iE '^1\. \*\*Live driver is Fable')

# ---------------------------------------------------------------------------
# Test 1: case 1's trigger names both driver-pin spellings for Fable —
# scoped to case 1's own line, not the whole Step 7.8 block.
# ---------------------------------------------------------------------------
if [ -n "$case1_line" ] && echo "$case1_line" | grep -qF '"fable"' && echo "$case1_line" | grep -qF '"claude-fable-5"'; then
    pass "Step 7.8 case 1 names both 'fable' and 'claude-fable-5' driver-pin spellings"
else
    fail "Step 7.8 case 1 doesn't name both Fable driver-pin spellings"
fi

# ---------------------------------------------------------------------------
# Test 2: the Fable-driver check fires even when advisorModel is already
# set — the exact gap that let the incident's config through silently.
# ---------------------------------------------------------------------------
if [ -n "$case1_line" ] && echo "$case1_line" | grep -qiE '(driver|main model).*fable' && echo "$step_block" | grep -qiE '(even if|even with).*advisorModel.*already set'; then
    pass "Step 7.8 fires on Fable-as-driver even when advisorModel is already set"
else
    fail "Step 7.8 doesn't override the advisorModel-already-set skip for a Fable driver pin"
fi

# ---------------------------------------------------------------------------
# Test 3: the step doesn't just say "reconsider" — it names the actual
# failure mode (safeguard auto-switches on medical/legal/bio content).
# ---------------------------------------------------------------------------
if echo "$step_block" | grep -qiE 'safeguard' && echo "$step_block" | grep -qiE 'auto-switch'; then
    pass "Step 7.8 warns about safeguard auto-switches specifically"
else
    fail "Step 7.8 doesn't mention safeguard auto-switches (the actual incident failure mode)"
fi

# ---------------------------------------------------------------------------
# Test 4: the existing (unrelated to Fable) pin-without-advisorModel case is
# still present — this change must not have deleted the original trigger.
# ---------------------------------------------------------------------------
if echo "$step_block" | grep -qiF 'no `advisorModel`'; then
    pass "Step 7.8 still covers the original pin-without-advisorModel case"
else
    fail "Step 7.8 lost its original pin-without-advisorModel trigger"
fi

# ---------------------------------------------------------------------------
# Test 5 (#452 round 1 finding 2): the advisorModel-only migration case must
# explicitly write ONLY advisorModel — not silently reuse case 1's full
# driver-overwriting write instruction, which would let a Claude following
# this block clobber an existing Opus/opusplan driver pin.
# ---------------------------------------------------------------------------
if echo "$step_block" | grep -qiE 'writes \*\*only\*\* `advisorModel`'; then
    pass "Step 7.8's advisorModel-only case writes only advisorModel, preserving the existing driver"
else
    fail "Step 7.8's advisorModel-only case doesn't scope its write to advisorModel alone"
fi

# ---------------------------------------------------------------------------
# Test 6 (#452 round 1 finding 1): case 1 must also catch an UNPINNED live
# Fable driver (a /model pick that was never saved to settings.json) by
# checking the session's own self-reported model identity, not only the
# settings.json pin — otherwise the incident's actual scenario (no pin at
# all) sails through silently.
# ---------------------------------------------------------------------------
if echo "$step_block" | grep -qiE 'unpinned' && echo "$step_block" | grep -qiE 'self-reported model'; then
    pass "Step 7.8 case 1 also checks the live self-reported model identity, not just the pin"
else
    fail "Step 7.8 doesn't check the live model identity for an unpinned Fable driver"
fi

# ---------------------------------------------------------------------------
# Test 7 (#452 round 1 finding 4): the Setup A quota claim must be hedged
# ("generally lower ... narrow[s]") to match AI_SETUP_LANES.md, not an
# unqualified "less quota" claim.
# ---------------------------------------------------------------------------
if echo "$step_block" | grep -qiE 'generally lower quota' && echo "$step_block" | grep -qiE 'narrow'; then
    pass "Step 7.8's Setup A quota claim is hedged, matching AI_SETUP_LANES.md"
else
    fail "Step 7.8's Setup A quota claim is unqualified, drifting from AI_SETUP_LANES.md"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
