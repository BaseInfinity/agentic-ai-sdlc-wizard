#!/bin/bash
# tests/test-stop-hook-terminates.sh
#
# A Stop hook that blocks MUST honour `stop_hook_active`.
#
# Claude Code re-invokes a Stop hook after it blocks. If the hook has no way to
# know that it is itself the reason the turn did not end, it re-evaluates the
# same unchanged state, blocks again, and loops until the harness force-breaks
# it. The harness states the contract verbatim when it does:
#
#   "For Stop/SubagentStop hooks, check stop_hook_active in the input and
#    return success while it's true."
#
# Observed 2026-07-27 in a consumer repo (BaseInfinity/claude-sdlc-wizard#477):
# nine consecutive blocks with an identical verdict before the harness
# overrode. The trigger was a repo whose test suite has KNOWN, INVESTIGATED,
# pre-existing failures — the correct engineering state, which the hook's
# "suite shown to PASS" criterion cannot express. So the agent could never
# satisfy it and the missing guard turned one bad verdict into an infinite one.
#
# Why this was not caught before shipping: every fixture in this repo has a
# green suite, so the hook never blocked, so it was never re-invoked. We tested
# the happy path of a guard whose entire purpose is the unhappy path.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== Stop hooks terminate ==="
echo

HOOK="$REPO_ROOT/hooks/codex-review-stop-check.sh"

# A Stop hook re-invoked while already active must let the turn end, whatever
# it would otherwise have decided. Run from a dirty worktree so the hook has
# something to complain about — otherwise this passes vacuously.
tmp=$(mktemp -d "${TMPDIR:-/tmp}/stophook.XXXXXX")
(
    cd "$tmp" || exit 1
    git init -q . 2>/dev/null
    git config user.email t@t.local; git config user.name t
    echo "print(1)" > code.py          # significant (not doc-only), uncommitted
    git add code.py 2>/dev/null
)

out=$(printf '%s' '{"stop_hook_active":true}' \
    | (cd "$tmp" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" 2>&1)) && rc=0 || rc=$?
if [ "${rc:-0}" -eq 0 ]; then
    pass "hook exits 0 when stop_hook_active is true"
else
    fail "hook exited $rc while stop_hook_active was true — this is the infinite-loop condition (out: $out)"
fi

# The governing constraint, asserted on BEHAVIOUR: this hook must never prevent
# the user from getting their response, so it must never exit 2 (the blocking
# code) on a normal stop. The real script exits 0 unconditionally.
#
# This assertion replaces one that passed on EITHER branch — it accepted "hook
# produced output" OR "hook was silent", which is every possible outcome. That
# vacuity is why Codex's round-6 symlink swap scored 3/3 while the hook exited 2
# on a normal stop: the allowlist trusted the pathname and nothing executed the
# thing behind it. It is also the exact ROADMAP #490 defect class described
# below, sitting in the file that describes it.
out2=$(printf '%s' '{}' \
    | (cd "$tmp" && CLAUDE_PROJECT_DIR="$tmp" bash "$HOOK" 2>&1)) && rc2=0 || rc2=$?
if [ "${rc2:-0}" -eq 0 ]; then
    pass "hook exits 0 on a normal stop — it cannot block the turn"
else
    fail "hook exited $rc2 on a normal stop; exit 2 blocks the user's response (out: $out2)"
fi

rm -rf "$tmp"

# The allowlist matches a command STRING, so it certifies a pathname and not the
# code behind it. Codex replaced the permitted script with a symlink to a
# blocking one and the suite still passed. Require the real thing.
sym=""
while IFS= read -r s; do
    [ -L "$s" ] && sym="$sym ${s#./}"
done < <(find . -name 'codex-review-stop-check.sh' -not -path './.git/*')
if [ -z "$sym" ]; then
    pass "every codex-review-stop-check.sh is a regular file, not a symlink"
else
    fail "codex-review-stop-check.sh is a symlink:$sym — the allowlist trusts this path, so what it points at must not be swappable"
fi

# The Cowork prompt-type Stop hook was REMOVED in GH #484. The ~110 lines of
# assertions that lived here checked properties of its PROMPT — that a
# DO-NOT-BLOCK section existed, that it named exemptions, that stop_hook_active
# was mentioned. They passed continuously while the hook produced 11 false
# positives in 12 firings, because asserting a prompt contains words cannot
# distinguish a working judge from a broken one. That is the ROADMAP #490
# defect class, and it is why they are deleted rather than ported.

# GH #484 — the prompt-based Stop hook is REMOVED, not softened.
#
# Evidence: 12 firings in one session, 11 false. It blocked turns that changed
# no files, turns whose verification was stated in the response, and five times
# it quoted its own in-flight exemption and then overrode it. It fired zero
# times during the v1.91.0 release work that contained ten real defects.
#
# Three prompt rewrites preceded this; each added exemption language that the
# evaluator then ignored. The prompt was correct and not followed, so a fourth
# rewrite was not the fix.
#
# The repo's own deterministic Stop hook states the governing constraint in its
# header: "Stop fires at the end of every turn, not just at true session end,
# and it must never prevent the user from getting their response." A blocking
# Stop hook violates that by construction. codex-review-stop-check.sh keeps the
# real coverage, non-blockingly.
# THREE BYPASSES, ONE ROOT CAUSE. Codex broke this check three consecutive
# rounds at the v1.92.0 gate, and each time the fix was "handle the thing it
# just named":
#
#   Round 1 — the check read two hardcoded manifest paths. A plugin.json `hooks`
#   field POINTING AT an alternate manifest smuggled a blocking Stop hook past
#   it while `claude plugin validate` passed.
#   Round 2 — the round-1 fix handled only `isinstance(h, str)`, so a
#   schema-valid INLINE `hooks` object in plugin.json did it again.
#   Round 3 — the round-2 fix resolved every SHAPE but still only from known
#   FILES, so a `hooks` entry on a marketplace.json plugin record did it again.
#   Codex confirmed that one installs enabled and enters the runtime registry.
#
#   Round 4 — the round-3 fix scanned every .json but flagged only type=="prompt",
#   so a COMMAND-type Stop exiting 2 blocked just as hard and passed; and it
#   scanned only .json, so a Stop hook in SKILL.md YAML frontmatter — a
#   documented non-JSON hook source — passed too. Both were exclusions I had
#   made deliberately and asked Codex to challenge; both were wrong. My argument
#   that Cowork cannot run shell hooks was refuted outright: it can.
#
# Enumerating what to forbid failed the same way enumerating sources did. So the
# rule is now a POSITIVE ANCHOR — an allowlist of exactly one known-good hook,
# with everything else denied by construction:
#
#     The ONLY Stop hooks permitted anywhere in this repo are the three EXACT
#     command strings that invoke the deterministic, non-blocking
#     codex-review-stop-check.sh. ANY other Stop hook — any type, any file, any
#     nesting depth — is a violation.
#
#   Round 5 — I first matched that command by SUBSTRING, and argued the weakness
#   was acceptable because this is a drift guard, not a security boundary. Codex
#   disagreed and executed the bypass: `exit 2 # codex-review-stop-check.sh` and
#   `./evil/codex-review-stop-check.sh` both passed. Exact match now. Also round
#   5: the scan EXCLUDED .reviews/, and a plugin could point at a manifest inside
#   it — an exclusion I added for speed became the hole, which is the same
#   mistake as rounds 1-4 in a new place. Only .git and node_modules are skipped
#   now; neither is a hook load source.
#
# Scanned surfaces: .json, .yaml/.yml, and YAML frontmatter in .md. This does not
# depend on knowing where Claude Code loads hooks from, so it survives new load
# paths. It also forbids legitimate fixtures — accepted deliberately, because
# tests build fixtures in mktemp dirs this scan never sees.
#
# KNOWN FLOOR — stated rather than implied: a scan of repo files cannot see a
# Stop hook registered at install time or at runtime by something no repo file
# expresses. This guards the repository, not the live session.
test_no_blocking_prompt_stop_hook() {
    local bad
    bad=$(python3 - "$REPO_ROOT" <<'PYEOF'
import json, os, re, sys
try:
    import yaml
except ImportError:
    yaml = None

root = sys.argv[1]
bad = []

# The permitted Stop hooks, matched EXACTLY. Substring matching was bypassed in
# round 5 by both `exit 2 # codex-review-stop-check.sh` and a lookalike path
# `./evil/codex-review-stop-check.sh`. The three registrations spell the path
# differently, so all three literals are listed rather than pattern-matched.
# Adding a fourth spelling should be a deliberate edit here, not an accident.
ALLOWED = frozenset((
    '${CLAUDE_PLUGIN_ROOT}/hooks/codex-review-stop-check.sh',
    '"$CLAUDE_PROJECT_DIR"/.claude/hooks/codex-review-stop-check.sh',
    '"$CLAUDE_PROJECT_DIR"/hooks/codex-review-stop-check.sh',
))

CRITICAL = ("hooks/hooks.json", "cowork/hooks/hooks.json")

def is_critical(rel):
    return rel in CRITICAL or rel.endswith((".claude-plugin/plugin.json",
                                            ".claude-plugin/marketplace.json"))

def scan(node, rel, trail):
    """Report every Stop hook that is not the single allowlisted one."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "Stop":
                for entry in (v if isinstance(v, list) else [v]):
                    if not isinstance(entry, dict):
                        continue
                    for h in entry.get("hooks") or []:
                        if not isinstance(h, dict):
                            continue
                        if (h.get("type") == "command"
                                and h.get("command") in ALLOWED):
                            continue          # a known-good registration
                        bad.append("%s%s/Stop (type=%s)"
                                   % (rel, trail, h.get("type")))
            scan(v, rel, "%s/%s" % (trail, k))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            scan(v, rel, "%s[%d]" % (trail, i))

FRONTMATTER = re.compile(r"\A---\r?\n(.*?)\r?\n---\r?\n", re.S)

def documents(path, rel):
    """Yield decoded structured documents from a file, or None if not one."""
    ext = os.path.splitext(path)[1]
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except OSError as e:
        if is_critical(rel):
            bad.append("%s (unreadable: %s)" % (rel, e))
        return
    try:
        if ext == ".json":
            yield json.loads(raw)
        elif ext in (".yaml", ".yml") and yaml:
            for d in yaml.safe_load_all(raw):
                yield d
        elif ext == ".md" and yaml:
            m = FRONTMATTER.match(raw)
            if m:
                yield yaml.safe_load(m.group(1))
    except Exception as e:
        # Malformed content is a defect only for the manifests we depend on;
        # elsewhere Claude Code cannot load it either, and tests/fixtures/
        # deliberately ships a malformed file for another suite.
        if is_critical(rel):
            bad.append("%s (unreadable: %s)" % (rel, str(e)[:60]))

if yaml is None:
    bad.append("python3 yaml module unavailable — cannot scan .md/.yaml hook "
               "sources; install it rather than trusting a partial scan")

# A missing shipped manifest is a FAILURE, not a skip: this suite once exited 0
# with cowork/hooks/hooks.json deleted.
for rel in CRITICAL:
    if not os.path.isfile(os.path.join(root, rel)):
        bad.append("shipped manifest missing: " + rel)

for dirpath, dirnames, filenames in os.walk(root):
    # Every exclusion here has eventually been the hole. .reviews/ fell in round
    # 5; node_modules fell in round 6, where Codex loaded a blocking manifest
    # from it that passed strict validation. Only .git is skipped now — it
    # stores objects, not manifests Claude Code loads.
    dirnames[:] = [d for d in dirnames if d != ".git"]
    for fn in filenames:
        if not fn.endswith((".json", ".yaml", ".yml", ".md")):
            continue
        p = os.path.join(dirpath, fn)
        rel = os.path.relpath(p, root)
        for doc in documents(p, rel):
            if doc is not None:
                scan(doc, rel, "")

print(" ".join(sorted(set(bad))))
PYEOF
)
    if [ -z "$bad" ]; then
        pass "the only Stop hook in the repo is codex-review-stop-check.sh (allowlist, not a source or type list)"
    else
        # Deliberately not appending "it blocks on every turn" to every line —
        # that is true of a found hook but not of an unreadable or missing
        # manifest, and those are reported here too.
        fail "Stop-hook allowlist violated: $bad"
        fail "(a blocking Stop hook blocks on every turn; the prompt one scored 11 false positives in 12 firings, which is why #484 removed it)"
    fi
}
test_no_blocking_prompt_stop_hook

echo
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
