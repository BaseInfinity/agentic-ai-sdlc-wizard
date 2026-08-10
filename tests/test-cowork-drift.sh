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
  if [ "$sdlc_wizard_source_info" = "github|BaseInfinity/claude-sdlc-harness" ]; then
    pass "root marketplace.json's sdlc-wizard entry uses {source: github, repo: BaseInfinity/claude-sdlc-harness}"
  else
    fail "root marketplace.json's sdlc-wizard entry is misconfigured (got: '$sdlc_wizard_source_info', expected 'github|BaseInfinity/claude-sdlc-harness') — Cowork's remote validator rejects bare-string sources"
  fi
else
  fail "root .claude-plugin/marketplace.json missing (skipping source-type check)"
fi

# Test 4g (#455 live diagnostic, 2026-07-21): the git-subdir entry's "url" field
# must be a full https:// URL, not owner/repo shorthand. Live Cowork server logs
# returned, verbatim:
#   "sdlc-wizard-cowork: Git source URL must use https://, got: BaseInfinity/claude-sdlc-harness"
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
  if [ "$cowork_url" = "https://github.com/BaseInfinity/claude-sdlc-harness.git" ]; then
    pass "sdlc-wizard-cowork's git-subdir url is the exact expected full https:// URL"
  else
    fail "sdlc-wizard-cowork's git-subdir url ('$cowork_url') doesn't match the expected 'https://github.com/BaseInfinity/claude-sdlc-harness.git' — Cowork's remote validator rejects owner/repo shorthand"
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

# Test 5b: this repo's own dogfooded skill matches canonical (GH #513)
#
# `.claude/skills/sdlc` is a TRACKED SYMLINK (mode 120000 -> ../../skills/sdlc),
# so this diffs the canonical file against itself and cannot fail on a normal
# checkout. That is not a defect and not a vacuous test: it is a regression guard
# for someone replacing the symlink with a real, driftable copy — exactly the
# second-source problem #513 is about. Stated plainly because a test whose
# comment oversells what it detects is the defect class this suite polices
# (Fable round 6).
#
# cowork/ was byte-checked and .claude/ was not, so .claude/skills/sdlc/SKILL.md
# could drift from the file consumers actually receive while every suite stayed
# green — and this repo dogfoods that copy, so drift there means we run a
# different skill than we ship. #513 removed a second install path in the wizard
# doc for exactly this destination; this closes the same gap on disk.
if [ -f "$PROJECT_ROOT/.claude/skills/sdlc/SKILL.md" ] && [ -f "$PROJECT_ROOT/skills/sdlc/SKILL.md" ]; then
  if diff -q "$PROJECT_ROOT/.claude/skills/sdlc/SKILL.md" "$PROJECT_ROOT/skills/sdlc/SKILL.md" >/dev/null 2>&1; then
    pass "repo-local .claude sdlc skill matches canonical"
  else
    fail "repo-local .claude/skills/sdlc/SKILL.md DRIFTED from canonical (run: cp skills/sdlc/SKILL.md .claude/skills/sdlc/SKILL.md)"
  fi
else
  fail ".claude/skills/sdlc/SKILL.md or canonical skills/sdlc/SKILL.md missing"
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

# Test 12: hooks.json has NO UserPromptSubmit hook
# GH #561: the UserPromptSubmit prompt classifier was REMOVED. It denied the
# maintainer TWICE, and the second denial came after a repair:
#   2026-08-07 — denied "do the prose rename now, dont TDD something like this,
#     it will most likely only ever happen once so just verify after". That is a
#     stated reason plus a stated alternative: a safeguard being SUBSTITUTED,
#     not removed. A justified-exception carve-out was shipped in response, and
#     old Test 18 pinned its text.
#   2026-08-10 — denied an instruction to CODIFY a policy change, classifying a
#     description of policy as an attempt to evade policy.
# The first repair was textually pinned by a passing test and still failed
# operationally. That is what makes deletion the answer rather than a third
# narrowing: no prompt wording guarantees an LLM classification outcome, and
# the hook is unfalsifiable from inside — reporting the false positive requires
# a prompt it may block. Same class as the #484 Stop hook (Test 13). Blocking
# hooks fire on ACTS (PreToolUse), never on turn-level subject matter.
# Honest cost: in Cowork, "skip planning/review" followed by edits to
# EXISTING files now hits no gate at all — PreToolUse fails open for edits
# and the CLI's commit/merge gates cannot run there. Guidance, not gates.
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
assert 'UserPromptSubmit' not in d, 'UserPromptSubmit key is back'
" 2>/dev/null; then
    pass "hooks.json has NO UserPromptSubmit hook (GH #561 — it blocked the maintainer's own policy instruction)"
  else
    fail "a UserPromptSubmit hook returned to cowork/hooks.json — GH #561 removed it; turn-level subject-matter classification is not a gate"
  fi
else
  fail "hooks.json not found (skipping UserPromptSubmit check)"
fi

# Test 13: hooks.json has Stop confidence check hook
# GH #484: the Stop prompt hook was REMOVED, so this now asserts its ABSENCE.
# It fired 12 times in one session and was wrong 11 of them — blocking turns
# that changed no files, turns already verified, and five times quoting its own
# in-flight exemption before overriding it. A Stop hook fires at the end of
# EVERY turn, which is why hooks/codex-review-stop-check.sh's header says one
# "must never prevent the user from getting their response."
if [ -f "$PROJECT_ROOT/cowork/hooks/hooks.json" ]; then
  if python3 -c "
import json
d=json.load(open('$PROJECT_ROOT/cowork/hooks/hooks.json'))['hooks']
assert 'Stop' not in d, 'Stop key is back'
" 2>/dev/null; then
    pass "hooks.json has NO Stop hook (GH #484 — a blocking Stop hook fires every turn)"
  else
    fail "a Stop hook returned to cowork/hooks.json — GH #484 removed it after 11 false positives in 12 firings"
  fi
else
  fail "hooks.json not found"
fi

# Test 13b (#561): NO `hooks` declaration in any tracked shipped file except
# cowork/hooks/hooks.json.
#
# Tests 12 and 13 assert two events are absent from ONE file. That proves
# nothing if a hook can be declared elsewhere — and it can. Three successive
# enumerations of "where hooks can be registered" were each declared complete
# and each disproven within a round:
#   1. hooks/hooks.json only          -> broken by an inline `hooks` in plugin.json
#   2. + plugin.json                  -> a marketplace ENTRY's `hooks` takes precedence
#   3. + both marketplace manifests   -> broken by a hook in SKILL.md YAML frontmatter
# Every miss was found by reading Anthropic's docs, not ours, because each
# attempt quantified over ANTHROPIC'S set of registration mechanisms — an open
# set they own and extend. A fourth hand-enumeration is the same method.
#
# So this quantifies over a set THIS REPO owns instead: a hook must be declared
# in bytes the plugin ships, and `git ls-files` closes that set. A new shipped
# file is scanned automatically rather than silently missed.
#
# FAIL-CLOSED is the load-bearing clause. A tracked file whose format has no
# parser here FAILS. Without it the format list is just a hand-enumeration one
# level down, with the same silent-green shape, and round 5 finds it.
#
# tests/test-stop-hook-terminates.sh learned this same lesson over four rounds
# (see its header); this reuses that traversal deliberately.
#
# NOT covered, and this is a real future-release boundary rather than an excuse:
# a mechanism using a key NOT named `hooks` inside a format already scanned.
# Undocumented today, and NOTHING mechanical here covers it. Division of labor,
# stated honestly: this walk = every documented surface in the source tree, fail
# closed, every push. Release-time `claude plugin details` = manifest-registered
# hooks in the INSTALLED artifact only — empirically blind to frontmatter hooks
# (2026-08-10: an active frontmatter UserPromptSubmit hook did not appear in its
# inventory), so it is not an oracle. The interactive `/hooks` command DOES see
# frontmatter hooks, but it is session-bound and cannot gate anything.
# Undocumented mechanisms: cross-model review, which found surfaces 2, 3 and 4
# when every mechanical check missed them.
# Wrapped in a function so the heredoc stays at statement level: it cannot live
# inside a command substitution, and a temp file would make the test fail in
# environments where TMPDIR is not writable.
_cowork_hooks_scan() {
python3 - "$PROJECT_ROOT" <<'PYEOF'
import json, os, re, subprocess, sys
try:
    import yaml
except ImportError:
    print("python3 yaml module missing - it is a stated test dependency", file=sys.stderr)
    sys.exit(1)

ROOT = sys.argv[1]
EXEMPT = "cowork/hooks/hooks.json"
FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.S)

# -z / NUL split, NOT .split(): a tracked filename containing whitespace would
# otherwise be shredded into nonexistent paths, both skipped, silent green. The
# round-4 review proved it with `cowork/skills/extra skill/SKILL.md`.
tracked = [f for f in subprocess.check_output(
    ["git", "-C", ROOT, "ls-files", "-z", "--", "cowork/"]).decode().split("\0") if f]
tracked.append(".claude-plugin/marketplace.json")

bad = []

def scan(node, rel, trail):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "hooks":
                bad.append("%s at %s/%s" % (rel, trail, k))
            scan(v, rel, "%s/%s" % (trail, k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            scan(v, rel, "%s[%d]" % (trail, i))

for rel in tracked:
    if rel == EXEMPT:
        continue
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        continue
    ext = os.path.splitext(path)[1]
    raw = open(path, encoding="utf-8").read()
    try:
        if ext == ".json":
            scan(json.loads(raw), rel, "")
        elif ext in (".yaml", ".yml"):
            for d in yaml.safe_load_all(raw):
                scan(d, rel, "")
        elif ext == ".md":
            m = FRONTMATTER.match(raw)
            if m:
                scan(yaml.safe_load(m.group(1)), rel, "frontmatter")
        else:
            bad.append("%s (UNSCANNABLE shipped format '%s' - no parser, so a "
                       "hooks declaration in it would be invisible)" % (rel, ext))
    except Exception as e:
        bad.append("%s (unparseable: %s)" % (rel, str(e)[:60]))

assert not bad, "; ".join(bad)
PYEOF
}
if hooks_scan_err=$(_cowork_hooks_scan 2>&1 >/dev/null); then
  pass "no \`hooks\` declaration outside cowork/hooks/hooks.json in any tracked shipped file (.json keys, .yaml docs, .md frontmatter; unknown formats fail closed)"
else
  fail "a \`hooks\` declaration exists outside cowork/hooks/hooks.json, or a tracked shipped file has a format this scan cannot read — either way a hook could be registered where Tests 12 and 13 cannot see it (GH #561): $(printf '%s' "$hooks_scan_err" | tail -1)"
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

# GH #561: Test 14e is GONE with its subject. It pinned properties of the
# UserPromptSubmit prompt's TEXT — which framing it must use, what it must not
# demand. Contract assertions on a deleted prompt die with it, same as the #484
# deletion note directly below.

# GH #484: the Stop prompt hook is GONE, so its contract assertions are gone
# with it. ~90 lines here pinned properties of that prompt's TEXT — which
# exemptions it named, what it must not demand. All passed while the hook was
# wrong 11 times in 12 firings, because a prompt containing the right words
# tells you nothing about whether the evaluator follows them. Deleted rather
# than ported: that is the ROADMAP #490 defect class, and the #477 rewrite these
# lines protected is what produced the prompt that then had to be removed.


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

# GH #561: Test 18 is GONE with its subject. It pinned the text of the
# justified-exception carve-out added after the 2026-08-07 denial — the
# first repair to this hook. It passed while the hook went on to deny the
# maintainer a second time (see Test 12). Contract assertions on a deleted
# prompt die with it, same as Test 14e and the #484 note above.

# Test 19: the skill must declare what happens when the wizard doc is absent.
#
# Cowork consumers receive SIX files — README, hooks.json, two plugin manifests,
# and the two SKILL.md copies. They never receive CLAUDE_CODE_SDLC_WIZARD.md,
# and there is no mechanism to give it to them: it is 271 KB (277,908 bytes)
# against a 35 KB plugin (35,627 bytes across those six files, measured
# 2026-08-08), written for a CLI Cowork does not have.
#
# So every "full protocol: wizard doc" pointer in the skill is a dangling
# reference for those users, and GH #489 is adding more of them as content moves
# out of the byte-capped skill. One sentence at the top converts all of them from
# broken references into declared graceful degradation.
#
# This assertion is load-bearing, not decorative. #489's own finding is that byte
# pressure deletes exactly the prose no test protects — three content defects in
# one session came from trimming to fit. Without this check, the next trim round
# removes the sentence and the defect quietly returns.
if [ -f "$PROJECT_ROOT/skills/sdlc/SKILL.md" ] && [ -f "$PROJECT_ROOT/cowork/skills/sdlc/SKILL.md" ]; then
  missing=""
  for f in "$PROJECT_ROOT/skills/sdlc/SKILL.md" "$PROJECT_ROOT/cowork/skills/sdlc/SKILL.md"; do
    grep -qiE "complete on its own" "$f" && grep -qiE "if absent, do not hunt for it" "$f" \
      || missing="$missing $(basename "$(dirname "$(dirname "$f")")")"
  done
  if [ -z "$missing" ]; then
    pass "skill declares the wizard-doc-absent convention (Cowork gets graceful degradation, not dangling pointers)"
  else
    fail "skill does not declare what to do when the wizard doc is absent — Cowork users never receive it, so every pointer is a dead end:$missing"
  fi
else
  fail "SKILL.md copies missing — cannot check the wizard-doc-absent convention"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
