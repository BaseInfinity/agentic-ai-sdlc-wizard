# Codex Desktop E2E Test: SDLC Wizard Cowork Plugin Install

Use this prompt with Codex Desktop computer-use to test installing the SDLC Wizard
plugin into Claude Cowork and verifying it works end-to-end.

## Prompt for Codex Desktop

```
You are testing the installation and functionality of a Claude Cowork plugin called
"SDLC Wizard". Your job is to install it, verify it loads, and test every component.
Screenshot each step as evidence.

## Step 1: Open Claude Desktop and navigate to Cowork

1. Open the Claude Desktop application
2. Click "Cowork" at the top center to switch to the Cowork tab
3. Screenshot the Cowork tab

## Step 2: Install the SDLC Wizard plugin

Try these install methods IN ORDER until one works:

### Method A: Browse plugins
1. Click "Customize" in the left sidebar
2. Click the "Plugins" tab
3. Click "Browse plugins"
4. Search for "sdlc-wizard" or "sdlc"
5. If found, click "Install"
6. Screenshot the result

### Method B: Add from GitHub URL
If Method A doesn't find it (plugin not yet in marketplace):
1. In the Customize > Plugins area, look for "Add plugin" or "Upload plugin" or
   any option to add a custom plugin
2. Use this URL: https://github.com/BaseInfinity/claude-sdlc-wizard/tree/main/cowork
3. Screenshot the result

### Method C: Local plugin directory
If Methods A and B don't work:
1. Open a terminal
2. Clone the repo: git clone https://github.com/BaseInfinity/claude-sdlc-wizard.git /tmp/sdlc-wizard
3. In Claude Desktop or Claude Code CLI, try:
   claude --plugin-dir /tmp/sdlc-wizard/cowork
4. Screenshot the result

Document which method worked.

## Step 3: Verify plugin is installed

1. Go to Customize > Plugins > Installed tab (or equivalent)
2. Confirm "sdlc-wizard-cowork" appears in the list
3. Check there are no errors (look for an Errors tab or red indicators)
4. Screenshot the installed plugins list

## Step 4: Test skills

### Test 4a: SDLC skill
1. In a Cowork conversation, type: /sdlc-wizard-cowork:sdlc
2. Verify the SDLC workflow guidance appears (planning, TDD, self-review steps)
3. Screenshot the response

### Test 4b: Feedback skill
1. Type: /sdlc-wizard-cowork:feedback
2. Verify the feedback skill responds with feedback collection guidance
3. Screenshot the response

## Step 5: Test hooks

### Test 5a: SDLC Baseline hook (UserPromptSubmit)
1. Type any normal prompt like "Help me write a Python function to sort a list"
2. Look for "SDLC BASELINE" text injected into Claude's context or behavior
3. Claude should mention planning, confidence levels, or TDD in its approach
4. Screenshot evidence of the hook firing

### Test 5b: TDD hook (PreToolUse on Write/Edit)
1. Ask Claude to create or edit a file
2. Before it writes, look for "TDD CHECK" behavior — Claude should ask about
   failing tests or mention writing tests first
3. Screenshot evidence

### Test 5c: Completion hook (Stop)
1. Let Claude finish a task
2. Look for completion check behavior — Claude should verify confidence level,
   self-review, and test status before finishing
3. Screenshot evidence

## Step 6: Document results

Create a summary with:
- Which install method worked (A, B, or C)
- Plugin version shown in the installed list
- Which skills loaded successfully
- Which hooks fired successfully
- Any errors encountered
- Screenshots of every step

## Success Criteria
- [ ] Plugin installs without errors
- [ ] "sdlc-wizard-cowork" appears in installed plugins
- [ ] /sdlc-wizard-cowork:sdlc skill invokes correctly
- [ ] /sdlc-wizard-cowork:feedback skill invokes correctly
- [ ] UserPromptSubmit hook fires (SDLC BASELINE)
- [ ] PreToolUse hook fires on Write/Edit (TDD CHECK)
- [ ] Stop hook fires (COMPLETION CHECK)
- [ ] No entries in plugin Errors tab
```

## Expected Outcome

If the plugin is NOT yet in the community marketplace (it hasn't been submitted yet),
Method A will fail. Method B or C should work for local/direct testing.

After verifying the plugin works via Method B or C, submit to the marketplace at:
- Individual: https://platform.claude.com/plugins/submit
- Team/Enterprise: https://claude.ai/admin-settings/directory/submissions/plugins/new

## Notes

- Plugin validates clean: `claude plugin validate cowork/` passes
- 17/17 drift tests pass in `tests/test-cowork-drift.sh`
- Plugin uses prompt-based hooks only (no bash/shell — works without filesystem access)
- Skills are copies of canonical skills, kept in sync by CI drift test
