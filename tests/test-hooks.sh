#!/bin/bash
# Test hook scripts
# Tests: output keywords, JSON handling, missing jq behavior

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$SCRIPT_DIR/../hooks"
PASSED=0
FAILED=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() {
    echo -e "${GREEN}PASS${NC}: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo -e "${RED}FAIL${NC}: $1"
    FAILED=$((FAILED + 1))
}

echo "=== Hook Script Tests ==="
echo ""

# ---- sdlc-prompt-check.sh tests ----

# Test 1: Script exists and is executable
test_sdlc_hook_exists() {
    if [ -x "$HOOKS_DIR/sdlc-prompt-check.sh" ]; then
        pass "sdlc-prompt-check.sh exists and is executable"
    else
        fail "sdlc-prompt-check.sh not found or not executable"
    fi
}

# Test 2: Output contains SDLC keywords
test_sdlc_hook_keywords() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    local has_all=true
    for keyword in "TodoWrite" "CONFIDENCE" "TDD" "TESTS" "SDLC"; do
        if ! echo "$output" | grep -qi "$keyword"; then
            has_all=false
            break
        fi
    done
    if [ "$has_all" = "true" ]; then
        pass "sdlc-prompt-check.sh contains all required keywords"
    else
        fail "sdlc-prompt-check.sh missing expected keywords"
    fi
}

# Test 3: Output contains skill auto-invoke rules
test_sdlc_hook_auto_invoke() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "AUTO-INVOKE"; then
        pass "sdlc-prompt-check.sh contains AUTO-INVOKE rules"
    else
        fail "sdlc-prompt-check.sh should contain AUTO-INVOKE rules"
    fi
}

# Test 4: Output contains workflow phases
test_sdlc_hook_phases() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "Plan Mode" && echo "$output" | grep -q "Implementation"; then
        pass "sdlc-prompt-check.sh contains workflow phases"
    else
        fail "sdlc-prompt-check.sh should contain workflow phases"
    fi
}

# Test 5: Output is reasonably sized (< 1000 chars for token efficiency)
test_sdlc_hook_size() {
    # Isolate from ambient $HOME/.cache/sdlc-wizard so a seeded signals
    # log (possible in any session that hit LOW/FAILED phrases) doesn't
    # make the "baseline" test secretly exercise the bump block. Codex
    # PR #203 round 1 repro: 2 seeded signals made this test measure
    # 1045 chars instead of the true no-bump baseline.
    local tmpdir
    tmpdir=$(mktemp -d)
    local output
    output=$(SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    local size
    size=$(echo "$output" | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$size" -lt 1000 ]; then
        pass "sdlc-prompt-check.sh output is token-efficient (${size} chars)"
    else
        fail "sdlc-prompt-check.sh output too large (${size} chars, should be <1000)"
    fi
}

# ---- Hook token-cost caps (ROADMAP #203) ----
# CC issue #50799 documents hidden SessionStart hook billing — hooks that
# emit unbounded output silently eat user tokens. Every hook that writes
# to stdout gets an explicit size cap here. A regression that grows a
# hook's output (unintentional echo loop, bloated nudge copy, duplicate
# warnings) must trip these tests rather than ship to consumers.

# sdlc-prompt-check worst-case: bump block + baseline. Separate from
# test_sdlc_hook_size (which asserts the no-bump baseline) so we know
# the baseline is lean AND the worst-case is bounded.
test_sdlc_hook_size_with_bump_firing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    echo 'x' > "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/cache"
    local now
    now=$(date +%s)
    printf '%s\tlow\n%s\tfailed\n' "$((now - 60))" "$((now - 30))" > "$tmpdir/cache/effort-signals.log"
    local size
    size=$(echo '{"prompt":"continue"}' | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh") | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$size" -lt 1300 ]; then
        pass "sdlc-prompt-check worst-case (bump+baseline) is bounded (${size} chars < 1300)"
    else
        fail "sdlc-prompt-check worst-case exceeded cap (${size} chars ≥ 1300) — regression in bump copy or baseline"
    fi
}

test_tdd_pretool_size_cap() {
    local size
    size=$(echo '{"tool_input":{"file_path":"/src/foo.ts"}}' | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null | wc -c | tr -d ' ')
    if [ "$size" -lt 500 ]; then
        pass "tdd-pretool-check output is bounded (${size} chars < 500)"
    else
        fail "tdd-pretool-check output exceeded cap (${size} chars ≥ 500)"
    fi
}

test_model_effort_size_cap() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    local size
    size=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$size" -lt 500 ]; then
        pass "model-effort-check output is bounded (${size} chars < 500)"
    else
        fail "model-effort-check output exceeded cap (${size} chars ≥ 500)"
    fi
}

test_instructions_loaded_size_cap() {
    # Stacked fixture: every emission branch in instructions-loaded-check.sh
    # must fire simultaneously. Codex PR #203 round 1 pointed out the original
    # fixture only exercised the loud-staleness branch (measured 557 chars,
    # cap was 3000 — 50-line bloat at 1509 still passed). This rebuilt fixture
    # stacks: loud staleness + cross-model review staleness + effort upgrade +
    # autocompact compound misconfig (#207) + dual-install + API review +
    # CC release + CC version check.
    local tmpdir
    tmpdir=$(mktemp -d)
    local fakehome="$tmpdir/home"
    local proj="$tmpdir/proj"
    mkdir -p "$fakehome/.claude/plugins-local/sdlc-wizard-wrap"
    mkdir -p "$proj/.claude/skills/update"
    mkdir -p "$proj/.github/workflows"
    mkdir -p "$proj/.reviews"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    echo '<!-- SDLC Wizard Version: 1.10.0 -->' > "$proj/SDLC.md"
    echo 'testing' > "$proj/TESTING.md"
    # Effort upgrade (jq + stale effort)
    echo '{"effortLevel":"high"}' > "$proj/.claude/settings.local.json"
    # #207: autocompact compound misconfig (both env vars set)
    cat > "$proj/.claude/settings.json" <<'STACKED_SETTINGS'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
STACKED_SETTINGS
    # API review nudge (weekly-api-update.yml + gh stub → 5 open)
    echo 'name: weekly-api-update' > "$proj/.github/workflows/weekly-api-update.yml"
    # CC release nudge (weekly-update.yml + gh stub → 5 open)
    echo 'name: weekly-update' > "$proj/.github/workflows/weekly-update.yml"
    # Cross-model review staleness (codex + .reviews/ + age>3d + commits>5)
    touch -t 202603010000 "$proj/.reviews/latest-review.md"
    (cd "$proj" && git init -q && git config user.email t@t.com && git config user.name t \
        && for i in 1 2 3 4 5 6; do echo "$i" > "f$i.txt" && git add . && git commit -qm "c$i"; done)
    # Stubs: npm (loud 24-minor nudge + CC version diff), gh (nudge counts),
    # codex (presence), claude (CC version)
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm" && chmod +x "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "5"\n' > "$tmpdir/bin/gh" && chmod +x "$tmpdir/bin/gh"
    printf '#!/bin/bash\ntrue\n' > "$tmpdir/bin/codex" && chmod +x "$tmpdir/bin/codex"
    printf '#!/bin/bash\necho "1.2.3"\n' > "$tmpdir/bin/claude" && chmod +x "$tmpdir/bin/claude"
    local size
    size=$(cd "$proj" && HOME="$fakehome" PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$proj" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    # Cap raised 1500 → 1700 to accommodate the autocompact compound-misconfig
    # branch added in v1.44.1 / #207. Each new diagnostic warning legitimately
    # earns its space — but keep the cap as a brevity gate so unbounded growth
    # gets caught.
    if [ "$size" -lt 1700 ]; then
        pass "instructions-loaded-check stacked worst-case (all 8 branches incl. #207) is bounded (${size} chars < 1700)"
    else
        fail "instructions-loaded-check stacked worst-case exceeded cap (${size} chars ≥ 1700)"
    fi
}

# ---- PreCompact seam-gate hook (ROADMAP #208) ----
# Blocks manual /compact when compacting would lose evidence the next
# cycle needs — specifically when a Codex review is PENDING or a git
# rebase/merge/cherry-pick is in flight. Auto-compact is NOT gated
# (matcher: "manual" only in settings.json) — blocking auto risks
# pushing past 100% context.

test_precompact_hook_exists() {
    if [ -x "$HOOKS_DIR/precompact-seam-check.sh" ]; then
        pass "precompact-seam-check.sh exists and is executable"
    else
        fail "precompact-seam-check.sh missing or not executable"
    fi
}

test_precompact_silent_without_handoff_or_git_op() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # No .reviews/handoff.json, no .git — should exit 0 silently
    local stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null)
    local rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "precompact hook silent when no handoff and no git ops"
    else
        fail "precompact hook should be silent (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_silent_when_handoff_certified() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "CERTIFIED", "round": 2}
JSON
    CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>/dev/null
    local rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ]; then
        pass "precompact hook silent when handoff status is CERTIFIED"
    else
        fail "precompact hook blocked on CERTIFIED handoff (rc=$rc)"
    fi
}

test_precompact_blocks_on_pending_review() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1}
JSON
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "HOLD" && echo "$stderr_out" | grep -q "PENDING_REVIEW"; then
        pass "precompact hook blocks (rc=2) with HOLD + PENDING_REVIEW on pending review"
    else
        fail "precompact should block on PENDING_REVIEW (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_pending_recheck() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 2}
JSON
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_RECHECK"; then
        pass "precompact hook blocks (rc=2) with PENDING_RECHECK on pending recheck"
    else
        fail "precompact should block on PENDING_RECHECK (rc=$rc)"
    fi
}

test_precompact_blocks_on_git_rebase_in_progress() {
    # .git/rebase-merge/ — interactive rebase / rebase with merge strategy
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-merge"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact hook blocks (rc=2) on in-progress rebase-merge"
    else
        fail "precompact should block on rebase-merge (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_git_rebase_apply_in_progress() {
    # .git/rebase-apply/ — non-interactive rebase / `git am` / patch-based rebase.
    # Distinct code path from rebase-merge in the hook. Codex R1 caught the miss.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-apply"
    echo "dummy" > "$tmpdir/.git/rebase-apply/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact hook blocks (rc=2) on in-progress rebase-apply"
    else
        fail "precompact should block on rebase-apply (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_git_merge_in_progress() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/MERGE_HEAD"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "precompact hook blocks (rc=2) on in-progress merge"
    else
        fail "precompact should block on merge (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_cherry_pick_in_progress() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/CHERRY_PICK_HEAD"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "cherry-pick"; then
        pass "precompact hook blocks (rc=2) on in-progress cherry-pick"
    else
        fail "precompact should block on cherry-pick (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_silent_on_stale_rebase_head_alone() {
    # Bug: .git/REBASE_HEAD can persist as a stale marker after a rebase
    # has finished cleanly. The authoritative "rebase in progress" signal
    # is .git/rebase-merge/ or .git/rebase-apply/ — REBASE_HEAD alone is
    # just a rebase-related ref (the stopped/replayed commit), not an
    # in-flight state. Hit live 2026-05-05: yesterday's clean rebase left
    # REBASE_HEAD behind and blocked the user's manual /compact for no real reason.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git"
    echo "abc123" > "$tmpdir/.git/REBASE_HEAD"
    # NO rebase-merge/ or rebase-apply/ — actual rebase has finished
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "precompact hook is silent on stale REBASE_HEAD without rebase-{merge,apply} dirs"
    else
        fail "precompact should be silent on stale REBASE_HEAD alone (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_rebase_head_with_rebase_merge_dir() {
    # Negative control: REBASE_HEAD + rebase-merge/ together = real rebase
    # in progress (git wrote REBASE_HEAD when it created the dir). MUST
    # still block. Distinguishes the stale-alone case above from a live one.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.git/rebase-merge"
    echo "abc123" > "$tmpdir/.git/REBASE_HEAD"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    local stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "precompact still blocks on REBASE_HEAD + rebase-merge dir (real rebase)"
    else
        fail "precompact should block on REBASE_HEAD + rebase-merge dir (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_size_cap() {
    # Worst case: all 4 blockers fire simultaneously (PENDING_RECHECK + rebase + merge + cherry-pick).
    # Should still emit a token-efficient HOLD message.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews" "$tmpdir/.git/rebase-merge"
    echo "dummy" > "$tmpdir/.git/rebase-merge/head-name"
    echo "abc" > "$tmpdir/.git/MERGE_HEAD"
    echo "def" > "$tmpdir/.git/CHERRY_PICK_HEAD"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 3}
JSON
    local size stderr_out rc=0
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    size=$(printf '%s' "$stderr_out" | wc -c | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && [ "$size" -lt 1000 ]; then
        pass "precompact hook stacked worst-case is bounded (${size} chars < 1000, rc=2)"
    else
        fail "precompact hook stacked worst-case exceeded cap or wrong rc (${size} chars, rc=$rc)"
    fi
}

# ---- Self-healing (ROADMAP #209) ----
# If handoff.json is PENDING_* but its PR has already merged, the artifact
# is stale from a prior review the user forgot to close out. Block every
# future /compact over a stale artifact is a worse UX than the bug we're
# preventing (mid-cycle compact), so the hook self-heals by querying
# `gh pr view <pr_number> --json state`. MERGED → treat as implicit
# CERTIFIED (unblock). Open/missing pr_number/gh unavailable → existing
# block behavior (safe fallback).

_precompact_mock_gh() {
    # Writes a mock `gh` to $1/gh that emits the given state for "pr view"
    # calls. Any other subcommand exits 1. Second arg = state string.
    local bindir="$1" state="$2"
    mkdir -p "$bindir"
    cat > "$bindir/gh" <<EOF
#!/bin/bash
if [ "\$1" = "pr" ] && [ "\$2" = "view" ]; then
    printf '%s\n' "$state"
    exit 0
fi
exit 1
EOF
    chmod +x "$bindir/gh"
}

test_precompact_self_heals_on_merged_pr() {
    # PENDING_RECHECK + pr_number set + gh says MERGED → implicit CERTIFIED → exit 0.
    # Also asserts ZERO stderr on unblock — self-heal must be silent, not a nag.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 2, "pr_number": 205}
JSON
    _precompact_mock_gh "$tmpdir/mockbin" "MERGED"
    local rc=0 stderr_out
    stderr_out=$(PATH="$tmpdir/mockbin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "precompact self-heals silently on merged PR (rc=0, stderr empty)"
    else
        fail "precompact should unblock silently when PR is merged (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_when_gh_missing() {
    # PENDING + pr_number + `gh` not on PATH → command -v gh fails → fallback to block.
    # Distinct code path from gh-errors (which hits command -v success + gh exit !=0).
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews" "$tmpdir/minbin"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1, "pr_number": 205}
JSON
    # Symlink only the bare utilities the hook needs — no gh.
    for bin in grep sed head cat stat; do
        if [ -x "/usr/bin/$bin" ]; then
            ln -sf "/usr/bin/$bin" "$tmpdir/minbin/$bin"
        elif [ -x "/bin/$bin" ]; then
            ln -sf "/bin/$bin" "$tmpdir/minbin/$bin"
        fi
    done
    local rc=0 stderr_out
    # Isolated PATH with zero gh — forces command -v gh to fail.
    stderr_out=$(PATH="$tmpdir/minbin" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW"; then
        pass "precompact falls back to block when gh missing from PATH (rc=2)"
    else
        fail "precompact should block when gh is unavailable (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_still_blocks_on_open_pr() {
    # PENDING + pr_number + gh says OPEN → still block (review genuinely in flight).
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1, "pr_number": 999}
JSON
    _precompact_mock_gh "$tmpdir/mockbin" "OPEN"
    local rc=0 stderr_out
    stderr_out=$(PATH="$tmpdir/mockbin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW"; then
        pass "precompact still blocks when PR is OPEN (rc=2)"
    else
        fail "precompact should block on open PR (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_when_no_pr_number() {
    # PENDING + no pr_number field → cannot self-heal → block (existing behavior).
    # Covers the backward-compat path where users haven't adopted the new schema.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 2}
JSON
    # Mock gh returns MERGED — but hook shouldn't even call it without pr_number.
    _precompact_mock_gh "$tmpdir/mockbin" "MERGED"
    local rc=0 stderr_out
    stderr_out=$(PATH="$tmpdir/mockbin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_RECHECK"; then
        pass "precompact blocks when pr_number is absent (no self-heal opt-in)"
    else
        fail "precompact should block without pr_number (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_when_gh_errors() {
    # PENDING + pr_number + gh exits non-zero (offline, not authed, rate-limited).
    # Functionally equivalent to "gh binary missing" — both resolve to fallback.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews" "$tmpdir/mockbin"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1, "pr_number": 205}
JSON
    # Mock gh that always fails (simulates offline, auth failure, etc.)
    cat > "$tmpdir/mockbin/gh" <<'EOF'
#!/bin/bash
echo "error: could not reach GitHub" >&2
exit 1
EOF
    chmod +x "$tmpdir/mockbin/gh"
    local rc=0 stderr_out
    stderr_out=$(PATH="$tmpdir/mockbin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW"; then
        pass "precompact falls back to block when gh errors (rc=2)"
    else
        fail "precompact should block on gh failure (rc=$rc, stderr='$stderr_out')"
    fi
}

# ---- Stale-handoff auto-expire (ROADMAP #229) ----
# The self-heal in #209 only works when handoff.json has a pr_number field.
# Reviews written before #209 (or ad-hoc reviews not tied to a PR) lack that
# field — their PENDING_* status blocks every future /compact forever until
# someone manually flips it. Discovered live-fire 2026-04-23 when the hook
# blocked a session-end compact because the precompact-seam-001 review
# (which SHIPPED the hook itself) had no pr_number.
#
# Fix: if PENDING_* AND no pr_number AND mtime older than SDLC_HANDOFF_STALE_DAYS
# (default 14), treat as implicit CERTIFIED and emit a one-line WARN (not HOLD).
# Threshold is env-overridable for test determinism and power-user tuning.

test_precompact_unblocks_stale_pending_without_pr_number() {
    # PENDING_RECHECK + no pr_number + mtime 4 months old → unblock with WARN.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 2}
JSON
    # Age the file: POSIX touch -t YYYYMMDDhhmm, 2026-01-01 ~ 4 months before test date.
    touch -t 202601010000 "$tmpdir/.reviews/handoff.json"
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && echo "$stderr_out" | grep -qi "stale"; then
        pass "precompact unblocks (rc=0) stale PENDING handoff without pr_number, emits WARN"
    else
        fail "precompact should unblock stale PENDING without pr_number (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_still_blocks_fresh_pending_without_pr_number() {
    # Regression guard: fresh (just-created) PENDING + no pr_number → BLOCK.
    # We do NOT want stale-expire to short-circuit genuine in-flight reviews.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1}
JSON
    # File mtime is "now" (just created) → age 0 days, far below 14-day threshold.
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW"; then
        pass "precompact still blocks fresh PENDING without pr_number (no premature expire)"
    else
        fail "precompact should block fresh PENDING (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_stale_with_pr_number_prefers_self_heal() {
    # Stale mtime but pr_number present → hook prefers the #209 self-heal path
    # (query gh for PR state), not the stale-expire branch. If PR is OPEN, still
    # block — the review is live, age is irrelevant. Proves the two paths don't
    # fight: pr_number takes priority over mtime.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1, "pr_number": 999}
JSON
    touch -t 202601010000 "$tmpdir/.reviews/handoff.json"
    _precompact_mock_gh "$tmpdir/mockbin" "OPEN"
    local rc=0 stderr_out
    stderr_out=$(PATH="$tmpdir/mockbin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW" && ! echo "$stderr_out" | grep -qi "stale"; then
        pass "precompact with pr_number uses self-heal path (blocks on OPEN PR, ignores mtime)"
    else
        fail "precompact should prefer pr_number self-heal over stale-expire (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_stale_threshold_invalid_falls_back() {
    # SDLC_HANDOFF_STALE_DAYS="foo" (typo/invalid) must NOT leak bash
    # arithmetic error to stderr. Hook silently falls back to default 14 and
    # behaves as if no override was set. Caught by Codex P2 review of PR #227.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1}
JSON
    # Fresh file + invalid env var + default-14-threshold → still blocks cleanly.
    local rc=0 stderr_out
    stderr_out=$(SDLC_HANDOFF_STALE_DAYS=foo CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_REVIEW" && ! echo "$stderr_out" | grep -qi "integer expression"; then
        pass "precompact silently ignores invalid SDLC_HANDOFF_STALE_DAYS (no shell error leaked)"
    else
        fail "precompact should tolerate bad env var without shell noise (rc=$rc, stderr='$stderr_out')"
    fi
}

test_handoff_template_documents_pr_number() {
    # ROADMAP #209 closure: the precompact hook self-heals on PENDING_* handoffs
    # by querying `gh pr view <pr_number> --json state` — but consumers can only
    # opt in if the field is DOCUMENTED in EVERY handoff schema (consumers read
    # whichever example they hit first). Without docs, the self-heal path is
    # dead code.
    #
    # Codex round-1 caught a false-green: the old test required ANY occurrence
    # of `pr_number` per file, so removing it from one of the wizard's two
    # schemas left the other intact and passed. Round-2 fix below uses the
    # `"status": "PENDING_REVIEW"` marker to count handoff schema instances
    # per file and asserts pr_number occurrence count >= handoff count.
    # Mutation: deleting pr_number from ANY schema instance drops the count
    # below handoff count and flips the test to FAIL.
    local skill="$SCRIPT_DIR/../skills/sdlc/SKILL.md"
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    local missing=""

    # Coverage check: every handoff schema must include pr_number.
    # PENDING_REVIEW uniquely marks handoff JSON (response.json uses PENDING_RECHECK).
    # NOTE: `grep -c` exits 1 when count is 0; `|| true` discards the failing
    # exit status without appending extra text (using `|| echo 0` here would
    # double-print "0\n0" and break integer comparison under set -e).
    local skill_handoffs skill_pr
    skill_handoffs=$(grep -c '"status": "PENDING_REVIEW"' "$skill" 2>/dev/null || true)
    skill_pr=$(grep -c '"pr_number":' "$skill" 2>/dev/null || true)
    [ "${skill_pr:-0}" -lt "${skill_handoffs:-0}" ] && missing="${missing}skill-coverage(${skill_pr:-0}/${skill_handoffs:-0}) "

    local wizard_handoffs wizard_pr
    wizard_handoffs=$(grep -c '"status": "PENDING_REVIEW"' "$wizard" 2>/dev/null || true)
    wizard_pr=$(grep -c '"pr_number":' "$wizard" 2>/dev/null || true)
    [ "${wizard_pr:-0}" -lt "${wizard_handoffs:-0}" ] && missing="${missing}wizard-coverage(${wizard_pr:-0}/${wizard_handoffs:-0}) "

    # Context check: at least one occurrence per file must sit within 8 lines
    # of self-heal context so consumers learn WHY they'd set it.
    if grep -q '"pr_number":' "$skill" && ! grep -B8 -A8 '"pr_number":' "$skill" | grep -qiE 'self.heal|PreCompact|#209|merged.*PR|precompact'; then
        missing="${missing}skill-context "
    fi
    if grep -q '"pr_number":' "$wizard" && ! grep -B8 -A8 '"pr_number":' "$wizard" | grep -qiE 'self.heal|PreCompact|#209|merged.*PR|precompact'; then
        missing="${missing}wizard-context "
    fi

    if [ -z "$missing" ]; then
        pass "handoff template documents pr_number in every schema with self-heal context (#209 opt-in)"
    else
        fail "handoff template missing pr_number opt-in docs: $missing"
    fi
}

test_precompact_stale_threshold_override() {
    # SDLC_HANDOFF_STALE_DAYS=0 → every PENDING without pr_number is "stale".
    # Covers the env-override code path and lets power users tune their own
    # threshold without editing the hook.
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_RECHECK", "round": 2}
JSON
    # File is fresh. With SDLC_HANDOFF_STALE_DAYS=0, even age=0 counts as stale.
    local rc=0 stderr_out
    stderr_out=$(SDLC_HANDOFF_STALE_DAYS=0 CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && echo "$stderr_out" | grep -qi "stale"; then
        pass "precompact respects SDLC_HANDOFF_STALE_DAYS override (0 = always stale)"
    else
        fail "precompact should honor stale-days override (rc=$rc, stderr='$stderr_out')"
    fi
}

# ---- Path (c) — fixes_applied SHAs in HEAD ancestry self-heal (#257) ----
# Solo-developer pattern: write fixes, commit, run targeted recheck via
# `codex exec`, see CERTIFIED in latest-review.md, ship the feature.
# Forgetting to update handoff.json status is realistic — the file is buried
# and the visible signals (latest-review.md "CERTIFIED" + commits landed)
# already tell the developer they're done. PreCompact should auto-CERTIFY
# silently in this case rather than blocking forever on a stale handoff.

# Helper: init a minimal repo at $1 with commits whose SHAs we can cite.
# Echoes the short SHA of the last commit so tests can write it into
# fixes_applied.
_precompact_init_repo_with_commit() {
    local dir="$1" msg="${2:-fix something}"
    git -C "$dir" init -q 2>/dev/null
    git -C "$dir" config user.email t@t.com
    git -C "$dir" config user.name t
    echo "content" > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -qm "$msg"
    git -C "$dir" rev-parse --short=7 HEAD
}

# Auto-CERTIFY when all SHAs in fixes_applied are in HEAD ancestry AND
# latest-review.md says CERTIFIED.
test_precompact_self_heals_on_sha_ancestry_when_review_certified() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 8/10. CERTIFIED.
No findings.
MD
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit ${sha} — added validation"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ]; then
        pass "#257: precompact self-heals on PENDING_RECHECK with SHAs in HEAD + CERTIFIED review (rc=0)"
    else
        fail "#257: should self-heal when SHAs in HEAD + review CERTIFIED (rc=$rc, stderr='$stderr_out')"
    fi
}

# Negative: SHA NOT in HEAD ancestry → must still HOLD
test_precompact_blocks_when_sha_not_in_head_ancestry() {
    local tmpdir
    tmpdir=$(mktemp -d)
    _precompact_init_repo_with_commit "$tmpdir" >/dev/null
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 8/10. CERTIFIED.
MD
    # Cite a SHA that doesn't exist in this repo
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit deadbeefcafe — phantom"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_RECHECK"; then
        pass "#257: precompact blocks when fixes_applied SHA is NOT in HEAD ancestry (rc=2)"
    else
        fail "#257: should block on phantom SHA (rc=$rc, stderr='$stderr_out')"
    fi
}

# Negative: SHA in HEAD ancestry BUT review NOT CERTIFIED → still HOLD
test_precompact_blocks_when_sha_in_head_but_review_not_certified() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 4/10. NOT CERTIFIED.
ID 1: P1 missing validation.
MD
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit ${sha} — partial fix"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_RECHECK"; then
        pass "#257: precompact blocks when review.md says NOT CERTIFIED even with SHAs in HEAD (rc=2)"
    else
        fail "#257: should block on NOT CERTIFIED review (rc=$rc, stderr='$stderr_out')"
    fi
}

# Negative: missing latest-review.md → still HOLD (path c needs both signals)
test_precompact_blocks_when_review_md_missing() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    # No latest-review.md
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit ${sha} — no review file"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ]; then
        pass "#257: precompact blocks when latest-review.md is missing (path c needs both signals)"
    else
        fail "#257: should block when latest-review.md missing (rc=$rc, stderr='$stderr_out')"
    fi
}

# All SHAs in HEAD: if fixes_applied has multiple SHAs, ALL must be in HEAD.
# A single phantom SHA blocks the heal.
test_precompact_blocks_when_any_sha_not_in_head() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 8/10. CERTIFIED.
MD
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit ${sha} — real",
    "FIXED in commit deadbeefcafe — phantom"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ]; then
        pass "#257: precompact blocks when ANY fixes_applied SHA is NOT in HEAD"
    else
        fail "#257: should block on partial SHA-ancestry coverage (rc=$rc, stderr='$stderr_out')"
    fi
}

# Codex round 1 P1: awk's `/\]/` mid-string match terminated the
# fixes_applied block early on entries like "[x] FIXED in <sha>", letting
# later phantom SHAs leak past path (c) and false-heal. Bracket extraction
# must track depth + string literals to terminate ONLY on the array's real
# closing `]`.
test_precompact_blocks_on_phantom_sha_after_markdown_checkbox_in_fixes_applied() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 8/10. CERTIFIED.
MD
    # First entry uses `[x]` markdown checkbox — naive `/\]/` matching
    # would terminate the array right after `[x]`, hiding the phantom
    # SHA on the next line.
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "[x] FIXED in commit ${sha} — real",
    "[x] FIXED in commit deadbeefcafe — phantom"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ]; then
        pass "#257 Codex#1: precompact blocks when phantom SHA hides behind '[x]' markdown checkbox in fixes_applied"
    else
        fail "#257 Codex#1: '[x]' markdown checkbox should not let phantom SHA past path (c) (rc=$rc, stderr='$stderr_out')"
    fi
}

# Codex round 1 P2: UUID fragments matched the bare \b[0-9a-f]{7,40}\b
# regex (e.g. UUID '123e4567-e89b-12d3-a456-426614174000' has '123e4567'
# and '426614174000' as substrings). Validate each candidate via `git
# rev-parse --verify` so UUID-style IDs in fixes_applied (mission UUIDs,
# Linear ticket IDs, etc.) don't false-block a legitimate heal by failing
# the ancestry check.
test_precompact_self_heals_with_uuid_in_fixes_applied() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 9/10. CERTIFIED.
MD
    # Real SHA + a UUID. UUID fragments would match the SHA regex but
    # aren't valid git objects, so git rev-parse --verify drops them.
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED ticket 123e4567-e89b-12d3-a456-426614174000 in commit ${sha}"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "#257 Codex#2: precompact heals when fixes_applied contains UUIDs alongside real SHA (rc=0, silent)"
    else
        fail "#257 Codex#2: UUID fragments should not false-block path (c) heal (rc=$rc, stderr='$stderr_out')"
    fi
}

# Path (b) takes precedence when no SHAs are in fixes_applied — i.e. don't
# break the existing stale-handoff path when the new path can't apply.
test_precompact_falls_through_to_stale_path_when_no_shas() {
    local tmpdir
    tmpdir=$(mktemp -d)
    _precompact_init_repo_with_commit "$tmpdir" >/dev/null
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": ["just text without any 7-hex SHA"]
}
JSON
    # File is fresh, but with SDLC_HANDOFF_STALE_DAYS=0 the stale path heals
    # this. If path (c) erroneously short-circuits when no SHAs are present,
    # the stale-path warn won't fire.
    local rc=0 stderr_out
    stderr_out=$(SDLC_HANDOFF_STALE_DAYS=0 CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && echo "$stderr_out" | grep -qi "stale"; then
        pass "#257: precompact falls through to path (b) stale-warn when fixes_applied has no SHAs"
    else
        fail "#257: should fall through to stale path when no SHAs in fixes_applied (rc=$rc, stderr='$stderr_out')"
    fi
}

# ---- Effort auto-bump signal detection (ROADMAP #195) ----
# Hook scans UserPromptSubmit payload for LOW-confidence / FAILED-repeatedly /
# CONFUSED phrases; logs a signal; when ≥2 recent signals accumulate in a
# 30-minute window, emits a loud /effort xhigh nudge so Claude escalates
# BEFORE burning more budget at 'high' effort (user feedback memory:
# "Dynamic effort bump is mandatory").

test_effort_bump_logs_signal_on_low_phrase() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    local payload='{"prompt":"I am stuck on this bug, tried twice and still failing"}'
    echo "$payload" | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" > /dev/null)
    if [ -f "$tmpdir/cache/effort-signals.log" ] && [ -s "$tmpdir/cache/effort-signals.log" ]; then
        pass "Low-confidence phrase in prompt logs a signal"
    else
        fail "Expected effort-signals.log entry after LOW/FAILED phrase"
    fi
    rm -rf "$tmpdir"
}

test_effort_bump_no_log_on_normal_prompt() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    local payload='{"prompt":"add a new route for the health endpoint"}'
    echo "$payload" | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" > /dev/null)
    if [ -f "$tmpdir/cache/effort-signals.log" ] && [ -s "$tmpdir/cache/effort-signals.log" ]; then
        fail "Neutral prompt should not log signal"
    else
        pass "Neutral prompt does not log a signal"
    fi
    rm -rf "$tmpdir"
}

test_effort_bump_nudge_fires_on_2_recent_signals() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/cache"
    local now
    now=$(date +%s)
    printf '%s\tlow\n%s\tfailed\n' "$((now - 60))" "$((now - 30))" > "$tmpdir/cache/effort-signals.log"
    local output
    output=$(echo '{"prompt":"continue"}' | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh"))
    rm -rf "$tmpdir"
    # Require BOTH a loud marker AND the actionable /effort command — either
    # alone is a weaker nudge that the user can gloss over.
    if echo "$output" | grep -qE 'EFFORT BUMP|ESCALATE EFFORT' && echo "$output" | grep -qE '/effort[[:space:]]+xhigh'; then
        pass "Bump nudge fires (loud marker + /effort xhigh) when 2 recent signals are logged"
    else
        fail "Expected bump nudge with marker + /effort xhigh, got: $output"
    fi
}

test_effort_bump_silent_on_1_signal() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/cache"
    local now
    now=$(date +%s)
    printf '%s\tlow\n' "$((now - 60))" > "$tmpdir/cache/effort-signals.log"
    local output
    output=$(echo '{"prompt":"continue"}' | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh"))
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE '/effort[[:space:]]+xhigh|EFFORT BUMP'; then
        fail "Bump nudge should not fire on a single signal"
    else
        pass "Single signal does not trigger bump nudge"
    fi
}

# Codex round 1 (P1): bare "confused"/"tried twice"/"can't figure" substrings
# fired on ambient/educational prompts like "How do I detect a CONFUSED state?"
# Fix: patterns require first-person ownership. This test guards the regression.
test_effort_bump_no_log_on_ambient_mention() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Codex round 1 & 2 findings: bare "confused" / "tried twice" / "low
    # confidence" / "failed again" / "still failing" / "keeps failing" /
    # "not sure why" all fired on educational prompts. Every generic phrase
    # the reviewer flagged is tested here.
    local ambient_prompts=(
        '{"prompt":"How do I detect a CONFUSED state in a bash case statement?"}'
        '{"prompt":"When would I use tried twice as a retry label?"}'
        '{"prompt":"How should I name a low confidence badge in the UI?"}'
        '{"prompt":"What does failed again mean in a retry log message?"}'
        '{"prompt":"How do I detect still failing states in a test runner?"}'
        '{"prompt":"What keeps failing mean for an idempotent job?"}'
        '{"prompt":"not sure why the GPS chip needs a fallback — can you explain?"}'
    )
    local ok=true
    local leak=""
    local p
    for p in "${ambient_prompts[@]}"; do
        rm -rf "$tmpdir/cache"
        echo "$p" | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" > /dev/null)
        if [ -f "$tmpdir/cache/effort-signals.log" ] && [ -s "$tmpdir/cache/effort-signals.log" ]; then
            ok=false
            leak="$p"
            break
        fi
    done
    rm -rf "$tmpdir"
    if [ "$ok" = true ]; then
        pass "Ambient/educational mentions of all 7 generic trigger words do not log a signal"
    else
        fail "Ambient prompt logged a signal (regression): $leak"
    fi
}

# Codex round 1 (P1): hook emitted 'No such file or directory' on stderr when
# HOME was unset or cache path pointed at a regular file. Redirection failure
# leaked past `|| true`. Fix wraps the whole write in a { ... } 2>/dev/null
# group. Regression test asserts stderr is empty on HOME=''.
test_effort_bump_silent_stderr_on_unwritable_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    local stderr_file="$tmpdir/stderr"
    local payload='{"prompt":"I am stuck on this"}'
    # HOME unset → default cache dir becomes /.cache/sdlc-wizard (unwritable)
    echo "$payload" | (cd "$tmpdir" && unset HOME; unset SDLC_WIZARD_CACHE_DIR; CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" >/dev/null 2>"$stderr_file")
    local stderr_size
    stderr_size=$(wc -c < "$stderr_file" | tr -d ' ')
    rm -rf "$tmpdir"
    if [ "${stderr_size:-0}" -eq 0 ]; then
        pass "Hook stderr is empty when cache path is unwritable"
    else
        fail "Hook leaked to stderr on unwritable cache (${stderr_size} bytes): $(cat "$stderr_file" 2>/dev/null)"
    fi
}

# Codex round 1 (P2): log grew unbounded. Fix prunes entries >1h old on write.
# Seed with many stale entries; invoke the hook once with a fresh signal;
# assert the resulting file has far fewer lines than what was seeded.
test_effort_bump_prunes_stale_log_entries() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/cache"
    # Seed 100 stale entries (each > 1 hour old)
    local base
    base=$(( $(date +%s) - 7200 ))
    local i=0
    while [ $i -lt 100 ]; do
        printf '%s\tlow\n' "$((base + i))" >> "$tmpdir/cache/effort-signals.log"
        i=$((i + 1))
    done
    local before
    before=$(wc -l < "$tmpdir/cache/effort-signals.log" | tr -d ' ')
    # Trigger a fresh write (adds 1 line, prunes stale)
    local payload='{"prompt":"I am stuck on this"}'
    echo "$payload" | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh" > /dev/null)
    local after
    after=$(wc -l < "$tmpdir/cache/effort-signals.log" | tr -d ' ')
    rm -rf "$tmpdir"
    # Expect: stale entries dropped, fresh signal appended → final count ≤ 5
    if [ "${before:-0}" -eq 100 ] && [ "${after:-0}" -le 5 ]; then
        pass "Stale log entries (>1h old) are pruned on write (100 → ${after})"
    else
        fail "Log was not pruned (before=${before}, after=${after})"
    fi
}

test_effort_bump_old_signals_ignored() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.33.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/cache"
    local now
    now=$(date +%s)
    # Both signals >30 min old — must be ignored
    printf '%s\tlow\n%s\tfailed\n' "$((now - 3700))" "$((now - 2400))" > "$tmpdir/cache/effort-signals.log"
    local output
    output=$(echo '{"prompt":"continue"}' | (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/sdlc-prompt-check.sh"))
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE '/effort[[:space:]]+xhigh|EFFORT BUMP'; then
        fail "Signals >30 min old should be ignored"
    else
        pass "Signals older than 30 min do not trigger bump nudge"
    fi
}

# ---- tdd-pretool-check.sh tests ----

# Test 6: Script exists and is executable
test_tdd_hook_exists() {
    if [ -x "$HOOKS_DIR/tdd-pretool-check.sh" ]; then
        pass "tdd-pretool-check.sh exists and is executable"
    else
        fail "tdd-pretool-check.sh not found or not executable"
    fi
}

# Test 7: Source file edit produces TDD warning JSON
test_tdd_hook_src_warning() {
    local input='{"tool_input": {"file_path": "/project/src/app.js"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "TDD CHECK"; then
        pass "tdd-pretool-check.sh warns on src/ file edits"
    else
        fail "Should warn when editing src/ files, got: $output"
    fi
}

# Test 8: Source file edit produces valid JSON output
test_tdd_hook_valid_json() {
    local input='{"tool_input": {"file_path": "/project/src/utils/helper.ts"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if echo "$output" | jq -e '.hookSpecificOutput' > /dev/null 2>&1; then
        pass "tdd-pretool-check.sh outputs valid JSON for src/ edits"
    else
        fail "Output should be valid JSON with hookSpecificOutput, got: $output"
    fi
}

# Test 9: Test file edit exits cleanly (no warning)
test_tdd_hook_test_file_ok() {
    local input='{"tool_input": {"file_path": "tests/test-something.sh"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "tdd-pretool-check.sh allows test file edits silently"
    else
        fail "Test file edits should produce no output, got: $output"
    fi
}

# Test 10: Non-workflow, non-test file produces no output
test_tdd_hook_other_file_ok() {
    local input='{"tool_input": {"file_path": "README.md"}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    if [ -z "$output" ]; then
        pass "tdd-pretool-check.sh allows other file edits silently"
    else
        fail "Non-workflow edits should produce no output, got: $output"
    fi
}

# Test 11: Missing file_path in input handled gracefully
test_tdd_hook_missing_path() {
    local input='{"tool_input": {}}'
    local output
    output=$(echo "$input" | "$HOOKS_DIR/tdd-pretool-check.sh" 2>/dev/null)
    local exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "tdd-pretool-check.sh handles missing file_path gracefully"
    else
        fail "Should handle missing file_path without crashing, exit code: $exit_code"
    fi
}

# ---- instructions-loaded-check.sh tests ----

# Test 12: Script exists and is executable
test_instructions_hook_exists() {
    if [ -x "$HOOKS_DIR/instructions-loaded-check.sh" ]; then
        pass "instructions-loaded-check.sh exists and is executable"
    else
        fail "instructions-loaded-check.sh not found or not executable"
    fi
}

# Test 13: Warns when SDLC.md is missing
test_instructions_hook_missing_sdlc() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/TESTING.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "SDLC.md"; then
        pass "instructions-loaded-check.sh warns when SDLC.md missing"
    else
        fail "Should warn about missing SDLC.md, got: $output"
    fi
}

# Test 14: Warns when TESTING.md is missing
test_instructions_hook_missing_testing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "TESTING.md"; then
        pass "instructions-loaded-check.sh warns when TESTING.md missing"
    else
        fail "Should warn about missing TESTING.md, got: $output"
    fi
}

# Test 15: Silent when neither file exists (not an SDLC project, #173)
test_instructions_hook_missing_both() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent when neither SDLC file exists (#173)"
    else
        fail "Should be silent when no SDLC project, got: $output"
    fi
}

# Test 16: No warning when both files exist
test_instructions_hook_all_present() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Mock claude + npm so CC version check doesn't produce output
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif [ "$1" = "--version" ]; then echo "2.1.90 (Claude Code)"; else echo "1.23.0"; fi\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nif [ "$1" = "view" ] && echo "$@" | grep -q "claude-code"; then echo "2.1.90"; elif [ "$1" = "view" ]; then echo "1.23.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/claude" "$tmpdir/bin/npm" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent when all files present"
    else
        fail "Should produce no output when files exist, got: $output"
    fi
}

# Test 17: Exits cleanly (exit 0) regardless of missing files
test_instructions_hook_exit_code() {
    local tmpdir
    tmpdir=$(mktemp -d)
    (cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh") > /dev/null 2>&1
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "instructions-loaded-check.sh exits cleanly even with missing files"
    else
        fail "Should exit 0 even when files missing, got exit code: $exit_code"
    fi
}

# Test 18: Hook output has no trailing whitespace
test_instructions_hook_no_trailing_whitespace() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Both files missing = worst case for trailing whitespace
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Check that no line ends with trailing whitespace (runtime output)
    if echo "$output" | grep -q '[[:blank:]]$'; then
        fail "instructions-loaded-check.sh output has trailing whitespace"
        return
    fi
    # Also check the script source itself for baked-in trailing whitespace
    if grep -q '[[:blank:]]$' "$HOOKS_DIR/instructions-loaded-check.sh"; then
        fail "instructions-loaded-check.sh source has trailing whitespace"
    else
        pass "instructions-loaded-check.sh output has no trailing whitespace"
    fi
}

# ---- Setup completeness tests (wizard dogfood) ----

# Test 19: SDLC.md contains wizard version metadata comment
test_sdlc_version_metadata() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- SDLC Wizard Version: [0-9]' "$sdlc_md"; then
        pass "SDLC.md contains wizard version metadata comment"
    else
        fail "SDLC.md should contain <!-- SDLC Wizard Version: X.X.X --> metadata comment"
    fi
}

# Test 20: SDLC.md wizard version matches wizard document version
test_sdlc_version_matches_wizard() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"

    local installed_version
    installed_version=$(grep -o 'SDLC Wizard Version: [0-9.]*' "$sdlc_md" | head -1 | sed 's/SDLC Wizard Version: //')
    local wizard_version
    wizard_version=$(grep -o 'SDLC Wizard Version: [0-9.]*' "$wizard" | head -1 | sed 's/SDLC Wizard Version: //')

    if [ -z "$installed_version" ]; then
        fail "Could not extract version from SDLC.md"
        return
    fi
    if [ "$installed_version" = "$wizard_version" ]; then
        pass "SDLC.md version ($installed_version) matches wizard ($wizard_version)"
    else
        fail "SDLC.md version ($installed_version) != wizard version ($wizard_version)"
    fi
}

# Test 21: SDLC.md contains setup date metadata
test_sdlc_setup_date() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- Setup Date: [0-9]' "$sdlc_md"; then
        pass "SDLC.md contains setup date metadata comment"
    else
        fail "SDLC.md should contain <!-- Setup Date: YYYY-MM-DD --> metadata comment"
    fi
}

# Test 22: SDLC.md contains completed steps metadata
test_sdlc_completed_steps() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -q '<!-- Completed Steps:' "$sdlc_md"; then
        pass "SDLC.md contains completed steps metadata comment"
    else
        fail "SDLC.md should contain <!-- Completed Steps: ... --> metadata comment"
    fi
}

# Test 23: Light hook references /code-review (not outdated subagent pattern)
test_sdlc_hook_self_review_reference() {
    local output
    output=$("$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    if echo "$output" | grep -q "/code-review"; then
        pass "sdlc-prompt-check.sh references /code-review for self-review"
    else
        fail "sdlc-prompt-check.sh should reference /code-review, not outdated subagent pattern"
    fi
}

# Test 24: SDLC.md update frequency says weekly (not daily)
test_sdlc_update_frequency() {
    local sdlc_md="$SCRIPT_DIR/../SDLC.md"
    if grep -qi "daily.*workflow.*checks\|daily.*checks.*for.*update" "$sdlc_md"; then
        fail "SDLC.md says 'daily' but update workflow runs weekly"
    else
        pass "SDLC.md does not falsely claim daily update checks"
    fi
}

# Test 25: instructions-loaded-check.sh mentions setup-wizard on partial setup
test_instructions_hook_mentions_setup_wizard() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Partial setup: only TESTING.md exists — should warn about missing SDLC.md
    # CWD must be below HOME for walk-up to check the project dir
    mkdir -p "$tmpdir/project"
    touch "$tmpdir/project/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard"; then
        pass "instructions-loaded-check.sh mentions setup-wizard on partial setup"
    else
        fail "Should mention setup-wizard skill invocation, got: $output"
    fi
}

# Test 26: sdlc-prompt-check outputs setup-wizard directive when SDLC.md missing
test_sdlc_hook_setup_redirect_missing_sdlc() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/TESTING.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to setup-wizard when SDLC.md missing"
    else
        fail "Should output setup-wizard directive (not SDLC BASELINE) when SDLC.md missing"
    fi
}

# Test 27: sdlc-prompt-check outputs setup-wizard directive when TESTING.md missing
test_sdlc_hook_setup_redirect_missing_testing() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to setup-wizard when TESTING.md missing"
    else
        fail "Should output setup-wizard directive (not SDLC BASELINE) when TESTING.md missing"
    fi
}

# Test 28: sdlc-prompt-check outputs normal baseline when both files exist (non-empty)
test_sdlc_hook_normal_when_setup_complete() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local output
    output=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE" && ! echo "$output" | grep -q "SETUP NOT COMPLETE"; then
        pass "sdlc-prompt-check.sh outputs normal baseline when setup complete"
    else
        fail "Should output SDLC BASELINE (not setup redirect) when both files exist"
    fi
}

# Test 29: sdlc-prompt-check redirects when files are empty stubs
test_sdlc_hook_setup_redirect_empty_stubs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    touch "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard" && ! echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh redirects to setup-wizard for empty stub files"
    else
        fail "Empty stub files should trigger setup-wizard redirect, not baseline"
    fi
}

# Test 30: Template hook redirects to setup-wizard on partial setup (one file present)
test_template_hook_setup_redirect() {
    local TEMPLATE_HOOK="$SCRIPT_DIR/../hooks/sdlc-prompt-check.sh"
    if [ ! -f "$TEMPLATE_HOOK" ]; then fail "Template hook not found"; return; fi
    local tmpdir
    tmpdir=$(mktemp -d)
    # Partial setup: only TESTING.md exists, CWD below HOME for walk-up
    mkdir -p "$tmpdir/project"
    touch "$tmpdir/project/TESTING.md"
    local output
    output=$(cd "$tmpdir/project" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" bash "$TEMPLATE_HOOK" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard"; then
        pass "Template hook redirects to setup-wizard on partial setup"
    else
        fail "Template hook should redirect to setup-wizard, got: $output"
    fi
}

# ---- Effort level recommendation tests ----

# Test 31: Wizard doc has "Effort Level" section
test_wizard_effort_level_section() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -q "## .*Effort Level" "$wizard"; then
        pass "Wizard doc has Effort Level section"
    else
        fail "Wizard doc should have an Effort Level section"
    fi
}

# Test 32: Wizard doc recommends high as default effort
test_wizard_effort_high_default() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -qi "high.*default\|default.*high" "$wizard" && grep -q "effort.*high\|high.*effort" "$wizard"; then
        pass "Wizard doc recommends high as default effort"
    else
        fail "Wizard doc should recommend high as the default effort level"
    fi
}

# Test 33: Wizard confidence table mentions /effort max for LOW confidence
test_wizard_confidence_effort_max() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -q '/effort max' "$wizard" && grep -q 'LOW' "$wizard"; then
        # Verify they appear in proximity (within the confidence table area)
        local section
        section=$(sed -n '/## Confidence Check/,/^## /p' "$wizard")
        if echo "$section" | grep -q '/effort max'; then
            pass "Wizard confidence table mentions /effort max"
        else
            fail "Wizard confidence table should mention /effort max for LOW confidence"
        fi
    else
        fail "Wizard should mention /effort max in confidence section"
    fi
}

# Test 34: SDLC skill confidence table mentions /effort max for LOW confidence
test_skill_confidence_effort_max() {
    local skill="$SCRIPT_DIR/../.claude/skills/sdlc/SKILL.md"
    local section
    section=$(sed -n '/## Confidence Check/,/^## /p' "$skill")
    if echo "$section" | grep -q '/effort max'; then
        pass "SDLC skill confidence table mentions /effort max"
    else
        fail "SDLC skill confidence table should mention /effort max for LOW confidence"
    fi
}

# ---------------------------------------------------------------------------
# SDLC Enforcement Gap Audit Tests
# Verify that documented SDLC sections have TodoWrite enforcement
# ---------------------------------------------------------------------------

SKILL_TEMPLATE="$SCRIPT_DIR/../skills/sdlc/SKILL.md"

# Test: TodoWrite checklist has "capture learnings" / "after session" task
test_todowrite_has_capture_learnings() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'capture.*learning\|after.*session\|learnings'; then
        pass "TodoWrite has capture learnings task"
    else
        fail "TodoWrite missing capture learnings task — After Session section not enforced"
    fi
}

# Test: TodoWrite checklist has scope guard / stay in lane reminder
test_todowrite_has_scope_guard() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'scope.*guard\|stay.*lane\|scope.*check\|only.*related'; then
        pass "TodoWrite has scope guard task"
    else
        fail "TodoWrite missing scope guard task — Scope Guard section not enforced"
    fi
}

# Test: TodoWrite checklist has deployment conditional tasks
test_todowrite_has_deploy_tasks() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'deploy\|post-deploy\|deployment'; then
        pass "TodoWrite has deployment tasks"
    else
        fail "TodoWrite missing deployment tasks — Deployment section not enforced"
    fi
}

# Test: TodoWrite checklist has new pattern approval check
test_todowrite_has_new_pattern_check() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'new.*pattern\|pattern.*approv\|pattern.*exist'; then
        pass "TodoWrite has new pattern approval check"
    else
        fail "TodoWrite missing new pattern check — New Pattern section not enforced"
    fi
}

# Test: TodoWrite checklist has legacy/delete code check
test_todowrite_has_legacy_delete_check() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    if echo "$todowrite_section" | grep -qi 'legacy\|delete.*old\|fallback.*code\|backward.*compat'; then
        pass "TodoWrite has legacy code delete check"
    else
        fail "TodoWrite missing legacy delete check — DELETE Legacy Code section not enforced"
    fi
}

# Test: Enforcement coverage score — count documented sections with TodoWrite tasks
# This is the "audit score" — tracks how many prose sections have enforcement
test_enforcement_coverage_score() {
    local todowrite_section
    todowrite_section=$(sed -n '/^TodoWrite(\[/,/^\])/p' "$SKILL_TEMPLATE")
    local enforced=0
    local total=12

    # Already enforced (baseline)
    echo "$todowrite_section" | grep -qi 'doc\|read.*doc' && enforced=$((enforced + 1))          # Planning: read docs
    echo "$todowrite_section" | grep -qi 'DRY\|reuse\|pattern.*exist' && enforced=$((enforced + 1)) # DRY scan
    echo "$todowrite_section" | grep -qi 'blast.*radius\|depend' && enforced=$((enforced + 1))    # Blast radius
    echo "$todowrite_section" | grep -qi 'confidence' && enforced=$((enforced + 1))                # Confidence
    echo "$todowrite_section" | grep -qi 'TDD RED\|failing test' && enforced=$((enforced + 1))    # TDD RED
    echo "$todowrite_section" | grep -qi 'self.review\|code.review' && enforced=$((enforced + 1)) # Self-review
    echo "$todowrite_section" | grep -qi 'security' && enforced=$((enforced + 1))                  # Security review

    # New enforcement (gaps we're fixing)
    echo "$todowrite_section" | grep -qi 'capture.*learning\|after.*session' && enforced=$((enforced + 1))  # After Session
    echo "$todowrite_section" | grep -qi 'scope.*guard\|stay.*lane\|scope.*check' && enforced=$((enforced + 1))   # Scope Guard
    echo "$todowrite_section" | grep -qi 'deploy' && enforced=$((enforced + 1))                    # Deploy tasks
    echo "$todowrite_section" | grep -qi 'new.*pattern\|pattern.*approv' && enforced=$((enforced + 1))  # New pattern
    echo "$todowrite_section" | grep -qi 'legacy\|delete.*old\|fallback' && enforced=$((enforced + 1))  # Legacy delete

    if [ "$enforced" -ge "$total" ]; then
        pass "Enforcement coverage: $enforced/$total documented sections have TodoWrite tasks"
    else
        fail "Enforcement coverage: $enforced/$total — missing TodoWrite tasks for $((total - enforced)) documented sections"
    fi
}

# Run all tests
test_sdlc_hook_exists
test_sdlc_hook_keywords
test_sdlc_hook_auto_invoke
test_sdlc_hook_phases
test_sdlc_hook_size
test_sdlc_hook_size_with_bump_firing
test_tdd_pretool_size_cap
test_model_effort_size_cap
test_instructions_loaded_size_cap
test_precompact_hook_exists
test_precompact_silent_without_handoff_or_git_op
test_precompact_silent_when_handoff_certified
test_precompact_blocks_on_pending_review
test_precompact_blocks_on_pending_recheck
test_precompact_blocks_on_git_rebase_in_progress
test_precompact_blocks_on_git_rebase_apply_in_progress
test_precompact_blocks_on_git_merge_in_progress
test_precompact_blocks_on_cherry_pick_in_progress
test_precompact_silent_on_stale_rebase_head_alone
test_precompact_blocks_on_rebase_head_with_rebase_merge_dir
test_precompact_size_cap
test_precompact_self_heals_on_merged_pr
test_precompact_still_blocks_on_open_pr
test_precompact_blocks_when_no_pr_number
test_precompact_blocks_when_gh_errors
test_precompact_blocks_when_gh_missing
test_precompact_unblocks_stale_pending_without_pr_number
test_precompact_still_blocks_fresh_pending_without_pr_number
test_precompact_stale_with_pr_number_prefers_self_heal
test_precompact_stale_threshold_invalid_falls_back
test_precompact_stale_threshold_override
test_precompact_self_heals_on_sha_ancestry_when_review_certified
test_precompact_blocks_when_sha_not_in_head_ancestry
test_precompact_blocks_when_sha_in_head_but_review_not_certified
test_precompact_blocks_when_review_md_missing
test_precompact_blocks_when_any_sha_not_in_head
test_precompact_blocks_on_phantom_sha_after_markdown_checkbox_in_fixes_applied
test_precompact_self_heals_with_uuid_in_fixes_applied

# Codex round 2 P1: in_string toggle wasn't escape-aware, so \" inside a
# JSON string flipped the flag prematurely. An entry containing `\"]`
# before a later phantom SHA would exit the fixes_applied array early,
# missing the phantom and false-healing.
test_precompact_blocks_on_phantom_sha_after_escaped_quote_bracket() {
    local tmpdir sha
    tmpdir=$(mktemp -d)
    sha=$(_precompact_init_repo_with_commit "$tmpdir")
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/latest-review.md" <<'MD'
score: 8/10. CERTIFIED.
MD
    # Real SHA in an entry containing escaped-quote + bracket (`\"]`),
    # then a phantom SHA on the next line. Pre-fix, the array extractor
    # exited on the `]` after the (mistakenly closed) string and missed
    # the phantom. Expected behavior: phantom SHA fails ancestry → block.
    cat > "$tmpdir/.reviews/handoff.json" <<JSON
{
  "status": "PENDING_RECHECK",
  "round": 2,
  "fixes_applied": [
    "FIXED in commit ${sha} — replaced \"foo\" with \"bar]\" in test",
    "FIXED in commit deadbeefcafe — phantom"
  ]
}
JSON
    local rc=0 stderr_out
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ]; then
        pass "#257 Codex#R2: precompact blocks when phantom SHA hides behind escaped-quote + ']' in fixes_applied"
    else
        fail "#257 Codex#R2: escaped-quote bracket should not let phantom SHA past path (c) (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_blocks_on_phantom_sha_after_escaped_quote_bracket
test_precompact_falls_through_to_stale_path_when_no_shas

# ---- #240: dry-run env vars for safe smoke-testing ----
# Consumer issue: smoke-testing hook behavior required cp'ing real
# .reviews/handoff.json + .git/ aside, fabricating fake state, restoring —
# error-prone (clobbered real handoff.json mid-test). New env vars
# SDLC_DRY_RUN_HANDOFF_STATUS and SDLC_DRY_RUN_GIT_STATE simulate state
# without touching the filesystem. Override real state when set.

test_precompact_dry_run_handoff_status_blocks_on_pending_recheck() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # Empty project — no .reviews/, no .git/. Pre-fix: hook exits 0 silent.
    # With env var: hook should treat status as PENDING_RECHECK → block.
    stderr_out=$(SDLC_DRY_RUN_HANDOFF_STATUS=PENDING_RECHECK \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -q "PENDING_RECHECK"; then
        pass "#240: SDLC_DRY_RUN_HANDOFF_STATUS=PENDING_RECHECK simulates block (rc=2)"
    else
        fail "#240: dry-run handoff status should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_handoff_status_silent_on_certified() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # Real handoff says PENDING; dry-run override says CERTIFIED → silent
    mkdir -p "$tmpdir/.reviews"
    cat > "$tmpdir/.reviews/handoff.json" <<'JSON'
{"status": "PENDING_REVIEW", "round": 1}
JSON
    stderr_out=$(SDLC_DRY_RUN_HANDOFF_STATUS=CERTIFIED \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "#240: SDLC_DRY_RUN_HANDOFF_STATUS=CERTIFIED overrides real PENDING handoff (rc=0 silent)"
    else
        fail "#240: dry-run CERTIFIED should override real PENDING (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_rebase_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # No .git/, but env var simulates rebase
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=rebase \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "rebase"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=rebase simulates rebase block (rc=2)"
    else
        fail "#240: dry-run git rebase should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_merge_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=merge \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=merge simulates merge block (rc=2)"
    else
        fail "#240: dry-run git merge should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_git_state_cherry_pick_blocks() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=cherry-pick \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "cherry"; then
        pass "#240: SDLC_DRY_RUN_GIT_STATE=cherry-pick simulates cherry-pick block (rc=2)"
    else
        fail "#240: dry-run cherry-pick should simulate block (rc=$rc, stderr='$stderr_out')"
    fi
}

# Critical: dry-run must NOT mutate real state. Run a dry-run that would
# trigger HOLD; then re-run without dry-run env vars and confirm real
# state (no handoff, no git op) returns silent rc=0.
test_precompact_dry_run_does_not_mutate_real_state() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # Run dry-run that would block. Suppress non-zero with || true so set -e
    # doesn't terminate the test runner on the expected rc=2.
    SDLC_DRY_RUN_HANDOFF_STATUS=PENDING_RECHECK \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null > /dev/null 2>&1 || true
    # Now run without dry-run → real state is empty → silent
    stderr_out=$(CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 0 ] && [ -z "$stderr_out" ]; then
        pass "#240: dry-run does not mutate real state (subsequent real run is silent)"
    else
        fail "#240: dry-run should not leave persistent state (rc=$rc, stderr='$stderr_out')"
    fi
}

# Codex round 1 P1: invalid SDLC_DRY_RUN_GIT_STATE values (typos like
# "bogus") used to skip the real .git/ check entirely — silently bypassing
# the merge-in-progress safety. Now: unknown values fall through to real
# state checks, so a typo can't disable the safety check.
test_precompact_dry_run_git_state_typo_falls_back_to_real_check() {
    local tmpdir rc=0 stderr_out
    tmpdir=$(mktemp -d)
    # Real .git/MERGE_HEAD present
    mkdir -p "$tmpdir/.git"
    touch "$tmpdir/.git/MERGE_HEAD"
    # Bogus dry-run value should NOT bypass real merge-in-progress check
    stderr_out=$(SDLC_DRY_RUN_GIT_STATE=bogus \
        CLAUDE_PROJECT_DIR="$tmpdir" \
        "$HOOKS_DIR/precompact-seam-check.sh" < /dev/null 2>&1 >/dev/null) || rc=$?
    rm -rf "$tmpdir"
    if [ "$rc" -eq 2 ] && echo "$stderr_out" | grep -qi "merge"; then
        pass "#240 Codex#1: typo in SDLC_DRY_RUN_GIT_STATE falls back to real .git/ check (no safety bypass)"
    else
        fail "#240 Codex#1: typo should fall back to real check (rc=$rc, stderr='$stderr_out')"
    fi
}

test_precompact_dry_run_handoff_status_blocks_on_pending_recheck
test_precompact_dry_run_handoff_status_silent_on_certified
test_precompact_dry_run_git_state_rebase_blocks
test_precompact_dry_run_git_state_merge_blocks
test_precompact_dry_run_git_state_cherry_pick_blocks
test_precompact_dry_run_git_state_typo_falls_back_to_real_check
test_precompact_dry_run_does_not_mutate_real_state
test_handoff_template_documents_pr_number
test_effort_bump_logs_signal_on_low_phrase
test_effort_bump_no_log_on_normal_prompt
test_effort_bump_nudge_fires_on_2_recent_signals
test_effort_bump_silent_on_1_signal
test_effort_bump_old_signals_ignored
test_effort_bump_no_log_on_ambient_mention
test_effort_bump_silent_stderr_on_unwritable_cache
test_effort_bump_prunes_stale_log_entries
test_tdd_hook_exists
test_tdd_hook_src_warning
test_tdd_hook_valid_json
test_tdd_hook_test_file_ok
test_tdd_hook_other_file_ok
test_tdd_hook_missing_path
test_instructions_hook_exists
test_instructions_hook_missing_sdlc
test_instructions_hook_missing_testing
test_instructions_hook_missing_both
test_instructions_hook_all_present
test_instructions_hook_exit_code
test_instructions_hook_no_trailing_whitespace
test_sdlc_version_metadata
test_sdlc_version_matches_wizard
test_sdlc_setup_date
test_sdlc_completed_steps
test_sdlc_hook_self_review_reference
test_sdlc_update_frequency
test_instructions_hook_mentions_setup_wizard
test_sdlc_hook_setup_redirect_missing_sdlc
test_sdlc_hook_setup_redirect_missing_testing
test_sdlc_hook_normal_when_setup_complete
test_sdlc_hook_setup_redirect_empty_stubs
test_template_hook_setup_redirect
test_wizard_effort_level_section
test_wizard_effort_high_default
test_wizard_confidence_effort_max
test_skill_confidence_effort_max

echo ""
echo "--- Update notification tests ---"

# Test 35: Shows update notification when newer version available
test_update_notification_newer_available() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Create fake npm that returns a newer version
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.22.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "update available" && echo "$output" | grep -q "1.20.0" && echo "$output" | grep -q "1.22.0"; then
        pass "Shows update notification when newer version available"
    else
        fail "Should show update notification with both versions, got: $output"
    fi
}

# Test 36: No notification when versions match
test_update_notification_same_version() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.22.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.22.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "update available"; then
        fail "Should NOT show update notification when versions match, got: $output"
    else
        pass "No update notification when versions match"
    fi
}

# Test 37: No notification when npm is not available
test_update_notification_npm_unavailable() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    # Empty bin dir — npm not in PATH
    mkdir -p "$tmpdir/bin"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -q "update available"; then
        pass "No notification and exit 0 when npm unavailable"
    else
        fail "Should silently skip when npm unavailable, exit=$exit_code, got: $output"
    fi
}

# Test 38: No notification when npm fails (e.g., network error)
test_update_notification_npm_fails() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    local exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ] && ! echo "$output" | grep -q "update available"; then
        pass "No notification and exit 0 when npm fails"
    else
        fail "Should silently skip when npm fails, exit=$exit_code, got: $output"
    fi
}

# Test 39: No notification when SDLC.md lacks version metadata
test_update_notification_no_version_metadata() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC Config" > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nif echo "$@" | grep -q "claude-code"; then echo "2.1.90"; else echo "1.22.0"; fi\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\necho "2.1.90 (Claude Code)"\n' > "$tmpdir/bin/claude"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "Wizard.*update available"; then
        fail "Should NOT show wizard notification when SDLC.md has no version metadata, got: $output"
    else
        pass "No notification when SDLC.md lacks version metadata"
    fi
}

# Test 40: Update notification mentions /update-wizard
test_update_notification_mentions_update_wizard() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.20.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.22.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "/update-wizard"; then
        pass "Update notification mentions /update-wizard"
    else
        fail "Update notification should mention /update-wizard, got: $output"
    fi
}

# Test (ROADMAP #196): Loud staleness nudge when ≥3 minor versions behind.
# User feedback 2026-04-18: the 1-line "update available" nudge is too easy
# to skip — users went months without running /update. This test drives a
# stronger, multi-line warning when the gap is material (≥3 minor versions).
test_update_notification_loud_when_3_minor_behind() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Louder format must mention the exact delta (9 here) AND use stronger
    # language than the one-line fallback. Require both an explicit "behind"
    # count and a WARNING/!! marker so the nudge stands out.
    echo "$output" | grep -qE '(9.*minor.*behind|behind.*9.*minor|9[[:space:]]*versions.*behind)' || ok=false
    echo "$output" | grep -qE 'WARNING|!!|⚠|strongly recommend' || ok=false
    echo "$output" | grep -q '/update-wizard' || ok=false
    if [ "$ok" = true ]; then
        pass "Loud nudge fires when ≥3 minor versions behind (1.25.0 → 1.34.0)"
    else
        fail "Expected loud '9 minor versions behind' nudge, got: $output"
    fi
}

# Companion: mild nudge (1-2 minor behind) does NOT print the loud markers.
# This ensures we don't over-warn on small gaps.
test_update_notification_mild_when_2_minor_behind() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.32.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Must still mention the update is available
    echo "$output" | grep -q "update available" || ok=false
    # Must NOT include the loud markers
    if echo "$output" | grep -qE 'minor.*behind|strongly recommend'; then
        ok=false
    fi
    if [ "$ok" = true ]; then
        pass "Mild nudge (no loud markers) for 2 minor versions behind"
    else
        fail "Expected mild one-line nudge for 2-minor gap, got: $output"
    fi
}

# Cache: npm is only called once per 24h. On second invocation with a fresh
# cache file, the hook must use the cached value instead of re-invoking npm.
test_update_notification_uses_daily_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # npm returns 1.34.0 on first call; on second call it would return
    # nothing (we replace the binary to prove the cache is used).
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    # First run — populates cache
    (cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" > /dev/null 2>/dev/null)
    # Replace npm with one that fails — forces the hook to use the cache or skip
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    # Second run — should still see the loud nudge because cache is <24h old
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'minor.*behind'; then
        pass "Second invocation uses daily cache (no re-fetch from npm)"
    else
        fail "Second invocation should use cached latest version, got: $output"
    fi
}

# Codex round 1 (P1): malformed cache contents (whitespace, non-version like
# "junk") were being treated as valid, producing "Latest: junk" / bogus
# "99 behind" output. Strict semver validation must reject non-x.y.z content
# and fall back to npm.
test_update_notification_rejects_malformed_cache_junk() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Seed cache with garbage — must be ignored, npm must be called
    printf 'junk' > "$tmpdir/cache/latest-version"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    # Must NOT leak "junk" into output
    if echo "$output" | grep -q 'junk'; then ok=false; fi
    # Must fall back to npm and produce real 1.34.0 nudge
    echo "$output" | grep -q '1.34.0' || ok=false
    if [ "$ok" = true ]; then
        pass "Malformed cache ('junk') is rejected and npm refetched"
    else
        fail "Expected malformed cache to be ignored, got: $output"
    fi
}

test_update_notification_rejects_malformed_cache_whitespace() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Whitespace-only cache contents — must be rejected
    printf '   \n' > "$tmpdir/cache/latest-version"
    printf '#!/bin/bash\necho "1.34.0"\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Must not print "99 behind" (which would indicate whitespace → major-bump delta)
    if echo "$output" | grep -qE '99.*minor.*behind'; then
        fail "Whitespace cache leaked through, got: $output"
    else
        pass "Whitespace-only cache is rejected"
    fi
}

# Codex round 1 (P2): npm returning a non-numeric minor field (e.g.
# "1.alpha.0") must not run delta math. awk '$2+0' silently coerces alpha
# to 0, producing nonsense output. Strict semver gate must reject.
test_update_notification_rejects_non_numeric_minor() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.25.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin"
    # Stub returns non-numeric minor ONLY for the wizard package; anything
    # else (e.g. the CC version check later in the hook) errors silently so
    # we're only exercising the wizard-version path.
    cat > "$tmpdir/bin/npm" <<'NPMEOF'
#!/bin/bash
if [[ "$*" == *"agentic-sdlc-wizard"* ]]; then
    echo "1.alpha.0"
else
    exit 1
fi
NPMEOF
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    # Must not surface "1.alpha.0" to the user or compute a bogus delta
    if echo "$output" | grep -q '1.alpha.0'; then
        fail "Non-numeric version leaked to output, got: $output"
    elif echo "$output" | grep -qE 'SDLC Wizard update available|minor.*behind'; then
        fail "Expected silent skip on invalid npm response, got: $output"
    else
        pass "Non-numeric minor field (1.alpha.0) is rejected silently"
    fi
}

# Test (#254 Bug 2 / #239): when cached "latest" < installed (cache poison
# post-upgrade, or stale-but-not-expired cache after a release), the hook MUST
# stay silent — never emit a reverse "update available" nudge. Previous
# behavior printed "1.42.1 → 1.41.1" because line 80 used `!=` equality.
test_update_notification_silent_when_installed_newer_than_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.43.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # Cache holds an older version (post-upgrade scenario)
    printf '1.41.1' > "$tmpdir/cache/latest-version"
    # Make sure the file looks fresh so the cache age check passes
    touch "$tmpdir/cache/latest-version"
    # npm should not be called — but stub it just in case
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'update available|minor.*behind'; then
        fail "#254 Bug 2: Hook emitted reverse nudge when installed > latest, got: $output"
    else
        pass "#254 Bug 2: Hook silent when installed (1.43.0) > cached latest (1.41.1)"
    fi
}

# Test (#239): when npm view fails AND cache is missing/stale, the hook should
# surface the failure once (one-line warning) instead of silently serving
# nothing. Currently the version-check block produces no output at all in
# this state — user has no way to know the nudge mechanism is broken.
test_update_notification_surfaces_npm_failure() {
    local tmpdir
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.30.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/bin" "$tmpdir/cache"
    # No cache file; npm fails with EPERM-style error
    cat > "$tmpdir/bin/npm" <<'NPMEOF'
#!/bin/bash
echo "npm error code EPERM" >&2
exit 1
NPMEOF
    chmod +x "$tmpdir/bin/npm"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>&1)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'npm view failed|npm.*unavailable|version check unavailable'; then
        pass "#239: Hook surfaces npm failure with one-line warning when cache miss"
    else
        fail "#239: Expected one-line warning on npm failure, got: $output"
    fi
}

test_update_notification_newer_available
test_update_notification_same_version
test_update_notification_npm_unavailable
test_update_notification_npm_fails
test_update_notification_no_version_metadata
test_update_notification_mentions_update_wizard
test_update_notification_loud_when_3_minor_behind
test_update_notification_mild_when_2_minor_behind
test_update_notification_uses_daily_cache
test_update_notification_rejects_malformed_cache_junk
test_update_notification_rejects_malformed_cache_whitespace
test_update_notification_rejects_non_numeric_minor
test_update_notification_silent_when_installed_newer_than_cache
test_update_notification_surfaces_npm_failure

echo ""
echo "--- Hook if-conditional tests (#68) ---"

# Test: settings.json PreToolUse hook has `if` field
test_settings_has_if_field() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    if [ -n "$if_value" ]; then
        pass "settings.json PreToolUse hook has 'if' field"
    else
        fail "settings.json PreToolUse hook should have 'if' field for conditional filtering"
    fi
}

# Test: if field targets workflow files (*.yml in .github/workflows/)
test_if_field_targets_workflows() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    if echo "$if_value" | grep -qF '.github/workflows/'; then
        pass "if field targets .github/workflows/ files"
    else
        fail "if field should target .github/workflows/ files, got: $if_value"
    fi
}

# Test: CLI template settings.json also has if field
test_template_settings_has_if_field() {
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local if_value
    if_value=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$template")
    if [ -n "$if_value" ]; then
        pass "CLI template settings.json PreToolUse hook has 'if' field"
    else
        fail "CLI template settings.json should have 'if' field matching repo settings"
    fi
}

# Test: Wizard doc documents the if field
test_wizard_documents_if_field() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    if grep -q '"if"' "$wizard" || grep -q '`if`.*field\|`if`.*hook\|hook.*`if`' "$wizard"; then
        pass "Wizard doc documents the if field"
    else
        fail "Wizard doc should document the hook if field"
    fi
}

# Test: Wizard settings.json example includes if field
test_wizard_settings_example_has_if() {
    local wizard="$SCRIPT_DIR/../CLAUDE_CODE_SDLC_WIZARD.md"
    # The settings.json code block in the wizard should show the if field
    if grep -q '"if":' "$wizard"; then
        pass "Wizard settings.json example includes if field"
    else
        fail "Wizard settings.json example should include the if field"
    fi
}

# Test: if field in repo settings matches template settings (parity)
test_if_field_parity() {
    local settings="$SCRIPT_DIR/../.claude/settings.json"
    local template="$SCRIPT_DIR/../cli/templates/settings.json"
    local repo_if template_if
    repo_if=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$settings")
    template_if=$(jq -r '.hooks.PreToolUse[0].hooks[0].if // empty' "$template")
    # Template uses /src/ pattern, repo uses .github/workflows/ — both should have if field
    # but values differ because repo is customized for this meta-project
    if [ -n "$repo_if" ] && [ -n "$template_if" ]; then
        pass "Both repo and template settings have if field (parity check)"
    else
        fail "Both repo ($repo_if) and template ($template_if) should have if field"
    fi
}

test_settings_has_if_field
test_if_field_targets_workflows
test_template_settings_has_if_field
test_wizard_documents_if_field
test_wizard_settings_example_has_if
test_if_field_parity

echo ""
echo "--- CWD walk-up tests (#171: monorepo / nested project support) ---"

# Test: Shared helper _find-sdlc-root.sh exists
test_find_sdlc_root_helper_exists() {
    if [ -f "$HOOKS_DIR/_find-sdlc-root.sh" ]; then
        pass "_find-sdlc-root.sh helper exists"
    else
        fail "_find-sdlc-root.sh helper not found (needed by sdlc-prompt-check + instructions-loaded-check)"
    fi
}

# Test: sdlc-prompt-check walks up from CWD to find nested SDLC.md
test_sdlc_hook_cwd_walkup_finds_nested() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Project at $tmpdir/project/, but CLAUDE_PROJECT_DIR is empty (simulates parent launch)
    mkdir -p "$tmpdir/project/src/components"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    local output
    # Run hook from deep inside the project — CWD walk should find SDLC.md
    output=$(cd "$tmpdir/project/src/components" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE" && ! echo "$output" | grep -q "SETUP NOT COMPLETE"; then
        pass "sdlc-prompt-check.sh walks up from CWD to find nested SDLC.md"
    else
        fail "sdlc-prompt-check.sh should walk up from CWD when CLAUDE_PROJECT_DIR is empty"
    fi
}

# Test: CWD walk-up prefers nearest SDLC.md (monorepo with per-package setup)
test_sdlc_hook_cwd_walkup_prefers_nearest() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # Monorepo root has SDLC.md, but sub-package also has its own
    echo "# Root SDLC" > "$tmpdir/SDLC.md"
    echo "# Root Testing" > "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/packages/api/src"
    echo "# API SDLC" > "$tmpdir/packages/api/SDLC.md"
    echo "# API Testing" > "$tmpdir/packages/api/TESTING.md"
    local output
    # CWD is deep inside packages/api — should find packages/api/SDLC.md first
    output=$(cd "$tmpdir/packages/api/src" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "SDLC BASELINE"; then
        pass "sdlc-prompt-check.sh prefers nearest SDLC.md in monorepo"
    else
        fail "Should find nearest SDLC.md when multiple exist in ancestor chain"
    fi
}

# Test: Falls back to CLAUDE_PROJECT_DIR when CWD walk finds nothing
test_sdlc_hook_cwd_walkup_fallback() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # CWD has nothing — hook should exit silently (#173: no fallback to CLAUDE_PROJECT_DIR)
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "sdlc-prompt-check.sh exits silently when CWD walk finds no SDLC project"
    else
        fail "Should exit silently when CWD walk finds nothing, got: $(echo "$output" | head -1)"
    fi
}

# Test: instructions-loaded-check also walks up from CWD
test_instructions_hook_cwd_walkup() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/project/src"
    # Use the CURRENT wizard version from package.json so the staleness nudge
    # (≥3 minor behind = loud warning) never fires. Version drift between
    # test fixture + current release was a foot-gun pre-fix (the loud nudge
    # contains "missing" which spuriously triggered the negative grep below).
    local current_version
    current_version=$(grep -oE '"version":\s*"[0-9.]+"' "$SCRIPT_DIR/../package.json" | grep -oE '[0-9.]+')
    echo "<!-- SDLC Wizard Version: ${current_version} -->" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    # Mock npm/claude/codex to prevent version check output
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir/project/src" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ] || ! echo "$output" | grep -qi "missing"; then
        pass "instructions-loaded-check.sh walks up from CWD (no false warning)"
    else
        fail "instructions-loaded-check.sh should walk up from CWD, got: $output"
    fi
}

# Test: CWD walk-up with empty SDLC.md still triggers setup (non-empty check preserved)
test_sdlc_hook_cwd_walkup_empty_stubs() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/project/src"
    touch "$tmpdir/project/SDLC.md"   # empty
    touch "$tmpdir/project/TESTING.md" # empty
    local output
    output=$(cd "$tmpdir/project/src" && CLAUDE_PROJECT_DIR="" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q "setup-wizard"; then
        pass "CWD walk-up still triggers setup for empty stub files"
    else
        fail "Empty stubs found by CWD walk should still trigger setup-wizard"
    fi
}

# Test: Non-SDLC directory — hooks silent when walk-up finds nothing (#173)
test_sdlc_hook_silent_non_sdlc_dir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # CWD has no SDLC.md anywhere up to $HOME, CLAUDE_PROJECT_DIR unset
    local output
    output=$(cd "$tmpdir" && CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/sdlc-prompt-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "sdlc-prompt-check.sh silent in non-SDLC directory (#173)"
    else
        fail "sdlc-prompt-check.sh should be silent in non-SDLC dir, got: $(echo "$output" | head -1)"
    fi
}

# Test: instructions-loaded-check silent in non-SDLC directory (#173)
test_instructions_hook_silent_non_sdlc_dir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    local output
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "instructions-loaded-check.sh silent in non-SDLC directory (#173)"
    else
        fail "instructions-loaded-check.sh should be silent in non-SDLC dir, got: $(echo "$output" | head -1)"
    fi
}

test_find_sdlc_root_helper_exists
test_sdlc_hook_cwd_walkup_finds_nested
test_sdlc_hook_cwd_walkup_prefers_nearest
test_sdlc_hook_cwd_walkup_fallback
test_instructions_hook_cwd_walkup
test_sdlc_hook_cwd_walkup_empty_stubs
test_sdlc_hook_silent_non_sdlc_dir
test_instructions_hook_silent_non_sdlc_dir

echo ""
echo "--- Model/effort upgrade detection (#179) ---"

# Test: model-effort-check.sh exists and is executable
test_model_effort_check_exists() {
    if [ -x "$HOOKS_DIR/model-effort-check.sh" ]; then
        pass "model-effort-check.sh exists and is executable"
    else
        fail "model-effort-check.sh not found or not executable"
    fi
}

# Test: detects stale effort and outputs upgrade nudge with model recommendation.
# The nudge must name the opus[1m] alias specifically so the command is copy-pasteable.
test_model_effort_check_stale_effort() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '/effort' \
        && echo "$output" | grep -q 'recommended model' \
        && echo "$output" | grep -qF 'opus[1m]'; then
        pass "model-effort-check.sh nudges effort + recommends opus[1m] when effort is stale"
    else
        fail "model-effort-check.sh should nudge /effort and recommend 'opus[1m]', got: $output"
    fi
}

# Test: silent when effort is already current
test_model_effort_check_silent_when_current() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"xhigh"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "model-effort-check.sh silent when effort is current"
    else
        fail "model-effort-check.sh should be silent when current, got: $output"
    fi
}

# Test: graceful when no JSON stdin (non-blocking)
test_model_effort_check_no_stdin() {
    local exit_code
    echo "" | "$HOOKS_DIR/model-effort-check.sh" > /dev/null 2>&1
    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        pass "model-effort-check.sh exits 0 when stdin is empty"
    else
        fail "model-effort-check.sh should exit 0 on empty stdin, got exit $exit_code"
    fi
}

# Test: settings.json has SessionStart hook wired
test_settings_has_session_start_hook() {
    local SETTINGS="$SCRIPT_DIR/../.claude/settings.json"
    if [ ! -f "$SETTINGS" ]; then fail "settings.json not found"; return; fi
    if grep -q '"SessionStart"' "$SETTINGS" && grep -q 'model-effort-check.sh' "$SETTINGS"; then
        pass "settings.json wires SessionStart hook to model-effort-check.sh"
    else
        fail "settings.json should have SessionStart hook for model-effort-check.sh"
    fi
}

# Test: nested CWD uses CLAUDE_PROJECT_DIR for settings (Codex P0 fix)
test_model_effort_check_nested_cwd() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude" "$tmpdir/src/deep"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(cd "$tmpdir/src/deep" && echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="/nonexistent" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q '/effort'; then
        pass "model-effort-check.sh finds project settings via CLAUDE_PROJECT_DIR from nested CWD"
    else
        fail "model-effort-check.sh should find project settings from nested CWD, got: $output"
    fi
}

# Test: settings.json precedence — local overrides project
test_model_effort_check_local_overrides_project() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"high"}' > "$tmpdir/.claude/settings.json"
    echo '{"effortLevel":"xhigh"}' > "$tmpdir/.claude/settings.local.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="/nonexistent" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "model-effort-check.sh respects local settings override (xhigh from local, silent)"
    else
        fail "model-effort-check.sh should respect local settings.json override, got: $output"
    fi
}

# Test: effort=max is silent (preferred; above the floor, no nudge needed)
# Per ROADMAP #217: xhigh is the floor, max is preferred. Anything at-or-above the
# floor should produce no output.
test_model_effort_check_max_is_silent() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"effortLevel":"max"}' > "$tmpdir/.claude/settings.json"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if [ -z "$output" ]; then
        pass "model-effort-check.sh silent when effort=max (preferred, above floor)"
    else
        fail "model-effort-check.sh should be silent when effort=max, got: $output"
    fi
}

# Test: below-xhigh produces LOUD warning mentioning SDLC compliance + /effort max
# Per ROADMAP #217: below-xhigh breaks SDLC compliance on Opus 4.7 (shallow reasoning,
# skipped TDD, dropped self-review). Hook must produce a distinguishable WARNING that
# recommends /effort max (not just the soft "upgrade available" nudge).
test_model_effort_check_below_xhigh_loud_warning() {
    local tmpdir
    tmpdir=$(mktemp -d)
    local fails=0
    for bad_effort in high medium low; do
        mkdir -p "$tmpdir/.claude"
        echo "{\"effortLevel\":\"$bad_effort\"}" > "$tmpdir/.claude/settings.json"
        local output
        output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/model-effort-check.sh" 2>/dev/null)
        # Must contain: WARNING marker, SDLC mention, explicit /effort max recommendation
        if ! echo "$output" | grep -q 'WARNING'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing WARNING marker: $output" >&2
        fi
        if ! echo "$output" | grep -qi 'SDLC'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing SDLC mention: $output" >&2
        fi
        if ! echo "$output" | grep -q '/effort max'; then
            fails=$((fails+1))
            echo "  [$bad_effort] missing '/effort max' recommendation: $output" >&2
        fi
        rm -rf "$tmpdir/.claude"
    done
    rm -rf "$tmpdir"
    if [ "$fails" -eq 0 ]; then
        pass "model-effort-check.sh produces LOUD WARNING + SDLC + /effort max for high/medium/low"
    else
        fail "model-effort-check.sh LOUD warning has $fails missing markers across high/medium/low"
    fi
}

# Regression test (ROADMAP #217): instructions-loaded-check.sh must NOT emit its
# own effort/model nudge. The duplicate check used the old xhigh-as-recommended
# logic, so effort=max produced a false "Upgrade available" nudge. Single source
# of truth is hooks/model-effort-check.sh.
test_instructions_loaded_no_duplicate_effort_nudge() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Effort=max should be silent; the duplicate in instructions-loaded used to
    # flag it as needing upgrade to xhigh, which is backwards post-#217.
    echo '{"effortLevel":"max"}' > "$tmpdir/.claude/settings.json"
    # instructions-loaded-check needs SDLC.md to proceed past its own gate
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local output
    output=$(echo '{}' | CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -q 'Upgrade available: effort'; then
        fail "instructions-loaded-check.sh emitted stale 'Upgrade available: effort' nudge — should delegate to model-effort-check.sh (#217)"
    elif echo "$output" | grep -q 'effort.*→.*xhigh'; then
        fail "instructions-loaded-check.sh recommends xhigh — stale per #217 (max is preferred, xhigh is floor)"
    else
        pass "instructions-loaded-check.sh does not duplicate effort/model nudge (delegated to model-effort-check.sh per #217)"
    fi
}

test_model_effort_check_exists
test_model_effort_check_stale_effort
test_model_effort_check_silent_when_current
test_model_effort_check_max_is_silent
test_model_effort_check_below_xhigh_loud_warning
test_model_effort_check_no_stdin
test_settings_has_session_start_hook
test_model_effort_check_nested_cwd
test_model_effort_check_local_overrides_project
test_instructions_loaded_no_duplicate_effort_nudge

# ROADMAP token-bloat audit: prevent 2× per-prompt hook print when both
# project (.claude/settings.json) and plugin (hooks.json) register the same
# hook (e.g., the wizard's own dogfood + locally-installed plugin).
# Helper: dedupe_plugin_or_project — plugin invocation yields if project also
# registers the same hook. Project always wins; consumer plugin-only installs
# still fire normally.
test_dedupe_plugin_yields_to_project() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"$CLAUDE_PROJECT_DIR/hooks/sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        fail "plugin invocation should yield (return 1) when project settings.json registers same hook"
    else
        pass "plugin invocation yields to project registration (no double-print)"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_plugin_proceeds_when_no_project_registration() {
    local tmpdir
    tmpdir=$(mktemp -d)
    # No .claude/settings.json — consumer plugin-only install
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "plugin proceeds when no project settings.json (consumer plugin-only)"
    else
        fail "plugin should proceed when no project registration exists"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_plugin_proceeds_when_project_settings_unrelated() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # Project settings.json exists but doesn't register THIS hook
    echo '{"hooks":{"PostToolUse":[{"hooks":[{"command":"some-other-hook.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/somebody/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "plugin proceeds when project settings exists but doesn't register this hook"
    else
        fail "plugin should proceed when project settings doesn't reference this hook by name"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_project_invocation_always_proceeds() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local non_plugin_path="/Users/somebody/myrepo/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$non_plugin_path" "$tmpdir"; then
        pass "project (non-plugin) invocation always proceeds regardless of settings"
    else
        fail "non-plugin invocation should never yield"
    fi
    rm -rf "$tmpdir"
}

test_dedupe_recognizes_plugins_cache_path() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    echo '{"hooks":{"UserPromptSubmit":[{"hooks":[{"command":"sdlc-prompt-check.sh"}]}]}}' > "$tmpdir/.claude/settings.json"
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    # Marketplace install path uses /plugins/cache/ instead of /plugins-local/
    local fake_cache_path="/Users/somebody/.claude/plugins/cache/sdlc-wizard-local/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_cache_path" "$tmpdir"; then
        fail "marketplace plugin path (/plugins/cache/) should also yield"
    else
        pass "marketplace plugin path (/plugins/cache/) yields to project"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-001 regression (Codex round 1): helper must not depend on `basename`.
# Uses parameter expansion so it survives PATH-restricted test environments.
test_dedupe_works_with_path_restricted() {
    # Static-analysis test (Codex DEDUPE-001): the dedupe helper must NOT call
    # external `basename` — it must use parameter expansion `${path##*/}`.
    # Direct PATH-restriction simulation is unreliable on macOS (Gatekeeper
    # kills cp'd /usr/bin/grep), so we verify the property statically: the
    # helper's source code uses parameter expansion and contains no basename.
    local helper="$HOOKS_DIR/_find-sdlc-root.sh"
    local fails=0
    # Match a basename invocation in CODE (not in comments): grep non-comment
    # lines for `$(basename` or backtick-basename subshell forms.
    if /usr/bin/grep -vE '^\s*#' "$helper" | /usr/bin/grep -qE '\$\(basename|`basename' 2>/dev/null; then
        fails=$((fails + 1))
        echo "  helper still calls external 'basename' command" >&2
    fi
    if ! /usr/bin/grep -q 'script_path##\*/' "$helper" 2>/dev/null; then
        fails=$((fails + 1))
        echo "  helper missing parameter-expansion form '\${script_path##*/}'" >&2
    fi
    if [ "$fails" -eq 0 ]; then
        pass "dedupe helper uses parameter expansion, no external 'basename' (PATH-restricted safe)"
    else
        fail "dedupe helper has $fails parameter-expansion regressions (#DEDUPE-001)"
    fi
}

# DEDUPE-002 regression (Codex round 1): script-name match must be scoped to
# `"command"` JSON entries, not anywhere in settings.json. Otherwise a hook
# basename appearing in `permissions.allow` falsely triggers yield.
test_dedupe_does_not_match_basename_in_permissions() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    # settings.json mentions "sdlc-prompt-check.sh" only in permissions.allow,
    # NOT in any hook command registration.
    cat > "$tmpdir/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(./hooks/sdlc-prompt-check.sh *)"]
  },
  "hooks": {
    "PostToolUse": [
      {"hooks": [{"command": "some-other-hook.sh"}]}
    ]
  }
}
JSON
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/x/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        pass "dedupe ignores script name in permissions.allow (project does not register the hook)"
    else
        fail "dedupe falsely yielded — script name in permissions.allow should not count as registration"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-002 positive: still yields when the basename appears in a real
# `"command"` registration (the legitimate dual-install scenario).
test_dedupe_matches_command_field_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    mkdir -p "$tmpdir/.claude"
    cat > "$tmpdir/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {"hooks": [{"command": "$CLAUDE_PROJECT_DIR/hooks/sdlc-prompt-check.sh"}]}
    ]
  }
}
JSON
    # shellcheck disable=SC1090
    source "$HOOKS_DIR/_find-sdlc-root.sh"
    local fake_plugin_path="/Users/x/.claude/plugins-local/sdlc-wizard-wrap/plugins/sdlc-wizard/hooks/sdlc-prompt-check.sh"
    if dedupe_plugin_or_project "$fake_plugin_path" "$tmpdir"; then
        fail "dedupe should yield when basename appears in a hook \"command\" registration"
    else
        pass "dedupe matches \"command\" field correctly (legitimate dual-install yields)"
    fi
    rm -rf "$tmpdir"
}

# DEDUPE-003 regression: hook scripts must source helper correctly even when
# invoked directly from the hooks/ directory (BASH_SOURCE[0] has no slash).
test_dedupe_hook_direct_invocation_no_slash() {
    # Run sdlc-prompt-check.sh via bash from inside hooks/ where BASH_SOURCE[0]
    # is just the filename — the no-slash fallback to "." must source helper.
    local tmpdir
    tmpdir=$(mktemp -d)
    echo "# SDLC" > "$tmpdir/SDLC.md"
    echo "# Testing" > "$tmpdir/TESTING.md"
    local rc=0 stderr_out
    stderr_out=$(cd "$HOOKS_DIR" && CLAUDE_PROJECT_DIR="$tmpdir" bash -c './sdlc-prompt-check.sh </dev/null' 2>&1) || rc=$?
    rm -rf "$tmpdir"
    # Expect rc=0 AND no "No such file or directory" for _find-sdlc-root.sh
    if [ "$rc" -eq 0 ] && ! echo "$stderr_out" | grep -q 'No such file'; then
        pass "hook handles direct invocation with no-slash BASH_SOURCE (sources helper via . fallback)"
    else
        fail "hook failed direct invocation (rc=$rc, stderr='$stderr_out')"
    fi
}

test_dedupe_plugin_yields_to_project
test_dedupe_plugin_proceeds_when_no_project_registration
test_dedupe_plugin_proceeds_when_project_settings_unrelated
test_dedupe_project_invocation_always_proceeds
test_dedupe_recognizes_plugins_cache_path
test_dedupe_works_with_path_restricted
test_dedupe_does_not_match_basename_in_permissions
test_dedupe_matches_command_field_only
test_dedupe_hook_direct_invocation_no_slash

echo ""
echo "--- SDLC enforcement gap audit ---"
test_todowrite_has_capture_learnings
test_todowrite_has_scope_guard
test_todowrite_has_deploy_tasks
test_todowrite_has_new_pattern_check
test_todowrite_has_legacy_delete_check
test_enforcement_coverage_score

echo ""
echo "--- Dual-channel install drift guardrails (#181) ---"

# Helper: create a fake project + fake HOME with plugin install path
prepare_dual_install_fixture() {
    local tmpdir="$1"
    local plugin_which="$2"  # "local", "cache", "both", or "none"
    local has_cli_skills="$3"  # "yes" or "no"
    mkdir -p "$tmpdir/project"
    touch "$tmpdir/project/SDLC.md"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    if [ "$has_cli_skills" = "yes" ]; then
        mkdir -p "$tmpdir/project/.claude/skills/update"
        echo "# Update skill" > "$tmpdir/project/.claude/skills/update/SKILL.md"
    fi
    mkdir -p "$tmpdir/.claude"
    if [ "$plugin_which" = "local" ] || [ "$plugin_which" = "both" ]; then
        mkdir -p "$tmpdir/.claude/plugins-local/sdlc-wizard-wrap"
    fi
    if [ "$plugin_which" = "cache" ] || [ "$plugin_which" = "both" ]; then
        mkdir -p "$tmpdir/.claude/plugins/cache/sdlc-wizard-local"
    fi
    # Mock npm/claude/codex so version/update checks are silent
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
}

# Test: hook emits dual-install nudge when BOTH CLI skills and plugin paths exist
test_instructions_hook_dual_install_nudge_local() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "local" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "dual-install\|both channels\|plugin.*and.*CLI\|CLI.*and.*plugin\|pick one"; then
        pass "instructions-loaded-check.sh emits dual-install nudge (plugins-local)"
    else
        fail "Should emit dual-install nudge when CLI skills + plugins-local present, got: $output"
    fi
}

# Test: hook emits dual-install nudge when plugin cache path exists
test_instructions_hook_dual_install_nudge_cache() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "cache" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qi "dual-install\|both channels\|plugin.*and.*CLI\|CLI.*and.*plugin\|pick one"; then
        pass "instructions-loaded-check.sh emits dual-install nudge (plugins cache)"
    else
        fail "Should emit dual-install nudge when CLI skills + plugin cache present, got: $output"
    fi
}

# Test: hook silent when only plugin installed (no CLI skills in project)
test_instructions_hook_silent_plugin_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "no"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "instructions-loaded-check.sh silent when plugin-only (no CLI skills)"
    else
        fail "Should NOT emit dual-install nudge when only plugin present, got: $output"
    fi
}

# Test: hook silent when only CLI skills installed (no plugin paths)
test_instructions_hook_silent_cli_only() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "none" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "instructions-loaded-check.sh silent when CLI-only (no plugin paths)"
    else
        fail "Should NOT emit dual-install nudge when only CLI skills present, got: $output"
    fi
}

# Test: dual-install nudge is non-blocking (exit 0)
test_instructions_hook_dual_install_non_blocking() {
    local tmpdir exit_code
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    (cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh") > /dev/null 2>&1
    exit_code=$?
    rm -rf "$tmpdir"
    if [ "$exit_code" -eq 0 ]; then
        pass "instructions-loaded-check.sh dual-install nudge is non-blocking (exit 0)"
    else
        fail "Hook should exit 0 even with dual-install nudge (exit=$exit_code)"
    fi
}

# Test (#238): dual-channel nudge stays silent when the user has explicitly
# acknowledged the dual-install setup via a sentinel file. Without this
# silence mechanism, the warning fires on every SessionStart and trains
# users to ignore all hook output — including legit signals.
test_instructions_hook_dual_install_silenced_by_ack_sentinel() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # User acknowledged the dual-install setup
    mkdir -p "$tmpdir/cache"
    touch "$tmpdir/cache/dual-channel-acknowledged"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if ! echo "$output" | grep -qi "dual-install\|both channels\|pick one"; then
        pass "#238: dual-install nudge silenced by ack sentinel"
    else
        fail "#238: ack sentinel should silence dual-install nudge, got: $output"
    fi
}

# Test (#238): mention the silence mechanism in the dual-install nudge so
# users know how to acknowledge it (otherwise the sentinel is undiscoverable).
test_instructions_hook_dual_install_nudge_mentions_silence() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # No sentinel — nudge should fire and reference the silence path
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE 'dual-channel-acknowledged|silence.*nudge|to silence|acknowledge'; then
        pass "#238: dual-install nudge mentions how to silence it"
    else
        fail "#238: nudge should reference the ack sentinel path, got: $output"
    fi
}

# Test (#238 Codex finding 1): the printed silence hint must work even when
# the cache dir doesn't exist yet (fresh install on a new host has no
# ~/.cache/sdlc-wizard/ until something creates it). Plain `touch <path>`
# fails with "No such file or directory" when the parent dir is missing.
test_instructions_hook_dual_install_silence_hint_works_when_cache_dir_absent() {
    local tmpdir nudge ack_cmd
    tmpdir=$(mktemp -d)
    prepare_dual_install_fixture "$tmpdir" "both" "yes"
    # Deliberately do NOT create $tmpdir/cache — simulate fresh install
    if [ -d "$tmpdir/cache" ]; then
        rm -rf "$tmpdir/cache"
    fi
    nudge=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    # Extract the line that contains the ack command. The hint must be
    # actionable: running the printed command should succeed even with
    # a missing cache dir.
    ack_cmd=$(echo "$nudge" | grep -E 'Keep both' | sed 's/.*Keep both:[[:space:]]*//;s/[[:space:]]*(silences.*$//')
    if [ -z "$ack_cmd" ]; then
        fail "#238 Codex#1: no 'Keep both' silence hint in nudge output"
        rm -rf "$tmpdir"
        return
    fi
    # Run the suggested command. If it fails (e.g. cache dir missing),
    # the hint is broken.
    bash -c "$ack_cmd" 2>/dev/null
    local rc=$?
    if [ "$rc" -eq 0 ] && [ -f "$tmpdir/cache/dual-channel-acknowledged" ]; then
        pass "#238 Codex#1: silence hint works even with missing cache dir"
    else
        fail "#238 Codex#1: printed silence command failed (rc=$rc) — hint should mkdir -p first. Cmd: $ack_cmd"
    fi
    rm -rf "$tmpdir"
}

test_instructions_hook_dual_install_nudge_local
test_instructions_hook_dual_install_nudge_cache
test_instructions_hook_silent_plugin_only
test_instructions_hook_silent_cli_only
test_instructions_hook_dual_install_non_blocking
test_instructions_hook_dual_install_silenced_by_ack_sentinel
test_instructions_hook_dual_install_nudge_mentions_silence
test_instructions_hook_dual_install_silence_hint_works_when_cache_dir_absent

# Test (#207): when settings.json has BOTH `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`
# AND `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, the hook must warn about the
# compound misconfiguration. Setting both compounds (e.g. 30% × 400K = 120K
# trigger, which is ~12% of a 1M window) — a docs footgun the consumer
# (issue #207) hit in practice when autocompact fired at 12% context.
test_instructions_hook_warns_on_autocompact_compound_misconfig() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "model": "opus[1m]",
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    local ok=true
    echo "$output" | grep -qiE 'autocompact|AUTOCOMPACT' || ok=false
    echo "$output" | grep -q 'CLAUDE_AUTOCOMPACT_PCT_OVERRIDE' || ok=false
    echo "$output" | grep -q 'CLAUDE_CODE_AUTO_COMPACT_WINDOW' || ok=false
    echo "$output" | grep -qE 'compound|combined|both|alternative|pick one|either' || ok=false
    if [ "$ok" = true ]; then
        pass "#207: warns when settings.json has both PCT_OVERRIDE + AUTO_COMPACT_WINDOW"
    else
        fail "#207: expected compound-misconfig warning, got: $output"
    fi
}

test_instructions_hook_silent_on_single_autocompact_pct_only() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'autocompact.*compound|both.*autocompact|PCT_OVERRIDE.*AUTO_COMPACT_WINDOW'; then
        fail "#207: should not warn when only PCT_OVERRIDE is set, got: $output"
    else
        pass "#207: silent when only PCT_OVERRIDE is set (single-knob)"
    fi
}

test_instructions_hook_silent_on_single_autocompact_window_only() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'autocompact.*compound|both.*autocompact|PCT_OVERRIDE.*AUTO_COMPACT_WINDOW'; then
        fail "#207: should not warn when only AUTO_COMPACT_WINDOW is set, got: $output"
    else
        pass "#207: silent when only AUTO_COMPACT_WINDOW is set (single-knob)"
    fi
}

# #207: warning shows effective compound trigger (30% × 400K = 120K) so user
# can diagnose impact from the warning alone.
test_instructions_hook_compound_warning_shows_effective_trigger() {
    local tmpdir output
    tmpdir=$(mktemp -d)
    echo '<!-- SDLC Wizard Version: 1.44.0 -->' > "$tmpdir/SDLC.md"
    touch "$tmpdir/TESTING.md"
    mkdir -p "$tmpdir/.claude" "$tmpdir/bin"
    cat > "$tmpdir/.claude/settings.json" <<'EOF'
{
  "env": {
    "CLAUDE_AUTOCOMPACT_PCT_OVERRIDE": "30",
    "CLAUDE_CODE_AUTO_COMPACT_WINDOW": "400000"
  }
}
EOF
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex"
    mkdir -p "$tmpdir/home"
    output=$(cd "$tmpdir" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir" HOME="$tmpdir/home" SDLC_WIZARD_CACHE_DIR="$tmpdir/cache" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qE '120000|120[Kk]|120,000'; then
        pass "#207: warning shows effective compound trigger (120K = 30% × 400K)"
    else
        fail "#207: expected effective trigger (120K) in warning, got: $output"
    fi
}

test_instructions_hook_warns_on_autocompact_compound_misconfig
test_instructions_hook_silent_on_single_autocompact_pct_only
test_instructions_hook_silent_on_single_autocompact_window_only
test_instructions_hook_compound_warning_shows_effective_trigger

echo ""
echo "--- CC release review nudge (#85) ---"

# Helper: fixture with weekly-update.yml + mocked gh returning configurable PR count
prepare_cc_update_fixture() {
    local tmpdir="$1"
    local pr_count="$2"       # integer — count returned by mocked gh
    local has_workflow="$3"   # "yes" or "no"
    mkdir -p "$tmpdir/project"
    echo "# SDLC" > "$tmpdir/project/SDLC.md"
    echo "# Testing" > "$tmpdir/project/TESTING.md"
    if [ "$has_workflow" = "yes" ]; then
        mkdir -p "$tmpdir/project/.github/workflows"
        echo "name: Weekly Update" > "$tmpdir/project/.github/workflows/weekly-update.yml"
    fi
    mkdir -p "$tmpdir/bin"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/npm"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/claude"
    printf '#!/bin/bash\nexit 1\n' > "$tmpdir/bin/codex"
    # Mock gh: returns pr_count when asked for auto-update PRs, empty otherwise
    cat > "$tmpdir/bin/gh" <<EOF
#!/bin/bash
# Look at full args — distinguish 'pr list ... auto-update' from other calls
for arg in "\$@"; do
    if [ "\$arg" = "auto-update" ]; then
        echo "$pr_count"
        exit 0
    fi
    if [ "\$arg" = "api-review-needed" ]; then
        echo "0"
        exit 0
    fi
done
# Default: empty (keeps other gh calls quiet)
echo ""
exit 0
EOF
    chmod +x "$tmpdir/bin/npm" "$tmpdir/bin/claude" "$tmpdir/bin/codex" "$tmpdir/bin/gh"
}

test_hook_queries_auto_update_label() {
    if grep -qF 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh"; then
        pass "hook queries for auto-update label"
    else
        fail "hook must check for open PRs with auto-update label (#85)"
    fi
}

test_hook_gates_cc_nudge_on_weekly_update_workflow() {
    # Mirror the api-review-needed gating pattern — only fire when the
    # detector workflow lives in this repo (not in consumer projects).
    if grep -B1 -A10 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh" | grep -q 'weekly-update.yml'; then
        pass "hook gates CC update nudge on weekly-update.yml presence"
    else
        fail "hook must gate auto-update nudge on .github/workflows/weekly-update.yml"
    fi
}

test_hook_guards_gh_for_cc_nudge() {
    if grep -B1 -A10 'auto-update' "$HOOKS_DIR/instructions-loaded-check.sh" | grep -q 'command -v gh'; then
        pass "hook guards on gh availability for CC nudge"
    else
        fail "hook must check 'command -v gh' before querying auto-update PRs"
    fi
}

test_hook_emits_cc_nudge_when_pending() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "2" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'Claude Code.*update.*pending|auto-update.*PR|CC.*release.*review'; then
        pass "hook emits CC update nudge when auto-update PRs open"
    else
        fail "Should emit nudge when gh reports open auto-update PR(s), got: $output"
    fi
}

test_hook_silent_when_no_pending_cc_updates() {
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "0" "yes"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'Claude Code.*update.*pending|auto-update.*PR|CC.*release.*review'; then
        fail "Should be silent when no open auto-update PRs, got: $output"
    else
        pass "hook silent when no auto-update PRs pending"
    fi
}

test_hook_silent_without_weekly_update_workflow() {
    # Consumer projects don't own the detector — don't pester them.
    local tmpdir
    tmpdir=$(mktemp -d)
    prepare_cc_update_fixture "$tmpdir" "3" "no"
    local output
    output=$(cd "$tmpdir/project" && PATH="$tmpdir/bin:$PATH" CLAUDE_PROJECT_DIR="$tmpdir/project" HOME="$tmpdir" "$HOOKS_DIR/instructions-loaded-check.sh" 2>/dev/null)
    rm -rf "$tmpdir"
    if echo "$output" | grep -qiE 'auto-update.*PR|CC.*release.*review'; then
        fail "Consumer project without detector workflow shouldn't see upstream nudge, got: $output"
    else
        pass "hook silent without weekly-update.yml (consumer project)"
    fi
}

test_hook_queries_auto_update_label
test_hook_gates_cc_nudge_on_weekly_update_workflow
test_hook_guards_gh_for_cc_nudge
test_hook_emits_cc_nudge_when_pending
test_hook_silent_when_no_pending_cc_updates
test_hook_silent_without_weekly_update_workflow

echo ""
echo "=== Results ==="
echo "Passed: $PASSED"
echo "Failed: $FAILED"

if [ $FAILED -gt 0 ]; then
    exit 1
fi

echo ""
echo "All hook tests passed!"
