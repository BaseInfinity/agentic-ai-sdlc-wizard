#!/bin/bash
# Quality test: pr-review.yml skips Claude PR review on the wizard's own self-PRs.
#
# The `review` job runs claude-code-action@v1 which requires ANTHROPIC_API_KEY
# with a positive credit balance. The wizard maintainer runs an "API canary" —
# keeping the credit balance dead so unexpected API draws are detected. That
# means the review job has been failing on every wizard self-PR with
# "Credit balance is too low".
#
# The wizard uses Codex for cross-model review on its own PRs (see SDLC skill),
# so the Claude PR review is redundant on self-repo. Consumers using pr-review.yml
# in their own projects benefit from the Claude PR review and SHOULD have it run.
#
# Fix: skip the review job when the workflow runs in BaseInfinity/claude-sdlc-wizard.
# Consumers' forks/copies of pr-review.yml run normally.
#
# Lessons learned (from 7 self-PRs merged with red review job in v1.39.0–v1.42.0):
# - Red CI normalizes red — a NEW review failure (e.g., real bug detected) would
#   look identical to the canary failure and be missed.
# - "Required check is green so I can merge" is not the same as "all checks green".
# - SDLC: ALL TESTS MUST PASS BEFORE COMMIT — no exceptions, including non-required.

set -e

WORKFLOW="${WORKFLOW:-.github/workflows/pr-review.yml}"
PASSED=0
FAILED=0

pass() { echo "PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "FAIL: $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$WORKFLOW" ]; then
    echo "FAIL: $WORKFLOW not found"
    exit 1
fi

# Test 1: Workflow has the EXACT NEGATIVE comparison for EVERY slug this repo
# answers to. A literal `==` would invert the semantics (skip consumers, run on
# self) — must catch that.
#
# Both the current and the planned slug are required, because a GitHub rename
# does NOT rewrite this string. The condition would silently start matching, and
# the paid self-review this skip exists to prevent would begin running on our own
# PRs — costing quota with no signal that anything changed. GitHub redirects web
# and git operations; it does not redirect a literal comparison inside a
# workflow. Listing both slugs makes the rename a no-op for this gate, in either
# direction, so it can be flipped without a flag day.
for slug in "BaseInfinity/claude-sdlc-wizard" "BaseInfinity/claude-sdlc-harness"; do
    if grep -qE "github\.repository[[:space:]]*!=[[:space:]]*['\"]${slug}['\"]" "$WORKFLOW"; then
        pass "Workflow uses exact negative comparison: github.repository != '$slug'"
    else
        fail "Workflow must use exact: github.repository != '$slug' — verify operator and string both"
    fi
done

# Test 1b: Negative control — explicitly fail if `==` operator is used (would skip consumers).
if grep -qE "github\.repository[[:space:]]*==[[:space:]]*['\"]BaseInfinity/claude-sdlc-wizard['\"]" "$WORKFLOW"; then
    fail 'Workflow uses == instead of != — this would skip CONSUMERS and run on the wizard self-repo (inverted semantics)'
else
    pass 'No inverted github.repository == comparison (consumer projects safe)'
fi

# Test 2: The skip condition lives on the `review` job (not just one step).
# Workflow-level skip is more reliable than step-level — no half-runs.
review_job_block=$(awk '
  /^  review:/ { flag=1; next }
  /^  [a-z][a-z-]*:/ && flag { flag=0 }
  flag { print }
' "$WORKFLOW" | head -30)

if echo "$review_job_block" | grep -qE "github\.repository.*BaseInfinity/claude-sdlc-wizard"; then
    pass "Skip condition is on the review job's if: gate (no half-runs)"
else
    fail "Skip condition must be in the review job's if: block, near the top"
fi

# Test 3: Workflow YAML still parses (don't break the file with the edit).
if python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))" 2>/dev/null; then
    pass "Workflow YAML still parses"
else
    fail "Workflow YAML broken after the edit"
fi

# Test 4: Audit policy documented in CI_CD.md.
if grep -qE "self.PR.*skip|skip.*self.PR|API canary.*review|claude-code-action.*self" CI_CD.md 2>/dev/null; then
    pass "CI_CD.md documents the self-PR skip policy"
else
    fail "CI_CD.md must document why review is skipped on self-PRs (API canary, Codex supersedes)"
fi

# Test 5: CHANGELOG mentions the fix.
if grep -qE "^## \[1\.42\.1\]" CHANGELOG.md 2>/dev/null; then
    cl_entry=$(awk '/^## \[1\.42\.1\]/,/^## \[1\.42\.0\]/' CHANGELOG.md | sed '$d')
    if echo "$cl_entry" | grep -qiE "review.*skip|self.PR|API canary|red.*CI"; then
        pass "CHANGELOG [1.42.1] documents the CI fix"
    else
        fail "CHANGELOG [1.42.1] must reference the review skip / canary fix"
    fi
else
    fail "CHANGELOG [1.42.1] entry missing"
fi

# Test 6: Negative control — the review step itself still calls claude-code-action
# (we're skipping execution, not removing the workflow). Consumers should still get the review.
if grep -qE "uses: anthropics/claude-code-action" "$WORKFLOW"; then
    pass "Workflow still wires claude-code-action (consumer projects benefit)"
else
    fail "Workflow must still call claude-code-action — only the SELF-repo runs are skipped"
fi

echo ""
echo "Results: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
