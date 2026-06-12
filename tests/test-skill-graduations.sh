#!/bin/bash
set -e

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL="$PROJECT_ROOT/skills/sdlc/SKILL.md"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Skill Graduation Tests ==="
echo ""

# --- Confidence Ramp Pattern ---
echo "--- Confidence Ramp Pattern ---"

# Test 1: SKILL.md mentions the confidence ramp workflow
if grep -qi "confidence ramp" "$SKILL"; then
  pass "SKILL.md documents confidence ramp pattern"
else
  fail "SKILL.md missing confidence ramp pattern"
fi

# Test 2: Mentions Fable batch review as part of the ramp
if grep -q "batch.*review\|batch.*consult" "$SKILL"; then
  pass "confidence ramp includes batch review step"
else
  fail "confidence ramp missing batch review step"
fi

# Test 3: Confidence ramp line includes /goal and Codex check
if grep -qi "confidence ramp" "$SKILL" | head -1 && grep -i "confidence ramp" "$SKILL" | grep -q "/goal" && grep -i "confidence ramp" "$SKILL" | grep -q "Codex"; then
  pass "confidence ramp includes /goal + Codex check"
else
  fail "confidence ramp missing /goal or Codex check on the ramp line"
fi

echo ""
echo "--- Advisor Auto-Fallback ---"

# Test 4: SKILL.md documents advisor fallback
if grep -qi "advisor.*if down\|advisor.*fallback\|advisor.*unavailable\|fallback.*advisor" "$SKILL"; then
  pass "SKILL.md documents advisor fallback"
else
  fail "SKILL.md missing advisor fallback"
fi

# Test 5: Fallback spawns Fable subagent
if grep -q "Fable.*subagent\|subagent.*Fable\|spawn.*Fable\|Fable.*fallback" "$SKILL"; then
  pass "advisor fallback uses Fable subagent"
else
  fail "advisor fallback missing Fable subagent instruction"
fi

echo ""
echo "--- Budget Check ---"

# Test 6: SKILL.md stays under 20K chars
chars=$(wc -c < "$SKILL")
if [ "$chars" -le 20000 ]; then
  pass "SKILL.md is under 20K chars ($chars)"
else
  fail "SKILL.md exceeds 20K chars ($chars)"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
