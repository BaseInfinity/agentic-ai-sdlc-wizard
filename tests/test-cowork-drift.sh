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

# Test 4b (#455): cowork/.claude-plugin/marketplace.json exists and is valid JSON.
# This is NOT the primary GitHub install path (that's the root marketplace.json's
# git-subdir entry, tested below) — Anthropic's docs confirm a GitHub web-UI
# `/tree/branch/subdir` URL was never a supported marketplace source at all (only
# owner/repo shorthand, full git URLs, local paths, or direct marketplace.json URLs
# are). This self-contained manifest supports the documented local-path fallback
# (`/plugin marketplace add ./cowork` after cloning) so it still needs to exist.
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json" ]; then
  if python3 -c "import json; json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json'))" 2>/dev/null; then
    pass "cowork marketplace.json exists and is valid JSON"
  else
    fail "cowork marketplace.json is not valid JSON"
  fi
else
  fail "cowork/.claude-plugin/marketplace.json missing (breaks local-path marketplace add)"
fi

# Test 4c (#455): marketplace.json's plugin entry sources itself ("." relative to
# cowork/.claude-plugin/), not the repo root — this is a self-contained marketplace
# scoped to the cowork subtree, distinct from the root marketplace.json.
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json" ]; then
  source_val=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json'))
plugins = d.get('plugins', [])
print(plugins[0].get('source', '') if plugins else '')
" 2>/dev/null)
  if [ "$source_val" = "." ]; then
    pass "cowork marketplace.json plugin entry sources itself (\".\")"
  else
    fail "cowork marketplace.json plugin entry source is '$source_val', expected '.'"
  fi
else
  fail "marketplace.json missing (skipping source check)"
fi

# Test 4d (#455): marketplace.json's registered plugin name/version match plugin.json —
# prevents the marketplace listing and the actual installable plugin from drifting apart.
if [ -f "$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json" ] && [ -f "$PROJECT_ROOT/cowork/.claude-plugin/plugin.json" ]; then
  mp_name=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json'))
plugins = d.get('plugins', [])
print(plugins[0].get('name', '') if plugins else '')
" 2>/dev/null)
  mp_ver=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/marketplace.json'))
plugins = d.get('plugins', [])
print(plugins[0].get('version', '') if plugins else '')
" 2>/dev/null)
  plugin_name=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/plugin.json')).get('name',''))" 2>/dev/null)
  plugin_ver=$(python3 -c "import json; print(json.load(open('$PROJECT_ROOT/cowork/.claude-plugin/plugin.json')).get('version',''))" 2>/dev/null)
  if [ "$mp_name" = "$plugin_name" ] && [ "$mp_ver" = "$plugin_ver" ]; then
    pass "marketplace.json entry matches plugin.json (name=$mp_name, version=$mp_ver)"
  else
    fail "marketplace.json entry (name=$mp_name, version=$mp_ver) drifted from plugin.json (name=$plugin_name, version=$plugin_ver)"
  fi
else
  fail "marketplace.json or plugin.json missing (skipping parity check)"
fi

# Test 4e (#455, corrected root cause): the ROOT marketplace.json must register
# sdlc-wizard-cowork via a git-subdir source pointing at path "cowork" — this is
# the actual documented GitHub install path per Anthropic's plugin-marketplaces
# schema (git-subdir source type, used for a plugin nested in a subdirectory of a
# repo). A GitHub web-UI subtree URL alone was never a valid marketplace source.
if [ -f "$PROJECT_ROOT/.claude-plugin/marketplace.json" ]; then
  cowork_entry=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/.claude-plugin/marketplace.json'))
for p in d.get('plugins', []):
    if p.get('name') == 'sdlc-wizard-cowork':
        src = p.get('source', {})
        print(f\"{src.get('source','')}|{src.get('path','')}\")
        break
" 2>/dev/null)
  if [ "$cowork_entry" = "git-subdir|cowork" ]; then
    pass "root marketplace.json registers sdlc-wizard-cowork via git-subdir source, path=cowork"
  else
    fail "root marketplace.json's sdlc-wizard-cowork entry is missing or misconfigured (got: '$cowork_entry', expected 'git-subdir|cowork')"
  fi
else
  fail "root .claude-plugin/marketplace.json missing (skipping git-subdir entry check)"
fi

# Test 4f (#455 live diagnostic, 2026-07-21): the root marketplace.json's
# "sdlc-wizard" entry must NOT use a bare string source ("."). Live Cowork
# server logs (claude.ai-web.log) returned, verbatim:
#   "sdlc-wizard: External plugin sources must be objects with a 'source' field"
# — Cowork's remote validator rejects bare-string sources outright for external
# (non-local) marketplace resolution, even though "." validates fine for local/
# CLI use. This is a real, server-confirmed defect, not an inferred one.
if [ -f "$PROJECT_ROOT/.claude-plugin/marketplace.json" ]; then
  sdlc_wizard_source_info=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/.claude-plugin/marketplace.json'))
for p in d.get('plugins', []):
    if p.get('name') == 'sdlc-wizard':
        src = p.get('source')
        if isinstance(src, dict):
            print(f\"{src.get('source','')}|{src.get('repo','')}\")
        else:
            print(f'notdict|{src}')
        break
" 2>/dev/null)
  if [ "$sdlc_wizard_source_info" = "github|BaseInfinity/claude-sdlc-wizard" ]; then
    pass "root marketplace.json's sdlc-wizard entry uses {source: github, repo: BaseInfinity/claude-sdlc-wizard}"
  else
    fail "root marketplace.json's sdlc-wizard entry is misconfigured (got: '$sdlc_wizard_source_info', expected 'github|BaseInfinity/claude-sdlc-wizard') — Cowork's remote validator rejects bare-string sources"
  fi
else
  fail "root .claude-plugin/marketplace.json missing (skipping source-type check)"
fi

# Test 4g (#455 live diagnostic, 2026-07-21): the git-subdir entry's "url" field
# must be a full https:// URL, not owner/repo shorthand. Live Cowork server logs
# returned, verbatim:
#   "sdlc-wizard-cowork: Git source URL must use https://, got: BaseInfinity/claude-sdlc-wizard"
# Anthropic's general plugin-marketplaces docs show shorthand as valid for
# git-subdir's url field, but Cowork's remote/account-scoped backend enforces a
# stricter requirement than the documented baseline — confirmed via live error
# text, not inferred from docs alone.
if [ -f "$PROJECT_ROOT/.claude-plugin/marketplace.json" ]; then
  cowork_url=$(python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/.claude-plugin/marketplace.json'))
for p in d.get('plugins', []):
    if p.get('name') == 'sdlc-wizard-cowork':
        print(p.get('source', {}).get('url', ''))
        break
" 2>/dev/null)
  if [ "$cowork_url" = "https://github.com/BaseInfinity/claude-sdlc-wizard.git" ]; then
    pass "sdlc-wizard-cowork's git-subdir url is the exact expected full https:// URL"
  else
    fail "sdlc-wizard-cowork's git-subdir url ('$cowork_url') doesn't match the expected 'https://github.com/BaseInfinity/claude-sdlc-wizard.git' — Cowork's remote validator rejects owner/repo shorthand"
  fi
else
  fail "root .claude-plugin/marketplace.json missing (skipping url-format check)"
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

# Test 7b (#455): README must document the real install flow (marketplace add +
# plugin install by name), not the broken bare subtree URL that caused #455 —
# regression guard so the docs can't silently revert to the invalid format.
if [ -f "$PROJECT_ROOT/cowork/README.md" ]; then
  if grep -qF "/plugin marketplace add" "$PROJECT_ROOT/cowork/README.md" && \
     grep -qF "sdlc-wizard-cowork@" "$PROJECT_ROOT/cowork/README.md"; then
    pass "README documents the real marketplace-add + plugin-install flow"
  else
    fail "README doesn't document '/plugin marketplace add' + 'sdlc-wizard-cowork@<marketplace>' install commands"
  fi
else
  fail "README missing (skipping install-flow check)"
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

# Test 14b (#456): every prompt hook should explicitly reference $ARGUMENTS.
# Per Anthropic's documented prompt-hook contract (code.claude.com/docs/en/hooks,
# verified against the raw docs, not a summarized fetch — an earlier round of
# this fix mis-cited this contract from a hallucinated WebFetch summary and was
# corrected by Codex xhigh review), the hook input JSON is auto-appended to the
# prompt even if $ARGUMENTS is omitted — so omitting it does NOT make the
# evaluator blind. Referencing it explicitly is still best practice (it lets you
# control where the context appears relative to your instructions, matching
# Anthropic's own official examples), so this stays a requirement, just not for
# the "otherwise blind" reason originally claimed here.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
missing = []
for event, matchers in d.items():
    for m in matchers:
        for h in m.get('hooks', []):
            if h.get('type') == 'prompt' and '\$ARGUMENTS' not in h.get('prompt', ''):
                missing.append(event)
assert not missing, f'missing \$ARGUMENTS in: {missing}'
" 2>/dev/null; then
    pass "every prompt hook explicitly references \$ARGUMENTS (best practice, though input JSON auto-appends if omitted)"
  else
    fail "at least one prompt hook doesn't explicitly reference \$ARGUMENTS (not blind — auto-appended — but still worse practice)"
  fi
else
  fail "hooks.json not found (skipping \$ARGUMENTS check)"
fi

# Test 14c (#456, corrected — the original version of this test asserted
# numbered checklists are always wrong, which Codex xhigh review disproved:
# Anthropic's own official Stop-hook example at code.claude.com/docs/en/hooks
# uses a numbered multi-condition list feeding one decision. The REAL defect
# in the original hooks.json wasn't the numbered format — it was never telling
# the evaluator the required response schema at all). Every prompt hook must
# explicitly instruct the evaluator to respond with the real schema
# ({"ok": true} / {"ok": false, "reason": ...}), matching Anthropic's own
# examples — not the "yes"/"no" schema this fix originally (incorrectly)
# assumed, which was itself corrected after Codex disputed it with a citation.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
missing = []
for event, matchers in d.items():
    for m in matchers:
        for h in m.get('hooks', []):
            if h.get('type') != 'prompt':
                continue
            prompt = h.get('prompt', '')
            if '\"ok\": true' not in prompt or '\"ok\": false' not in prompt:
                missing.append(event)
assert not missing, f'missing explicit ok/false response schema in: {missing}'
" 2>/dev/null; then
    pass "every prompt hook explicitly instructs the real {ok: true/false} response schema"
  else
    fail "at least one prompt hook doesn't explicitly instruct the {\"ok\": true/false} response format"
  fi
else
  fail "hooks.json not found (skipping response-schema check)"
fi

# Test 14d (#456 Codex round-1 finding 2): PreToolUse's test-file heuristic must
# guard against the substring false-positive Codex demonstrated ("contest.py",
# "specification_parser.ts" both contain "test"/"spec" as substrings but are NOT
# test files) — checked by requiring the prompt spell out that guard explicitly.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
prompt = next((hk.get('prompt','') for m in d.get('PreToolUse',[]) for hk in m.get('hooks',[]) if hk.get('type')=='prompt'), '')
assert 'contest.py' in prompt or 'substring' in prompt.lower(), 'no substring-false-positive guard found'
" 2>/dev/null; then
    pass "PreToolUse prompt guards against the substring false-positive (contest.py etc.)"
  else
    fail "PreToolUse prompt doesn't guard against 'test'/'spec' substring false positives"
  fi
else
  fail "hooks.json not found (skipping substring-guard check)"
fi

# Test 14e (#456 Codex round-1 finding 3): UserPromptSubmit must NOT deny plain
# code requests just for lacking a user-authored plan — a block on this event
# ends the turn with no retry, so denying ordinary prompts (e.g. "write a
# function to sort a list", the exact prompt from the #432 E2E test) would be
# actively disruptive. It must instead only deny prompts that explicitly try to
# bypass safeguards.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
prompt = next((hk.get('prompt','') for m in d.get('UserPromptSubmit',[]) for hk in m.get('hooks',[]) if hk.get('type')=='prompt'), '')
assert 'skip' in prompt.lower() or 'bypass' in prompt.lower(), 'no explicit-bypass framing found'
assert 'already state a plan' not in prompt.lower(), 'still requires the USER to pre-state a plan (denies ordinary requests)'
" 2>/dev/null; then
    pass "UserPromptSubmit denies only explicit bypass requests, not ordinary code prompts"
  else
    fail "UserPromptSubmit still denies ordinary code prompts for lacking a user-stated plan, or lost the bypass framing"
  fi
else
  fail "hooks.json not found (skipping UserPromptSubmit scope check)"
fi

# Test 14f (#456 Codex round-1 finding 4): Stop must require tests to actually
# PASS, not merely run — Codex demonstrated "HIGH confidence; pytest ran with 3
# failures" satisfied the prior (broken) criteria. Must also restore the
# self-review requirement the README promises but the prior rewrite dropped.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d = json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
prompt = next((hk.get('prompt','') for m in d.get('Stop',[]) for hk in m.get('hooks',[]) if hk.get('type')=='prompt'), '')
p = prompt.lower()
# CONTRACT CHANGED 2026-07-27 (issue #477). This previously asserted that the
# judge REQUIRE a passing suite and narrated self-review. Both were removed
# deliberately, not weakened by accident:
#   - The judge sees response text, not tool calls. It cannot verify a test
#     OUTCOME, only whether prose claims one. Demanding a green suite made the
#     hook unusable in any repo with known pre-existing failures — it blocked a
#     consumer 9 consecutive times until the harness force-broke the loop, on a
#     turn whose only action was a read-only git-status check.
#   - The wizard installs everywhere, so a gate that assumes a green suite
#     assumes something most real repos cannot provide.
# The judge now blocks on ONE thing it can actually see: code changed with no
# verification attempted at all. These assertions pin the replacement contract
# so it cannot be silently re-tightened or further loosened.
assert 'no attempt to test it' in p, 'lost the single blocking condition (unverified work)'
assert 'failing tests are information' in p, 'test OUTCOMES are being judged again — unverifiable'
assert 'stop_hook_active' in p, 'repeat-suppression missing — the hook can loop forever'
assert 'this turn only' in p, 'turn scoping missing — prior work re-triggers the block'
assert 'when uncertain' in p, 'no fail-open rule — the judge will block on ambiguity'
" 2>/dev/null; then
    pass "Stop blocks only on unverified work, fails open, and cannot loop"
  else
    fail "Stop hook contract broken: see the comment above for what each assertion pins"
  fi
else
  fail "hooks.json not found (skipping Stop pass/self-review check)"
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
