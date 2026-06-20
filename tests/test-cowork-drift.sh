#!/bin/bash
set -e

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Cowork Plugin Drift Tests ==="
echo ""

# Test 1: cowork/ directory exists
echo "--- Structure Tests ---"
if [ -d "$PROJECT_ROOT/cowork" ]; then
  pass "cowork/ directory exists"
else
  fail "cowork/ directory missing"
fi

# Test 2: plugin.json exists and is valid JSON
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/plugin.json" ]; then
  if python3 -c "import json; json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/plugin.json'))" 2>/dev/null; then
    pass "cowork plugin.json is valid JSON"
  else
    fail "cowork plugin.json is not valid JSON"
  fi
else
  fail "cowork/.claude-plugin/plugin.json missing"
fi

# Test 3: plugin.json has required fields
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/plugin.json" ]; then
  name=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/plugin.json')).get('name',''))" 2>/dev/null)
  if [ -n "$name" ]; then
    pass "plugin.json has name field: $name"
  else
    fail "plugin.json missing name field"
  fi
else
  fail "plugin.json not found (skipping field check)"
fi

# Test 4: README.md exists
if [ -f "$PROJECT_ROOT/cowork/README.md" ]; then
  pass "cowork/README.md exists"
else
  fail "cowork/README.md missing"
fi

echo ""
echo "--- Skill Drift Tests ---"

# Test 5: sdlc skill matches canonical
if [ -f "$PROJECT_ROOT/cowork/skills/sdlc/SKILL.md" ] && [ -f "$PROJECT_ROOT/skills/sdlc/SKILL.md" ]; then
  if diff -q "$PROJECT_ROOT/cowork/skills/sdlc/SKILL.md" "$PROJECT_ROOT/skills/sdlc/SKILL.md" >/dev/null 2>&1; then
    pass "cowork sdlc skill matches canonical"
  else
    fail "cowork sdlc skill DRIFTED from canonical (run: cp skills/sdlc/SKILL.md cowork/skills/sdlc/SKILL.md)"
  fi
else
  fail "cowork/skills/sdlc/SKILL.md or canonical skills/sdlc/SKILL.md missing"
fi

# Test 6: feedback skill matches canonical
if [ -f "$PROJECT_ROOT/cowork/skills/feedback/SKILL.md" ] && [ -f "$PROJECT_ROOT/skills/feedback/SKILL.md" ]; then
  if diff -q "$PROJECT_ROOT/cowork/skills/feedback/SKILL.md" "$PROJECT_ROOT/skills/feedback/SKILL.md" >/dev/null 2>&1; then
    pass "cowork feedback skill matches canonical"
  else
    fail "cowork feedback skill DRIFTED from canonical (run: cp skills/feedback/SKILL.md cowork/skills/feedback/SKILL.md)"
  fi
else
  fail "cowork/skills/feedback/SKILL.md or canonical skills/feedback/SKILL.md missing"
fi

echo ""
echo "--- Content Validation Tests ---"

# Test 7: README documents the enforcement gap (no hooks)
if [ -f "$PROJECT_ROOT/cowork/README.md" ]; then
  if grep -qi "hook" "$PROJECT_ROOT/cowork/README.md"; then
    pass "README mentions hooks (enforcement gap documented)"
  else
    fail "README does not mention hooks — must document enforcement gap"
  fi
else
  fail "README missing (skipping content check)"
fi

# Test 8: No hooks directory in cowork (deliberate omission)
if [ ! -d "$PROJECT_ROOT/cowork/hooks" ]; then
  pass "cowork has no hooks/ directory (deliberate — enforcement gap)"
else
  fail "cowork has hooks/ directory — Cowork hook support is unverified, remove"
fi

# Test 9: plugin.json version matches root package.json
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/plugin.json" ] && [ -f "$PROJECT_ROOT/package.json" ]; then
  cowork_ver=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/plugin.json')).get('version',''))" 2>/dev/null)
  root_ver=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/package.json')).get('version',''))" 2>/dev/null)
  if [ "$cowork_ver" = "$root_ver" ]; then
    pass "cowork plugin version ($cowork_ver) matches root package.json ($root_ver)"
  else
    fail "cowork plugin version ($cowork_ver) != root package.json ($root_ver)"
  fi
else
  fail "plugin.json or package.json missing (skipping version check)"
fi

echo ""
echo "--- ROADMAP Tracking Tests ---"

# Test 10: ROADMAP has a Cowork enhancement entry
if grep -q "Cowork plugin enhancement" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null; then
  pass "ROADMAP tracks Cowork plugin enhancement"
else
  fail "ROADMAP missing Cowork plugin enhancement entry"
fi

# Test 11: ROADMAP Cowork entry mentions prompt-based hooks specifically
if grep -A10 "Cowork plugin enhancement" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null | grep -qi "prompt.*hook\|prompt-based"; then
  pass "ROADMAP Cowork entry mentions prompt-based hooks"
else
  fail "ROADMAP Cowork entry does not mention prompt-based hooks — key deliverable missing"
fi

# Test 12: ROADMAP has Dynamic Workflows evaluation entry
if grep -q "Dynamic Workflows" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null; then
  pass "ROADMAP tracks Dynamic Workflows evaluation"
else
  fail "ROADMAP missing Dynamic Workflows evaluation entry"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
