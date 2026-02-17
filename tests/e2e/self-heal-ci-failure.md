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
