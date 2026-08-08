#!/bin/bash
# Tests for roadmap #100: API feature detection in auto-update.
# Quality tests proving:
#   - Detector workflow exists + parses + targets right source
#   - Idempotency keys (label, state file, issue title) are pinned
#   - Session-start hook nudges when api-review-needed issues exist
#
# Pattern: detector-only workflow (no LLM calls). Shepherd pattern per #36:
# Action does cheap detection, session does deep analysis + adoption.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PASSED=0
FAILED=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

pass() { echo -e "${GREEN}PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
fail() { echo -e "${RED}FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }

echo "=== API Feature Detection (#100) Tests ==="
echo ""

WORKFLOW="$REPO_ROOT/.github/workflows/weekly-api-update.yml"
STATE_FILE="$REPO_ROOT/.github/last-checked-api-date.txt"
HOOK="$REPO_ROOT/hooks/instructions-loaded-check.sh"

# ────────────────────────────────────────────
# Workflow presence + parse
# ────────────────────────────────────────────

test_workflow_exists() {
    if [ -f "$WORKFLOW" ]; then
        pass "weekly-api-update.yml exists"
    else
        fail "weekly-api-update.yml not found at $WORKFLOW"
    fi
}

test_workflow_parses_yaml() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
        pass "weekly-api-update.yml is valid YAML"
    else
        fail "weekly-api-update.yml failed YAML parse"
    fi
}

# ────────────────────────────────────────────
# Triggers — cron + manual dispatch
# ────────────────────────────────────────────

test_workflow_has_cron() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    # Five space-separated cron fields between quotes (digits, *, /, ,, -).
    if grep -qE "cron: *['\"][][:digit:]*/,-]+ [][:digit:]*/,-]+ [][:digit:]*/,-]+ [][:digit:]*/,-]+ [][:digit:]*/,-]+['\"]" "$WORKFLOW"; then
        pass "weekly-api-update.yml has cron trigger"
    else
        fail "weekly-api-update.yml missing cron trigger"
    fi
}

test_workflow_has_dispatch() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -q "workflow_dispatch:" "$WORKFLOW"; then
        pass "weekly-api-update.yml has workflow_dispatch"
    else
        fail "weekly-api-update.yml missing workflow_dispatch"
    fi
}

# Stagger from weekly-update.yml (09:00 UTC) — api watcher at 10:00 UTC Monday.
# Prevents both workflows hitting GH API + Anthropic at the same minute.
#
# Implementation note (Codex round 1, ROADMAP #231 Phase 4): grep-based parsing
# false-greens because grep matches commented-out cron lines too. We use Python
# YAML parsing so only ACTIVE schedules are compared. If weekly-update.yml has
# no active schedule (which it doesn't post-#212 Option 1), the test passes
# trivially — there's no collision to detect.
test_workflow_cron_staggered() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    local other="$REPO_ROOT/.github/workflows/weekly-update.yml"

    local result
    result=$(python3 -c "
import yaml
def active_crons(path):
    try:
        with open(path) as f:
            wf = yaml.safe_load(f)
    except Exception:
        return []
    on = wf.get(True, wf.get('on', {}))
    if not isinstance(on, dict):
        return []
    sched = on.get('schedule', []) or []
    return [s.get('cron', '') for s in sched if isinstance(s, dict) and s.get('cron')]

api_crons = active_crons('$WORKFLOW')
release_crons = active_crons('$other')
if not api_crons:
    print('SKIP:no_api_cron')
elif not release_crons:
    print('SKIP:no_active_release_cron')
else:
    overlap = set(api_crons) & set(release_crons)
    if overlap:
        print('FAIL:collision:' + ','.join(overlap))
    else:
        print('PASS:api=' + ','.join(api_crons) + ' release=' + ','.join(release_crons))
" 2>&1)

    case "$result" in
        SKIP:no_api_cron)
            pass "skipped: weekly-api-update.yml has no active cron"
            ;;
        SKIP:no_active_release_cron)
            pass "skipped: weekly-update.yml has no active cron (no collision possible)"
            ;;
        FAIL:collision:*)
            fail "api cron collides with weekly-update cron — stagger to avoid burst (${result#FAIL:collision:})"
            ;;
        PASS:*)
            pass "api cron staggers from release cron (${result#PASS:})"
            ;;
        *)
            fail "could not parse cron values: $result"
            ;;
    esac
}

# Regression test for Codex round 1 P1: confirm the stagger test ACTUALLY
# detects an active-vs-active cron collision (the original grep version
# false-greened because it matched commented cron lines).
#
# We synthesize a temporary workflow file that has an ACTIVE schedule
# matching weekly-api-update.yml's cron, then verify the YAML-parsing logic
# above produces a FAIL: result. This proves the stagger test isn't a
# silent no-op.
test_workflow_cron_collision_detected() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi

    local api_cron
    api_cron=$(python3 -c "
import yaml
with open('$WORKFLOW') as f:
    wf = yaml.safe_load(f)
on = wf.get(True, wf.get('on', {}))
sched = on.get('schedule', []) if isinstance(on, dict) else []
crons = [s.get('cron') for s in sched if isinstance(s, dict) and s.get('cron')]
print(crons[0] if crons else '')
" 2>/dev/null)

    if [ -z "$api_cron" ]; then
        # If the api watcher itself has no cron, the regression target doesn't
        # apply — pass trivially (the staggered test would also skip).
        pass "n/a: weekly-api-update.yml has no active cron to collide with"
        return
    fi

    local tmpdir
    tmpdir=$(mktemp -d -t cron-collision-test.XXXXXX)
    trap "rm -rf '$tmpdir'" RETURN

    # Synthesize a fake "release" workflow with the SAME active cron as the api watcher
    cat > "$tmpdir/release.yml" <<EOF
name: Fake Release
on:
  schedule:
    - cron: '$api_cron'
jobs:
  noop:
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF

    local result
    result=$(python3 -c "
import yaml
def active_crons(path):
    with open(path) as f:
        wf = yaml.safe_load(f)
    on = wf.get(True, wf.get('on', {}))
    if not isinstance(on, dict): return []
    sched = on.get('schedule', []) or []
    return [s.get('cron', '') for s in sched if isinstance(s, dict) and s.get('cron')]

api = active_crons('$WORKFLOW')
rel = active_crons('$tmpdir/release.yml')
overlap = set(api) & set(rel)
print('COLLISION' if overlap else 'NO_COLLISION')
" 2>&1)

    if [ "$result" = "COLLISION" ]; then
        pass "stagger test correctly detects active-vs-active cron collision"
    else
        fail "stagger test failed to detect synthesized active cron collision: $result"
    fi
}

# ────────────────────────────────────────────
# Source + permissions
# ────────────────────────────────────────────

test_workflow_targets_platform_claude_com() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -q "platform.claude.com/docs/en/release-notes/api" "$WORKFLOW"; then
        pass "workflow fetches platform.claude.com changelog URL"
    else
        fail "workflow should target platform.claude.com/docs/en/release-notes/api"
    fi
}

test_workflow_has_issues_write_permission() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    # Need issues:write to open/update the tracking issue
    if grep -qE "issues: *write" "$WORKFLOW"; then
        pass "workflow declares issues: write permission"
    else
        fail "workflow must declare issues: write to open tracking issue"
    fi
}

test_workflow_declares_no_pr_permission() {
    # PR permission unused — detector doesn't open PRs, only issues.
    # Fails closed: if we ever add PRs, update this test deliberately.
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -qE "pull-requests: *write" "$WORKFLOW"; then
        fail "workflow should NOT request pull-requests: write (detector only opens issues)"
    else
        pass "workflow correctly omits pull-requests: write"
    fi
}

# ────────────────────────────────────────────
# State + idempotency
# ────────────────────────────────────────────

test_workflow_references_state_file() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -q "last-checked-api-date.txt" "$WORKFLOW"; then
        pass "workflow references .github/last-checked-api-date.txt"
    else
        fail "workflow must persist last-checked date for idempotency"
    fi
}

test_workflow_uses_review_label() {
    # Label is the idempotency key — session-start hook queries by label.
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -qF 'api-review-needed' "$WORKFLOW"; then
        pass "workflow uses 'api-review-needed' label"
    else
        fail "workflow must label tracking issue 'api-review-needed'"
    fi
}

# Workflow must NOT invoke claude-code-action — detector is intentionally
# LLM-free per #36 shepherd pattern. LLM analysis happens in user's session.
test_workflow_no_claude_code_action() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -q "anthropics/claude-code-action" "$WORKFLOW"; then
        fail "workflow should NOT use claude-code-action — detector is LLM-free (shepherd pattern)"
    else
        pass "workflow is LLM-free (no claude-code-action)"
    fi
}

# ────────────────────────────────────────────
# State file seed
# ────────────────────────────────────────────

test_state_file_exists() {
    # Seed value must exist so first run doesn't flood the repo with
    # every historical changelog entry.
    if [ -f "$STATE_FILE" ]; then
        pass ".github/last-checked-api-date.txt exists (seed present)"
    else
        fail ".github/last-checked-api-date.txt missing — seed required"
    fi
}

test_state_file_valid_iso_date() {
    if [ ! -f "$STATE_FILE" ]; then fail "skip: state file missing"; return; fi
    local date_val
    date_val=$(tr -d '\n' < "$STATE_FILE")
    if [[ "$date_val" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        pass "state file contains ISO date ($date_val)"
    else
        fail "state file should contain YYYY-MM-DD, got: '$date_val'"
    fi
}

# ────────────────────────────────────────────
# Session-start hook nudge
# ────────────────────────────────────────────

test_hook_queries_api_review_label() {
    if [ ! -f "$HOOK" ]; then fail "skip: hook missing"; return; fi
    if grep -qF 'api-review-needed' "$HOOK"; then
        pass "hook queries for api-review-needed label"
    else
        fail "hook must check for open issues with api-review-needed label"
    fi
}

test_hook_uses_gh_cli_defensively() {
    # Hook must guard on 'gh' availability — don't break sessions on machines
    # without gh installed. Pattern matches existing npm/codex guards.
    if [ ! -f "$HOOK" ]; then fail "skip: hook missing"; return; fi
    # Expect a "command -v gh" check somewhere in the api-review block.
    if grep -B1 -A10 'api-review-needed' "$HOOK" | grep -q 'command -v gh'; then
        pass "hook guards on gh availability"
    else
        fail "hook must check 'command -v gh' before calling gh api"
    fi
}

test_hook_still_exits_zero() {
    # Hook is non-blocking — must end with exit 0 after all checks.
    if [ ! -f "$HOOK" ]; then fail "skip: hook missing"; return; fi
    if tail -5 "$HOOK" | grep -q '^exit 0'; then
        pass "hook still exits 0 (non-blocking)"
    else
        fail "hook must end with 'exit 0' — session start cannot block"
    fi
}

# ────────────────────────────────────────────
# Wizard doc surfaces the shepherd pattern
# ────────────────────────────────────────────

test_wizard_doc_documents_shepherd_pattern() {
    local DOC="$REPO_ROOT/CLAUDE_CODE_SDLC_WIZARD.md"
    if [ ! -f "$DOC" ]; then fail "skip: wizard doc missing"; return; fi
    # Must mention the detector pattern so readers understand why the
    # session-start nudge exists and what to do about it.
    if grep -qF 'api-review-needed' "$DOC"; then
        pass "CLAUDE_CODE_SDLC_WIZARD.md mentions api-review-needed label"
    else
        fail "wizard doc should document the API feature shepherd pattern"
    fi
}

# ────────────────────────────────────────────
# Source: must be .md, not HTML
# ────────────────────────────────────────────

# Codex round-1 finding #3: platform.claude.com serves raw markdown when the
# doc path gets `.md` appended. Parsing markdown is strictly more stable than
# scraping rendered HTML.
test_workflow_uses_md_source() {
    if [ ! -f "$WORKFLOW" ]; then fail "skip: workflow missing"; return; fi
    if grep -qF 'release-notes/api.md' "$WORKFLOW"; then
        pass "workflow uses .md source (not HTML)"
    else
        fail "workflow should fetch release-notes/api.md — markdown is more stable than HTML"
    fi
}

# ────────────────────────────────────────────
# Parser — executable against fixtures (not just grep)
# ────────────────────────────────────────────

PARSER="$REPO_ROOT/scripts/parse-api-changelog.py"
FIXTURE="$REPO_ROOT/tests/fixtures/api-changelog/sample.md"

test_parser_exists() {
    if [ -x "$PARSER" ]; then
        pass "parse-api-changelog.py exists and is executable"
    else
        fail "scripts/parse-api-changelog.py must exist + be executable"
    fi
}

test_parser_finds_all_fixture_dates() {
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    # Very old last-date → all 5 fixture entries should emerge.
    local out count
    out=$("$PARSER" "$FIXTURE" "1970-01-01" 2>/dev/null)
    count=$(printf '%s\n' "$out" | grep -c '^[0-9]')
    if [ "$count" -eq 5 ]; then
        pass "parser finds all 5 fixture entries"
    else
        fail "parser returned ${count} entries, expected 5"
    fi
}

test_parser_filters_by_last_date() {
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    # last=2026-04-09 → only the 2026-04-16 entry is newer (equality excluded).
    local out count
    out=$("$PARSER" "$FIXTURE" "2026-04-09" 2>/dev/null)
    count=$(printf '%s\n' "$out" | grep -c '^[0-9]')
    if [ "$count" -eq 1 ] && printf '%s' "$out" | grep -q '2026-04-16'; then
        pass "parser correctly filters by last-date (equality excluded)"
    else
        fail "parser filtering broken: got '$out'"
    fi
}

test_parser_handles_ordinal_dates() {
    # Regression guard: entries like 'January 23rd, 2025' must parse.
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    if "$PARSER" "$FIXTURE" "1970-01-01" 2>/dev/null | grep -q '^2025-01-23'; then
        pass "parser normalizes ordinal dates (23rd → 23)"
    else
        fail "parser failed to parse 'January 23rd, 2025'"
    fi
}

test_parser_rejects_bad_last_date() {
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    if "$PARSER" "$FIXTURE" "not-a-date" 2>/dev/null; then
        fail "parser accepted invalid last-date"
    else
        pass "parser rejects invalid last-date"
    fi
}

test_parser_writes_latest_date_file() {
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    local outdir="${TMPDIR:-/tmp}"
    rm -f "$outdir/latest_date.txt" "$outdir/new_count.txt"
    "$PARSER" "$FIXTURE" "1970-01-01" >/dev/null 2>&1
    local latest
    latest=$(cat "$outdir/latest_date.txt" 2>/dev/null || return 0)
    if [ "$latest" = "2026-04-16" ]; then
        pass "parser writes latest_date.txt with newest entry"
    else
        fail "latest_date.txt expected 2026-04-16, got '$latest'"
    fi
}

test_parser_captures_bullet_summary() {
    # Issue body UX: each entry needs WHAT changed, not just the date.
    # Parser output must be iso\traw_header\tbullet_summary.
    if [ ! -x "$PARSER" ] || [ ! -f "$FIXTURE" ]; then
        fail "skip: parser or fixture missing"; return
    fi
    local out line third
    out=$("$PARSER" "$FIXTURE" "1970-01-01" 2>/dev/null)
    line=$(printf '%s\n' "$out" | grep '^2026-04-16' | head -1)
    # Count tabs: must be >= 2 (3 columns).
    local tab_count
    tab_count=$(printf '%s' "$line" | tr -cd '\t' | wc -c | tr -d ' ')
    if [ "$tab_count" -lt 2 ]; then
        fail "parser output missing bullet column (tabs=$tab_count): '$line'"
        return
    fi
    third=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
    if printf '%s' "$third" | grep -qi 'Opus 4\.7'; then
        pass "parser captures bullet summary under date header"
    else
        fail "bullet summary missing expected feature text: '$third'"
    fi
}

test_parser_bullets_survive_subheaders() {
    # Codex finding #1: bullet search must bound on next DATE header, not any
    # h2-h4 header. Regression: a non-date sub-header inside a date block
    # shouldn't drop that block's bullets.
    if [ ! -x "$PARSER" ]; then
        fail "skip: parser missing"; return
    fi
    local tmp
    tmp="${TMPDIR:-/tmp}/api-parser-subheader.$$.md"
    {
        echo "# Claude Platform"
        echo ""
        echo "### April 16, 2026"
        echo "Intro paragraph (no bullet)."
        echo "#### SDKs"
        echo "- SDK-level feature for April 16"
        echo ""
        echo "### April 9, 2026"
        echo "- April 9 feature"
    } > "$tmp"
    local out line third
    out=$("$PARSER" "$tmp" "1970-01-01" 2>/dev/null)
    rm -f "$tmp"
    line=$(printf '%s\n' "$out" | grep '^2026-04-16' | head -1)
    third=$(printf '%s' "$line" | awk -F'\t' '{print $3}')
    if printf '%s' "$third" | grep -q 'SDK-level feature'; then
        pass "parser bounds bullets on next date header (survives sub-headers)"
    else
        fail "sub-header regression: 2026-04-16 bullets missing, got '$third'"
    fi
}

test_parser_scrubs_tabs_in_bullets() {
    # Claude PR review P2.1: tab chars in bullet text would break the TSV
    # 3-column contract. Parser owns the delimiter — scrub tabs to spaces.
    if [ ! -x "$PARSER" ]; then
        fail "skip: parser missing"; return
    fi
    local tmp
    tmp="${TMPDIR:-/tmp}/api-parser-tab.$$.md"
    printf '# H\n\n### March 2, 2026\n- before\tafter middle\ttab\n' > "$tmp"
    local out tabs
    out=$("$PARSER" "$tmp" "1970-01-01" 2>/dev/null)
    rm -f "$tmp"
    # Expected output: exactly 2 tabs (column separators), none inside bullet.
    tabs=$(printf '%s' "$out" | tr -cd '\t' | wc -c | tr -d ' ')
    if [ "$tabs" -eq 2 ]; then
        pass "parser scrubs tabs from bullet text (preserves TSV invariant)"
    else
        fail "parser emitted $tabs tabs, expected exactly 2 (col separators): '$out'"
    fi
}

test_parser_truncates_long_bullet_summary() {
    # Sanity bound: issue bodies shouldn't include novella-length bullets.
    # Parser must cap bullet_summary (we target ~200 chars).
    if [ ! -x "$PARSER" ]; then
        fail "skip: parser missing"; return
    fi
    local tmp
    tmp="${TMPDIR:-/tmp}/api-parser-long-bullet.$$.md"
    {
        echo "# Header"
        echo ""
        echo "### March 1, 2026"
        # 300-char bullet
        printf -- "- "
        printf 'x%.0s' $(seq 1 300)
        echo ""
    } > "$tmp"
    local out third len
    out=$("$PARSER" "$tmp" "1970-01-01" 2>/dev/null)
    rm -f "$tmp"
    third=$(printf '%s' "$out" | awk -F'\t' '{print $3}')
    len=${#third}
    if [ "$len" -gt 0 ] && [ "$len" -le 220 ]; then
        pass "parser truncates long bullet summary ($len chars)"
    else
        fail "bullet summary length=$len out of bounds (expected 1-220)"
    fi
}

# ────────────────────────────────────────────
# Hook repo-gating — fork/consumer safety
# ────────────────────────────────────────────

# Codex round-1 finding #2: the CLI distributes this hook to consumer repos.
# The nudge must gate on LOCAL presence of the detector workflow so user
# projects aren't pestered with upstream-wizard issues.
test_hook_gates_on_local_workflow_file() {
    if [ ! -f "$HOOK" ]; then fail "skip: hook missing"; return; fi
    if grep -q 'weekly-api-update.yml' "$HOOK"; then
        pass "hook gates nudge on local weekly-api-update.yml presence"
    else
        fail "hook must check .github/workflows/weekly-api-update.yml exists before nudging (fork/consumer safety)"
    fi
}

# Regression guard against Codex round-1 finding #2: the hook MUST NOT
# hardcode the upstream wizard repo when querying issues. After the gate
# check, `gh issue list` (no --repo) hits the current working repo.
test_hook_does_not_hardcode_upstream_repo() {
    if [ ! -f "$HOOK" ]; then fail "skip: hook missing"; return; fi
    # Look inside the api-review block only (not other lines referencing the repo).
    if awk '/API feature review nudge/,/^fi$/' "$HOOK" | grep -q 'BaseInfinity/claude-sdlc-harness'; then
        fail "hook hardcodes upstream repo in api-review block — forks will see wrong issues"
    else
        pass "hook queries current repo (not hardcoded upstream)"
    fi
}

# ────────────────────────────────────────────
# State push — must be non-blocking
# ────────────────────────────────────────────

# Codex round-1 finding #1: branch protection rejects direct pushes to main.
# State push must tolerate rejection (issue-level idempotency keeps us safe).
test_state_push_is_nonblocking() {
    local PERSIST="$REPO_ROOT/scripts/persist-api-state.sh"
    if [ ! -f "$PERSIST" ]; then fail "skip: persist script missing"; return; fi
    # Accept `git push || true` or `git push || echo ...` — both make the
    # step succeed when the push is rejected.
    if grep -qE 'git push \|\| (true|echo)' "$PERSIST"; then
        pass "persist script treats state push as best-effort (survives branch protection)"
    else
        fail "git push must be non-blocking (|| true or || echo) to survive branch protection on main"
    fi
}

# ────────────────────────────────────────────
# Executable path coverage (Codex round-2 finding)
# ────────────────────────────────────────────

# Integration test: plant a sandbox repo with a mocked `git push` that fails,
# confirm the persist script still exits 0. Proves the `|| echo` guard works
# under `set -euo pipefail` (the actual workflow environment).
test_persist_survives_rejected_push() {
    local PERSIST="$REPO_ROOT/scripts/persist-api-state.sh"
    if [ ! -x "$PERSIST" ]; then fail "skip: persist script missing"; return; fi
    local sandbox
    sandbox=$(mktemp -d "${TMPDIR:-/tmp}/persist-test.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -rf '$sandbox'" RETURN

    # Build a throwaway git repo.
    (
        cd "$sandbox"
        git init --quiet --initial-branch=main
        git config user.email "test@example.com"
        git config user.name  "Test"
        mkdir -p .github
        echo "1970-01-01" > .github/last-checked-api-date.txt
        git add .github/last-checked-api-date.txt
        git commit --quiet -m "init"
    )

    # Mock `git push` to fail (simulates branch protection rejection).
    local bin="$sandbox/bin"
    mkdir -p "$bin"
    cat > "$bin/git" <<'EOF'
#!/bin/bash
if [ "$1" = "push" ]; then
    echo "rejected" >&2
    exit 1
fi
exec /usr/bin/env -i PATH="/usr/bin:/bin" /usr/bin/git "$@" 2>/dev/null || /usr/bin/git "$@"
EOF
    chmod +x "$bin/git"

    # Run the script with mocked git. If $? == 0, the `|| echo` guard worked.
    if (cd "$sandbox" && PATH="$bin:$PATH" "$PERSIST" ".github/last-checked-api-date.txt" "2026-04-17") >/dev/null 2>&1; then
        pass "persist script exits 0 even when git push is rejected"
    else
        fail "persist script propagated rejected push failure — || echo guard broken"
    fi
}

# Integration test: plant a sandbox SDLC project with + without the detector
# workflow, mock `gh` to always report 1 pending api-review issue, run the
# hook, verify the nudge fires ONLY when the local workflow file is present.
test_hook_nudges_only_when_workflow_local() {
    local HOOK_FILE="$REPO_ROOT/hooks/instructions-loaded-check.sh"
    local FIND_SDLC="$REPO_ROOT/hooks/_find-sdlc-root.sh"
    if [ ! -f "$HOOK_FILE" ] || [ ! -f "$FIND_SDLC" ]; then
        fail "skip: hook or helper missing"; return
    fi
    local sandbox
    sandbox=$(mktemp -d "${TMPDIR:-/tmp}/hook-test.XXXXXX")
    # shellcheck disable=SC2064
    trap "rm -rf '$sandbox'" RETURN

    # SDLC root with both required files.
    mkdir -p "$sandbox/project"
    touch "$sandbox/project/SDLC.md" "$sandbox/project/TESTING.md"

    # Copy the hook + its helper into the sandbox so we don't need to mess
    # with paths. The hook sources _find-sdlc-root.sh from its own dir.
    local hook_dir="$sandbox/project/.hooks"
    mkdir -p "$hook_dir"
    cp "$HOOK_FILE" "$hook_dir/instructions-loaded-check.sh"
    cp "$FIND_SDLC" "$hook_dir/_find-sdlc-root.sh"

    # Mock gh: report 1 open api-review-needed issue.
    local bin="$sandbox/bin"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'EOF'
#!/bin/bash
# Minimal mock: "gh issue list ... --jq 'length'" → return count as integer.
# The real hook uses `--jq 'length'` to get an int, so the mock must honor that.
if [ "$1" = "issue" ] && [ "$2" = "list" ]; then
    # Walk args for --jq value.
    jq_expr=""
    for arg in "$@"; do
        if [ "$prev" = "--jq" ]; then jq_expr="$arg"; fi
        prev="$arg"
    done
    if [ "$jq_expr" = "length" ]; then
        echo "1"
    else
        echo '[{"number":42}]'
    fi
    exit 0
fi
exit 0
EOF
    chmod +x "$bin/gh"

    # Clear env vars that could confuse the hook.
    export CLAUDE_PROJECT_DIR="$sandbox/project"

    # Case A: no local workflow file → nudge must NOT appear.
    local out_no
    out_no=$(cd "$sandbox/project" && PATH="$bin:$PATH" bash "$hook_dir/instructions-loaded-check.sh" 2>&1)
    if echo "$out_no" | grep -q "api-review-needed"; then
        fail "hook nudged when no local workflow file exists — gate is broken"
        return
    fi

    # Case B: plant the workflow file → nudge MUST appear.
    mkdir -p "$sandbox/project/.github/workflows"
    touch "$sandbox/project/.github/workflows/weekly-api-update.yml"
    local out_yes
    out_yes=$(cd "$sandbox/project" && PATH="$bin:$PATH" bash "$hook_dir/instructions-loaded-check.sh" 2>&1)
    if echo "$out_yes" | grep -q "Anthropic API features pending review"; then
        pass "hook nudge fires only when local weekly-api-update.yml exists"
    else
        fail "hook did not nudge when local workflow file was present"
    fi
}

# ────────────────────────────────────────────
# Run
# ────────────────────────────────────────────

test_workflow_exists
test_workflow_parses_yaml
test_workflow_has_cron
test_workflow_has_dispatch
test_workflow_cron_staggered
test_workflow_cron_collision_detected
test_workflow_targets_platform_claude_com
test_workflow_uses_md_source
test_workflow_has_issues_write_permission
test_workflow_declares_no_pr_permission
test_workflow_references_state_file
test_workflow_uses_review_label
test_workflow_no_claude_code_action
test_state_file_exists
test_state_file_valid_iso_date
test_hook_queries_api_review_label
test_hook_uses_gh_cli_defensively
test_hook_still_exits_zero
test_hook_gates_on_local_workflow_file
test_hook_does_not_hardcode_upstream_repo
test_state_push_is_nonblocking
test_wizard_doc_documents_shepherd_pattern
test_parser_exists
test_parser_finds_all_fixture_dates
test_parser_filters_by_last_date
test_parser_handles_ordinal_dates
test_parser_rejects_bad_last_date
test_parser_writes_latest_date_file
test_parser_captures_bullet_summary
test_parser_bullets_survive_subheaders
test_parser_scrubs_tabs_in_bullets
test_parser_truncates_long_bullet_summary
test_persist_survives_rejected_push
test_hook_nudges_only_when_workflow_local

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

echo "All API feature detection tests passed!"
