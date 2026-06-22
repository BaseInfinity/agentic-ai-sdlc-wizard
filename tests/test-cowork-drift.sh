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

# Test 7: README documents prompt-based hooks
if [ -f "$PROJECT_ROOT/cowork/README.md" ]; then
  if grep -qi "prompt.*hook\|prompt-based" "$PROJECT_ROOT/cowork/README.md"; then
    pass "README documents prompt-based hooks"
  else
    fail "README does not document prompt-based hooks"
  fi
else
  fail "README missing (skipping content check)"
fi

# Test 8: hooks/hooks.json exists and is valid JSON
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "import json; json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))" 2>/dev/null; then
    pass "cowork hooks/hooks.json exists and is valid JSON"
  else
    fail "cowork hooks/hooks.json is not valid JSON"
  fi
else
  fail "cowork/hooks/hooks.json missing — prompt-based hooks required"
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
echo "--- Hook Quality Tests ---"

# Test 10: hooks.json has correct wrapper structure (events under "hooks" key)
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))
assert 'hooks' in d, 'missing top-level hooks key'
assert isinstance(d['hooks'], dict), 'hooks must be a dict'
" 2>/dev/null; then
    pass "hooks.json has correct wrapper structure (events under 'hooks' key)"
  else
    fail "hooks.json has wrong structure — events must be under 'hooks' key, not at root"
  fi
else
  fail "hooks.json not found (skipping structure check)"
fi

# Test 11: hooks.json has PreToolUse TDD hook
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
ptus=d.get('PreToolUse',[])
assert any('Write' in h.get('matcher','') or 'Edit' in h.get('matcher','') for h in ptus), 'no Write/Edit matcher'
assert any(hk.get('type')=='prompt' for h in ptus for hk in h.get('hooks',[])), 'no prompt type'
" 2>/dev/null; then
    pass "hooks.json has PreToolUse TDD prompt hook for Write/Edit"
  else
    fail "hooks.json missing PreToolUse TDD prompt hook for Write/Edit"
  fi
else
  fail "hooks.json not found (skipping PreToolUse check)"
fi

# Test 12: hooks.json has UserPromptSubmit SDLC baseline hook
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
ups=d.get('UserPromptSubmit',[])
assert len(ups)>0, 'no UserPromptSubmit hooks'
assert any(hk.get('type')=='prompt' for h in ups for hk in h.get('hooks',[])), 'no prompt type'
" 2>/dev/null; then
    pass "hooks.json has UserPromptSubmit SDLC baseline prompt hook"
  else
    fail "hooks.json missing UserPromptSubmit SDLC baseline prompt hook"
  fi
else
  fail "hooks.json not found (skipping UserPromptSubmit check)"
fi

# Test 13: hooks.json has Stop confidence check hook
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
stops=d.get('Stop',[])
assert len(stops)>0, 'no Stop hooks'
assert any(hk.get('type')=='prompt' for h in stops for hk in h.get('hooks',[])), 'no prompt type'
" 2>/dev/null; then
    pass "hooks.json has Stop confidence check prompt hook"
  else
    fail "hooks.json missing Stop confidence check prompt hook"
  fi
else
  fail "hooks.json not found (skipping Stop check)"
fi

# Test 14: All hooks are prompt type (no command type — Cowork has no shell)
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
for event, matchers in d.items():
  for m in matchers:
    for h in m.get('hooks',[]):
      assert h.get('type')=='prompt', f'{event} has non-prompt hook type: {h.get(\"type\")}'
" 2>/dev/null; then
    pass "all cowork hooks are prompt type (no shell dependency)"
  else
    fail "cowork has non-prompt hook types — Cowork has no shell access"
  fi
else
  fail "hooks.json not found (skipping type check)"
fi

echo ""
echo "--- ROADMAP Tracking Tests ---"

# Test 15: ROADMAP has a Cowork enhancement entry
if grep -q "Cowork plugin enhancement" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null; then
  pass "ROADMAP tracks Cowork plugin enhancement"
else
  fail "ROADMAP missing Cowork plugin enhancement entry"
fi

# Test 16: ROADMAP Cowork entry mentions prompt-based hooks specifically
if grep -A10 "Cowork plugin enhancement" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null | grep -qi "prompt.*hook\|prompt-based"; then
  pass "ROADMAP Cowork entry mentions prompt-based hooks"
else
  fail "ROADMAP Cowork entry does not mention prompt-based hooks — key deliverable missing"
fi

# Test 17: ROADMAP has Dynamic Workflows evaluation entry
if grep -q "Dynamic Workflows" "$PROJECT_ROOT/ROADMAP.md" 2>/dev/null; then
  pass "ROADMAP tracks Dynamic Workflows evaluation"
else
  fail "ROADMAP missing Dynamic Workflows evaluation entry"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
