# Self-Heal CI Failure — Manual Live Test Procedure

## Purpose

Verify that `ci-self-heal.yml` actually triggers and fixes CI failures end-to-end in real GitHub Actions. The automated tests in `test-self-heal-simulation.sh` cover the logic locally; this procedure validates the full workflow_run → Claude fix → commit → re-trigger cycle.

## Prerequisites

- Repository has `ci-self-heal.yml` on the default branch (main)
- `ANTHROPIC_API_KEY` secret is configured
- No other PRs are running CI simultaneously (avoids confusion)

## Procedure

### Step 1: Create Intentional Breakage

```bash
git checkout -b test/self-heal-live
```

Introduce a deliberate CI failure. Choose ONE of:

**Option A: Break a test** (safest)
```bash
# In tests/test-version-logic.sh, add a failing test:
echo '
test_intentional_fail() {
    fail "Intentional failure for self-heal test"
}
test_intentional_fail
' >> tests/test-version-logic.sh
```

**Option B: Break YAML validation** (quick)
```bash
# Add invalid YAML to a workflow file copy
echo "  invalid_yaml: [" >> .github/workflows/ci.yml
```

### Step 2: Push and Open PR

```bash
git add -A
git commit -m "test: intentional CI failure for self-heal validation"
git push -u origin test/self-heal-live
gh pr create --title "test: self-heal live validation" --body "Intentional CI failure to test self-healing loop. Will auto-close after test."
```

### Step 3: Observe CI Failure

1. Wait for CI to run and **fail** (should take ~2-5 minutes for validation job)
2. Verify the failure is from your intentional breakage, not something else
3. Note the CI run ID from the Actions tab

### Step 4: Observe Self-Heal Trigger

1. Go to Actions tab → filter by "CI Auto-Fix" workflow
2. You should see a new run triggered by `workflow_run` within ~30 seconds of CI failure
3. If no run appears after 2 minutes:
   - Check that `ci-self-heal.yml` is on the default branch
   - Check the workflow's `name:` field matches what CI references
   - Check the `if:` condition isn't filtering out your case

### Step 5: Verify Self-Heal Behavior

Monitor the autofix run and verify:

- [ ] **PR comment posted**: Sticky comment with `ci-autofix` header appears on the PR
- [ ] **Attempt counter**: Shows "Attempt 1/3" (not 0/3 or wrong count)
- [ ] **Source detection**: Shows correct trigger source (CI failure)
- [ ] **Claude execution**: Claude reads the failure logs and attempts a fix
- [ ] **Commit pushed**: An `[autofix 1/3]` commit appears on the PR branch
- [ ] **CI re-triggered**: CI runs again after the fix commit

### Step 6: Evaluate the Fix

After Claude's fix commit:

1. **Did CI pass?** If yes, the loop worked end-to-end
2. **Did Claude fix the right thing?** Review the autofix commit diff
3. **Did the loop stop?** After CI passes, no more autofix runs should trigger

### Step 7: Cleanup

```bash
# Close the test PR
gh pr close test/self-heal-live --comment "Self-heal test complete"

# Delete the branch
git checkout main
git branch -D test/self-heal-live
git push origin --delete test/self-heal-live
```

## What to Check in Logs

| Step | What to Look For | Where |
|------|------------------|-------|
| Trigger | `workflow_run` event with `conclusion: failure` | Actions → CI Auto-Fix |
| PR lookup | `Found PR #N` (not "No open PR found") | Autofix run logs |
| Retry count | `Previous autofix attempts: 0 / 3` | Autofix run logs |
| Context | `Captured N lines of failure context` | "Download CI failure logs" step |
| Claude | Tool calls to Read, Edit | "Run Claude to fix issues" step |
| Commit | `[autofix 1/3] fix: auto-fix from ci-failure` | Git history |
| Re-trigger | `Re-triggering CI via workflow_dispatch` | "Re-trigger CI" step |

## Expected Results

| Scenario | Expected Outcome |
|----------|------------------|
| Simple test failure | Claude removes the bad test, CI passes on retry |
| YAML syntax error | Claude fixes the YAML, CI passes on retry |
| Complex logic bug | Claude may need 2-3 attempts (check retry counter increments) |
| Unfixable error | Max retries (3) reached, "Manual intervention required" comment posted |

## Failure Modes

| Issue | Likely Cause | Fix |
|-------|--------------|-----|
| No autofix run triggered | `workflow_run` registry mismatch | Check `name:` field matches, push a comment change to force re-registration |
| "No open PR found" | Branch name mismatch in API query | Check PR is open and branch matches |
| Claude makes no changes | Failure context too vague or truncated | Check the 200-line truncation captured the relevant error |
| Infinite loop | `MAX_AUTOFIX_RETRIES` not counting correctly | Check git log grep pattern matches commit format |

---

## Multi-Path Stress Test

### Purpose

Verify all 3 self-heal trigger paths work in a single PR cascade:
1. **CI failure** mode — self-heal fixes a broken test
2. **Review findings (criticals)** — self-heal fixes command injection
3. **Review findings (all-findings)** — self-heal fixes suggestions too

This extends the single-path test above by exercising the full loop including the `all-findings` level.

### Prerequisites

Same as above, plus:
- PR #51 (or equivalent) merged to main — `all-findings` level must be on default branch
- `ci-self-heal.yml` on default branch with `AUTOFIX_LEVEL: all-findings`

### Step 1: Create Branch with 4 Intentional Bugs

```bash
git checkout -b test/self-heal-stress
```

**Bug 1 — CI breaker** (triggers ci-failure mode):
```bash
# In tests/test-version-logic.sh, add a failing test function (before "Run all tests")
# and add the call in the test execution list (before results summary):
test_intentional_ci_break() {
    fail "STRESS TEST: intentional CI failure for self-heal validation"
}
# ... added to test execution list before results check ...
test_intentional_ci_break
```

**Bugs 2-4 — Review findings** (trigger review-findings mode):

Create `tests/e2e/lib/retry-utils.sh` with these intentional bugs:

| Bug # | Severity | What | Why it's a finding |
|-------|----------|------|-------------------|
| 2 | Critical | `eval $COMMAND` (unquoted) | Command injection — textbook security bug |
| 3 | Medium | `seq 0 $MAX_RETRIES` | Off-by-one: runs N+1 times instead of N |
| 4 | Suggestion | Missing `set -e` | Convention violation — all scripts should have it |

```bash
#!/bin/bash
# Retry utilities for E2E test execution
# NOTE: This file contains INTENTIONAL bugs for self-heal stress testing

retry_command() {
    local COMMAND="$1"
    local MAX_RETRIES="${2:-3}"
    local DELAY="${3:-5}"

    for i in $(seq 0 $MAX_RETRIES); do
        echo "Attempt $i of $MAX_RETRIES..."
        if eval $COMMAND; then
            echo "Command succeeded on attempt $i"
            return 0
        fi
        echo "Attempt $i failed, retrying in ${DELAY}s..."
        sleep "$DELAY"
    done

    echo "All $MAX_RETRIES retries exhausted"
    return 1
}
```

### Step 2: Push and Open PR

```bash
git add tests/test-version-logic.sh tests/e2e/lib/retry-utils.sh
git commit -m "test: self-heal multi-path stress test (4 intentional bugs)"
git push -u origin test/self-heal-stress
gh pr create \
  --title "test: self-heal multi-path stress test" \
  --body "Multi-path stress test for self-heal loop. Contains 4 intentional bugs.
Will auto-close after test. See tests/e2e/self-heal-ci-failure.md for procedure."
```

### Step 3: Expected Cascade

```
Push PR
  → CI validate FAILS (bug 1: broken test)
  → self-heal attempt 1 (ci-failure mode)
    → Claude removes broken test → [autofix 1/3] → push
      → CI re-runs → PASSES
      → PR Review runs → finds bugs 2,3,4
      → self-heal attempt 2 (review-findings, all-findings mode)
        → Claude fixes all findings → [autofix 2/3] → push
          → CI re-runs → PASSES
          → PR Review → APPROVE (clean) → DONE
```

### Step 4: Verification Checklist

**Attempt 1 (CI failure):**
- [ ] Self-heal triggered within 60s of CI failure
- [ ] PR comment shows "Attempt 1/3" with `ci-failure` source
- [ ] Claude removed the broken test (not the whole file)
- [ ] Commit message: `[autofix 1/3] fix: auto-fix from ci-failure`
- [ ] CI re-triggered via `gh workflow run`

**Between attempts:**
- [ ] CI passes on the fixed code
- [ ] PR Review runs and finds bugs 2-4
- [ ] Review comment contains critical/medium/suggestion findings

**Attempt 2 (review findings):**
- [ ] Self-heal triggered within 60s of review completion
- [ ] PR comment updated to show "Attempt 2/3" with `review-findings` source
- [ ] Claude fixed `eval $COMMAND` → `"$COMMAND"` (bug 2)
- [ ] Claude fixed `seq 0` → `seq 1` (bug 3)
- [ ] Claude added `set -e` (bug 4)
- [ ] Commit message: `[autofix 2/3] fix: auto-fix from review-findings`

**Final state:**
- [ ] CI passes clean
- [ ] PR Review shows no critical findings
- [ ] No attempt 3 triggered (loop stopped)
- [ ] Total autofix attempts: exactly 2

### Step 5: Cleanup

```bash
# Remove the stress test fixture file before closing the PR.
# gh pr close without merging does not clean up committed files if the
# branch was previously pushed; removing it explicitly prevents the file
# from lingering if the branch is re-used or cherry-picked elsewhere.
git rm tests/e2e/lib/retry-utils.sh
git commit -m "cleanup: remove retry-utils.sh stress test fixture"
git push origin test/self-heal-stress

gh pr close test/self-heal-stress --comment "Multi-path stress test complete. Results documented."
git checkout main
git branch -D test/self-heal-stress
git push origin --delete test/self-heal-stress
```

### Results Log

_Record results here after each execution._

| Date | Attempt 1 | Attempt 2 | Final State | Notes |
|------|-----------|-----------|-------------|-------|
| 2026-02-19 | PASS | PASS | Clean (7 commits, CI green) | Attempt 1: ci-failure, removed broken test. Attempt 2: review-findings (suggestions), fixed doc cleanup + test ordering. Attempt 3: review-findings (suggestions), deleted retry-utils.sh + reordered tests. Review flagged eval/seq bugs as intentional (correct — labeled bugs trick reviewers). All 3/3 attempts used. |
